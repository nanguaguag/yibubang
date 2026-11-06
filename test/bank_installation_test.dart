import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/question_bank_file_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  final repository = QuestionBankRepository();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('bank-install-test-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'databases'));
  });
  tearDown(() async {
    await DatabaseHelper().close();
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  Future<File> artifact(String version, List<String> ids) async {
    final target = await directory.createTemp('artifact-');
    return BankCreationService(
      request: (_, __) async => {'code': 200, 'data': [{
        'chapter_id': 's', 'children': [{'chapter_id': 'c', 'count': ids.length}],
      }]},
      fetchChapter: (_, __) async => YkbChapterFetchResult(code: '200', message: '',
        questions: ids.map((id) => <String, dynamic>{'id': id, 'title': id}).toList()),
    ).build(root: BankIdentityNode({'identity_id': '38', 'title': '医学'}, []),
      bankId: 'fixture', name: '医学', version: version, directory: target);
  }

  test('installation shares global answers, recounts with ATTACH and records actual new IDs', () async {
    final userDb = await UserDBHelper().database;
    await userDb.insert('Question', {'id': '1', 'status': 1, 'user_answer': 'A'});
    final first = await artifact('1.0.0', ['1', '2']);
    await repository.importFile(first.path);
    final next = await artifact('1.0.1', ['1', '3']);
    await repository.importFile(next.path);
    final history = await repository.history('fixture');
    expect(history.first['added'], 1);
    expect(history.first['question_count'], 2);
    expect(history.length, 2);
    expect((await userDb.query('Question')).single['user_answer'], 'A');
    expect((await userDb.query('IdentitySubject')).single['correct'], 1);
    expect((await userDb.rawQuery('PRAGMA database_list')).any((r) => r['name'] == 'install_bank'), isFalse);
  });

  test('history failure rolls back file, catalog, counts and history together', () async {
    final first = await artifact('1.0.0', ['1']);
    final installed = await repository.importFile(first.path);
    final bytes = await File(installed.localPath).readAsBytes();
    final userDb = await UserDBHelper().database;
    await userDb.execute("CREATE TRIGGER reject_history BEFORE INSERT ON BankHistory BEGIN SELECT RAISE(ABORT, 'injected failure'); END");
    final next = await artifact('1.0.1', ['2', '3']);
    await expectLater(repository.importFile(next.path), throwsA(isA<DatabaseException>()));
    expect(await File(installed.localPath).readAsBytes(), bytes);
    expect((await repository.find('fixture'))!.version, '1.0.0');
    expect((await repository.history('fixture')).length, 1);
  });

  test('conflict choice reserves installation and cancelling releases the lock', () async {
    final first = await artifact('1.0.0', ['1']);
    await repository.importFile(first.path);
    final choice = Completer<BankImportMode?>();
    final shown = Completer<void>();
    final pending = repository.importFile(first.path, onConflict: (_) {
      shown.complete();
      return choice.future;
    });
    final cancelled = expectLater(pending, throwsA(isA<BankImportCancelled>()));
    await shown.future;
    await expectLater(repository.importFile(first.path), throwsStateError);
    choice.complete(null);
    await cancelled;
    await repository.importFile(first.path);
  });

  test('full rebuild preserves deep identities, increments version and rejects incomplete access', () async {
    final first = await artifact('1.0.0', ['old']);
    final bank = await repository.importFile(first.path);
    await (await UserDBHelper().database).update('IdentitySubject', {'selected': 1});
    final progress = <String>[];
    final rebuilt = await YkbBankSyncService.syncBank(bank,
      creationService: _CatalogService(), onBankProgress: (value) => progress.add(value.stage));
    expect(rebuilt!.version, '1.0.1');
    final db = await openDatabase(rebuilt.localPath, readOnly: true, singleInstance: false);
    expect((await db.query('Identity')).length, 3);
    expect((await db.query('IdentityQuestion')).single['identity_id'], '3801');
    expect((await db.query('Question')).single['id'], 'new');
    await db.close();
    final choices = await (await UserDBHelper().database).query('IdentitySubject',
      where: 'identity_id = ?', whereArgs: ['3801']);
    expect(choices.single['selected'], 1);
    expect(progress.last, '重建完成');
    final bytes = await File(rebuilt.localPath).readAsBytes();
    await expectLater(YkbBankSyncService.syncBank(rebuilt,
      creationService: _CatalogService(restricted: true)), throwsStateError);
    expect(await File(rebuilt.localPath).readAsBytes(), bytes);
    expect((await repository.history('fixture')).length, 2);
  });
}

class _CatalogService extends BankCreationService {
  _CatalogService({bool restricted = false}) : super(
    request: (_, __) async => {'code': 200, 'data': [{
      'chapter_id': 's', 'children': [{'chapter_id': 'c', 'count': 1}],
    }]},
    fetchChapter: (_, __) async => restricted
        ? const YkbChapterFetchResult(code: '203', message: '无权限')
        : const YkbChapterFetchResult(code: '200', message: '', questions: [{'id': 'new'}]),
  );

  @override
  Future<List<BankIdentityNode>> identities() async => BankIdentityNode.parse([{
    'identity_id': '0', 'children': [{
      'identity_id': '38', 'children': [{
        'identity_id': '380', 'children': [{'identity_id': '3801', 'category': 'chapter'}],
      }],
    }],
  }]);
}
