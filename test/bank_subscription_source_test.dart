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
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/widgets/bank_subscription_settings.dart';

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
      await service.refresh();
      final bank = (await QuestionBankRepository().find('fixture'))!;
      await service.setBankSource(bank, 'https://example.org/revised.zip');
      final entries = await service.refresh();
      expect(entries.length, 2);
      expect(await service.sourceFor(bank), 'https://example.org/revised.zip');
      expect(
        entries.singleWhere((r) => r['bank_id'] == 'other')['subscription_url'],
        'https://example.org/manifest.json',
      );
      await service.refresh(bankId: 'fixture');
      expect((await service.cached()).length, 2);
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
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await BankSubscriptionService.instance.automatic(), isTrue);
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
