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
