import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/services/ykb_sync_service.dart';

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
}
