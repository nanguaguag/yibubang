import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String previous;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('db_history_');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDown(() async {
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  final fixtures =
      jsonDecode(
            File('test/fixtures/user_schema_history.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in fixtures.entries) {
    test('历史v${entry.key} (${entry.value['commit']})跳跃升级保留答案笔记并恢复约束', () async {
      final db = await openDatabase(
        p.join(dir.path, 'user_data.sqlite'),
        version: int.parse(entry.key),
        onCreate: (db, v) async {
          for (final sql in entry.value['sql'] as List) {
            await db.execute(sql as String);
          }
        },
      );
      await db.insert('Question', {
        'id': 'q',
        'status': 2,
        'user_answer': 'B',
        'collection': 1,
        'cut_question': '1',
        'chapter_id': 'c',
        'chapter_parent_id': 's',
      });
      await db.insert('Notes', {
        'id': 'n',
        'question_id': 'q',
        'content': '旧笔记',
        'imgs': '[]',
        'timestamp': 1,
      });
      await db.insert('Activities', {
        'id': 'a',
        'title': 'NewAnswer',
        'description': '旧流水',
        'timestamp': 1,
      });
      await db.close();
      final upgraded = await UserDBHelper().database;
      expect(await upgraded.getVersion(), UserDBHelper.schemaVersion);
      final q = (await upgraded.query('Question')).single;
      expect(
        [
          q['id'],
          q['status'],
          q['user_answer'],
          q['collection'],
          q['cut_question'],
        ],
        ['q', 2, 'B', 1, '1'],
      );
      expect((await upgraded.query('Notes')).single['content'], '旧笔记');
      expect((await upgraded.query('Activities')).single['description'], '旧流水');
      expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await upgraded.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      final pk = (await upgraded.rawQuery(
        'PRAGMA table_info(Question)',
      )).where((r) => (r['pk'] as int) > 0);
      expect(pk.map((r) => r['name']), ['id']);
      expect(
        (await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index'",
        )).map((r) => r['name']),
        containsAll([
          'idx_question_updated',
          'idx_notes_question',
          'idx_custom_flashcards_qid',
          'idx_activity_time_bank',
        ]),
      );
      await UserDBHelper().close();
      expect(
        (await (await UserDBHelper().database).query(
          'Notes',
        )).single['content'],
        '旧笔记',
      );
    });
  }
  test('Notes脏行自愈失败恢复ON、保留原表行，修正后可重试且修订号保留', () async {
    final db = await openDatabase(p.join(dir.path, 'dirty.sqlite'));
    try {
      await db.execute(
        'CREATE TABLE Question(id TEXT PRIMARY KEY,chapter_id TEXT,chapter_parent_id TEXT,updated_at INTEGER)',
      );
      await db.execute(
        'CREATE TABLE Notes(id TEXT PRIMARY KEY,question_id TEXT,content TEXT,imgs TEXT,timestamp INTEGER,revision INTEGER,FOREIGN KEY(question_id) REFERENCES questions(id))',
      );
      await db.insert('Notes', {
        'id': 'n',
        'question_id': 'q',
        'content': null,
        'imgs': '[]',
        'timestamp': 1,
        'revision': 7,
      });
      await db.execute('PRAGMA foreign_keys=ON');
      await expectLater(
        UserDBHelper().repairDatabaseForTesting(db),
        throwsA(anything),
      );
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect((await db.query('Notes')).single['revision'], 7);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='Notes_new'",
        ),
        isEmpty,
      );
      await db.execute('PRAGMA foreign_keys=OFF');
      await db.update('Notes', {'content': '修正'});
      await db.execute('PRAGMA foreign_keys=ON');
      await UserDBHelper().repairDatabaseForTesting(db);
      expect((await db.query('Notes')).single['revision'], 7);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
    }
  });
  test('高版本脏Notes启动拒绝开放写连接，原库可诊断修正后重开', () async {
    final db = await openDatabase(
      p.join(dir.path, 'user_data.sqlite'),
      version: 15,
      onCreate: (db, v) async {
        for (final sql in fixtures['15']['sql'] as List) {
          await db.execute(sql as String);
        }
      },
    );
    await db.execute('DROP TABLE Notes');
    await db.execute(
      'CREATE TABLE Notes(id TEXT PRIMARY KEY,question_id TEXT,content TEXT,imgs TEXT,timestamp INTEGER,FOREIGN KEY(question_id) REFERENCES questions(id))',
    );
    await db.insert('Notes', {
      'id': 'n',
      'question_id': 'q',
      'content': null,
      'imgs': '[]',
      'timestamp': 1,
    });
    await db.close();
    await expectLater(UserDBHelper().database, throwsA(anything));
    final diagnostic = await openDatabase(p.join(dir.path, 'user_data.sqlite'));
    expect((await diagnostic.query('Notes')).single['content'], null);
    await diagnostic.update('Notes', {'content': '保留修正'});
    await diagnostic.close();
    final reopened = await UserDBHelper().database;
    expect((await reopened.query('Notes')).single['content'], '保留修正');
    expect(
      (await reopened.rawQuery('PRAGMA foreign_keys')).single.values.single,
      1,
    );
  });
  test('中途升级失败事务回滚原行及DDL，重开后可重新迁移', () async {
    final db = await openDatabase(
      p.join(dir.path, 'rollback.sqlite'),
      version: 7,
      onCreate: (db, v) async {
        for (final sql in fixtures['7']['sql'] as List) {
          await db.execute(sql as String);
        }
      },
    );
    try {
      await db.insert('Question', {'id': 'q', 'status': 1, 'user_answer': 'A'});
      // 让第8版的增列失败，前面DDL/数据变更须全部回滚。
      await db.execute('DROP TABLE Notes');
      await expectLater(
        UserDBHelper().upgradeForTesting(
          db,
          7,
          newVersion: UserDBHelper.schemaVersion,
        ),
        throwsA(anything),
      );
      expect((await db.query('Question')).single['user_answer'], 'A');
      expect(await db.getVersion(), 7);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='NoteSyncQueue'",
        ),
        isEmpty,
      );
      final noteSql =
          (fixtures['7']['sql'] as List).firstWhere(
                (sql) => (sql as String).contains(
                  'CREATE TABLE IF NOT EXISTS Notes',
                ),
              )
              as String;
      await db.execute(noteSql);
      await UserDBHelper().upgradeForTesting(
        db,
        7,
        newVersion: UserDBHelper.schemaVersion,
      );
      expect((await db.query('Question')).single['user_answer'], 'A');
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='CloudDeletedActivities'",
        ),
        isNotEmpty,
      );
    } finally {
      await db.close();
    }
  });
  test('已有闪卡关联列但丢索引，重复自愈补齐索引', () async {
    final db = await openDatabase(p.join(dir.path, 'index.sqlite'));
    try {
      await db.execute(
        'CREATE TABLE CustomFlashcards(id TEXT PRIMARY KEY,question_id TEXT)',
      );
      await UserDBHelper().repairDatabaseForTesting(db);
      await UserDBHelper().repairDatabaseForTesting(db);
      expect(
        (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='idx_custom_flashcards_qid'",
        )).length,
        1,
      );
    } finally {
      await db.close();
    }
  });
}
