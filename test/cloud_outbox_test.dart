import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/cloud_outbox.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/services/cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database db;
  late String previous;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
    SharedPreferences.setMockInitialValues({
      'cloud_sync_enabled': true,
      'cloud_sync_user_id': 'u',
      'cloud_sync_device_token': 't',
    });
    await CloudSyncService.instance.init();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cloud_outbox_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await UserDBHelper().database;
    await CloudSyncService.instance.resetSyncCursor();
  });
  tearDown(() async {
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  http.Response response(
    Map<String, dynamic> body, {
    List<Map<String, Object?>> questions = const [],
  }) => http.Response(
    jsonEncode({
      'data': {
        'protocol': 2,
        'server_time': 9999999999,
        'next_cursor': (body['pull_cursor'] as int? ?? 0) + 1,
        'high_watermark': (body['pull_cursor'] as int? ?? 0) + 1,
        'has_more': false,
        'accepted_seqs': (body['mutations'] as List)
            .map((m) => m['seq'])
            .toList(),
        'pull_questions': questions,
        'pull_activities': [],
      },
    }),
    200,
  );

  test('同步期间变更、慢时钟与补录流水都按序号上传', () async {
    await db.insert('Question', {
      'id': 'q',
      'status': 1,
      'user_answer': 'A',
      'updated_at': 100,
    });
    final sent = <List<dynamic>>[];
    var calls = 0;
    await http.runWithClient(
      () async {
        expect((await CloudSyncService.instance.sync()).success, true);
        expect((await CloudSyncService.instance.sync()).success, true);
      },
      () => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        sent.add(body['mutations'] as List);
        if (calls++ == 0) {
          await db.update('Question', {
            'user_answer': 'B',
            'status': 2,
            'updated_at': 1,
          }, where: "id='q'");
          await db.insert('Activities', {
            'id': 'old',
            'title': 'NewAnswer',
            'description': '',
            'timestamp': 1,
            'is_right': '0',
          });
        }
        return response(body);
      }),
    );
    expect(sent[0].length, 1);
    expect(sent[1].length, 2);
    expect((sent[1][0]['payload'] as Map)['user_answer'], 'B');
    expect((sent[1][1]['payload'] as Map)['timestamp'], 1);
    expect(await db.query('CloudOutbox'), isEmpty);
  });
  test('收藏只上传收藏字段，下载保护同期未确认答案且不会回传', () async {
    await db.insert('Question', {
      'id': 'q',
      'status': 1,
      'user_answer': 'A',
      'updated_at': 100,
    });
    await CloudOutbox.bind(db, 'u');
    await db.delete('CloudOutbox');
    await db.update('Question', {
      'collection': 1,
      'updated_at': 101,
    }, where: "id='q'");
    await http.runWithClient(
      () async {
        expect((await CloudSyncService.instance.sync()).success, true);
      },
      () => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final payload = (body['mutations'] as List).single['payload'] as Map;
        expect(payload.keys.toSet(), {'collection', 'updated_at'});
        await db.update('Question', {
          'user_answer': 'B',
          'status': 2,
          'updated_at': 1,
        }, where: "id='q'");
        return response(
          body,
          questions: [
            {
              'id': 'q',
              'user_answer': 'C',
              'status': 1,
              'collection': 1,
              'updated_at': 1000,
            },
          ],
        );
      }),
    );
    expect((await db.query('Question')).single['user_answer'], 'B');
    expect((await db.query('CloudOutbox')).length, 1);
  });
  test('事务回滚同时回滚变更，进程重开后保留待上传序号', () async {
    await expectLater(
      db.transaction((tx) async {
        await tx.insert('Question', {'id': 'rollback', 'status': 1});
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(await db.query('CloudOutbox'), isEmpty);
    await db.insert('Question', {'id': 'kept', 'collection': 1});
    final before = await db.query('CloudOutbox');
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    expect(await db.query('CloudOutbox'), before);
  });
  test('v15升级至当前schema保留原答案并引导首次上传', () async {
    for (final name in [
      'cloud_question_insert',
      'cloud_question_update',
      'cloud_activity_insert',
    ]) {
      await db.execute('DROP TRIGGER $name');
    }
    for (final table in [
      'CloudOutbox',
      'CloudSyncAccounts',
      'CloudSyncContext',
    ]) {
      await db.execute('DROP TABLE $table');
    }
    await db.setVersion(15);
    await db.insert('Question', {
      'id': 'legacy',
      'status': 2,
      'user_answer': 'B',
      'updated_at': 1,
    });
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    expect(await db.getVersion(), 19);
    await CloudOutbox.bind(db, 'u');
    expect((await db.query('Question')).single['user_answer'], 'B');
    expect((await db.query('CloudOutbox')).single['entity_id'], 'legacy');
  });
  test('分页中断后从已落库游标续传，坏页不会推进游标', () async {
    final requested = <int>[];
    var fail = true;
    await http.runWithClient(
      () async {
        expect((await CloudSyncService.instance.sync()).success, false);
        expect(await CloudOutbox.pullCursor(db, 'u'), 500);
        expect((await db.query('Question')).length, 1);
        fail = false;
        expect((await CloudSyncService.instance.sync()).success, true);
        expect(await CloudOutbox.pullCursor(db, 'u'), 501);
      },
      () => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final cursor = body['pull_cursor'] as int;
        requested.add(cursor);
        if (cursor == 500 && fail) return http.Response('failure', 500);
        return http.Response(
          jsonEncode({
            'data': {
              'protocol': 2,
              'accepted_seqs': [],
              'server_time': 1000,
              'next_cursor': cursor == 0 ? 500 : 501,
              'high_watermark': 501,
              'has_more': cursor == 0,
              'pull_questions': [
                {'id': cursor == 0 ? 'first' : 'last', 'status': 1},
              ],
              'pull_activities': [],
            },
          }),
          200,
        );
      }),
    );
    expect(requested, [0, 500, 500]);
    await expectLater(
      CloudOutbox.mergePage(db, 'u', {
        'next_cursor': 502,
        'high_watermark': 502,
        'has_more': false,
        'pull_questions': [
          {'id': 'bad', 'status': null},
        ],
        'pull_activities': [],
      }, 501),
      throwsA(isA<DatabaseException>()),
    );
    expect(await CloudOutbox.pullCursor(db, 'u'), 501);
    expect(await db.query('Question', where: "id='bad'"), isEmpty);
    expect((await db.query('CloudSyncContext')).single['applying'], 0);
  });
  test('501项第二片失败后重启只重传未确认1项，空增量不重传历史', () async {
    final batch = db.batch();
    for (var i = 0; i < 501; i++) {
      batch.insert('Question', {'id': 'q$i', 'status': 1});
    }
    await batch.commit(noResult: true);
    final lengths = <int>[];
    var calls = 0;
    await http.runWithClient(
      () async {
        expect((await CloudSyncService.instance.sync()).success, false);
        expect((await db.query('CloudOutbox')).length, 1);
        await UserDBHelper().close();
        db = await UserDBHelper().database;
        expect((await CloudSyncService.instance.sync()).success, true);
        expect((await CloudSyncService.instance.sync()).success, true);
      },
      () => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        lengths.add((body['mutations'] as List).length);
        if (++calls == 2) return http.Response('failed', 500);
        return response(body);
      }),
    );
    expect(lengths, [500, 1, 1, 0]);
  });
  test('旧服务端或缺少明确确认时保留队列', () async {
    await db.insert('Question', {'id': 'q', 'status': 1});
    await http.runWithClient(
      () async {
        expect((await CloudSyncService.instance.sync()).success, false);
      },
      () => MockClient(
        (req) async => http.Response('{"data":{"server_time":200}}', 200),
      ),
    );
    expect((await db.query('CloudOutbox')).length, 1);
  });
}
