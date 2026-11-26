import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../db/data_transfer.dart';
import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import 'sync_debug_log.dart';
import 'ykb_bank_sync_service.dart' show SyncPacing;

/// 医考帮做题记录拉取结果
class YkbPullResult {
  final int identityCount;
  final int fetched;
  final int applied;
  final int skipped;
  final int alreadyAnswered;
  final int notInBank;
  final int invalidRecords;
  final String? error;
  final int elapsedMs;

  const YkbPullResult({
    this.identityCount = 0,
    this.fetched = 0,
    this.applied = 0,
    this.skipped = 0,
    this.alreadyAnswered = 0,
    this.notInBank = 0,
    this.invalidRecords = 0,
    this.error,
    this.elapsedMs = 0,
  });

  bool get isSuccess => error == null;

  String get summary {
    final counts =
        '远端 $fetched 条，新增合并 $applied 条；'
        '跳过 $skipped 条（本地已作答 $alreadyAnswered、当前题库无此题 $notInBank、记录不完整 $invalidRecords）。'
        '本地答案优先保留。';
    if (error != null) return '拉取未全部完成：$error。$counts';
    return '检查 $identityCount 个身份，$counts';
  }
}

/// 从医考帮拉取做题记录（答案与对错）并合并到本地。
///
/// 服务端 `/allquestion/main/userAnswer` 按「叶子身份」返回答题记录：
/// 临床期末题库的本地身份是 20101，但它只是父级，直接用 20101 查询会返回
/// 0 条；真正的记录挂在 201010~201013 这些叶子身份下。这里先从本地题库的
/// Identity 树里取出叶子身份，再逐个拉取。
class YkbPullService {
  static final YkbPullService instance = YkbPullService._internal();
  YkbPullService._internal();

  static const String keySyncProgressToYkb = 'sync_ykb_progress_enabled';
  static const String keyLastPullTime = 'ykb_pull_last_sync_time';

  static const int _minIntervalMs = 10 * 60 * 1000;

  bool _isPulling = false;

  static Future<YkbPullResult> pullForBank(
    QuestionBank bank, {
    SyncPacing pacing = const SyncPacing(),
  }) => instance.pullForActiveBank(
    force: true,
    manual: true,
    bank: bank,
    pacing: pacing,
  );

