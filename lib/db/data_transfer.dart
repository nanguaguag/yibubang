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
Future<bool> rebuildQuestionCount() async {
  final qbankPath = await DatabaseHelper().getDatabasePath(); 
  final escaped = qbankPath.replaceAll("'", "''");
  final userDb = await UserDBHelper().database;

  // 1) 先 attach（同一个连接）
  await userDb.execute("PRAGMA busy_timeout = 3000;");
  await userDb.execute("ATTACH DATABASE '$escaped' AS qbank;");

  try {
    // 2) 再做事务（不要在 txn 里 detach）
    await userDb.transaction((txn) async {
      await txn
          .rawUpdate('UPDATE IdentitySubject SET correct = 0, incorrect = 0');
      await txn
          .rawUpdate('UPDATE IdentityChapter SET correct = 0, incorrect = 0');

      await txn.rawInsert(r'''
        INSERT INTO IdentityChapter (identity_id, subject_id, chapter_id, correct, incorrect)
        SELECT
          iq.identity_id,
          iq.subject_id,
          iq.chapter_id,
          SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END) AS correct,
          SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END) AS incorrect
        FROM Question AS uq
        JOIN qbank.IdentityQuestion AS iq
          ON uq.id = iq.question_id
        WHERE uq.status IN (1, 2)
        GROUP BY iq.identity_id, iq.subject_id, iq.chapter_id
        ON CONFLICT(identity_id, chapter_id) DO UPDATE SET
          correct   = excluded.correct,
          incorrect = excluded.incorrect;
      ''');

      await txn.execute(r'''
        INSERT INTO IdentitySubject (identity_id, subject_id, correct, incorrect)
        SELECT
          iq.identity_id,
          iq.subject_id,
          SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END) AS correct,
          SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END) AS incorrect
        FROM Question AS uq
        JOIN qbank.IdentityQuestion AS iq
          ON uq.id = iq.question_id
        WHERE uq.status IN (1, 2)
        GROUP BY iq.identity_id, iq.subject_id
        ON CONFLICT(identity_id, subject_id) DO UPDATE SET
          correct   = excluded.correct,
          incorrect = excluded.incorrect;
      ''');
    });
  } finally {
    // 3) 事务结束后再 detach
    await userDb.execute("DETACH DATABASE qbank;");
  }

  return true;
}
