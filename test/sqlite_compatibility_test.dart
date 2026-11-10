import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/data_transfer.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;
  late Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite_compat_test_');
    dbPath = p.join(tempDir.path, 'test_user_data.sqlite');
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE Question (
            id TEXT PRIMARY KEY,
            chapter_id TEXT,
            chapter_parent_id TEXT,
            cut_question TEXT DEFAULT '0' NOT NULL,
            user_answer TEXT DEFAULT "" NOT NULL,
            status INTEGER DEFAULT 0 NOT NULL,
            collection INTEGER DEFAULT 0 NOT NULL,
            updated_at INTEGER DEFAULT 0 NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IdentitySubject (
            bank_id TEXT NOT NULL,
            identity_id TEXT,
            subject_id TEXT,
            correct INTEGER DEFAULT 0 NOT NULL,
            incorrect INTEGER DEFAULT 0 NOT NULL,
            selected INTEGER DEFAULT 0 NOT NULL,
            PRIMARY KEY (bank_id, identity_id, subject_id)
          )
        ''');

        await db.execute('''
          CREATE TABLE IdentityChapter (
            bank_id TEXT NOT NULL,
            identity_id TEXT,
            subject_id TEXT,
            chapter_id TEXT,
            correct INTEGER DEFAULT 0 NOT NULL,
            incorrect INTEGER DEFAULT 0 NOT NULL,
            PRIMARY KEY (bank_id, identity_id, subject_id, chapter_id)
          )
        ''');
      },
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SQLite Compatibility & Syntax Safety Tests (Issue #23)', () {
    test('sqlite_version can be queried successfully', () async {
      final res = await db.rawQuery('SELECT sqlite_version() AS version');
      expect(res.isNotEmpty, isTrue);
      final version = res.first['version'] as String;
      expect(version.isNotEmpty, isTrue);
    });

    test('LWW Question sync merge (INSERT OR IGNORE + UPDATE) operates correctly', () async {
      final batch = db.batch();

      // 1. 插入初始题目 (updated_at = 1000)
      batch.rawInsert('''
        INSERT OR IGNORE INTO Question (id, chapter_id, chapter_parent_id, cut_question, user_answer, status, collection, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', ['q1', 'c1', 'cp1', '0', 'A', 1, 0, 1000]);
      batch.rawUpdate('''
        UPDATE Question
        SET chapter_id = ?, chapter_parent_id = ?, cut_question = ?, user_answer = ?, status = ?, collection = ?, updated_at = ?
        WHERE id = ? AND ? >= updated_at
      ''', ['c1', 'cp1', '0', 'A', 1, 0, 1000, 'q1', 1000]);

      await batch.commit(noResult: true);

      var rows = await db.query('Question', where: 'id = ?', whereArgs: ['q1']);
      expect(rows.first['user_answer'], 'A');
      expect(rows.first['updated_at'], 1000);

      // 2. 云端较新数据同步过来 (updated_at = 2000 > 1000)，应当胜出覆盖
      final batch2 = db.batch();
      batch2.rawInsert('''
        INSERT OR IGNORE INTO Question (id, chapter_id, chapter_parent_id, cut_question, user_answer, status, collection, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', ['q1', 'c1', 'cp1', '0', 'B', 2, 1, 2000]);
      batch2.rawUpdate('''
        UPDATE Question
        SET chapter_id = ?, chapter_parent_id = ?, cut_question = ?, user_answer = ?, status = ?, collection = ?, updated_at = ?
        WHERE id = ? AND ? >= updated_at
      ''', ['c1', 'cp1', '0', 'B', 2, 1, 2000, 'q1', 2000]);

      await batch2.commit(noResult: true);

      rows = await db.query('Question', where: 'id = ?', whereArgs: ['q1']);
      expect(rows.first['user_answer'], 'B');
      expect(rows.first['status'], 2);
      expect(rows.first['collection'], 1);
      expect(rows.first['updated_at'], 2000);

      // 3. 较旧的云端数据同步过来 (updated_at = 1500 < 2000)，本地记录应当被保护
      final batch3 = db.batch();
      batch3.rawInsert('''
        INSERT OR IGNORE INTO Question (id, chapter_id, chapter_parent_id, cut_question, user_answer, status, collection, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', ['q1', 'c1', 'cp1', '0', 'C', 1, 0, 1500]);
      batch3.rawUpdate('''
        UPDATE Question
        SET chapter_id = ?, chapter_parent_id = ?, cut_question = ?, user_answer = ?, status = ?, collection = ?, updated_at = ?
        WHERE id = ? AND ? >= updated_at
      ''', ['c1', 'cp1', '0', 'C', 1, 0, 1500, 'q1', 1500]);

      await batch3.commit(noResult: true);

      rows = await db.query('Question', where: 'id = ?', whereArgs: ['q1']);
      expect(rows.first['user_answer'], 'B'); // 依然是 B，没有被覆盖
      expect(rows.first['updated_at'], 2000);
    });

    test('IdentitySubject & IdentityChapter atomic increment without UPSERT', () async {
      final batch = db.batch();

      // 首次答对 1 题
      batch.rawInsert('''
        INSERT OR IGNORE INTO IdentitySubject(bank_id, identity_id, subject_id, correct, incorrect, selected)
        VALUES(?, ?, ?, 0, 0, 0);
      ''', ['bank_1', 'id_1', 'sub_1']);
      batch.rawUpdate('''
        UPDATE IdentitySubject
        SET correct = correct + ?, incorrect = incorrect + ?
        WHERE bank_id = ? AND identity_id = ? AND subject_id = ?;
      ''', [1, 0, 'bank_1', 'id_1', 'sub_1']);

      // 再次答错 1 题
      batch.rawInsert('''
        INSERT OR IGNORE INTO IdentitySubject(bank_id, identity_id, subject_id, correct, incorrect, selected)
        VALUES(?, ?, ?, 0, 0, 0);
      ''', ['bank_1', 'id_1', 'sub_1']);
      batch.rawUpdate('''
        UPDATE IdentitySubject
        SET correct = correct + ?, incorrect = incorrect + ?
        WHERE bank_id = ? AND identity_id = ? AND subject_id = ?;
      ''', [0, 1, 'bank_1', 'id_1', 'sub_1']);

      await batch.commit(noResult: true);

      final rows = await db.query('IdentitySubject', where: 'bank_id = ? AND subject_id = ?', whereArgs: ['bank_1', 'sub_1']);
      expect(rows.length, 1);
      expect(rows.first['correct'], 1);
      expect(rows.first['incorrect'], 1);
      expect(rows.first['selected'], 0);
    });

    test('rebuildAttachedQuestionCount with INSERT OR REPLACE preserves data integrity', () async {
      // 预先插入一条记录，包含 selected = 1
      await db.insert('IdentitySubject', {
        'bank_id': 'bank_test',
        'identity_id': 'id_root',
        'subject_id': 'sub_1',
        'correct': 10,
        'incorrect': 5,
        'selected': 1,
      });

      // 创建一个模拟的只读题库数据库
      final bankPath = p.join(tempDir.path, 'fixture_bank.sqlite');
      final bankDb = await openDatabase(bankPath, version: 1, onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IdentityQuestion (
            identity_id TEXT,
            subject_id TEXT,
            chapter_id TEXT,
            question_id TEXT PRIMARY KEY
          )
        ''');
      });
      await bankDb.insert('IdentityQuestion', {
        'identity_id': 'id_root',
        'subject_id': 'sub_1',
        'chapter_id': 'chap_1',
        'question_id': 'q_done_1',
      });
      await bankDb.close();

      // 在用户库中插入作答记录
      await db.insert('Question', {
        'id': 'q_done_1',
        'status': 1, // 正确
        'updated_at': 5000,
      });

      // ATTACH 题库并执行 rebuildAttachedQuestionCount
      await db.execute("ATTACH DATABASE '$bankPath' AS fixture_bank");
      try {
        await db.transaction((txn) async {
          await rebuildAttachedQuestionCount(txn, 'bank_test', alias: 'fixture_bank');
        });
      } finally {
        await db.execute('DETACH DATABASE fixture_bank');
      }

      final subjectRows = await db.query('IdentitySubject', where: 'bank_id = ?', whereArgs: ['bank_test']);
      expect(subjectRows.length, 1);
      expect(subjectRows.first['correct'], 1);
      expect(subjectRows.first['incorrect'], 0);
      expect(subjectRows.first['selected'], 1); // 确认 selected = 1 被完整保留

      final chapterRows = await db.query('IdentityChapter', where: 'bank_id = ?', whereArgs: ['bank_test']);
      expect(chapterRows.length, 1);
      expect(chapterRows.first['correct'], 1);
      expect(chapterRows.first['incorrect'], 0);
    });
  });
}
