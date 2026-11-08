import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/services/daily_review_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String userDbPath;
  late String bankDbPath;
  late Database userDb;
  late Database bankDb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('daily_review_test_');
    userDbPath = p.join(tempDir.path, 'user_data.sqlite');
    bankDbPath = p.join(tempDir.path, 'fixture_bank.sqlite');

    // 1. 创建题库数据库 (fixture_bank.sqlite)
    bankDb = await openDatabase(bankDbPath, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE Question (
          id TEXT PRIMARY KEY,
          title TEXT,
          chapter_id TEXT,
          chapter_parent_id TEXT,
          answer TEXT,
          type TEXT
        )
      ''');
    });

    // 插入 10 道测试题
    for (int i = 1; i <= 10; i++) {
      await bankDb.insert('Question', {
        'id': 'q_$i',
        'title': 'Question $i Title',
        'chapter_id': 'chap_1',
        'chapter_parent_id': 'sub_1',
        'answer': 'A',
        'type': '1',
      });
    }

    // 2. 创建用户数据库 (user_data.sqlite，具备 v14 表结构)
    userDb = await openDatabase(userDbPath, version: 14);
    await UserDBHelper().createSpacedRepetitionTablesForTesting(userDb);
    await userDb.execute('''
      CREATE TABLE IF NOT EXISTS Question (
        id TEXT PRIMARY KEY,
        chapter_id TEXT,
        chapter_parent_id TEXT,
        cut_question TEXT DEFAULT '0',
        user_answer TEXT DEFAULT '',
        status INTEGER DEFAULT 0,
        collection INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0
      )
    ''');
    await userDb.execute('''
      CREATE TABLE IF NOT EXISTS Activities (
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        timestamp INTEGER,
        bank_id TEXT,
        question_id TEXT,
        is_right TEXT,
        duration INTEGER DEFAULT 0
      )
    ''');
    await userDb.execute('''
      CREATE TABLE IF NOT EXISTS Notes (
        id TEXT PRIMARY KEY,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
  });

  tearDown(() async {
    await userDb.close();
    await bankDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DailyReviewService Integration Tests', () {
    test('buildDailySession filters cut questions from both due and new pools', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 12, 0, 0);

      // 设定 q_1 为斩题 (cut_question = '1')
      await userDb.insert('Question', {
        'id': 'q_1',
        'cut_question': '1',
        'status': 1,
      });

      // 设定 q_2 为今日到期复习题目
      await spacedRepo.saveItem(
        SpacedReviewItem(
          itemId: 'q_2',
          state: ReviewState.review,
          reps: 2,
          interval: 3,
          dueDate: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        ),
        userDb,
      );

      // 设定 q_3 为到期复习题，但已被用户斩掉 (cut_question = '1')
      await userDb.insert('Question', {
        'id': 'q_3',
        'cut_question': '1',
        'status': 1,
      });
      await spacedRepo.saveItem(
        SpacedReviewItem(
          itemId: 'q_3',
          state: ReviewState.review,
          reps: 2,
          interval: 3,
          dueDate: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        ),
        userDb,
      );

      // 创建计划：每日新题 3 道，复习上限 5 道，指向测试题库，抽取来源为全题库新题
      final plan = ReviewPlan(
        id: 'plan_test',
        name: '测试计划',
        bankId: 'fixture_bank',
        sourceTypes: const ['all'],
        dailyNewTarget: 3,
        dailyReviewLimit: 5,
      );
      await spacedRepo.savePlan(plan, userDb);
      await spacedRepo.setActivePlan('plan_test', userDb);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        bankPathResolver: (_) async => bankDbPath,
        userDbHelper: UserDBHelper(),
      );

      // 使用自定义方法注入 bank 路径的 session 构建验证
      final session = await service.buildDailySession(
        customPlan: plan.copyWith(bankId: 'fixture_bank'),
        now: now,
        executor: userDb,
      );

      // 验证到期队列：q_2 应该在队列中，q_3（已斩）被严格过滤剔除
      expect(session.dueQueue.map((e) => e.questionId), contains('q_2'));
      expect(session.dueQueue.map((e) => e.questionId), isNot(contains('q_3')));

      // 校验 q_3 在 SpacedReviewItem 中被自动标记为 mastered
      final q3Item = await spacedRepo.getItem('q_3', userDb);
      expect(q3Item?.state, ReviewState.mastered);

      // 验证新题队列：数量等于 target 3，且绝对不包含已斩的 q_1，也不包含复习的 q_2 / q_3
      expect(session.newQueue.length, 3);
      final newIds = session.newQueue.map((e) => e.questionId).toSet();
      expect(newIds, isNot(contains('q_1')));
      expect(newIds, isNot(contains('q_2')));
      expect(newIds, isNot(contains('q_3')));

      // 验证队列合并顺序：复习在前，新题在后（复习优先）
      final all = session.allItems;
      expect(all.first.questionId, 'q_2');
      expect(all.first.isNew, isFalse);
      expect(all.skip(1).every((e) => e.isNew), isTrue);
    });

    test('submitReviewResult updates spaced review state, user Question and Activities', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 12, 0, 0);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        userDbHelper: UserDBHelper(),
      );

      // 提交对 q_4 的 Good 评级（做题用时 8 秒，用户选 B）
      final updated = await service.submitReviewResult(
        questionId: 'q_4',
        rating: ReviewRating.good,
        durationSeconds: 8,
        userAnswer: 'B',
        bankId: 'fixture_bank',
        now: now,
        executor: userDb,
      );

      expect(updated.itemId, 'q_4');
      expect(updated.reps, 1);
      expect(updated.interval, 1);
      expect(updated.lastRating, ReviewRating.good);

      // 验证 user_data.Question 已更新
      final qRows = await userDb.query('Question', where: 'id = ?', whereArgs: ['q_4']);
      expect(qRows.length, 1);
      expect(qRows.first['user_answer'], 'B');
      expect(qRows.first['status'], 1); // 正确

      // 验证 Activities 流水已记账
      final actRows = await userDb.query('Activities', where: 'question_id = ?', whereArgs: ['q_4']);
      expect(actRows.length, 1);
      expect(actRows.first['duration'], 8);
      expect(actRows.first['is_right'], '1');
      expect(actRows.first['description'], contains('GOOD'));
    });

    test('getTodaySummary calculates completed and remaining counts accurately', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 12, 0, 0);

      final plan = ReviewPlan(
        id: 'plan_summary',
        name: '概览测试计划',
        bankId: 'fixture_bank',
        dailyNewTarget: 5,
        dailyReviewLimit: 10,
      );
      await spacedRepo.savePlan(plan, userDb);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        userDbHelper: UserDBHelper(),
      );

      // 提交 2 道今日新题
      await service.submitReviewResult(
        questionId: 'q_5',
        rating: ReviewRating.good,
        now: now,
        executor: userDb,
      );
      await service.submitReviewResult(
        questionId: 'q_6',
        rating: ReviewRating.easy,
        now: now,
        executor: userDb,
      );

      final summary = await service.getTodaySummary(
        customPlan: plan,
        now: now,
        executor: userDb,
      );

      expect(summary.dailyNewTarget, 5);
      expect(summary.completedNewToday, 2);
      expect(summary.remainingNewCount, 3); // 5 - 2 = 3
    });

    test('buildDailySession draws only from selected sources and covered subjects', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 12, 0, 0);

      // 插入题目：q_7 (活跃课程错题), q_8 (活跃课程收藏), q_9 (已完结课程错题)
      await userDb.insert('Question', {
        'id': 'q_7',
        'chapter_parent_id': 'sub_active',
        'status': 2,
        'collection': 0,
        'cut_question': '0',
      });
      await userDb.insert('Question', {
        'id': 'q_8',
        'chapter_parent_id': 'sub_active',
        'status': 1,
        'collection': 1,
        'cut_question': '0',
      });
      await userDb.insert('Question', {
        'id': 'q_9',
        'chapter_parent_id': 'sub_finished',
        'status': 2,
        'collection': 0,
        'cut_question': '0',
      });

      // 计划：仅抽选错题与收藏，且仅覆盖 sub_active
      final plan = ReviewPlan(
        id: 'plan_filter',
        name: '自定义抽题范围计划',
        bankId: 'fixture_bank',
        sourceTypes: const ['wrong', 'collected'],
        coveredSubjects: const ['sub_active'],
        dailyNewTarget: 10,
        dailyReviewLimit: 10,
      );
      await spacedRepo.savePlan(plan, userDb);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        bankPathResolver: (_) async => bankDbPath,
        userDbHelper: UserDBHelper(),
      );

      final session = await service.buildDailySession(
        customPlan: plan,
        now: now,
        executor: userDb,
      );

      final newIds = session.newQueue.map((e) => e.questionId).toSet();
      expect(newIds, contains('q_7')); // 活跃课程错题包含
      expect(newIds, contains('q_8')); // 活跃课程收藏包含
      expect(newIds, isNot(contains('q_9'))); // 已完结课程错题严格排除！
    });

    test('cutQuestion marks SpacedReviewItem as mastered and updates poolMasteredCount', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 14, 0, 0);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        bankPathResolver: (_) async => bankDbPath,
        userDbHelper: UserDBHelper(),
      );

      final plan = ReviewPlan(
        id: 'plan_cut',
        name: '斩题测试计划',
        bankId: 'fixture_bank',
      );
      await spacedRepo.savePlan(plan, userDb);

      // 斩掉 q_1
      await service.cutQuestion(
        questionId: 'q_1',
        bankId: 'fixture_bank',
        planId: plan.id,
        now: now,
        executor: userDb,
      );

      // 验证 SpacedReviewItem 与 Question 状态
      final item = await spacedRepo.getItem('q_1', userDb);
      expect(item?.state, ReviewState.mastered);

      final qRows = await userDb.query('Question', where: 'id = ?', whereArgs: ['q_1']);
      expect(qRows.first['cut_question'], '1');

      // 验证 Summary 中熟练斩题计数
      final summary = await service.getTodaySummary(
        customPlan: plan,
        now: now,
        executor: userDb,
      );
      expect(summary.poolMasteredCount, greaterThanOrEqualTo(1));
    });

    test('buildDailySession draws note cards when note is selected and flags isFromNote', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 14, 0, 0);

      // 插入题目 q_note 并在 Notes 表添加记录
      await bankDb.insert('Question', {
        'id': 'q_note',
        'title': 'Note Question Title',
        'chapter_id': 'chap_1',
        'chapter_parent_id': 'sub_1',
        'answer': 'B',
        'type': '1',
      });
      await userDb.insert('Notes', {
        'id': 'note_1',
        'question_id': 'q_note',
        'content': '口腔组织病理学考点速记',
        'imgs': '[]',
        'timestamp': now.millisecondsSinceEpoch,
      });

      // 计划：仅抽选笔记卡片
      final plan = ReviewPlan(
        id: 'plan_note',
        name: '速记笔记专攻计划',
        bankId: 'fixture_bank',
        sourceTypes: const ['note'],
        dailyNewTarget: 5,
        dailyReviewLimit: 5,
      );
      await spacedRepo.savePlan(plan, userDb);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        bankPathResolver: (_) async => bankDbPath,
        userDbHelper: UserDBHelper(),
      );

      final session = await service.buildDailySession(
        customPlan: plan,
        now: now,
        executor: userDb,
      );

      expect(session.newQueue.any((e) => e.questionId == 'q_note'), isTrue);
      final noteItem = session.newQueue.firstWhere((e) => e.questionId == 'q_note');
      expect(noteItem.isFromNote, isTrue);
    });

    test('isExtraSession enters cram mode when due and new queues are exhausted', () async {
      final spacedRepo = SpacedReviewRepository();
      final now = DateTime(2026, 11, 8, 14, 0, 0);

      // 准备在学状态的题目 q_learn (state = learning, 但 due_date 在明天)
      final tomorrow = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
      await spacedRepo.saveItem(
        SpacedReviewItem(
          itemId: 'q_2',
          planId: 'plan_cram',
          state: ReviewState.learning,
          dueDate: tomorrow,
          lastReviewAt: now.millisecondsSinceEpoch,
        ),
        userDb,
      );

      // 计划：已无可抽取新题
      final plan = ReviewPlan(
        id: 'plan_cram',
        name: '巩固测试计划',
        bankId: 'fixture_bank',
        sourceTypes: const ['wrong'], // 没有错题可抽
        dailyNewTarget: 5,
        dailyReviewLimit: 5,
      );
      await spacedRepo.savePlan(plan, userDb);

      final service = DailyReviewService(
        spacedRepo: spacedRepo,
        bankPathResolver: (_) async => bankDbPath,
        userDbHelper: UserDBHelper(),
      );

      // extra = false 时，今日无到期无新题
      final normalSession = await service.buildDailySession(
        customPlan: plan,
        now: now,
        isExtraSession: false,
        executor: userDb,
      );
      expect(normalSession.allItems.isEmpty, isTrue);
      expect(normalSession.isCramMode, isFalse);

      // extra = true 时，自动拉取在学题目提前巩固！杜绝 0 题报错
      final extraSession = await service.buildDailySession(
        customPlan: plan,
        now: now,
        isExtraSession: true,
        executor: userDb,
      );
      expect(extraSession.allItems.isNotEmpty, isTrue);
      expect(extraSession.isCramMode, isTrue);
      expect(extraSession.allItems.first.questionId, 'q_2');
    });
  });
}
