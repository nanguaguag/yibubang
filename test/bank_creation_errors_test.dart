import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/models/bank_creation_report.dart';
import 'package:yibubang/models/bank_progress.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('bank-errors-'),
  );
  tearDown(() => directory.delete(recursive: true));
  BankIdentityNode root(String id) =>
      BankIdentityNode({'identity_id': id, 'title': '学科$id'}, []);

  Map<String, dynamic> catalog(List<String> chapters) => {
    'code': 200,
    'data': [
      {
        'chapter_id': 's',
        'title': '课程',
        'children': [
          for (final id in chapters)
            {'chapter_id': id, 'title': id, 'count': id == 'malformed' ? 2 : 1},
        ],
      },
    ],
  };
  const good = YkbChapterFetchResult(
    code: '200',
    message: '',
    questions: [
      {'id': 'q'},
    ],
  );

  test(
    'ignore logs directory and chapter errors, rolls back invalid chapters and saves only complete content',
    () async {
      final run = BankCreationReport();
      final calls = <BankCreationIssue>[];
      final progress = <BankProgress>[];
      final tree = BankIdentityNode(
        {'identity_id': '38', 'title': '医学'},
        [root('381'), root('382')],
      );
      final service = BankCreationService(
        request: (_, params) async => params['identity_id'] == '381'
            ? {'code': '203', 'message': '无查看权限'}
            : catalog(['good', 'restricted', 'malformed', 'short', 'server']),
        fetchChapter: (_, id) async => switch (id) {
          'restricted' => const YkbChapterFetchResult(
            code: '203',
            message: '无查看权限',
          ),
          'server' => const YkbChapterFetchResult(code: '500', message: '服务异常'),
          'short' => const YkbChapterFetchResult(
            code: '200',
            message: '',
            questions: [],
          ),
          'malformed' => const YkbChapterFetchResult(
            code: '200',
            message: '',
            questions: [
              {'id': 'partial'},
              {'id': ''},
            ],
          ),
          _ => good,
        },
      );
      final file = await service.build(
        root: tree,
        bankId: 'partial',
        name: '医学',
        version: '1.0.0',
        directory: directory,
        report: run,
        onProgress: progress.add,
        onError: (issue) async {
          calls.add(issue);
          return BankCreationErrorAction.ignore;
        },
      );
      expect(calls.length, 5);
      expect(calls.first.stage, '课程目录');
      expect(calls.first.code, '203');
      expect(calls.last.code, '500');
      expect(run.failures.length, 5);
      expect(run.successes.where((r) => r.stage == '章节').length, 1);
      expect(progress.last.completed, 5);
      final db = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      expect((await db.query('Question')).single['id'], 'q');
      expect((await db.query('IdentityChapter')).single['chapter_id'], 'good');
      expect((await db.query('BankMeta')).single['question_count'], 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test(
    'ignore all prompts once across multiple selected banks but records every failure',
    () async {
      final run = BankCreationReport();
      var prompts = 0;
      final service = BankCreationService(
        request: (_, __) async =>
            catalog(['good', 'restricted1', 'restricted2']),
        fetchChapter: (_, id) async => id == 'good'
            ? good
            : const YkbChapterFetchResult(code: '203', message: '无权限'),
      );
      for (final id in ['38', '39']) {
        await service.build(
          root: root(id),
          bankId: 'bank$id',
          name: '学科$id',
          version: '1.0.0',
          directory: directory,
          report: run,
          onError: (_) async {
            prompts++;
            return BankCreationErrorAction.ignoreAll;
          },
        );
      }
      expect(prompts, 1);
      expect(run.failures.length, 4);
      expect(run.failures.map((r) => r.bankName).toSet(), {'学科38', '学科39'});
      expect(run.questionCounts, {'bank38': 1, 'bank39': 1});
    },
  );

  test(
    'terminating after a successful chapter deletes the unfinished artifact',
    () async {
      final run = BankCreationReport();
      final service = BankCreationService(
        request: (_, __) async => catalog(['good', 'restricted']),
        fetchChapter: (_, id) async => id == 'good'
            ? good
            : const YkbChapterFetchResult(code: '203', message: '无权限'),
      );
      await expectLater(
        service.build(
          root: root('38'),
          bankId: 'bank',
          name: '医学',
          version: '1.0.0',
          directory: directory,
          report: run,
          onError: (_) async => BankCreationErrorAction.terminate,
        ),
        throwsA(isA<BankCreationTerminated>()),
      );
      expect(await directory.list().toList(), isEmpty);
      expect(run.failures.length, 1);
      expect(run.successes.where((r) => r.stage == '章节').length, 1);
      expect(run.savedBanks, isEmpty);
    },
  );

  test(
    'cancellation while deciding an error deletes staging even when ignore is returned',
    () async {
      final cancellation = BankTaskCancellation();
      final service = BankCreationService(
        request: (_, __) async => catalog(['restricted']),
        fetchChapter: (_, __) async =>
            const YkbChapterFetchResult(code: '203', message: '无权限'),
      );
      await expectLater(
        service.build(
          root: root('38'),
          bankId: 'bank',
          name: '医学',
          version: '1.0.0',
          directory: directory,
          cancellation: cancellation,
          onError: (_) async {
            cancellation.cancelled = true;
            return BankCreationErrorAction.ignore;
          },
        ),
        throwsA(isA<BankTaskCancelled>()),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'ignoring every chapter never yields an empty installable bank',
    () async {
      final service = BankCreationService(
        request: (_, __) async => catalog(['restricted']),
        fetchChapter: (_, __) async =>
            const YkbChapterFetchResult(code: '203', message: '无权限'),
      );
      await expectLater(
        service.build(
          root: root('38'),
          bankId: 'bank',
          name: '医学',
          version: '1.0.0',
          directory: directory,
          onError: (_) async => BankCreationErrorAction.ignoreAll,
        ),
        throwsStateError,
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
}
