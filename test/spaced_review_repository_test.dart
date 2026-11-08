import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spaced_repo_test_');
    dbPath = p.join(tempDir.path, 'user_data.sqlite');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SpacedReviewRepository and SQLite v14 Upgrade Tests', () {
    test('v13 to v14 migration retains existing user answers and creates new tables', () async {
      final db = await openDatabase(dbPath, version: 13, onCreate: (db, version) async {
        await db.execute('CREATE TABLE Question (id TEXT PRIMARY KEY, user_answer TEXT, status INTEGER)');
        await db.execute('''
          CREATE TABLE Activities (
            id TEXT PRIMARY KEY, title TEXT, description TEXT, timestamp INTEGER,
            bank_id TEXT, question_id TEXT, duration INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE TABLE BankContentState (bank_id TEXT PRIMARY KEY, source_id TEXT)');
      });

      try {
        await db.insert('Question', {'id': 'q_test_1', 'user_answer': 'B', 'status': 1});
        await db.insert('Activities', {
          'id': 'act_1',
          'title': 'Test Act',
          'description': 'Description',
          'timestamp': 1000,
          'question_id': 'q_test_1',
          'duration': 5,
        });

        // 执行升级至 v14
        await UserDBHelper().upgradeForTesting(db, 13);

        // 校验原数据无损
        final questions = await db.query('Question');
        expect(questions.length, 1);
        expect(questions.first['id'], 'q_test_1');
        expect(questions.first['user_answer'], 'B');

        final acts = await db.query('Activities');
        expect(acts.length, 1);
        expect(acts.first['duration'], 5);

        // 校验新表与索引已生成
        final tables = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((r) => r['name'] as String).toSet();

        expect(tables, contains('ReviewPlans'));
        expect(tables, contains('SpacedReviewItem'));
        expect(tables, contains('CustomFlashcards'));

        final integrity = (await db.rawQuery('PRAGMA integrity_check')).first.values.first;
        expect(integrity, 'ok');
      } finally {
        await db.close();
      }
    });

    test('v14 to v15 upgrade safely adds source_types and covered_subjects to ReviewPlans', () async {
      final db = await openDatabase(dbPath, version: 14, onCreate: (db, version) async {
        // 模拟 v14 早期 ReviewPlans 表结构（具备 bank_id 等，但无 source_types 与 covered_subjects）
        await db.execute('''
          CREATE TABLE ReviewPlans (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            target_type TEXT NOT NULL DEFAULT 'all',
            bank_id TEXT,
            identity_id TEXT,
            subject_id TEXT,
            daily_new_target INTEGER NOT NULL DEFAULT 20,
            daily_review_limit INTEGER NOT NULL DEFAULT 50,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      });

      try {
        // 执行升级至 v15
        await UserDBHelper().upgradeForTesting(db, 14);

        final repo = SpacedReviewRepository();
        const plan = ReviewPlan(
          id: 'test_v15_plan',
          name: '测试升级计划',
          sourceTypes: ['wrong', 'collected'],
          coveredSubjects: ['sub_1', 'sub_2'],
        );

        // 保存包含 source_types 与 covered_subjects 的计划应成功且不抛出 SQL 异常
        await repo.savePlan(plan, db);

        final fetched = await repo.getPlan('test_v15_plan', db);
        expect(fetched, isNotNull);
        expect(fetched!.sourceTypes, ['wrong', 'collected']);
        expect(fetched.coveredSubjects, ['sub_1', 'sub_2']);
      } finally {
        await db.close();
      }
    });

    test('ReviewPlan CRUD and active plan management', () async {
      final db = await openDatabase(dbPath);
      await UserDBHelper().createSpacedRepetitionTablesForTesting(db);

      try {
        final repo = SpacedReviewRepository();

        // 初始无计划时自动创建并返回默认计划
        final defaultPlan = await repo.getOrCreateActivePlan(db);
        expect(defaultPlan.id, 'default_plan');
        expect(defaultPlan.isActive, isTrue);
        expect(defaultPlan.dailyNewTarget, 20);

        // 创建新计划
        final newPlan = const ReviewPlan(
          id: 'plan_internal_medicine',
          name: '内科学专攻',
          targetType: 'subject',
          subjectId: 'sub_101',
          dailyNewTarget: 30,
          dailyReviewLimit: 60,
          isActive: false,
        );
        await repo.savePlan(newPlan, db);

        var plans = await repo.getAllPlans(db);
        expect(plans.length, 2);

        // 切换激活计划
        await repo.setActivePlan('plan_internal_medicine', db);
        final active = await repo.getActivePlan(db);
        expect(active?.id, 'plan_internal_medicine');

        // 删除计划
        await repo.deletePlan('plan_internal_medicine', db);
        plans = await repo.getAllPlans(db);
        expect(plans.length, 1);
      } finally {
        await db.close();
      }
    });

    test('SpacedReviewItem save, query, batch and due filtering', () async {
      final db = await openDatabase(dbPath);
      await UserDBHelper().createSpacedRepetitionTablesForTesting(db);

      try {
        final repo = SpacedReviewRepository();
        final now = DateTime(2026, 11, 8, 12, 0, 0);

        // 插入项目
        final itemPast = SpacedReviewItem(
          itemId: 'item_due_yesterday',
          state: ReviewState.review,
          dueDate: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          reps: 2,
        );
        final itemToday = SpacedReviewItem(
          itemId: 'item_due_today',
          state: ReviewState.review,
          dueDate: now.millisecondsSinceEpoch,
          reps: 1,
        );
        final itemFuture = SpacedReviewItem(
          itemId: 'item_due_tomorrow',
          state: ReviewState.review,
          dueDate: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
          reps: 3,
        );
        final itemMastered = SpacedReviewItem(
          itemId: 'item_mastered',
          state: ReviewState.mastered,
          dueDate: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          reps: 6,
        );

        await repo.batchSaveItems([itemPast, itemToday, itemFuture, itemMastered], db);

        // 查询到期数（itemPast 和 itemToday 到期，itemFuture 未到期，itemMastered 排除）
        final dueCount = await repo.getDueCount(now: now, executor: db);
        expect(dueCount, 2);

        final dueItems = await repo.getDueItems(now: now, executor: db);
        expect(dueItems.length, 2);
        expect(dueItems.map((e) => e.itemId), containsAll(['item_due_yesterday', 'item_due_today']));

        // 状态统计
        final reviewCount = await repo.getReviewStateCount(
          state: ReviewState.review,
          executor: db,
        );
        expect(reviewCount, 3);

        final masteredCount = await repo.getReviewStateCount(
          state: ReviewState.mastered,
          executor: db,
        );
        expect(masteredCount, 1);

        // 未来 7 天预估
        final forecast = await repo.getDueForecast(days: 3, now: now, executor: db);
        expect(forecast.keys.length, 3);
        // 今天到期的数量
        expect(forecast['2026-11-08'], 1);
        // 明天到期的数量
        expect(forecast['2026-11-09'], 1);
      } finally {
        await db.close();
      }
    });

    test('CustomFlashcards CRUD automatically maintains SpacedReviewItem', () async {
      final db = await openDatabase(dbPath);
      await UserDBHelper().createSpacedRepetitionTablesForTesting(db);

      try {
        final repo = SpacedReviewRepository();

        final card = const CustomFlashcard(
          id: 'card_cardiology_1',
          title: '心室重构机制',
          front: '简述心室重构的主要病理生理机制',
          back: '心肌细胞肥大、心肌间质纤维化及心室几何构型改变。',
          tags: '内科,循环系统',
        );

        // 保存闪卡
        await repo.saveFlashcard(card, db);

        final fetchedCard = await repo.getFlashcard('card_cardiology_1', db);
        expect(fetchedCard, isNotNull);
        expect(fetchedCard?.title, '心室重构机制');

        // 校验对应的 SpacedReviewItem 已自动初始化
        final reviewItem = await repo.getItem('card_cardiology_1', db);
        expect(reviewItem, isNotNull);
        expect(reviewItem?.itemType, ReviewItemType.flashcard);
        expect(reviewItem?.state, ReviewState.new_);
        expect(reviewItem?.extra?['front'], contains('心室重构'));

        // 删除闪卡同时联动删除 SpacedReviewItem
        await repo.deleteFlashcard('card_cardiology_1', db);
        expect(await repo.getFlashcard('card_cardiology_1', db), isNull);
        expect(await repo.getItem('card_cardiology_1', db), isNull);
      } finally {
        await db.close();
      }
    });
  });
}
