import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/user_database_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database db;
  late String previous;
  final coordinator = UserDatabaseCoordinator.instance;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('db_gate_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await UserDBHelper().database;
  });
  tearDown(() async {
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  test('并行ATTACH临界区互斥，失败也DETACH并释放锁', () async {
    final path = p.join(dir.path, "bank's.sqlite");
    final fixture = await openDatabase(path);
    await fixture.execute('CREATE TABLE Item(id TEXT)');
    await fixture.close();
    Future<void> attach(bool fail) => coordinator.run(() async {
      await db.execute('ATTACH DATABASE ? AS bank', [path]);
      try {
        await db.transaction((tx) async {
          await tx.rawQuery('SELECT * FROM bank.Item');
          if (fail) throw StateError('abort');
        });
      } finally {
        await db.execute('DETACH DATABASE bank');
      }
    });
    final first = attach(true);
    final second = attach(false);
    await expectLater(first, throwsStateError);
    await second;
    expect(
      (await db.rawQuery(
        'PRAGMA database_list',
      )).any((r) => r['name'] == 'bank'),
      false,
    );
    expect(
      (await db.rawQuery('PRAGMA busy_timeout')).single.values.single,
      10000,
    );
  });
  test('缓存连接和batch写入等待维护，维护内可嵌套而不死锁', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final maintenance = coordinator.run(() async {
      entered.complete();
      await release.future;
      await db.rawQuery('SELECT 1');
    });
    await entered.future;
    var written = false;
    final batch = db.batch()..insert('Question', {'id': 'q'});
    final write = batch.commit().then((_) => written = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(written, false);
    release.complete();
    await maintenance;
    await write;
    expect((await db.query('Question')).single['id'], 'q');
  });
  test('维护关闭后旧句柄明确拒绝写入，开库请求恢复新连接', () async {
    await coordinator.run(() => UserDBHelper().close());
    await expectLater(db.insert('Question', {'id': 'old'}), throwsStateError);
    db = await UserDBHelper().database;
    await db.insert('Question', {'id': 'new'});
    expect(await db.getVersion(), 19);
  });
}
