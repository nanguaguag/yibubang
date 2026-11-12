import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_search.dart';

class AiSearchException implements Exception {
  final String message;
  final int? status;
  const AiSearchException(this.message, [this.status]);
  @override
  String toString() => message;
}

abstract class AiSearchGateway {
  Future<AiQuota> quota();
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String requestId,
  );
  void cancel();
  void dispose();
}

/// SSE frames may span arbitrary UTF-8/network boundaries.
Stream<AiStreamEvent> decodeAiEvents(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final decoded = jsonDecode(data.join('\n'));
        yield AiStreamEvent(event, Map<String, dynamic>.from(decoded));
      }
      event = 'message';
      data.clear();
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  // Our protocol always terminates complete frames with a blank line.
  if (data.isNotEmpty) throw const AiSearchException('连接提前结束，请重试');
}

class AiSearchClient implements AiSearchGateway {
  static const endpoint = String.fromEnvironment(
    'AI_SEARCH_ENDPOINT',
    defaultValue: 'https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app',
  );
  final String baseUrl;
  final http.Client Function() clientFactory;
  http.Client? _active;
  int _cancellation = 0;
  bool _disposed = false;
  Future<void>? _registration;
  String? _deviceId;
  String? _secret;
  AiSearchClient({
    this.baseUrl = endpoint,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<void> _identity() async {
    if (_deviceId != null) return;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('ai_installation_id');
    _secret = prefs.getString('ai_installation_secret');
    if (_deviceId == null || _secret == null) {
      final random = Random.secure();
      _deviceId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _secret = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('ai_installation_id', _deviceId!);
      await prefs.setString('ai_installation_secret', _secret!);
      await prefs.remove('ai_device_registered');
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Device-ID': _deviceId!,
    'Authorization': 'Bearer $_secret',
  };
  Future<void> _register() async {
    await _identity();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('ai_device_registered') == baseUrl) return;
    if (baseUrl.contains('PENDING')) {
      throw const AiSearchException('AI 搜索服务尚未配置');
    }
    final client = clientFactory();
    try {
      final r = await client
          .post(
            Uri.parse('$baseUrl/v1/devices'),
            headers: _headers,
            body: jsonEncode({'installation_id': _deviceId, 'secret': _secret}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw _error(r.statusCode, r.body);
      await prefs.setString('ai_device_registered', baseUrl);
    } finally {
      client.close();
    }
  }

  Future<void> _ready() => _registration ??= _register().catchError((Object e) {
    _registration = null;
    throw e;
  });
  AiSearchException _error(int code, String body) {
    try {
      return AiSearchException(
        (jsonDecode(body) as Map)['message'] as String? ?? '服务暂时不可用',
        code,
      );
    } catch (_) {
      return AiSearchException('服务暂时不可用（$code）', code);
    }
  }

  @override
  Future<AiQuota> quota() async {
    await _ready();
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/v1/quota'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw _error(response.statusCode, response.body);
      }
      return AiQuota.fromJson(jsonDecode(response.body));
    } finally {
      client.close();
    }
  }

  @override
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String requestId,
  ) async* {
    final cancellation = _cancellation;
    await _ready();
    if (_disposed || cancellation != _cancellation) return;
    final client = clientFactory();
    _active = client;
    try {
      final context = history
          .where((t) => t.status == 'complete')
          .toList()
          .reversed
          .take(3)
          .toList()
          .reversed
          .map((t) => {'question': t.question, 'answer': t.answer})
          .toList();
      final payload = {
        'question': question,
        'request_id': requestId,
        'history': context,
      };
      var encoded = jsonEncode(payload);
      // Bound the actual UTF-8 bytes, including long Chinese follow-up history.
      while (utf8.encode(encoded).length > 60000 && context.isNotEmpty) {
        context.removeAt(0);
        encoded = jsonEncode(payload);
      }
      final request = http.Request('POST', Uri.parse('$baseUrl/v1/search'))
        ..headers.addAll({..._headers, 'Accept': 'text/event-stream'})
        ..body = encoded;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw _error(response.statusCode, body);
      }
      var complete = false;
      await for (final event in decodeAiEvents(
        response.stream.timeout(const Duration(seconds: 90)),
      )) {
        if (event.type == 'done' || event.type == 'error') complete = true;
        yield event;
      }
      if (!complete) throw const AiSearchException('连接中断，已保留当前回答');
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void cancel() {
    ++_cancellation;
    _active?.close();
    _active = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}
