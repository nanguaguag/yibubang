import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/services/ykb_bank_smart_sync_service.dart';

void main() {
  sqfliteFfiInit();
  final service = YkbBankSmartSyncService.instance;
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE Question (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE IdentityQuestion (identity_id TEXT, question_id TEXT, chapter_id TEXT)',
    );
  });
  tearDown(() => db.close());

  test(
    'ID drift maps heart chapter by title instead of replacing kidney',
    () async {
      final mapping = await service.mappingForTesting(
        db: db,
        remote: {'id': '45011', 'title': '第十一章 肾', 'subjectId': 's'},
        local: [
          {'id': '45011', 'name': '心血管系统', 'subjectId': 's'},
          {'id': '45020', 'name': '第20章 肾', 'subjectId': 's'},
        ],
      );
      expect(mapping, {'id': '45020', 'method': 'title'});
    },
  );
  test('unmatched reused ID creates isolated chapter', () async {
    final mapping = await service.mappingForTesting(
      db: db,
      remote: {'id': '45011', 'title': '肾'},
      local: [
        {'id': '45011', 'name': '心血管系统'},
      ],
    );
    expect(mapping['method'], 'new');
    expect(mapping['id'], startsWith('ykb_45011_'));
  });
  test('saved mapping survives remote title changes', () async {
    final mapping = await service.mappingForTesting(
      db: db,
      remote: {'id': 'remote', 'title': '新标题'},
      local: [
        {'id': 'local', 'name': '旧标题'},
      ],
      state: {'local_chapter_id': 'local'},
    );
    expect(mapping, {'id': 'local', 'method': 'state'});
  });
  test('question overlap recovers renamed chapters', () async {
    for (var i = 0; i < 5; i++) {
      await db.insert('Question', {'id': '$i'});
      await db.insert('IdentityQuestion', {
        'identity_id': 'bank',
        'question_id': '$i',
        'chapter_id': 'local',
      });
    }
    final mapping = await service.mappingForTesting(
      db: db,
      remote: {'id': 'remote', 'title': '新标题', 'count': 5},
      local: [
        {'id': 'local', 'name': '旧内容', 'total': 5},
      ],
      questions: List.generate(5, (i) => {'id': '$i'}),
    );
    expect(mapping, {'id': 'local', 'method': 'overlap'});
  });
  test('content hash ignores answer state and mapping but detects edits', () {
    final first = service.contentHashForTesting({
      'title': '内容',
      'id': '1',
      'user_answer': 'A',
      'chapter_id': 'old',
    });
    expect(
      service.contentHashForTesting({
        'id': '1',
        'chapter_id': 'new',
        'title': '内容',
        'user_answer': 'B',
      }),
      first,
    );
    expect(
      service.contentHashForTesting({'id': '1', 'title': '更新内容'}),
      isNot(first),
    );
  });
  test('pending chapters preserve order and metadata across restart', () {
    final chapters = [
      {'id': '2', 'identityId': '201011', 'title': '肾', 'count': 32},
      {'id': '1', 'identityId': '201010', 'title': '心脏', 'count': 10},
    ];
    final restored = service.pendingForTesting(jsonEncode(chapters));
    expect(restored.map((c) => c['id']), ['2', '1']);
    expect(restored.first['identityId'], '201011');
    expect(restored.first['count'], 32);
    expect(service.pendingForTesting(jsonEncode(restored)), restored);
  });
  test('corrupt pending state can recover through a fresh manifest', () {
    expect(service.pendingForTesting('{broken'), isEmpty);
    expect(service.pendingForTesting('{}'), isEmpty);
  });
  for (final version in [9, 10]) {
    test(
      'v$version upgrades queues before v11 without losing user records',
      () async {
        await db.insert('Question', {'id': 'answered'});
        for (final table in ['NoteSyncQueue', 'YkbSyncQueue']) {
          await db.execute(
            'CREATE TABLE $table (id TEXT PRIMARY KEY${version == 10 ? ', last_response TEXT' : ''})',
          );
          await db.insert(table, {'id': 'queued'});
        }
        await UserDBHelper().upgradeForTesting(db, version);
        expect(await db.query('Question'), [
          {'id': 'answered'},
        ]);
        for (final table in ['NoteSyncQueue', 'YkbSyncQueue']) {
          expect(
            (await db.rawQuery(
              'PRAGMA table_info($table)',
            )).map((r) => r['name']),
            contains('last_response'),
          );
          expect((await db.query(table)).single['id'], 'queued');
        }
        await db.insert('YkbBankSyncState', {
          'bank_id': 'bank',
          'pending_json': '[1]',
        });
        await db.insert('YkbBankChapterState', {
          'bank_id': 'bank',
          'remote_chapter_id': 'c',
        });
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  test('onConfigure pragma configuration succeeds with rawQuery', () async {
    // 验证 PRAGMA journal_mode 和 foreign_keys 在 rawQuery 下正常执行不抛异常
    final wal = await db.rawQuery('PRAGMA journal_mode = WAL');
    expect(wal, isNotEmpty);
    final fk = await db.rawQuery('PRAGMA foreign_keys = ON');
    expect(fk, isEmpty);
  });
}
