import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:yibubang/models/question_bank.dart';
import 'package:yibubang/services/bank_export_service.dart';
import 'package:yibubang/models/bank_progress.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  final roots = BankIdentityNode.parse([{
    'identity_id': '20101', 'title': '期末', 'children': [{
      'identity_id': '201010', 'title': '大一', 'children': [{
        'identity_id': '2010101', 'title': '章节', 'category': 'chapter',
      }],
    }, {'identity_id': '201011', 'title': '大二', 'category': 'chapter'}],
  }]);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('bank-create-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  BankCreationService service({bool restricted = false}) => BankCreationService(
    request: (_, params) async => {'code': '200', 'data': [{
      'chapter_id': '37', 'title': '解剖', 'children': [{
        'chapter_id': '37000', 'title': '基础', 'count': 1,
      }],
    }]},
    fetchChapter: (entry, chapter) async => restricted
      ? const YkbChapterFetchResult(code: '203', message: '无权限')
      : const YkbChapterFetchResult(code: '200', message: '', questions: [{
          'id': 123, 'title': '共享题', 'user_answer': 'B', 'cut_question': '1',
        }]),
  );

  test('deep identities retain leaf relations and deduplicate shared questions', () async {
    final progress = <BankProgress>[];
    final file = await service().build(root: roots.single, bankId: 'custom', name: '期末', version: '1.0.0', directory: directory, onProgress: progress.add);
    final db = await openDatabase(file.path, readOnly: true);
    expect((await db.query('Identity')).length, 4);
    expect((await db.query('Question')).length, 1);
    expect((await db.query('IdentityQuestion')).map((r) => r['identity_id']).toSet(), {'2010101', '201011'});
    final meta = (await db.query('BankMeta')).single;
    expect(meta['question_count'], 1);
    expect(meta['relation_count'], 2);
    expect(meta['generated_at'] as int, lessThan(100000000000));
    expect((await db.query('Question')).single['user_answer'], '');
    expect((await db.query('Question')).single['cut_question'], '0');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(progress.last.completed, 2);
    expect(roots.single.selectedRoots({'20101', '201010'}), [roots.single]);
    await db.close();
  });

  test('restricted and cancelled creation do not leave an installable artifact', () async {
    await expectLater(service(restricted: true).build(root: roots.single, bankId: 'custom', name: '期末', version: '1.0.0', directory: directory), throwsStateError);
    expect(await directory.list().toList(), isEmpty);
    final cancellation = BankTaskCancellation()..cancelled = true;
    await expectLater(service().build(root: roots.single, bankId: 'custom', name: '期末', version: '1.0.0', directory: directory, cancellation: cancellation), throwsA(isA<BankTaskCancelled>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test('export produces a validated single bank ZIP without changing source', () async {
    final file = await service().build(root: roots.single, bankId: 'custom', name: '期末', version: '1.0.0', directory: directory);
    final db = await openDatabase(file.path);
    await db.update('Question', {'user_answer': 'B', 'cut_question': '1'});
    await db.close();
    final sourceBytes = await file.readAsBytes();
    final bank = QuestionBank.fromMap({'bank_id': 'custom', 'name': '期末', 'version': '1.0.0', 'local_path': file.path});
    final exportDirectory = await directory.createTemp('export-');
    final output = await BankExportService.prepare(bank, exportDirectory);
    final exported = await openDatabase(output.path, readOnly: true);
    expect((await exported.query('Question')).single['user_answer'], '');
    expect((await exported.query('Question')).single['cut_question'], '0');
    expect((await exported.query('IdentityQuestion')).length, 2);
    await exported.close();
    final zip = await BankExportService.zip(output, exportDirectory);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['custom.sqlite', 'manifest.json']);
    expect(await file.readAsBytes(), sourceBytes);
  });

  test('legacy export derives one standard root bank and keeps leaf relationships', () async {
    final file = await service().build(root: roots.single, bankId: 'custom', name: '期末', version: '1.0.0', directory: directory);
    final bank = QuestionBank.fromMap({'bank_id': 'legacy_combined', 'name': '合并库', 'local_path': file.path});
    final exportDirectory = await directory.createTemp('export-');
    final output = await BankExportService.prepare(bank, exportDirectory, rootId: '201010');
    final db = await openDatabase(output.path, readOnly: true);
    expect((await db.query('BankMeta')).single['bank_id'], 'legacy_201010');
    expect((await db.query('Identity')).length, 2);
    expect((await db.query('IdentityQuestion')).single['identity_id'], '2010101');
    expect((await db.query('BankMeta')).single['question_count'], 1);
    await db.close();
  });
}
