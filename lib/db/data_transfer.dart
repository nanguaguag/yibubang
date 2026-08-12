import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'question_bank_manager.dart';

/// 将 question_data.sqlite 中与用户数据相关的数据迁移到 user_data.sqlite 中
Future<bool> transferData() async {
  // 获取两个数据库的实例
  DatabaseHelper questionDB = DatabaseHelper();
  UserDBHelper userDB = UserDBHelper();
  final usrdb = await userDB.database;

  // 从 question_data.sqlite 的 Question 表中获取含有用户数据的记录，
  // 取出全部题目数据
  List<Map<String, dynamic>> subjectRecords =
      await questionDB.getByCondition('Subject', '1 = 1', []);
  List<Map<String, dynamic>> chapterRecords =
      await questionDB.getByCondition('Chapter', '1 = 1', []);

  // 插入 Subject 表数据
  await usrdb.transaction((txn) async {
    final batch = txn.batch();
    for (var record in subjectRecords) {
      batch.rawInsert('''
        INSERT OR REPLACE INTO Subject (id, name, selected, correct, incorrect, total)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        record['id'],
        record['name'],
        record['selected'] ?? 0,
        0,
        0,
        0,
      ]);
    }
    await batch.commit(noResult: true);
  });

  // 插入 Chapter 表数据
  await usrdb.transaction((txn) async {
    final batch = txn.batch();
    for (var record in chapterRecords) {
      batch.rawInsert('''
        INSERT OR REPLACE INTO Chapter (id, name, subject_id, correct, incorrect, total)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        record['id'],
        record['name'],
        record['subject_id'],
        0,
        0,
        0,
      ]);
    }
    await batch.commit(noResult: true);
  });

  // 分页处理 Question 表
  int limit = 1000;
  int offset = 0;

  while (true) {
    // 分页获取 Question 表数据
    List<Map<String, dynamic>> questionBatch = await questionDB
        .getByCondition('Question', '1 = 1 LIMIT $limit OFFSET $offset', []);

    if (questionBatch.isEmpty) break;

    await usrdb.transaction((txn) async {
      final batch = txn.batch();
      for (var record in questionBatch) {
        batch.rawInsert('''
          INSERT OR REPLACE INTO Question (id, chapter_id, chapter_parent_id, cut_question, user_answer, status, collection)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', [
          record['id'],
          record['chapter_id'],
          record['chapter_parent_id'],
          record['cut_question'] ?? "",
          record['user_answer'] ?? "",
          record['status'] ?? 0,
          record['collection'] ?? 0,
        ]);
      }
      await batch.commit(noResult: true);
    });

    offset += limit;
  }

  return true;
}

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
