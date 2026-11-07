import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/bank_source.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('source-catalog-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'db'));
  });
  tearDown(() async {
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });
  Map<String, dynamic> entry(String id) => {
    'bank_id': id,
    'identity_id': '38',
    'name': '医学',
    'version': '1.0.0',
    'schema_version': 1,
    'url': 'https://example.org/$id.zip',
    'sha256': 'a' * 64,
  };

  test(
    'saving normalized duplicate sources makes no requests and preserves signed parameters',
    () async {
      var requests = 0;
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient((_) async {
            requests++;
            return http.Response('', 500);
          }),
        ),
      );
      await service.saveSources([
        ' https://EXAMPLE.org/Bank.zip?token=a%2Fb#part ',
        'https://example.org/Bank.zip?token=a%2Fb',
      ]);
      expect(requests, 0);
      final sources = (await service.sources())
          .where((s) => !s.official)
          .toList();
      expect(sources.length, 1);
      expect(sources.single.url, 'https://example.org/Bank.zip?token=a%2Fb');
      expect(sources.single.status, BankSourceStatus.unchecked);
    },
  );

  test(
    'independent source failures and duplicate bank IDs keep one primary and candidates without installation',
    () async {
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient(
            (r) async =>
                r.url.host == 'example.org' && r.url.path != '/bad.json'
                ? http.Response(
                    jsonEncode({
                      'banks': [entry('fixture')],
                    }),
                    200,
                    headers: {'content-type': 'application/json; charset=utf-8'},
                  )
                : http.Response('offline', 503),
          ),
        ),
      );
      await service.saveSources([
        'https://example.org/first.json',
        'https://example.org/second.json',
        'https://example.org/bad.json',
      ]);
      final results = await service.check();
      expect(
        results.where((s) => s.status == BankSourceStatus.ready).length,
        2,
        reason: results.map((s) => '${s.url}: ${s.error}').join('\n'),
      );
      expect(
        results.where((s) => s.status == BankSourceStatus.failed).length,
        2,
      );
      final catalog = await service.store.read();
      expect(catalog.candidates('fixture').length, 2);
      expect(
        catalog.sourceFor('fixture')!.url,
        'https://example.org/first.json',
      );
      expect(
        (await QuestionBankRepository().find('fixture'))!.isInstalled,
        false,
      );
      await service.selectSource(
        (await QuestionBankRepository().find('fixture'))!,
        BankSource.fresh('https://example.org/second.json').id,
      );
      await service.check();
      expect(
        (await service.store.read()).sourceFor('fixture')!.url,
        'https://example.org/second.json',
      );
    },
  );

  test(
    'manifest conditional check reuses validated metadata on 304 and single-bank checks share a source',
    () async {
      final requests = <http.Request>[];
      final service = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient((r) async {
            requests.add(r);
            if (r.headers['If-None-Match'] == 'v1') {
              return http.Response('', 304);
            }
            return http.Response(
              jsonEncode({
                'banks': [entry('fixture'), entry('other')],
              }),
              200,
              headers: {'etag': 'v1', 'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      const url = 'https://example.org/manifest.json';
      await service.saveSources([url]);
      await service.check(sourceId: BankSource.fresh(url).id);
      final before = requests.length;
      await service.check(bankId: 'fixture');
      expect(requests.length, before + 1);
      expect(requests.last.headers['If-None-Match'], 'v1');
      expect(
        (await service.store.read()).sourceFor('fixture')!.entries.length,
        2,
      );
    },
  );

  test(
    'file check and unsupported HEAD never receive the full file body',
    () async {
      for (final headSupported in [true, false]) {
        final methods = <String>[];
        var chunks = 0;
        final loader = BankSubscriptionLoader(
          client: MockClient.streaming((r, _) async {
            methods.add(r.method);
            if (r.method == 'HEAD') {
              return http.StreamedResponse(
                const Stream.empty(),
                headSupported ? 200 : 405,
              );
            }
            return http.StreamedResponse(
              Stream<List<int>>.fromIterable(
                List.generate(100, (_) => [0x50, 0x4b, 0, 0]),
              ).map((chunk) {
                chunks++;
                return chunk;
              }),
              200,
              headers: {'content-type': 'application/zip'},
            );
          }),
        );
        final result = await loader.check(
          BankSource.fresh('https://example.org/bank.zip'),
        );
        expect(result.status, BankSourceStatus.needsDownload);
        expect(methods, headSupported ? ['HEAD'] : ['HEAD', 'GET']);
        // No bytes are retained, decompressed or used as update metadata.
        expect(result.entries, isEmpty);
        expect(chunks, lessThan(2));
      }
    },
  );
}
