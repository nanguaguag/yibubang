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

      final result = await _pullBank(bankId, sw, pacing);
      if (result.isSuccess) {
        await prefs.setInt(throttleKey, now);
      }
      return result;
    } catch (e, stack) {
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

      for (final raw in list) {
        if (raw is! Map) {
          skipped++;
          invalidRecords++;
          continue;
        }
        final questionId = raw['question_id']?.toString() ?? '';
        final answer = raw['answer']?.toString() ?? '';
        final right = raw['is_right']?.toString() ?? '';
        if (questionId.isEmpty ||
            answer.isEmpty ||
            (right != '0' && right != '1')) {
          skipped++;
          invalidRecords++;
          continue;
        }
        final isRight = raw['is_right']?.toString() == '1' ? 1 : 2;

        final bankQuestionRows = await bankDb.query(
          'Question',
          columns: ['chapter_id', 'chapter_parent_id'],
          where: 'id = ?',
          whereArgs: [questionId],
          limit: 1,
        );
        if (bankQuestionRows.isEmpty) {
          // 账号里可能包含其他题库的记录，本地题库没有对应题目时跳过。
          skipped++;
          notInBank++;
          continue;
        }
        final chapterId =
            bankQuestionRows.first['chapter_id']?.toString() ?? '';
        final chapterParentId =
            bankQuestionRows.first['chapter_parent_id']?.toString() ?? '';

        final localRows = await userDb.query(
          'Question',
          columns: ['id', 'status', 'user_answer', 'updated_at'],
          where: 'id = ?',
          whereArgs: [questionId],
          limit: 1,
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (localRows.isEmpty) {
          await userDb.insert('Question', {
            'id': questionId,
            'chapter_id': chapterId,
            'chapter_parent_id': chapterParentId,
            'cut_question': '0',
            'user_answer': answer,
            'status': isRight,
            'collection': 0,
            'updated_at': nowMs,
          });
          applied++;
        } else {
          final localStatus = (localRows.first['status'] as num?)?.toInt() ?? 0;
          if (localStatus != 0) {
            // 本地已作答优先，避免把本地更新的答案覆盖成云端旧记录。
            skipped++;
            alreadyAnswered++;
            continue;
          }
          await userDb.update(
            'Question',
            {'status': isRight, 'user_answer': answer, 'updated_at': nowMs},
            where: 'id = ?',
            whereArgs: [questionId],
          );
          applied++;
        }

        // 已有本地作答流水时不重复插入，避免统计重复计数。
        final existingActivity = await userDb.query(
          'Activities',
          columns: ['id'],
          where: "question_id = ? AND title IN ('NewAnswer', 'YkbPull')",
          whereArgs: [questionId],
          limit: 1,
        );
        if (existingActivity.isEmpty) {
          await userDb.insert('Activities', {
            'id': generateSimpleId(),
            'title': 'YkbPull',
            'description': jsonEncode({
              'question_id': questionId,
              'answer': answer,
              'is_right': raw['is_right']?.toString() ?? '',
              'identity_id': identityId,
              'remote_id': raw['id']?.toString() ?? '',
            }),
            'timestamp': nowMs,
            'bank_id': bankId,
            'question_id': questionId,
            'identity_id': identityId,
            'subject_id': chapterParentId,
            'chapter_id': chapterId,
            'is_right': isRight == 1 ? '1' : '0',
            'duration': 0,
          });
        }
      }
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
