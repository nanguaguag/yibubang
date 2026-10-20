import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'question_bank_manager.dart';
import '../models/answer_statistics.dart';

// 重新统计刷题数量
Future<bool> rebuildQuestionCount({String? bankId}) async {
  final prefs = await SharedPreferences.getInstance();
  final targetBankId = bankId ?? prefs.getString('activeBankId');
  if (targetBankId == null || targetBankId.isEmpty) {
    throw StateError('目标题库尚未初始化');
  }

  // 显式 bankId 必须决定实际打开的 SQLite 文件，不能再通过
  // DatabaseHelper.getDatabasePath() 间接读取当前 activeBankId。
  final databaseManager = QuestionBankDatabaseManager();
  final qbankPath = targetBankId == 'legacy_combined'
      ? p.join(await getDatabasesPath(), 'question_data.sqlite')
      : await databaseManager.pathFor(targetBankId);
  if (!await File(qbankPath).exists()) {
    throw StateError('目标题库文件不存在：$targetBankId');
  }
  if (targetBankId != 'legacy_combined') {
    final validation = await databaseManager.validateFile(
      qbankPath,
      expectedBankId: targetBankId,
    );
    if (!validation.isValid) {
      throw StateError('目标题库校验失败：${validation.message}');
    }
  }

  final userDb = await UserDBHelper().database;
  var attached = false;
  try {
    await userDb.rawQuery("PRAGMA busy_timeout = 3000;");
    final escaped = qbankPath.replaceAll("'", "''");
    await userDb.rawQuery("ATTACH DATABASE '$escaped' AS qbank;");
    attached = true;

    await userDb.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE IdentitySubject SET correct = 0, incorrect = 0 WHERE bank_id = ?',
        [targetBankId],
      );
      await txn.rawUpdate(
        'UPDATE IdentityChapter SET correct = 0, incorrect = 0 WHERE bank_id = ?',
        [targetBankId],
      );

      // IdentityQuestion 是题库中唯一的 identity/课程/章节关系真相。
      // 不使用 SharedPreferences.identityId 过滤，以覆盖题库中的完整
      // Identity 子树，并保持显式 bankId 的统计边界。
      await txn.rawInsert('''
        INSERT INTO IdentityChapter
          (bank_id, identity_id, subject_id, chapter_id, correct, incorrect)
        SELECT ?, iq.identity_id, iq.subject_id, iq.chapter_id,
          SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END),
          SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END)
        FROM Question AS uq
        JOIN qbank.IdentityQuestion AS iq ON uq.id = iq.question_id
        WHERE uq.status IN (1, 2)
        GROUP BY iq.identity_id, iq.subject_id, iq.chapter_id
        ON CONFLICT(bank_id, identity_id, subject_id, chapter_id) DO UPDATE SET
          correct = excluded.correct,
          incorrect = excluded.incorrect;
      ''', [targetBankId]);

      await txn.rawInsert('''
        INSERT INTO IdentitySubject
          (bank_id, identity_id, subject_id, correct, incorrect, selected)
        SELECT ?, sq.identity_id, sq.subject_id,
          SUM(CASE WHEN sq.status = 1 THEN 1 ELSE 0 END),
          SUM(CASE WHEN sq.status = 2 THEN 1 ELSE 0 END),
          COALESCE((SELECT selected FROM IdentitySubject old
            WHERE old.bank_id = ?
              AND old.identity_id = sq.identity_id
              AND old.subject_id = sq.subject_id), 0)
        FROM (
          SELECT DISTINCT iq.identity_id, iq.subject_id, uq.id, uq.status
          FROM Question AS uq
          JOIN qbank.IdentityQuestion AS iq ON uq.id = iq.question_id
          WHERE uq.status IN (1, 2)
        ) AS sq
        GROUP BY sq.identity_id, sq.subject_id
        ON CONFLICT(bank_id, identity_id, subject_id) DO UPDATE SET
          correct = excluded.correct,
          incorrect = excluded.incorrect;
      ''', [targetBankId, targetBankId]);
    });
  } finally {
    if (attached) {
      await userDb.execute('DETACH DATABASE qbank;');
    }
  }
  return true;
}

