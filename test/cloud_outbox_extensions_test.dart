import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/cloud_outbox.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CloudOutbox 扩展数据同步测试 (卡片、记忆曲线、复习计划)', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      // 创建业务表
      await db.execute('''CREATE TABLE CustomFlashcards (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        question_id TEXT,
        tags TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');

      await db.execute('''CREATE TABLE SpacedReviewItem (
        item_id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL DEFAULT '',
        item_type INTEGER NOT NULL DEFAULT 0,
        state INTEGER NOT NULL DEFAULT 0,
        step INTEGER NOT NULL DEFAULT 0,
        reps INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        difficulty REAL NOT NULL DEFAULT 0,
        stability REAL NOT NULL DEFAULT 0,
        due_date INTEGER NOT NULL DEFAULT 0,
        last_review_at INTEGER NOT NULL DEFAULT 0,
        extra TEXT
      )''');

      await db.execute('''CREATE TABLE ReviewPlans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        bank_id TEXT,
        daily_new_target INTEGER NOT NULL DEFAULT 20,
        daily_review_limit INTEGER NOT NULL DEFAULT 50,
        source_types TEXT NOT NULL DEFAULT '["wrong","collected","note"]',
        covered_subjects TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');

      await db.execute('''CREATE TABLE Question (
        id TEXT PRIMARY KEY,
        chapter_id TEXT,
        chapter_parent_id TEXT,
        cut_question TEXT DEFAULT '0',
        user_answer TEXT,
        status INTEGER DEFAULT 0,
        collection INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0
      )''');

      await db.execute('''CREATE TABLE Activities (
        id TEXT PRIMARY KEY,
        timestamp INTEGER,
        bank_id TEXT,
        question_id TEXT,
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        is_right TEXT,
        duration INTEGER DEFAULT 0,
        title TEXT DEFAULT 'NewAnswer',
        description TEXT DEFAULT ''
      )''');

      await db.execute('''CREATE TABLE Notes (
        id TEXT PRIMARY KEY,
        remote_id TEXT,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 0
      )''');

      await CloudOutbox.install(db);
      await CloudOutbox.bind(db, 'user_test_ext');
    });

    tearDown(() async {
      await db.close();
    });

    test('插入闪卡自动写入 CloudOutbox 并正确打包 mutation', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('CustomFlashcards', {
        'id': 'fc_001',
        'title': '闪卡测试',
        'front': '问题',
        'back': '答案',
        'question_id': 'q_100',
        'tags': '标签1',
        'created_at': now,
        'updated_at': now,
      });

      final outbox = await CloudOutbox.snapshot(db, 'user_test_ext');
      final fcItem = outbox.firstWhere((e) => e['kind'] == 'flashcard');
      expect(fcItem['entity_id'], 'fc_001');

      final mutation = await CloudOutbox.mutation(db, fcItem);
      expect(mutation['kind'], 'flashcard');
      final payload = mutation['payload'] as Map<String, dynamic>;
      expect(payload['title'], '闪卡测试');
      expect(payload['front'], '问题');
      expect(payload['back'], '答案');
    });

    test('删除闪卡自动生成 flashcard_delete 墓碑', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('CustomFlashcards', {
        'id': 'fc_del',
        'title': '待删除',
        'front': 'A',
        'back': 'B',
        'created_at': now,
        'updated_at': now,
      });

      await db.delete('CustomFlashcards', where: 'id=?', whereArgs: ['fc_del']);

      final outbox = await CloudOutbox.snapshot(db, 'user_test_ext');
      expect(outbox.any((e) => e['kind'] == 'flashcard'), isFalse);
      expect(outbox.any((e) => e['kind'] == 'flashcard_delete' && e['entity_id'] == 'fc_del'), isTrue);
    });

    test('更新记忆曲线状态与复习计划自动写入 CloudOutbox', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('SpacedReviewItem', {
        'item_id': 'q_review_1',
        'plan_id': 'plan_test',
        'item_type': 0,
        'state': 2, // review
        'step': 1,
        'reps': 3,
        'lapses': 0,
        'difficulty': 3.2,
        'stability': 5.0,
        'due_date': now + 100000,
        'last_review_at': now,
      });

      await db.insert('ReviewPlans', {
        'id': 'plan_test',
        'name': '冲刺计划',
        'bank_id': 'dental_final',
        'daily_new_target': 25,
        'daily_review_limit': 60,
        'source_types': '["wrong"]',
        'covered_subjects': '[]',
        'created_at': now,
        'updated_at': now,
      });

      final outbox = await CloudOutbox.snapshot(db, 'user_test_ext');
      expect(outbox.any((e) => e['kind'] == 'spaced_item' && e['entity_id'] == 'q_review_1'), isTrue);
      expect(outbox.any((e) => e['kind'] == 'review_plan' && e['entity_id'] == 'plan_test'), isTrue);
    });

    test('mergePage 正常合并云端下发的闪卡、记忆项和计划', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final serverPage = {
        'next_cursor': 10,
        'high_watermark': 10,
        'has_more': false,
        'pull_deleted_activities': <String>[],
        'pull_activities': <Map<String, dynamic>>[],
        'pull_questions': <Map<String, dynamic>>[],
        'pull_deleted_flashcards': ['fc_remote_del'],
        'pull_flashcards': [
          {
            'id': 'fc_remote_1',
            'title': '云端下发闪卡',
            'front': '云前',
            'back': '云后',
            'question_id': null,
            'tags': '云标签',
            'created_at': now,
            'updated_at': now,
          }
        ],
        'pull_spaced_items': [
          {
            'item_id': 'fc_remote_1',
            'plan_id': 'plan_remote',
            'item_type': 1,
            'state': 1,
            'step': 0,
            'reps': 1,
            'lapses': 0,
            'difficulty': 5.0,
            'stability': 1.0,
            'due_date': now + 86400000,
            'last_review_at': now,
          }
        ],
        'pull_review_plans': [
          {
            'id': 'plan_remote',
            'name': '云端计划',
            'bank_id': 'clinical_final',
            'daily_new_target': 15,
            'daily_review_limit': 45,
            'source_types': '["all"]',
            'covered_subjects': '[]',
            'created_at': now,
            'updated_at': now,
          }
        ]
      };

      await CloudOutbox.mergePage(db, 'user_test_ext', serverPage, 0);

      final cards = await db.query('CustomFlashcards', where: 'id=?', whereArgs: ['fc_remote_1']);
      expect(cards.length, 1);
      expect(cards.first['title'], '云端下发闪卡');

      final items = await db.query('SpacedReviewItem', where: 'item_id=?', whereArgs: ['fc_remote_1']);
      expect(items.length, 1);
      expect(items.first['plan_id'], 'plan_remote');

      final plans = await db.query('ReviewPlans', where: 'id=?', whereArgs: ['plan_remote']);
      expect(plans.length, 1);
      expect(plans.first['name'], '云端计划');
    });

    test('笔记新增、编辑、删除与云端拉取合并完整闭环', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('Question', {'id': 'q_note_1'});
      await db.insert('Notes', {
        'id': 'local_n1',
        'remote_id': 'r_100',
        'question_id': 'q_note_1',
        'content': '本地笔记内容',
        'imgs': '[]',
        'timestamp': now,
        'updated_at': now,
        'sync_status': 0,
      });

      var outbox = await CloudOutbox.snapshot(db, 'user_test_ext');
      final noteItem = outbox.firstWhere((e) => e['kind'] == 'note');
      expect(noteItem['entity_id'], 'local_n1');
      final mut = await CloudOutbox.mutation(db, noteItem);
      expect((mut['payload'] as Map)['content'], '本地笔记内容');

      // 删除笔记产生 note_delete 墓碑
      await db.delete('Notes', where: 'id=?', whereArgs: ['local_n1']);
      outbox = await CloudOutbox.snapshot(db, 'user_test_ext');
      expect(outbox.any((e) => e['kind'] == 'note'), isFalse);
      expect(
        outbox.any(
          (e) => e['kind'] == 'note_delete' && e['entity_id'] == 'local_n1',
        ),
        isTrue,
      );

      // 合并远端笔记（已删除的 local_n1 不会复活，新笔记 remote_n2 正常入库并自动补齐外键 Question）
      await CloudOutbox.mergePage(db, 'user_test_ext', {
        'next_cursor': 20,
        'high_watermark': 20,
        'has_more': false,
        'pull_deleted_activities': <String>[],
        'pull_activities': <Map<String, dynamic>>[],
        'pull_questions': <Map<String, dynamic>>[],
        'pull_notes': [
          {
            'id': 'local_n1',
            'remote_id': 'r_100',
            'question_id': 'q_note_1',
            'content': '旧笔记不应复活',
            'imgs': '[]',
            'timestamp': now,
            'updated_at': now,
          },
          {
            'id': 'remote_n2',
            'remote_id': 'r_200',
            'question_id': 'q_new_from_cloud',
            'content': '云端同步过来的新笔记',
            'imgs': '[]',
            'timestamp': now + 100,
            'updated_at': now + 100,
          },
        ],
        'pull_deleted_notes': <String>[],
      }, 0);

      final notes = await db.query('Notes');
      expect(notes.map((n) => n['id']).toList(), ['remote_n2']);
      expect(notes.single['content'], '云端同步过来的新笔记');
    });
  });
}