  /// 是否开启自动拉取医考帮做题记录
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySyncProgressToYkb) ?? true;
  }

  /// 拉取当前活动题库的做题记录。
  ///
  /// [force] 为 true 时忽略 10 分钟节流（手动刷新、登录后使用）。
  Future<YkbPullResult> pullForActiveBank({
    bool force = false,
    bool manual = false,
    QuestionBank? bank,
    SyncPacing pacing = const SyncPacing(),
  }) async {
    if (_isPulling) {
      return const YkbPullResult(error: '正在拉取中');
    }
    _isPulling = true;
    final sw = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('loggedin') ?? false)) {
        debugPrint('[YkbPullService] 未登录，跳过拉取');
        return const YkbPullResult(error: '未登录');
      }
      if (!manual && !await isEnabled()) {
        debugPrint('[YkbPullService] 自动拉取做题记录已关闭');
        return const YkbPullResult(error: '已关闭');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final bankId = bank?.bankId ?? prefs.getString('activeBankId') ?? '';
      final throttleKey =
          '$keyLastPullTime:${prefs.getString('user_id') ?? ''}:$bankId';
      final last = prefs.getInt(throttleKey) ?? 0;
      if (!force && last > 0 && now - last < _minIntervalMs) {
        debugPrint('[YkbPullService] 距上次拉取不足 10 分钟，跳过');
        return const YkbPullResult(error: '节流中');
      }

      if (bankId.isEmpty) {
        return const YkbPullResult(error: '没有活动题库');
      }

      unawaited(SyncDebugLog.instance.record(
        '拉取医考帮记录 · $bankId · ${manual ? '手动' : '自动'}',
      ));
      final result = await _pullBank(bankId, sw, pacing);
      if (result.isSuccess) {
        await prefs.setInt(throttleKey, now);
      }
      unawaited(SyncDebugLog.instance.record(
        '拉取医考帮记录 · ${result.isSuccess ? '完成' : '未全部完成'} · '
        '远端 ${result.fetched} 条 · 合并 ${result.applied} 条 · 跳过 ${result.skipped} 条',
      ));
      return result;
    } catch (e, stack) {
      unawaited(SyncDebugLog.instance.record('拉取医考帮记录 · 失败 · ${e.runtimeType}'));
      debugPrint('[YkbPullService] 拉取异常: $e');
      debugPrint('$stack');
      return YkbPullResult(
        error: e.toString(),
        elapsedMs: sw.elapsedMilliseconds,
      );
    } finally {
      _isPulling = false;
    }
  }

  Future<YkbPullResult> _pullBank(
    String bankId,
    Stopwatch sw,
    SyncPacing pacing,
  ) async {
    final userDb = await UserDBHelper().database;

    // 本地题库的根身份：临床期末为 20101，口腔/护理题库同理。
    final bankRows = await userDb.query(
      'QuestionBank',
      columns: ['identity_id'],
      where: 'bank_id = ?',
      whereArgs: [bankId],
      limit: 1,
    );
    final rootIdentityId = bankRows.isEmpty
        ? ''
        : (bankRows.first['identity_id']?.toString() ?? '');

    final bankDb = await QuestionBankDatabaseManager().openBank(bankId);
    final identities = await _leafIdentities(bankDb, rootIdentityId);
    if (identities.isEmpty) {
      return YkbPullResult(
        error: '未找到可拉取的身份',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    // 预取当前题库所有题目的章节归属，消除循环内 N+1 题库查询
    final bankQuestionMap = <String, ({String chapterId, String parentId})>{};
    final bankQuestions = await bankDb.query(
      'Question',
      columns: ['id', 'chapter_id', 'chapter_parent_id'],
    );
    for (final row in bankQuestions) {
      final qid = row['id']?.toString() ?? '';
      if (qid.isEmpty) continue;
      bankQuestionMap[qid] = (
        chapterId: row['chapter_id']?.toString() ?? '',
        parentId: row['chapter_parent_id']?.toString() ?? '',
      );
    }

    var fetched = 0;
    var applied = 0;
    var skipped = 0;
    var alreadyAnswered = 0;
    var notInBank = 0;
    var invalidRecords = 0;
    var tokenExpired = false;
    String? requestError;

    for (final identityId in identities) {
      final appId = await _appIdForIdentity(bankDb, identityId);
      await pacing.chapterDelay();
      await pacing.requestDelay();
      final resp = await basicReq('/allquestion/main/userAnswer', {
        'app_id': appId,
        'module_type': '1',
        'identity_id': identityId,
        'category': 'chapter',
        'type': 'all',
        'is_vip': '0',
        'is_svip': '0',
      }, method: 'GET');

      final code = resp['code']?.toString() ?? '';
      if (code == '309') {
        debugPrint('[YkbPullService] 登录态失效 (309)，停止拉取');
        tokenExpired = true;
        break;
      }
      if (code != '200') {
        debugPrint(
          '[YkbPullService] identity=$identityId 拉取失败: $code ${resp['message']}',
        );
        requestError = '身份 $identityId 拉取失败：$code';
        continue;
      }

      final list = resp['data'];
      if (list is! List || list.isEmpty) {
        debugPrint('[YkbPullService] identity=$identityId 无做题记录');
        continue;
      }
      fetched += list.length;
      debugPrint(
        '[YkbPullService] identity=$identityId 拉取到 ${list.length} 条记录',
      );

      // 收集本身份下属于当前题库的合法记录
      final validItems = <({
        String questionId,
        String answer,
        String rawRight,
        int status,
        bool isCut,
        int timestampMs,
        int durationMs,
        String remoteId,
        String chapterId,
        String chapterParentId,
      })>[];
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (final raw in list) {
        if (raw is! Map) {
          skipped++;
          invalidRecords++;
          continue;
        }
        final questionId = raw['question_id']?.toString() ?? '';
        final answer = raw['answer']?.toString() ?? '';
        final right = raw['is_right']?.toString() ?? '';
        final rawCut = raw['cut_question']?.toString() ??
            raw['is_cut']?.toString() ??
            '0';
        final isCut = rawCut == '1' || rawCut == 'cutted';
        final hasValidAnswer =
            answer.isNotEmpty && (right == '0' || right == '1');
        if (questionId.isEmpty || (!hasValidAnswer && !isCut)) {
          skipped++;
          invalidRecords++;
          continue;
        }
        final bankMeta = bankQuestionMap[questionId];
        if (bankMeta == null) {
          skipped++;
          notInBank++;
          continue;
        }
        final status = hasValidAnswer ? (right == '1' ? 1 : 2) : 0;
        final rawTime = int.tryParse(
              (raw['update_time'] ?? raw['ctime'] ?? raw['create_time'])
                      ?.toString() ??
                  '0',
            ) ??
            0;
        final tsMs = rawTime > 1000000000000
            ? rawTime
            : (rawTime > 0 ? rawTime * 1000 : nowMs);
        final durSec =
            int.tryParse(raw['duration']?.toString() ?? '0') ?? 0;

        validItems.add((
          questionId: questionId,
          answer: answer,
          rawRight: right,
          status: status,
          isCut: isCut,
          timestampMs: tsMs,
          durationMs: durSec > 0 ? durSec * 1000 : 0,
          remoteId: raw['id']?.toString() ?? '',
          chapterId: bankMeta.chapterId,
          chapterParentId: bankMeta.parentId,
        ));
      }

      if (validItems.isEmpty) continue;

      await userDb.transaction((tx) async {
        final qIds = validItems.map((e) => e.questionId).toSet().toList();
        final localQMap = <String, Map<String, Object?>>{};
        final answeredActivityQIds = <String>{};

        for (var i = 0; i < qIds.length; i += 500) {
          final chunk = qIds.sublist(
            i,
            i + 500 < qIds.length ? i + 500 : qIds.length,
          );
          final ph = List.filled(chunk.length, '?').join(',');
          final qRows = await tx.query(
            'Question',
            columns: ['id', 'status', 'user_answer', 'cut_question'],
            where: 'id IN ($ph)',
            whereArgs: chunk,
          );
          for (final r in qRows) {
            localQMap[r['id'] as String] = r;
          }
          final actRows = await tx.query(
            'Activities',
            columns: ['question_id'],
            where:
                "question_id IN ($ph) AND title IN ('NewAnswer', 'YkbPull')",
            whereArgs: chunk,
          );
          for (final r in actRows) {
            final qid = r['question_id']?.toString();
            if (qid != null) answeredActivityQIds.add(qid);
          }
        }

        final batch = tx.batch();
        for (final item in validItems) {
          final local = localQMap[item.questionId];
          if (local == null) {
            batch.insert('Question', {
              'id': item.questionId,
              'chapter_id': item.chapterId,
              'chapter_parent_id': item.chapterParentId,
              'cut_question': item.isCut ? '1' : '0',
              'user_answer': item.answer,
              'status': item.status,
              'collection': 0,
              'updated_at': item.timestampMs,
            });
            localQMap[item.questionId] = {
              'id': item.questionId,
              'status': item.status,
              'user_answer': item.answer,
              'cut_question': item.isCut ? '1' : '0',
            };
            applied++;
          } else {
            final localStatus = (local['status'] as num?)?.toInt() ?? 0;
            final localCut = local['cut_question']?.toString() ?? '0';
            final needApplyAnswer = localStatus == 0 && item.status != 0;
            final needApplyCut =
                item.isCut && localCut != '1' && localCut != 'cutted';
            if (!needApplyAnswer && !needApplyCut) {
              skipped++;
              alreadyAnswered++;
              continue;
            }
            final patch = <String, Object?>{
              'updated_at': item.timestampMs,
              if (needApplyAnswer) 'status': item.status,
              if (needApplyAnswer) 'user_answer': item.answer,
              if (needApplyCut) 'cut_question': '1',
            };
            batch.update(
              'Question',
              patch,
              where: 'id = ?',
              whereArgs: [item.questionId],
            );
            localQMap[item.questionId] = {...local, ...patch};
            applied++;
          }

          if (item.status != 0 &&
              !answeredActivityQIds.contains(item.questionId)) {
            answeredActivityQIds.add(item.questionId);
            batch.insert('Activities', {
              'id': generateSimpleId(),
              'title': 'YkbPull',
              'description': jsonEncode({
                'question_id': item.questionId,
                'answer': item.answer,
                'is_right': item.rawRight,
                'identity_id': identityId,
                'remote_id': item.remoteId,
              }),
              'timestamp': item.timestampMs,
              'bank_id': bankId,
              'question_id': item.questionId,
              'identity_id': identityId,
              'subject_id': item.chapterParentId,
              'chapter_id': item.chapterId,
              'is_right': item.status == 1 ? '1' : '0',
              'duration': item.durationMs,
            });
          }
        }
        await batch.commit(noResult: true);
      });
    }

    if (applied > 0) {
      await rebuildQuestionCount(bankId: bankId);
    }
    debugPrint(
      '[YkbPullService] 拉取完成: 身份 ${identities.length} 个, '
      '远端 $fetched 条, 合并 $applied 条, 跳过 $skipped 条 '
      '(${sw.elapsedMilliseconds}ms)',
    );
    return YkbPullResult(
      identityCount: identities.length,
      fetched: fetched,
      applied: applied,
      skipped: skipped,
      alreadyAnswered: alreadyAnswered,
      notInBank: notInBank,
      invalidRecords: invalidRecords,
      error: tokenExpired ? '登录已过期，请重新登录' : requestError,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// 取题库根身份下的叶子身份（如 20101 -> 201010~201013）。
  ///
  /// 老题库没有 Identity 表时，退化为题目上的 native_identity_id。
  Future<List<String>> _leafIdentities(
    Database bankDb,
    String rootIdentityId,
  ) async {
    final ids = <String>[];
    final parents = <String, String>{};
    try {
      final rows = await bankDb.query('Identity', columns: ['id', 'parent_id']);
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        ids.add(id);
        parents[id] = row['parent_id']?.toString() ?? '';
      }
    } catch (_) {
      // 老题库可能没有 Identity 表。
    }

    if (ids.isEmpty) {
      try {
        final rows = await bankDb.rawQuery(
          "SELECT DISTINCT native_identity_id FROM Question "
          "WHERE native_identity_id IS NOT NULL AND native_identity_id != ''",
        );
        return rows
            .map((r) => r['native_identity_id']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {
        return const [];
      }
    }

    final children = <String, List<String>>{};
    for (final entry in parents.entries) {
      children.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    if (rootIdentityId.isEmpty || !ids.contains(rootIdentityId)) {
      final leaves = ids
          .where((id) => (children[id] ?? const <String>[]).isEmpty)
          .toList();
      return leaves.isEmpty ? ids : leaves;
    }

    final result = <String>[];
    void visit(String id) {
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) {
        result.add(id);
        return;
      }
      for (final kid in kids) {
        visit(kid);
      }
    }

    visit(rootIdentityId);
    return result.isEmpty ? [rootIdentityId] : result;
  }

  /// 取该身份下题目使用的医考帮 app_id（临床期末为 40）。
  Future<String> _appIdForIdentity(Database bankDb, String identityId) async {
    try {
      final rows = await bankDb.query(
        'Question',
        columns: ['native_app_id'],
        where:
            "native_identity_id = ? "
            "AND native_app_id IS NOT NULL AND native_app_id != ''",
        whereArgs: [identityId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final appId = rows.first['native_app_id']?.toString() ?? '';
        if (appId.isNotEmpty) return appId;
      }
    } catch (_) {}

    try {
      final rows = await bankDb.query(
        'Question',
        columns: ['native_app_id'],
        where: "native_app_id IS NOT NULL AND native_app_id != ''",
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final appId = rows.first['native_app_id']?.toString() ?? '';
        if (appId.isNotEmpty) return appId;
      }
    } catch (_) {}

    return '12';
  }
}
