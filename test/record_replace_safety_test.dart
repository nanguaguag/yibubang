import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/record_sync_service.dart';

Uint8List zipDatabase(List<int> bytes) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()..addFile(ArchiveFile('user_data.sqlite', bytes.length, bytes)),
  )!,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String previous, path;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('record_replace_');
    await databaseFactory.setDatabasesPath(dir.path);
    path = p.join(dir.path, 'user_data.sqlite');
    final db = await UserDBHelper().database;
    await db.insert('Question', {'id': 'old', 'status': 1, 'user_answer': 'A'});
    await db.insert('Notes', {
      'id': 'note',
      'question_id': 'old',
      'content': '保留',
      'imgs': '[]',
      'timestamp': 1,
    });
  });
  tearDown(() async {
    RecordSyncService.beforeReplacementOpenForTesting = null;
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  Future<Uint8List> source() async {
    await UserDBHelper().close();
    final db = await openDatabase(path);
    await db.update('Question', {'user_answer': 'B'});
    await db.close();
    final bytes = await File(path).readAsBytes();
    final live = await UserDBHelper().database;
    await live.update('Question', {'user_answer': 'A'});
    return zipDatabase(bytes);
  }

  test('坏SQLite及题库冒充用户库被拒绝，原答案与笔记完整保留', () async {
    await expectLater(
      RecordSyncService.importReplace(zipDatabase([1, 2, 3])),
      throwsA(anything),
    );
    final fakePath = p.join(dir.path, 'fake.sqlite');
    final fake = await openDatabase(
      fakePath,
      version: 1,
      onCreate: (db, v) =>
          db.execute('CREATE TABLE Question(id TEXT PRIMARY KEY,title TEXT)'),
    );
    await fake.close();
    await expectLater(
      RecordSyncService.importReplace(
        zipDatabase(await File(fakePath).readAsBytes()),
      ),
      throwsFormatException,
    );
    final db = await UserDBHelper().database;
    expect((await db.query('Question')).single['user_answer'], 'A');
    expect((await db.query('Notes')).single['content'], '保留');
    expect(await db.rawQuery('PRAGMA integrity_check'), [
      {'integrity_check': 'ok'},
    ]);
  });
  test('有效替换备份包含最新WAL答案，开库失败恢复原库', () async {
    final bytes = await source();
    RecordSyncService.beforeReplacementOpenForTesting = () async =>
        throw StateError('模拟开库失败');
    await expectLater(RecordSyncService.importReplace(bytes), throwsStateError);
    var db = await UserDBHelper().database;
    expect((await db.query('Question')).single['user_answer'], 'A');
    RecordSyncService.beforeReplacementOpenForTesting = null;
    expect(await RecordSyncService.importReplace(bytes), true);
    db = await UserDBHelper().database;
    expect((await db.query('Question')).single['user_answer'], 'B');
    final backup = await openDatabase(
      '$path.backup',
      readOnly: true,
      singleInstance: false,
    );
    expect((await backup.query('Question')).single['user_answer'], 'A');
    await backup.close();
    expect(await File('$path.replace.json').exists(), false);
  });
  test('进程中断遗留替换日志在首次开库前恢复，恢复可重复运行', () async {
    await UserDBHelper().close();
    await File(path).copy('$path.backup');
    await File(
      '$path.replace.json',
    ).writeAsString(jsonEncode({'had_original': true}), flush: true);
    await File(path).writeAsBytes([1, 2, 3], flush: true);
    var db = await UserDBHelper().database;
    expect((await db.query('Question')).single['user_answer'], 'A');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    expect((await db.query('Notes')).single['content'], '保留');
  });
}
