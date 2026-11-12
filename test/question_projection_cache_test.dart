import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/data_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String previousPath;
  late String bankPath;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousPath = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('projection_cache_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await UserDBHelper().database;
    bankPath = p.join(dir.path, "bank's.sqlite");
    final fixture = await openDatabase(bankPath);
    await fixture.execute(
      'CREATE TABLE IdentityQuestion(question_id TEXT,identity_id TEXT,subject_id TEXT,chapter_id TEXT)',
    );
    await fixture.transaction((tx) async {
      final batch = tx.batch();
      for (var i = 0; i < 1000; i++) {
        batch.insert('IdentityQuestion', {
          'question_id': 'q$i',
          'identity_id': 'i',
          'subject_id': 's',
          'chapter_id': 'c',
        });
      }
      await batch.commit(noResult: true);
    });
    await fixture.close();
    await db.insert('Question', {'id': 'q0', 'status': 1});
  });
  tearDown(() async {
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await dir.delete(recursive: true);
  });

  Future<int> changes() async =>
      (await db.rawQuery('SELECT total_changes()')).single.values.single as int;
  Future<Object?> stamp() async => (await db.query(
    'QuestionProjectionState',
    where: 'bank_id=?',
    whereArgs: ['b'],
  )).single['source_stamp'];
  Future<void> counts(int correct, int incorrect, {String bankId = 'b'}) async {
    for (final table in ['IdentitySubject', 'IdentityChapter']) {
      final row = (await db.query(
        table,
        where: 'bank_id=?',
        whereArgs: [bankId],
      )).single;
      expect([row['correct'], row['incorrect']], [correct, incorrect]);
    }
  }

  Future<void> rebuild() async {
    await db.execute('ATTACH DATABASE ? AS cache_test_bank', [bankPath]);
    try {
      await db.transaction(
        (tx) => rebuildAttachedQuestionCount(tx, 'b', alias: 'cache_test_bank'),
      );
    } finally {
      await db.execute('DETACH DATABASE cache_test_bank');
    }
  }

  test('同文件原路径及真实路径十次热读取无写入，题库字节不变', () async {
    final hash = sha256.convert(await File(bankPath).readAsBytes());
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    final before = await changes();
    for (var i = 0; i < 10; i++) {
      await ensureQuestionCountProjection(
        'b',
        bankPath: i.isEven
            ? bankPath
            : await File(bankPath).resolveSymbolicLinks(),
      );
    }
    expect(await changes(), before);
    expect((await db.query('QuestionRelations')).length, 1000);
    await counts(1, 0);
    expect(sha256.convert(await File(bankPath).readAsBytes()), hash);
  });

  test(
    '符号链接与真实文件共享投影指纹',
    () async {
      final alias = Link(p.join(dir.path, 'bank_alias.sqlite'));
      await alias.create(bankPath);
      await ensureQuestionCountProjection('b', bankPath: alias.path);
      final before = await changes();
      final stored = await stamp();
      await ensureQuestionCountProjection('b', bankPath: bankPath);
      await ensureQuestionCountProjection('b', bankPath: alias.path);
      expect(await changes(), before);
      expect(await stamp(), stored);
      await counts(1, 0);
    },
    skip: Platform.isWindows ? 'Windows创建符号链接需额外系统权限，原/真实路径测试仍运行' : false,
  );

  test('历史路径指纹只重建一次且保留选课及全局题状态', () async {
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    await db.update('IdentitySubject', {'selected': 1});
    await db.update('QuestionProjectionState', {
      'source_stamp': 'legacy_alias_stamp',
    });
    final before = await changes();
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    expect(await changes(), greaterThan(before));
    final after = await changes();
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    expect(await changes(), after);
    expect((await db.query('IdentitySubject')).single['selected'], 1);
    expect((await db.query('Question')).single['status'], 1);
    await counts(1, 0);
  });

  test('文件修改仍使缓存失效并按新关系重建', () async {
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    final previous = await stamp();
    final fixture = await openDatabase(bankPath);
    await fixture.delete(
      'IdentityQuestion',
      where: 'question_id=?',
      whereArgs: ['q0'],
    );
    await fixture.close();
    final stat = await File(bankPath).stat();
    await File(
      bankPath,
    ).setLastModified(stat.modified.add(const Duration(seconds: 2)));
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    expect(await stamp(), isNot(previous));
    expect((await db.query('QuestionRelations')).length, 999);
    await counts(0, 0);
    expect((await db.query('Question')).single['status'], 1);
  });

  test('显式重算继续修正统计，热读取后触发器继续跨库共享', () async {
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    await ensureQuestionCountProjection('b2', bankPath: bankPath);
    await db.update(
      'IdentitySubject',
      {'correct': 999},
      where: 'bank_id=?',
      whereArgs: ['b'],
    );
    await rebuild();
    await counts(1, 0);
    final before = await changes();
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    expect(await changes(), before);
    await db.update(
      'Question',
      {'status': 2},
      where: 'id=?',
      whereArgs: ['q0'],
    );
    await counts(0, 1);
    await counts(0, 1, bankId: 'b2');
    expect((await db.query('Question')).length, 1);
  });

  test('路径失效明确报错且旧投影与用户状态不受破坏', () async {
    await ensureQuestionCountProjection('b', bankPath: bankPath);
    final previous = await stamp();
    await File(bankPath).delete();
    await expectLater(
      ensureQuestionCountProjection('b', bankPath: bankPath),
      throwsA(isA<FileSystemException>()),
    );
    expect(await stamp(), previous);
    await counts(1, 0);
    expect(
      (await db.rawQuery(
        'PRAGMA database_list',
      )).any((r) => r['name'] == 'projection_bank'),
      false,
    );
  });
}
