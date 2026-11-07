import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/bank_export_service.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';
import 'package:yibubang/services/question_bank_file_service.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/widgets/bank_subscription_settings.dart';
import 'package:yibubang/models/bank_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('subscription-test-');
    previousPath = await getDatabasesPath();
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'databases'));
  });
  tearDown(() async {
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  Future<File> artifact() =>
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
            {'id': '1'},
          ],
        ),
      ).build(
        root: BankIdentityNode({'identity_id': '38', 'title': '医学'}, []),
        bankId: 'fixture',
        name: '医学',
        version: '1.0.0',
        directory: directory,
      );

  test(
    'ZIP and SQLite subscription bodies are inspected as binary without installing',
    () async {
      final sqlite = await artifact();
      final zip = await BankExportService.zip(sqlite, directory);
      final loader = BankSubscriptionLoader(
        client: MockClient(
          (request) async => http.Response.bytes(
            await (request.url.path.endsWith('.zip') ? zip : sqlite)
                .readAsBytes(),
            200,
          ),
        ),
      );
      for (final url in [
        'https://example.org/bank.zip',
        'https://example.org/bank.sqlite',
      ]) {
        final loaded = await loader.load(url);
        expect(loaded.entries.single['bank_id'], 'fixture');
        expect(loaded.entries.single['identity_id'], '38');
        expect(loaded.entries.single['source_type'], 'file');
        expect(loaded.entries.single['sqlite_sha256'].toString().length, 64);
        expect(await QuestionBankRepository().find('fixture'), isNull);
        final artifactPath = loaded.artifacts['fixture']!.path;
        await loaded.dispose();
        expect(await File(artifactPath).exists(), isFalse);
      }
    },
  );

  test(
    'editing one bank subscription preserves other banks in a shared manifest',
    () async {
      final file = await artifact();
      final zip = await BankExportService.zip(file, directory);
      Map<String, dynamic> entry(String id) => {
        'bank_id': id,
        'identity_id': '38',
        'version': '1.0.0',
        'schema_version': 1,
        'url': 'https://example.org/$id.zip',
        'sha256': 'a' * 64,
      };
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient((request) async {
            if (request.url.path.endsWith('manifest.json')) {
              return http.Response(
                jsonEncode({
                  'banks': [entry('fixture'), entry('other')],
                }),
                200,
              );
            }
            return http.Response.bytes(await zip.readAsBytes(), 200);
          }),
        ),
      );
      await service.saveSources(['https://example.org/manifest.json']);
      await service.check();
      final bank = (await QuestionBankRepository().find('fixture'))!;
      await service.proposeBankSource(bank, 'https://example.org/revised.zip');
      await service.confirmSource(
        BankSource.fresh('https://example.org/revised.zip').id,
      );
      await service.selectSource(
        bank,
        BankSource.fresh('https://example.org/revised.zip').id,
      );
      await service.check();
      final entries = await service.cached();
      expect(
        entries
            .where((e) => ['fixture', 'other'].contains(e['bank_id']))
            .length,
        2,
      );
      expect(await service.sourceFor(bank), 'https://example.org/revised.zip');
      expect(
        entries.singleWhere((r) => r['bank_id'] == 'other')['subscription_url'],
        'https://example.org/manifest.json',
      );
      await service.check(bankId: 'fixture');
      expect(
        (await service.cached())
            .where((e) => ['fixture', 'other'].contains(e['bank_id']))
            .length,
        2,
      );
    },
  );

  test(
    'manual subscription update refreshes the source, installs new content and preserves global user answers',
    () async {
      final file = await artifact();
      final repository = QuestionBankRepository();
      final installed = await repository.importFile(
        file.path,
        updateEnabled: false,
      );
      final userDb = await UserDBHelper().database;
      await userDb.insert('Question', {
        'id': '1',
        'status': 1,
        'user_answer': 'A',
      });
      final updateDirectory = await directory.createTemp('update-');
      final updatedFile = await file.copy(
        p.join(updateDirectory.path, 'fixture.sqlite'),
      );
      // Prepare a new disposable content artifact; installed bank stays read-only.
      final content = await openDatabase(
        updatedFile.path,
        singleInstance: false,
      );
      await content.insert('Question', {'id': '2'});
      await content.insert('IdentityQuestion', {
        'identity_id': '38',
        'subject_id': 's',
        'chapter_id': 'c',
        'question_id': '2',
      });
      await QuestionBankFileService.recount(content, version: '1.0.1');
      await content.close();
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient(
            (_) async =>
                http.Response.bytes(await updatedFile.readAsBytes(), 200),
          ),
        ),
      );
      await service.saveSources(['https://example.org/fixture.sqlite']);
      // Automatic updates skip frozen content, while the manual button is explicit.
      await service.check();
      expect(
        (await repository.find('fixture'))!.contentHash,
        installed.contentHash,
      );
      await service.confirmSource(
        BankSource.fresh('https://example.org/fixture.sqlite').id,
      );
      await service.install(
        'fixture',
        onResolve: (_, __, ___) async => BankImportMode.replace,
      );
      final updated = (await repository.find('fixture'))!;
      expect(updated.version, '1.0.1');
      expect(updated.contentHash, isNot(installed.contentHash));
      expect(
        (await userDb.query(
          'Question',
          where: 'id = ?',
          whereArgs: ['1'],
        )).single['user_answer'],
        'A',
      );
      expect(
        (await userDb.query(
          'IdentitySubject',
          where: 'bank_id = ?',
          whereArgs: ['fixture'],
        )).single['correct'],
        1,
      );
      final history = await repository.history('fixture');
      expect(history.length, 2);
      expect(history.first['added'], 1);
      // Rechecking the same source must not reinstall or fabricate a history event.
      await service.confirmSource(
        BankSource.fresh('https://example.org/fixture.sqlite').id,
      );
      await service.install(
        'fixture',
        onResolve: (_, __, ___) async => BankImportMode.replace,
      );
      expect((await repository.history('fixture')).length, 2);
    },
  );

  test(
    'HTML error pages report a useful link error instead of UTF-8 failures',
    () async {
      final loader = BankSubscriptionLoader(
        client: MockClient(
          (_) async => http.Response('<html>not a bank</html>', 200),
        ),
      );
      await expectLater(
        loader.load('https://example.org/download'),
        throwsFormatException,
      );
    },
  );

  test(
    'automatic subscription interval persists and determines when checking is due',
    () async {
      final service = BankSubscriptionService();
      await service.configureAutomatic(true, 45);
      service.stop();
      expect(await BankSubscriptionService().intervalMinutes(), 45);
      expect(await service.automatic(), isTrue);
      final now = DateTime(2026, 11, 7, 12);
      await (await SharedPreferences.getInstance()).setInt(
        'bank_subscription_last_check',
        now.millisecondsSinceEpoch,
      );
      expect(
        await service.isDue(now.add(const Duration(minutes: 44))),
        isFalse,
      );
      expect(await service.isDue(now.add(const Duration(minutes: 45))), isTrue);
      await expectLater(
        service.configureAutomatic(true, 0),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'subscription auto-update and custom interval can be changed in settings',
    (tester) async {
      addTearDown(BankSubscriptionService.instance.stop);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BankSubscriptionSettings())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(await BankSubscriptionService.instance.automatic(), isTrue);
      expect(
        await BankSubscriptionService.instance.automaticInstallation(),
        isFalse,
      );
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(
        await BankSubscriptionService.instance.automaticInstallation(),
        isTrue,
      );
      await tester.tap(find.text('检查更新间隔'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1～10080 之间的整数'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '45');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(await BankSubscriptionService.instance.intervalMinutes(), 45);
      expect(find.text('每 45 分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Stop the application-wide timer before widget-test invariant checks.
      BankSubscriptionService.instance.stop();
    },
  );
}
