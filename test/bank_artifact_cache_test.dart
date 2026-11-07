import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/models/bank_source.dart';
import 'package:yibubang/services/bank_artifact_cache.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  late List<int> bytes;
  late BankSubscriptionLoader loader;
  late int requests;
  const url = 'https://example.org/fixture.sqlite';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('artifact-cache-test-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'db'));
    final file =
        await BankCreationService(
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
          fetchChapter: (_, __) async => YkbChapterFetchResult(
            code: '200',
            message: '',
            questions: [
              {'id': '1', 'title': '试题'},
            ],
          ),
        ).build(
          root: BankIdentityNode({'identity_id': '38', 'title': '医学'}, []),
          bankId: 'fixture',
          name: '医学',
          version: '1.0.0',
          directory: directory,
        );
    bytes = await file.readAsBytes();
    requests = 0;
    loader = BankSubscriptionLoader(
      client: MockClient((r) async {
        if (r.method == 'HEAD') {
          return http.Response(
            '',
            200,
            headers: {'etag': 'v1', 'content-type': 'application/octet-stream'},
          );
        }
        requests++;
        return http.Response.bytes(
          bytes,
          200,
          headers: {'etag': 'v1', 'content-type': 'application/octet-stream'},
        );
      }),
    );
  });
  tearDown(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  test(
    'persisted cache and concurrent acquires reuse one validated package; corrupted bytes download again',
    () async {
      final cache = BankArtifactCache(loader: loader);
      final leases = await Future.wait([
        cache.acquire(url),
        cache.acquire(url),
      ]);
      expect(requests, 1);
      final entry = leases.first.entry;
      final file = leases.first.file;
      for (final lease in leases) {
        await lease.dispose();
      }
      final persisted = await BankArtifactCache(
        loader: loader,
      ).acquire(url, expected: entry);
      expect(requests, 1);
      await persisted.dispose();
      await file.writeAsString('corrupt');
      final recovered = await cache.acquire(url, expected: entry);
      expect(requests, 2);
      expect(await recovered.file.readAsBytes(), bytes);
      await recovered.dispose();
    },
  );

  test(
    'LRU protects an active oversized package and cleans it on release',
    () async {
      final cache = BankArtifactCache(loader: loader, maxBytes: 1);
      final lease = await cache.acquire(url);
      await cache.prune();
      expect(await lease.file.exists(), isTrue);
      await lease.dispose();
      expect(await lease.file.exists(), isFalse);
    },
  );

  test(
    'download does not publish a package with a mismatched manifest',
    () async {
      final cache = BankArtifactCache(loader: loader);
      await expectLater(
        cache.acquire(url, expected: {'bank_id': 'other'}),
        throwsFormatException,
      );
      expect(await QuestionBankRepository().find('fixture'), isNull);
    },
  );

  test(
    'link import subscribes from the same download, checks with HEAD and never adds duplicate source',
    () async {
      final service = BankSubscriptionService(loader: loader);
      final bank = await service.importLink(url, subscribe: true);
      expect(bank.isInstalled, isTrue);
      expect(requests, 1);
      final catalog = await service.store.read();
      expect(catalog.sourceFor('fixture')!.etag, 'v1');
      expect(catalog.sourceFor('fixture')!.status, BankSourceStatus.ready);
      await service.check(bankId: 'fixture');
      expect(requests, 1);
      expect((await service.updateInfo(bank)).status, BankUpdateStatus.current);
      await service.saveSources([url, url]);
      expect((await service.sources()).where((s) => !s.official).length, 1);
      await service.install('fixture');
      expect(requests, 1);
    },
  );

  test(
    'explicit download confirmation and subsequent install use one package',
    () async {
      final service = BankSubscriptionService(loader: loader);
      await service.saveSources([url]);
      final id = BankSource.fresh(url).id;
      await service.check(sourceId: id);
      expect(requests, 0);
      expect(
        (await service.store.read()).sources[id]!.status,
        BankSourceStatus.needsDownload,
      );
      await service.confirmSource(id);
      expect(requests, 1);
      await service.install('fixture');
      expect(requests, 1);
    },
  );
}