/// 修复刷题统计误差。
///
/// 早期版本只在「对/错计数表」里更新，没有往 `Activities` 写入作答流水，
/// 导致已经做过的题在“统计”页缺失。这里把 `Question` 表中 status 为正确/做错
/// 的题目补记进 `Activities`，其中正确率、作答数会随已有计数保持一致，
/// 作答时间则平均分布到最近一年内（历史上没有精确作答时间，只能近似估计）。
///
/// 通过「已记录题目 id 去重」保证幂等：重复执行不会造成重复记录；之后
/// 新做的题由答题流程正常写入流水，也不受本次修复影响。
Future<void> repairActivities({String? bankId}) async {
  final prefs = await SharedPreferences.getInstance();
  final targetBankId = bankId ?? prefs.getString('activeBankId');
  debugPrint('[repairActivities] targetBankId=$targetBankId '
      'bankId参数=$bankId');
  if (targetBankId == null || targetBankId.isEmpty) {
    debugPrint('[repairActivities] bankId 为空，跳过修复');
    return;
  }

  final userDb = await UserDBHelper().database;

  // 1. 已记录到 Activities 的题目 id（真实答题流水 + 历史补记账都用它去重）
  final recordedRows = await userDb.rawQuery(
    'SELECT DISTINCT question_id FROM Activities '
    'WHERE question_id IS NOT NULL AND is_right IN (?, ?)',
    ['0', '1'],
  );
  final recordedIds = recordedRows
      .map((r) => r['question_id']?.toString())
      .whereType<String>()
      .toSet();
  debugPrint('[repairActivities] Activities已记录题目数=${recordedIds.length}');

  // 2. 已正确/做错的题目（包含更新时间戳）
  final done = await userDb.rawQuery(
    'SELECT id, status, chapter_parent_id, chapter_id, updated_at '
    'FROM Question WHERE status IN (?, ?) ORDER BY id ASC',
    [1, 2],
  );
  debugPrint('[repairActivities] Question中已作答(status1/2)题目数=${done.length}');
  if (done.isEmpty) {
    // 便于排查历史数据是否真的把 status 写进 Question 表
    final statusAll = await userDb.rawQuery(
      'SELECT status, COUNT(*) c FROM Question GROUP BY status',
    );
    debugPrint('[repairActivities] Question.status 分布=$statusAll');
    return;
  }

  final now = DateTime.now();
  final todayMid = DateTime(now.year, now.month, now.day, 10);
  final total = done.length;

  final batch = userDb.batch();
  var added = 0;
  var index = 0;
  for (final row in done) {
    final qid = row['id'].toString();
    if (recordedIds.contains(qid)) {
      continue;
    }
    final status = row['status'] as int;
    final isRight = status == 1 ? '1' : '0';
    final updatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;

    // 优先使用真实的 updated_at 作答时间戳；仅在历史完全无时间戳时才均分（兜底）
    final int ts;
    if (updatedAt > 0) {
      ts = updatedAt;
    } else {
      final daysBack = total == 1 ? 182 : ((index / (total - 1)) * 365).round();
      ts = todayMid.subtract(Duration(days: daysBack)).millisecondsSinceEpoch;
    }

    batch.insert('Activities', {
      'id': generateSimpleId(),
      'title': 'Backfill',
      'description': '',
      'timestamp': ts,
      'bank_id': targetBankId,
      'question_id': qid,
      'identity_id': prefs.getString('identityId'),
      'subject_id': row['chapter_parent_id'],
      'chapter_id': row['chapter_id'],
      'is_right': isRight,
      'duration': 0,
    });
    added++;
    index++;
  }
  debugPrint('[repairActivities] 本次新增补记=$added （跳过已记录=${total - added}）');
  if (added > 0) {
    await batch.commit(noResult: true);
    debugPrint('[repairActivities] 已写入 Activities 成功');
    notifyAnswersChanged();
  }
}

/// 清空全部做题记录：题目作答状态、作答流水、课程/章节对错计数全部归零，
/// 并重置「上次做题进度」。用于设置页的「数据清理」危险操作。
Future<void> clearAllRecords() async {
  final prefs = await SharedPreferences.getInstance();
  final userDb = await UserDBHelper().database;
  await userDb.transaction((txn) async {
    await txn.delete('Question');
    await txn.delete('Activities');
    await txn.rawUpdate(
      'UPDATE IdentitySubject SET correct = 0, incorrect = 0, selected = 0',
    );
    await txn.rawUpdate(
      'UPDATE IdentityChapter SET correct = 0, incorrect = 0',
    );
  });
  await prefs.remove('lastSubjectId');
  await prefs.remove('lastChapterId');
  await prefs.remove('lastQIndex');
}
