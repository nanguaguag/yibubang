// 当前源码审计探针：M01/M02现已断言正确行为，M13保留未修现状；全部数据位于临时目录。
// 探针位于 docs，分析器不会将其识别为 test 目录；仅这里调用现有测试钩子。
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/data_transfer.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/db/user_database_coordinator.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/screens/choosed_subjects_page.dart';
import 'package:yibubang/screens/daily_review_page.dart';
import 'package:yibubang/services/cloud_sync_service.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:yibubang/services/spaced_repetition_engine.dart';
import 'package:yibubang/widgets/daily_review_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String previousPath;
  late String bankPath;
  late Database userDb;
  late Database bank;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousPath = await getDatabasesPath();
  });
  Future<void> createBank(int count) async {
    bankPath = p.join(dir.path, 'fixture.sqlite');
    final writer = await openDatabase(bankPath);
    await writer.transaction((tx) async {
      await tx.execute(
        'CREATE TABLE Identity(id TEXT PRIMARY KEY,parent_id TEXT,name TEXT)',
      );
      await tx.execute('CREATE TABLE Subject(id TEXT PRIMARY KEY,name TEXT)');
      await tx.execute('CREATE TABLE Chapter(id TEXT PRIMARY KEY,name TEXT)');
      await tx.execute(
        'CREATE TABLE Question(id TEXT PRIMARY KEY,title TEXT,chapter_id TEXT,chapter_parent_id TEXT,answer TEXT,type TEXT)',
      );
      await tx.execute(
        'CREATE TABLE IdentitySubject(identity_id TEXT,subject_id TEXT,total INTEGER)',
      );
      await tx.execute(
        'CREATE TABLE IdentityChapter(identity_id TEXT,subject_id TEXT,chapter_id TEXT,total INTEGER)',
      );
      await tx.execute(
        'CREATE TABLE IdentityQuestion(question_id TEXT,identity_id TEXT,subject_id TEXT,chapter_id TEXT)',
      );
      await tx.rawInsert("INSERT INTO Identity VALUES ('i','-1','专业')");
      await tx.rawInsert("INSERT INTO Subject VALUES ('s','审计课程')");
      await tx.rawInsert("INSERT INTO Chapter VALUES ('c','审计章节')");
      await tx.rawInsert("INSERT INTO IdentitySubject VALUES ('i','s',?)", [
        count,
      ]);
      await tx.rawInsert("INSERT INTO IdentityChapter VALUES ('i','s','c',?)", [
        count,
      ]);
      await tx.rawInsert(
        '''WITH RECURSIVE ids(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM ids WHERE n<?)
        INSERT INTO Question SELECT 'q'||n,'题目'||n,'c','s','A','1' FROM ids''',
        [count],
      );
      await tx.rawInsert(
        "INSERT INTO IdentityQuestion SELECT id,'i','s','c' FROM Question",
      );
    });
    await writer.close();
    bank = await openDatabase(bankPath, readOnly: true, singleInstance: false);
    DatabaseHelper.setDatabaseForTesting(bank);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('post_a20_audit_');
    await databaseFactory.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({
      'activeBankId': 'fixture',
      'identityId': 'i',
      'autoResume': false,
      'spaced_algorithm': 'fsrs',
      'flashcard_3d_flip': false,
    });
    userDb = await UserDBHelper().database;
  });
  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await QuestionBankDatabaseManager().closeAll();
    await bank.close();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await dir.delete(recursive: true);
  });
  Future<void> drainWidgetIo(WidgetTester tester, Finder ready) async {
    for (var i = 0; i < 100 && ready.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready, findsWidgets);
  }

  testWidgets('云同步仅初始化通知不重载已显示首页课程', (tester) async {
    await tester.runAsync(() async {
      await createBank(1);
      await ensureQuestionCountProjection('fixture', bankPath: bankPath);
      await userDb.insert('IdentitySubject', {
        'bank_id': 'fixture',
        'identity_id': 'i',
        'subject_id': 's',
        'selected': 1,
        'correct': 0,
        'incorrect': 0,
      });
    });
    await tester.pumpWidget(const MaterialApp(home: ChoosedSubjectsPage()));
    await drainWidgetIo(tester, find.text('审计课程'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final entered = Zone.root.run(() => Completer<void>());
    final release = Zone.root.run(() => Completer<void>());
    late Future<void> maintenance;
    try {
      await tester.runAsync(() async {
        maintenance = UserDatabaseCoordinator.instance.run(() async {
          entered.complete();
          await release.future;
        });
        await entered.future;
      });
      await tester.runAsync(() => CloudSyncService.instance.init());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('审计课程'), findsOneWidget);
    } finally {
      await tester.runAsync(() async {
        release.complete();
        await maintenance;
      });
    }
    await drainWidgetIo(tester, find.text('审计课程'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('正常默认卡片入口传入SM2服务，绕过已保存fsrs配置', (tester) async {
    await tester.runAsync(() async {
      await createBank(1);
      final repo = SpacedReviewRepository();
      await repo.savePlan(
        ReviewPlan(
          id: 'p',
          name: '审计计划',
          bankId: bankPath,
          sourceTypes: const ['flashcard'],
          dailyNewTarget: 1,
        ),
        userDb,
      );
      await userDb.insert(
        'CustomFlashcards',
        const CustomFlashcard(id: 'fc', front: '审计正面', back: '审计背面').toMap(),
      );
      expect(
        (await SpacedRepetitionEngine.loadConfigured()).algorithmType,
        SpacedAlgorithmType.fsrsLite,
      );
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DailyReviewCard())),
    );
    await drainWidgetIo(tester, find.text('开始今日打卡'));
    await tester.tap(find.text('开始今日打卡'));
    await tester.pump();
    await drainWidgetIo(tester, find.byType(DailyReviewPage));
    final page = tester.widget<DailyReviewPage>(find.byType(DailyReviewPage));
    expect(page.service, isNotNull);
    expect(page.service!.engine.algorithmType, SpacedAlgorithmType.sm2);
    await drainWidgetIo(tester, find.text('审计正面'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('十万题冷投影、热投影、全量重建队头等待与完整概览计时', () async {
    await createBank(100000);
    final sw = Stopwatch()..start();
    await ensureQuestionCountProjection('fixture', bankPath: bankPath);
    final coldMs = sw.elapsedMilliseconds;
    final stamp = (await userDb.query(
      'QuestionProjectionState',
    )).single['source_stamp'];
    final stat = await File(bankPath).stat();
    final requestedStamp =
        '$bankPath:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    final changesBefore =
        (await userDb.rawQuery('SELECT total_changes()')).single.values.single
            as int;
    sw.reset();
    for (var i = 0; i < 10; i++) {
      await ensureQuestionCountProjection('fixture', bankPath: bankPath);
    }
    final hot10Ms = sw.elapsedMilliseconds;
    final aliasChanges =
        ((await userDb.rawQuery('SELECT total_changes()')).single.values.single
            as int) -
        changesBefore;
    final canonicalPath = await File(bankPath).resolveSymbolicLinks();
    sw.reset();
    for (var i = 0; i < 10; i++) {
      await ensureQuestionCountProjection('fixture', bankPath: canonicalPath);
    }
    final canonical10Ms = sw.elapsedMilliseconds;
    expect(aliasChanges, 0);
    expect(stamp, startsWith('$canonicalPath:'));
    final entered = Completer<void>();
    sw.reset();
    final maintenance = UserDatabaseCoordinator.instance.run(() async {
      await userDb.execute('ATTACH DATABASE ? AS audit_bank', [bankPath]);
      entered.complete();
      try {
        await userDb.transaction(
          (tx) =>
              rebuildAttachedQuestionCount(tx, 'fixture', alias: 'audit_bank'),
        );
      } finally {
        await userDb.execute('DETACH DATABASE audit_bank');
      }
    });
    await entered.future;
    final querySw = Stopwatch()..start();
    await userDb.rawQuery('SELECT 1');
    final queueMs = querySw.elapsedMilliseconds;
    await maintenance;
    final rebuildMs = sw.elapsedMilliseconds;
    await userDb.insert('Question', {'id': 'q1', 'status': 2});
    final service = DailyReviewService(
      bankPathsResolver: (_) async => {'fixture': bankPath},
    );
    sw.reset();
    for (var i = 0; i < 3; i++) {
      final summary = await service.getTodaySummary(
        customPlan: const ReviewPlan(id: 'p', name: 'p'),
        executor: userDb,
      );
      expect(summary.poolWrongCount, 1);
    }
    final summary3Ms = sw.elapsedMilliseconds;
    expect(
      (await userDb.rawQuery(
        'SELECT COUNT(*) FROM QuestionRelations',
      )).single.values.single,
      100000,
    );
    final sqlite = (await userDb.rawQuery(
      'SELECT sqlite_version()',
    )).single.values.single;
    // ignore: avoid_print
    print(
      'AUDIT_METRICS sqlite=$sqlite questions=100000 cold_projection_ms=$coldMs alias_projection_10_ms=$hot10Ms alias_sql_changes=$aliasChanges canonical_projection_10_ms=$canonical10Ms rebuild_ms=$rebuildMs select1_queue_ms=$queueMs full_summary_3_ms=$summary3Ms bank_bytes=${await File(bankPath).length()} stamp_match=${stamp == requestedStamp} requested_stamp=$requestedStamp stored_stamp=$stamp database_path=${bank.path}',
    );
  });
}
