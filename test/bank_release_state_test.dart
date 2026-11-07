import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/models/bank_source.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/bank_export_service.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';
import 'package:yibubang/services/question_bank_file_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previous;
  late BankSubscriptionService service;
  late Map<String, dynamic> entry;
  late File remote;
  var downloads = 0;
  final repository = QuestionBankRepository();
  const sourceUrl = 'https://example.org/manifest.json';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previous = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('release-state-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'db'));
    downloads = 0;
    service = BankSubscriptionService(
      loader: BankSubscriptionLoader(
        client: MockClient((r) async {
          if (r.url.path.endsWith('.json')) {
            return http.Response(
              jsonEncode({
                'banks': [entry],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          downloads++;
          return http.Response.bytes(await remote.readAsBytes(), 200);
        }),
      ),
    );
  });
  tearDown(() async {
    service.stop();
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previous);
    await directory.delete(recursive: true);
  });
  Future<File> artifact(String version, List<String> ids) async {
    final target = await directory.createTemp('content-');
    return BankCreationService(
      request: (_, __) async => {
        'code': 200,
        'data': [
          {
            'chapter_id': 's',
            'children': [
              {'chapter_id': 'c', 'count': ids.length},
            ],
          },
        ],
      },
      fetchChapter: (_, __) async => YkbChapterFetchResult(
        code: '200',
        message: '',
        questions: ids
            .map((id) => <String, dynamic>{'id': id, 'title': '$version-$id'})
            .toList(),
      ),
    ).build(
      root: BankIdentityNode({'identity_id': '38', 'title': '医学'}, []),
      bankId: 'fixture',
      name: '医学',
      version: version,
      directory: target,
    );
  }

  Future<void> publish(
    String version,
    List<String> ids, {
    bool zip = false,
    bool sqliteHash = true,
  }) async {
    final content = await artifact(version, ids);
    remote = zip
        ? await BankExportService.zip(
            content,
            await directory.createTemp('zip-'),
          )
        : content;
    entry = {
      'bank_id': 'fixture',
      'identity_id': '38',
      'name': '医学',
      'version': version,
      'schema_version': 1,
      'url': 'https://example.org/fixture.${zip ? 'zip' : 'sqlite'}',
      'sha256': sha256.convert(await remote.readAsBytes()).toString(),
      if (sqliteHash)
        'sqlite_sha256': sha256.convert(await content.readAsBytes()).toString(),
    };
    await service.saveSources([sourceUrl]);
    final results = await service.check(
      sourceId: BankSource.fresh(sourceUrl).id,
    );
    expect(
      results.single.status,
      BankSourceStatus.ready,
      reason: results.single.error,
    );
  }

  test(
    'merge advances upstream baseline while retaining local additions; same release never reinstalls',
    () async {
      await publish('1.0.0', ['1']);
      await service.install('fixture');
      await repository.importFile(
        (await artifact('1.0.1', ['1', 'local'])).path,
        onConflict: (_) async => BankImportMode.merge,
      );
      expect((await repository.contentState('fixture')).localRevision, 1);
      await publish('1.1.0', ['1', '2'], zip: true);
      final bank = (await repository.find('fixture'))!;
      expect(
        (await service.updateInfo(bank)).status,
        BankUpdateStatus.available,
      );
      await expectLater(
        service.install('fixture', automatic: true),
        throwsStateError,
      );
      final merged = await service.install(
        'fixture',
        onResolve: (_, info, diff) async {
          expect(diff.added, 1);
          expect(diff.changed, 1);
          expect(diff.localExtras, 1);
          return BankImportMode.merge;
        },
      );
      final state = await repository.contentState('fixture');
      expect(state.baseVersion, '1.1.0');
      expect(state.localRevision, 1);
      expect(
        (await service.updateInfo(merged)).status,
        BankUpdateStatus.current,
      );
      final history = await repository.history('fixture');
      await service.check(bankId: 'fixture');
      await service.install('fixture');
      expect((await repository.history('fixture')).length, history.length);
      expect(
        downloads,
        2,
        reason:
            'one package per published version; comparison and installation reuse cache',
      );
    },
  );

  test(
    'same-version changes and rollback require explicit choice; replacing clears local revision and preserves answers',
    () async {
      await publish('2.0.0', ['1']);
      await service.install('fixture');
      final userDb = await UserDBHelper().database;
      await userDb.insert('Question', {
        'id': '1',
        'user_answer': 'A',
        'status': 1,
      });
      await publish('2.0.0', ['1', '2']);
      expect(
        (await service.updateInfo((await repository.find('fixture'))!)).status,
        BankUpdateStatus.changed,
      );
      await expectLater(service.install('fixture'), throwsStateError);
      await service.install(
        'fixture',
        onResolve: (_, __, ___) async => BankImportMode.replace,
      );
      await publish('1.0.0', ['1']);
      expect(
        (await service.updateInfo((await repository.find('fixture'))!)).status,
        BankUpdateStatus.rollback,
      );
      await expectLater(
        service.install('fixture', automatic: true),
        throwsStateError,
      );
      await service.install(
        'fixture',
        onResolve: (_, __, ___) async => BankImportMode.replace,
      );
      expect((await repository.contentState('fixture')).localRevision, 0);
      expect((await userDb.query('Question')).single['user_answer'], 'A');
    },
  );

  test(
    'a changed upstream subject is rejected before download, preserving installed subject and history',
    () async {
      await publish('1.0.0', ['1']);
      final bank = await service.install('fixture');
      entry['identity_id'] = '39';
      entry['version'] = '1.1.0';
      await service.check(bankId: 'fixture');
      final before = downloads;
      await expectLater(service.install('fixture'), throwsFormatException);
      await expectLater(
        service.selectSource(bank, BankSource.fresh(sourceUrl).id),
        throwsFormatException,
      );
      expect(downloads, before);
      expect((await repository.find('fixture'))!.identityId, '38');
      expect((await repository.find('fixture'))!.contentHash, bank.contentHash);
      expect((await repository.history('fixture')).length, 1);
    },
  );

  test(
    'failed installation rolls back the upstream baseline with the file and history',
    () async {
      await publish('1.0.0', ['1']);
      final bank = await service.install('fixture');
      final before = (await repository.contentState('fixture')).toMap();
      await publish('1.1.0', ['1', '2']);
      await (await UserDBHelper().database).execute(
        "CREATE TRIGGER reject_baseline BEFORE INSERT ON BankContentState BEGIN SELECT RAISE(ABORT, 'failure'); END",
      );
      await expectLater(
        service.install('fixture'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repository.contentState('fixture')).toMap(), before);
      expect((await repository.find('fixture'))!.contentHash, bank.contentHash);
      expect((await repository.history('fixture')).length, 1);
    },
  );

  test(
    'manifest without SQLite hash still recognizes the same processed package',
    () async {
      await publish('1.0.0', ['1'], sqliteHash: false);
      final installed = await service.install('fixture');
      expect(
        (await service.updateInfo(installed)).status,
        BankUpdateStatus.current,
      );
      await service.install('fixture');
      expect(downloads, 1);
      expect((await repository.history('fixture')).length, 1);
    },
  );

  test(
    'scheduled checks install safe releases only, preserving locally supplemented banks',
    () async {
      await publish('1.0.0', ['1']);
      await service.install('fixture');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bank_subscription_auto', true);
      await prefs.setBool('bank_subscription_auto_install', true);
      await publish('1.1.0', ['1', '2']);
      await service.checkAutomatically();
      expect((await repository.contentState('fixture')).baseVersion, '1.1.0');
      await repository.importFile(
        (await artifact('1.1.1', ['1', '2', 'local'])).path,
        onConflict: (_) async => BankImportMode.merge,
      );
      await publish('1.2.0', ['1', '2', '3']);
      await prefs.remove('bank_subscription_last_check');
      await service.checkAutomatically();
      expect((await repository.contentState('fixture')).baseVersion, '1.1.0');
      expect(downloads, 2);
    },
  );

  test(
    'removing a bound source archives its URL and leaves installed content, history and candidates intact',
    () async {
      await publish('1.0.0', ['1']);
      final bank = await service.install('fixture');
      const mirror = 'https://example.org/mirror.json';
      await service.addSource(mirror);
      await service.check(sourceId: BankSource.fresh(mirror).id);
      final primary = BankSource.fresh(sourceUrl).id;
      await service.removeSource(primary);
      final catalog = await service.store.read();
      expect(catalog.sourceFor('fixture'), isNull);
      expect(catalog.sources[primary]!.active, isFalse);
      expect(catalog.sources[primary]!.url, sourceUrl);
      expect((await repository.find('fixture'))!.contentHash, bank.contentHash);
      expect((await repository.history('fixture')).length, 1);
      expect(catalog.candidates('fixture').length, 1);
      await service.selectSource(bank, BankSource.fresh(mirror).id);
      expect((await service.store.read()).sourceFor('fixture')!.url, mirror);
    },
  );

  test(
    'v12 migration adds empty baseline storage and preserves global answers',
    () async {
      final db = await openDatabase(
        p.join(directory.path, 'old-user.sqlite'),
        singleInstance: false,
      );
      try {
        await db.execute(
          'CREATE TABLE Question(id TEXT PRIMARY KEY, user_answer TEXT)',
        );
        await db.insert('Question', {'id': '1', 'user_answer': 'A'});
        await UserDBHelper().upgradeForTesting(db, 12);
        expect(await db.query('BankContentState'), isEmpty);
        expect((await db.query('Question')).single['user_answer'], 'A');
      } finally {
        await db.close();
      }
    },
  );

  test(
    'legacy unknown baseline stays pending comparison and exact known bytes establish a baseline',
    () async {
      final file = await artifact('9.0.0', ['1']);
      final old = await repository.importFile(file.path);
      await publish('1.0.0', ['2']);
      expect(
        (await service.updateInfo(old)).status,
        BankUpdateStatus.needsComparison,
      );
      entry['sqlite_sha256'] = old.contentHash;
      await service.check(bankId: 'fixture');
      expect((await service.updateInfo(old)).status, BankUpdateStatus.current);
      expect((await repository.contentState('fixture')).hasBaseline, isTrue);
    },
  );
}
