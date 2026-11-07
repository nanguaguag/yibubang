import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';
import 'package:yibubang/services/question_bank_file_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final repository = QuestionBankRepository();
  late Directory directory;
  late String previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previous = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('bank-delete-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'db'));
    await repository.initialize();
  });
  tearDown(() async {
    await DatabaseHelper().close();
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previous);
    await directory.delete(recursive: true);
  });

  Future<File> content(String id) async =>
      BankCreationService(
        request: (_, __) async => {
          'code': 200,
          'data': [
            {
              'chapter_id': 's',
              'children': [
                {'chapter_id': 'c', 'count': 1},
              ],
            },
          ],
        },
        fetchChapter: (_, __) async => const YkbChapterFetchResult(
          code: '200',
          message: '',
          questions: [
            {'id': 'q', 'title': '题目'},
          ],
        ),
      ).build(
        root: BankIdentityNode({'identity_id': '38', 'title': '医学'}, []),
        bankId: id,
        name: id,
        version: '1.0.0',
        directory: await directory.createTemp('content-'),
      );

  test(
    'deleting active content closes connections, removes backups and preserves personal data',
    () async {
      final bank = await repository.importFile((await content('first')).path);
      final other = await repository.importFile((await content('other')).path);
      await repository.selectBank(bank.bankId);
      final userDb = await UserDBHelper().database;
      await userDb.insert('Question', {
        'id': 'q',
        'user_answer': 'A',
        'status': 1,
        'collection': '1',
      });
      await userDb.insert('Notes', {
        'id': 'note',
        'question_id': 'q',
        'content': '笔记',
        'timestamp': 1,
      });
      await userDb.insert('Activities', {
        'id': 'activity',
        'title': '作答',
        'description': '',
        'timestamp': 1,
        'bank_id': bank.bankId,
      });
      await userDb.update(
        'IdentitySubject',
        {'selected': 1},
        where: 'bank_id = ?',
        whereArgs: [bank.bankId],
      );
      final personal = <String, List<Map<String, Object?>>>{
        for (final table in [
          'Question',
          'Notes',
          'Activities',
          'IdentitySubject',
          'IdentityChapter',
        ])
          table: await userDb.query(table),
      };
      await File(bank.localPath).copy('${bank.localPath}.bak');
      final connection = await QuestionBankDatabaseManager().openBank(
        bank.bankId,
      );
      await repository.deleteBank(bank.bankId);
      expect(connection.isOpen, isFalse);
      expect(await Directory(p.dirname(bank.localPath)).exists(), isFalse);
      expect(await repository.find(bank.bankId), isNull);
      expect(await repository.activeBankId(), other.bankId);
      expect(
        (await SharedPreferences.getInstance()).getString('identityId'),
        '38',
      );
      for (final table in personal.keys) {
        expect(await userDb.query(table), personal[table]);
      }
      expect((await repository.history(bank.bankId)).first['action'], '删除本地题库');
    },
  );

  test(
    'subscribed content remains available and reinstall rebuilds a clean baseline',
    () async {
      final bytes = await (await content('subscribed')).readAsBytes();
      var downloads = 0;
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient((_) async {
            downloads++;
            return http.Response.bytes(bytes, 200, headers: {'etag': 'v1'});
          }),
        ),
      );
      const url = 'https://example.org/subscribed.sqlite';
      final bank = await service.importLink(url, subscribe: true);
      await service.deleteBank(bank.bankId);
      final available = (await repository.find(bank.bankId))!;
      expect(available.isInstalled, isFalse);
      expect(available.localPath, isEmpty);
      expect((await service.store.read()).sourceFor(bank.bankId)!.url, url);
      expect((await repository.contentState(bank.bankId)).hasBaseline, isFalse);
      expect(downloads, 1);
      await expectLater(
        service.install(bank.bankId, automatic: true),
        throwsA(isA<BankImportCancelled>()),
      );
      final restored = await service.install(bank.bankId);
      expect(restored.isInstalled, isTrue);
      expect((await repository.contentState(bank.bankId)).hasBaseline, isTrue);
      expect((await repository.history(bank.bankId)).length, 3);
      expect(downloads, 1, reason: 'reinstallation reuses the validated cache');
    },
  );

  test(
    'metadata failure restores content, baseline and history and releases deletion lock',
    () async {
      final bank = await repository.importFile((await content('fixture')).path);
      final before = await File(bank.localPath).readAsBytes();
      final db = await UserDBHelper().database;
      await db.execute(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON BankContentState BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repository.deleteBank(bank.bankId),
        throwsA(isA<DatabaseException>()),
      );
      expect(await File(bank.localPath).readAsBytes(), before);
      expect((await repository.find(bank.bankId))!.isInstalled, isTrue);
      expect((await repository.history(bank.bankId)).length, 1);
      await db.execute('DROP TRIGGER reject_delete');
      await repository.deleteBank(bank.bankId);
      expect(await repository.find(bank.bankId), isNull);
    },
  );

  test(
    'deletion rejects paths outside owned content and concurrent installation',
    () async {
      final file = await content('fixture');
      final bank = await repository.importFile(file.path);
      final db = await UserDBHelper().database;
      await db.update(
        'QuestionBank',
        {'local_path': file.path},
        where: 'bank_id = ?',
        whereArgs: [bank.bankId],
      );
      await expectLater(repository.deleteBank(bank.bankId), throwsStateError);
      expect(await file.exists(), isTrue);
      await db.update(
        'QuestionBank',
        {'local_path': bank.localPath},
        where: 'bank_id = ?',
        whereArgs: [bank.bankId],
      );
      final choice = Completer<BankImportMode?>();
      final shown = Completer<void>();
      final pending = repository.importFile(
        file.path,
        onConflict: (_) {
          shown.complete();
          return choice.future;
        },
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<BankImportCancelled>()),
      );
      await shown.future;
      await expectLater(repository.deleteBank(bank.bankId), throwsStateError);
      choice.complete(null);
      await cancelled;
      await repository.deleteBank(bank.bankId);
    },
  );
}
