import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart'; // 假设此文件中包含 DatabaseHelper 和 UserDBHelper 的定义

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
  final activeBankId =
      bankId ?? prefs.getString('activeBankId') ?? 'dental_final';
  final identityId = prefs.getString('identityId') ??
      switch (activeBankId) {
        'clinical_final' => '20101',
        'nursing_final' => '11070',
        _ => '30401',
      };
  final qbankPath = await DatabaseHelper().getDatabasePath();
  final escaped = qbankPath.replaceAll("'", "''");
  final userDb = await UserDBHelper().database;

  await userDb.rawQuery("PRAGMA busy_timeout = 3000;");
  await userDb.rawQuery("ATTACH DATABASE '$escaped' AS qbank;");
  try {
    await userDb.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE IdentitySubject SET correct = 0, incorrect = 0 WHERE bank_id = ?',
        [activeBankId],
      );
      await txn.rawUpdate(
        'UPDATE IdentityChapter SET correct = 0, incorrect = 0 WHERE bank_id = ?',
        [activeBankId],
      );

      await txn.rawInsert('''
        INSERT INTO IdentityChapter
          (bank_id, identity_id, subject_id, chapter_id, correct, incorrect)
        SELECT ?, iq.identity_id, iq.subject_id, iq.chapter_id,
          SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END),
          SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END)
        FROM Question AS uq
        JOIN qbank.IdentityQuestion AS iq ON uq.id = iq.question_id
        WHERE uq.status IN (1, 2) AND iq.identity_id = ?
        GROUP BY iq.identity_id, iq.subject_id, iq.chapter_id
        ON CONFLICT(bank_id, identity_id, subject_id, chapter_id) DO UPDATE SET
          correct = excluded.correct,
          incorrect = excluded.incorrect;
      ''', [activeBankId, identityId]);

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
          WHERE uq.status IN (1, 2) AND iq.identity_id = ?
        ) AS sq
        GROUP BY sq.identity_id, sq.subject_id
        ON CONFLICT(bank_id, identity_id, subject_id) DO UPDATE SET
          correct = excluded.correct,
          incorrect = excluded.incorrect;
      ''', [activeBankId, activeBankId, identityId]);
    });
  } finally {
    await userDb.execute("DETACH DATABASE qbank;");
  }
  return true;
}
