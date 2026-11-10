import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/durable_sync_queue.dart';
import 'package:yibubang/services/ykb_sync_service.dart';
import 'package:yibubang/services/note_service.dart';
import 'package:yibubang/common/request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory dir;
  late String previous;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('official_queue_');
    await databaseFactory.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({'loggedin': true, 'user_id': 'u'});
    db = await UserDBHelper().database;
  });
  tearDown(() async {
    DurableSyncQueue.cancelWakeups();
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  for (final body in [
    '',
    'not-json',
    '<html>gateway</html>',
    '{}',
    '[]',
    'null',
    '{"code":null}',
    '{"code":true}',
  ]) {
    test('HTTP200无有效业务确认保留队列: $body', () async {
      await db.insert('YkbSyncQueue', {
        'id': 'pending',
        'owner_user_id': 'u',
        'type': 'answer',
        'payload': '{}',
        'created_at': 1,
      });
      await http.runWithClient(
        () => YkbSyncService.instance.processQueue(),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      final row = (await db.query('YkbSyncQueue')).single;
      expect(row['retry_count'], 1);
      expect(row['last_error'], isNotNull);
      expect(row['last_response'], contains('protocol_error'));
    });
  }
  test('非200传输状态即使body业务200仍保留任务', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'pending',
      'owner_user_id': 'u',
      'type': 'answer',
      'payload': '{}',
      'created_at': 1,
    });
    await http.runWithClient(
      () => YkbSyncService.instance.processQueue(),
      () => MockClient((_) async => http.Response('{"code":"200"}', 500)),
    );
    expect(
      (await db.query('YkbSyncQueue')).single['last_response'],
      contains('http_error'),
    );
  });
  for (final code in ['200', 200]) {
    test('明确业务成功后移除任务: $code', () async {
      await db.insert('YkbSyncQueue', {
        'id': 'pending',
        'owner_user_id': 'u',
        'type': 'answer',
        'payload': '{}',
        'created_at': 1,
      });
      final body = code is int ? '{"code":200}' : '{"code":"200"}';
      await http.runWithClient(
        () => YkbSyncService.instance.processQueue(),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      expect(await db.query('YkbSyncQueue'), isEmpty);
    });
  }
  test('未知任务类型保留并记录错误', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'pending',
      'owner_user_id': 'u',
      'type': 'future_type',
      'payload': '{}',
      'created_at': 1,
    });
    await YkbSyncService.instance.processQueue();
    expect(
      (await db.query('YkbSyncQueue')).single['last_error'],
      contains('不支持'),
    );
  });
  test('第五次失败保留任务并暂停，重启保留退避，手动重试可恢复', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'fifth',
      'type': 'answer',
      'payload': '{}',
      'created_at': 1,
      'owner_user_id': 'u',
      'retry_count': 4,
    });
    await http.runWithClient(
      () => YkbSyncService.instance.processQueue(),
      () => MockClient((_) async => http.Response('failed', 500)),
    );
    final row = (await db.query('YkbSyncQueue')).single;
    expect(row['retry_count'], 5);
    expect(row['queue_state'], 'paused');
    expect(
      row['next_attempt_at'] as int,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    expect(
      (await db.query('YkbSyncQueue')).single['next_attempt_at'],
      row['next_attempt_at'],
    );
    await http.runWithClient(() async {
      expect(await YkbSyncService.instance.retryItem('fifth'), true);
    }, () => MockClient((_) async => http.Response('{"code":200}', 200)));
    expect(await db.query('YkbSyncQueue'), isEmpty);
  });
  test('后台执行期间手动重试不会重复发包', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'busy',
      'type': 'answer',
      'payload': '{}',
      'created_at': 1,
      'owner_user_id': 'u',
    });
    final entered = Completer<void>(), release = Completer<void>();
    var calls = 0;
    await http.runWithClient(
      () async {
        final running = YkbSyncService.instance.processQueue();
        await entered.future;
        expect(await YkbSyncService.instance.retryItem('busy'), false);
        release.complete();
        await running;
      },
      () => MockClient((_) async {
        calls++;
        entered.complete();
        await release.future;
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 1);
  });
  test('不同账号与无归属旧任务不会自动发送', () async {
    for (final pair in {'mine': 'u', 'other': 'v', 'legacy': ''}.entries) {
      await db.insert('YkbSyncQueue', {
        'id': pair.key,
        'type': 'answer',
        'payload': '{}',
        'created_at': 1,
        'owner_user_id': pair.value,
      });
    }
    var calls = 0;
    await http.runWithClient(
      () => YkbSyncService.instance.processQueue(),
      () => MockClient((req) async {
        calls++;
        expect(Uri.splitQueryString(req.body)['user_id'], 'u');
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 1);
    expect((await db.query('YkbSyncQueue')).map((r) => r['id']).toSet(), {
      'other',
      'legacy',
    });
  });
  test('笔记队列超过15项主动续批且失败上限保留', () async {
    final batch = db.batch();
    for (var i = 0; i < 31; i++) {
      batch.insert('NoteSyncQueue', {
        'id': 'n$i',
        'action': 'delete',
        'note_id': 'remote$i',
        'question_id': 'q',
        'payload': jsonEncode({
          'subject_id': 's',
          'identity_id': 'i',
          'app_id': '12',
        }),
        'created_at': i,
        'owner_user_id': 'u',
      });
    }
    await batch.commit(noResult: true);
    var calls = 0;
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((_) async {
        calls++;
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 31);
    expect(await db.query('NoteSyncQueue'), isEmpty);
    await db.insert('NoteSyncQueue', {
      'id': 'fail',
      'action': 'delete',
      'note_id': 'remote',
      'question_id': 'q',
      'payload': '{}',
      'created_at': 1,
      'owner_user_id': 'u',
      'retry_count': 4,
    });
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((_) async => http.Response('fail', 500)),
    );
    expect((await db.query('NoteSyncQueue')).single['queue_state'], 'paused');
  });
  test('旧队列补列后保留原任务并隔离未知账号', () async {
    final legacy = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      for (final table in ['YkbSyncQueue', 'NoteSyncQueue']) {
        await legacy.execute(
          'CREATE TABLE $table(id TEXT PRIMARY KEY,payload TEXT,created_at INTEGER,retry_count INTEGER,last_error TEXT)',
        );
        await legacy.insert(table, {
          'id': 'old',
          'payload': '{}',
          'created_at': 1,
          'retry_count': 4,
        });
      }
      await DurableSyncQueue.install(legacy);
      for (final table in ['YkbSyncQueue', 'NoteSyncQueue']) {
        final row = (await legacy.query(table)).single;
        expect(row['id'], 'old');
        expect(row['retry_count'], 4);
        expect(row['owner_user_id'], '');
        expect(row['queue_state'], 'paused');
      }
    } finally {
      await legacy.close();
    }
  });
  test('已发包但未确认的任务在重启后不自动重复提交', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'uncertain',
      'type': 'answer',
      'payload': '{}',
      'created_at': 1,
      'owner_user_id': 'u',
      'queue_state': 'sending',
    });
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    var calls = 0;
    await http.runWithClient(
      () => YkbSyncService.instance.processQueue(),
      () => MockClient((_) async {
        calls++;
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 0);
    expect((await db.query('YkbSyncQueue')).single['queue_state'], 'sending');
  });
  test('明确业务失败持久化退避，立即再触发不重复尝试', () async {
    await db.insert('YkbSyncQueue', {
      'id': 'backoff',
      'type': 'answer',
      'payload': '{}',
      'created_at': 1,
      'owner_user_id': 'u',
    });
    var calls = 0;
    await http.runWithClient(
      () async {
        await YkbSyncService.instance.processQueue();
        await YkbSyncService.instance.processQueue();
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{"code":400}', 200);
      }),
    );
    expect(calls, 1);
    final row = (await db.query('YkbSyncQueue')).single;
    expect(row['queue_state'], 'pending');
    expect(
      row['next_attempt_at'] as int,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
  });
  test('请求有总deadline且超时关闭client；账号不符在发包前拒绝', () async {
    var closed = false, called = false;
    final client = _DeadlineClient(() => closed = true);
    await http.runWithClient(() async {
      await expectLater(
        basicReq('/fixture', {}, timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()),
      );
    }, () => client);
    expect(closed, true);
    await http.runWithClient(
      () async {
        await expectLater(
          basicReq('/fixture', {}, expectedOwner: 'v'),
          throwsStateError,
        );
      },
      () => MockClient((_) async {
        called = true;
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(called, false);
  });
}

class _DeadlineClient extends http.BaseClient {
  final void Function() onClose;
  _DeadlineClient(this.onClose);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() => onClose();
}
