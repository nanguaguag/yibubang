import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/ai_search_store.dart';
import '../db/database_helper.dart';
import '../models/ai_search.dart';
import 'ai_search_client.dart';

class AiSearchController extends ChangeNotifier {
  final AiSearchStore store;
  final AiSearchGateway gateway;
  List<AiSession> sessions = [];
  List<AiTurn> turns = [];
  AiSession? session;
  AiQuota? quota;
  bool loading = true;
  bool busy = false;
  String phase = '';
  String? error;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _saves = Future.value();
  Timer? _checkpoint;
  Timer? _reveal;
  String _pendingText = '';
  Completer<void>? _drained;
  AiTurn? _revealingTurn;

  void _enqueueText(AiTurn turn, String text) {
    _pendingText += text;
    _revealingTurn = turn;
    _drained ??= Completer<void>();
    _reveal ??= Timer.periodic(const Duration(milliseconds: 24), (_) {
      final runes = _pendingText.runes.toList();
      final count = (runes.length ~/ 6).clamp(2, 160).clamp(0, runes.length);
      turn.answer += String.fromCharCodes(runes.take(count));
      _pendingText = String.fromCharCodes(runes.skip(count));
      _notify();
      if (_pendingText.isEmpty) _flushText();
    });
  }

  void _flushText() {
    _reveal?.cancel();
    _reveal = null;
    _revealingTurn?.answer += _pendingText;
    _pendingText = '';
    _revealingTurn = null;
    _drained?.complete();
    _drained = null;
  }

  AiSearchController({AiSearchStore? store, AiSearchGateway? gateway})
    : store = store ?? AiSearchStore(),
      gateway = gateway ?? AiSearchClient();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void>? _initialization;
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      sessions = await store.sessions();
      if (!_disposed && sessions.isNotEmpty) {
        session = sessions.first;
        turns = await store.turns(session!.id);
      }
    } catch (_) {
      error = '读取会话失败，请重新打开页面';
    }
    loading = false;
    _notify();
    if (!_disposed) unawaited(refreshQuota());
  }

  Future<void> refreshQuota() async {
    try {
      final value = await gateway.quota();
      if (!_disposed &&
          (quota == null ||
              value.day.compareTo(quota!.day) > 0 ||
              (value.day == quota!.day &&
                  value.remaining <= quota!.remaining))) {
        quota = value;
      }
    } catch (_) {
      /* Retry when sending. */
    }
    _notify();
  }

  Future<void> select(AiSession value) async {
    if (busy || loading || _disposed) return;
    loading = true;
    _notify();
    try {
      final loaded = await store.turns(value.id);
      if (!_disposed) {
        session = value;
        turns = loaded;
        error = null;
      }
    } catch (_) {
      error = '读取会话失败，请重试';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> newSession() async {
    if (busy || loading || _disposed) return;
    session = null;
    turns = [];
    error = null;
    _notify();
  }

  Future<void> delete(AiSession value) async {
    if (busy || loading || _disposed) return;
    loading = true;
    _notify();
    try {
      await store.delete(value.id);
      sessions.removeWhere((s) => s.id == value.id);
      if (session?.id == value.id) {
        session = null;
        turns = [];
      }
    } catch (_) {
      error = '删除会话失败，请重试';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _save(AiTurn turn, int position) {
    final sid = session!.id;
    final title = turns.first.question.length > 36
        ? '${turns.first.question.substring(0, 36)}…'
        : turns.first.question;
    final snapshot = AiTurn.fromJson(turn.toJson());
    _saves = _saves
        .catchError((_) {})
        .then((_) => store.save(sid, snapshot, position, title));
    return _saves;
  }

  Future<void> send(String raw, {int? replaceFrom}) async {
    final question = raw.trim();
    if (busy || loading || _disposed || question.isEmpty) return;
    if (question.length > 2000) {
      error = '问题最多 2000 字';
      _notify();
      return;
    }
    if (replaceFrom != null &&
        (replaceFrom < 0 || replaceFrom >= turns.length)) {
      return;
    }
    busy = true;
    error = null;
    phase = '正在检索医学题库';
    final generation = ++_generation;
    _notify();
    AiTurn? turn;
    var position = 0;
    try {
      if (session == null) {
        final now = DateTime.now();
        session = AiSession(
          id: generateSimpleId(),
          title: question,
          createdAt: now,
          updatedAt: now,
        );
        await store.create(session!);
        sessions.insert(0, session!);
        if (_disposed || generation != _generation) return;
      }
      if (replaceFrom != null) {
        await store.truncate(session!.id, replaceFrom);
        turns = turns.take(replaceFrom).toList();
        if (_disposed || generation != _generation) return;
      }
      final history = List<AiTurn>.from(turns);
      turn = AiTurn(
        id: generateSimpleId(),
        question: question,
        createdAt: DateTime.now(),
      );
      position = turns.length;
      turns.add(turn);
      await _save(turn, position);
      _notify();
      if (_disposed || generation != _generation) {
        turn.status = 'stopped';
        return;
      }
      _checkpoint = Timer.periodic(const Duration(milliseconds: 700), (_) {
        if (busy) {
          unawaited(
            _save(turn!, position).catchError((_) {
              error = '本地保存失败，请检查存储空间';
              _notify();
            }),
          );
        }
      });
      await for (final event in gateway.search(question, history, turn.id)) {
        if (_disposed || generation != _generation) break;
        switch (event.type) {
          case 'phase':
            phase = event.data['message'] as String;
            break;
          case 'quota':
            quota = AiQuota.fromJson(event.data);
            break;
          case 'citations':
            turn.citations = (event.data['items'] as List)
                .map((c) => AiCitation.fromJson(Map<String, dynamic>.from(c)))
                .toList();
            break;
          case 'delta':
            _enqueueText(turn, event.data['text'] as String);
            turn.status = 'streaming';
            phase = '正在生成回答';
            break;
          case 'done':
            await _drained?.future;
            if (generation != _generation || _disposed) break;
            turn.status = 'complete';
            break;
          case 'error':
            _flushText();
            turn.status = 'error';
            turn.error = event.data['message'] as String? ?? '回答未完成，请重试';
            break;
        }
        _notify();
      }
      if (generation != _generation && turn.status != 'complete') {
        turn.status = 'stopped';
      } else if (turn.status == 'pending' || turn.status == 'streaming') {
        turn.status = 'error';
        turn.error = '连接中断，已保留当前回答';
      }
    } catch (e) {
      if (turn != null) {
        turn.status = generation == _generation ? 'error' : 'stopped';
        turn.error = generation == _generation
            ? (e is AiSearchException ? e.message : '网络连接失败，请重试')
            : null;
      } else {
        error = '创建或保存会话失败，请重试';
      }
    } finally {
      _flushText();
      _checkpoint?.cancel();
      _checkpoint = null;
      if (turn != null) {
        try {
          await _save(turn, position);
        } catch (_) {
          error = '本地保存失败，请检查存储空间';
        }
      }
      if (!_disposed) {
        try {
          sessions = await store.sessions();
        } catch (_) {
          error = '会话列表刷新失败，请重新打开页面';
        }
      }
      busy = false;
      _notify();
      if (!_disposed) unawaited(refreshQuota());
    }
  }

  void stop() {
    if (!busy) return;
    ++_generation;
    _flushText();
    gateway.cancel();
    phase = '正在停止';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _checkpoint?.cancel();
    _flushText();
    gateway.dispose();
    super.dispose();
  }
}
