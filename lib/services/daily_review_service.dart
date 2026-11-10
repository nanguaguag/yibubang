import '../db/user_database_coordinator.dart';
import '../db/data_transfer.dart';
import '../models/answer_statistics.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../models/daily_review_session.dart';
import '../models/question.dart';
import '../models/spaced_review_item.dart';
import '../repositories/question_bank_repository.dart';
import '../repositories/spaced_review_repository.dart';
import 'spaced_repetition_engine.dart';

class ReviewUnavailableException implements Exception {
  final String message;
  const ReviewUnavailableException(this.message);
  @override
  String toString() => message;
}

/// 每日抽题与记忆复习调度服务
///
/// 核心职责：
/// 1. 根据当前激活的 ReviewPlan，拉取今日到期复习题目（复习优先，受 dailyReviewLimit 约束，受覆盖课程约束）；
/// 2. 从自定义来源（错题、收藏、笔记、题库未做题）抽选今日新题（受 dailyNewTarget 约束）；
/// 3. 严格遵循系统铁律：只读题库与用户库物理隔离，自动过滤已斩题目（`isCut == true` / `cut_question == '1'`），跨库共享唯一 `question_id`。
class DailyReviewService {
  final SpacedReviewRepository _spacedRepo;
  final QuestionBankRepository _bankRepo;
  final QuestionBankDatabaseManager _dbManager;
  final SpacedRepetitionEngine _engine;
  final UserDBHelper _userDbHelper;
  final Future<String?> Function(ReviewPlan plan)? _bankPathResolver;

  DailyReviewService({
    SpacedReviewRepository? spacedRepo,
    QuestionBankRepository? bankRepo,
    QuestionBankDatabaseManager? dbManager,
    SpacedRepetitionEngine? engine,
    UserDBHelper? userDbHelper,
    Future<String?> Function(ReviewPlan plan)? bankPathResolver,
  }) : _spacedRepo = spacedRepo ?? SpacedReviewRepository(),
       _bankRepo = bankRepo ?? QuestionBankRepository(),
       _dbManager = dbManager ?? QuestionBankDatabaseManager(),
       _engine = engine ?? const SpacedRepetitionEngine(),
       _userDbHelper = userDbHelper ?? UserDBHelper(),
       _bankPathResolver = bankPathResolver;

  /// 组装今日刷题会话（到期复习队列 + 今日新题队列）
  /// [isExtraSession] 为 true 时表示用户主动“再学一组”，无视今日已完成目标限制，直接按 dailyNewTarget 抽取新卡片
  Future<DailyReviewSession> buildDailySession({
    ReviewPlan? customPlan,
    DateTime? now,
    DatabaseExecutor? executor,
    bool isExtraSession = false,
  }) async {
    final currentTime = now ?? DateTime.now();
    final todayStart = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    ).millisecondsSinceEpoch;

    final plan =
        customPlan ?? await _spacedRepo.getOrCreateActivePlan(executor);

    // 1. 计算今日已完成的学习统计
    final completedNewToday = await _countCompletedToday(
      todayStart: todayStart,
      isNew: true,
      planId: plan.id,
      executor: executor,
    );
    final completedReviewToday = await _countCompletedToday(
      todayStart: todayStart,
      isNew: false,
      planId: plan.id,
      executor: executor,
    );

    // 2. 拉取今日到期复习题目（复习优先）
    final remainingReviewBudget = isExtraSession
        ? plan.dailyReviewLimit
        : math.max(0, plan.dailyReviewLimit - completedReviewToday);
    List<DailyReviewQueueItem> dueQueue = [];
    if (remainingReviewBudget > 0) {
      dueQueue = await _fetchDueReviewQueue(
        plan: plan,
        limit: remainingReviewBudget,
        now: currentTime,
        executor: executor,
      );
    }

    // 3. 抽取今日新题（依用户设定的错题/收藏/笔记/覆盖课程进行智能抽取，滤除已学、已斩题目）
    final remainingNewBudget = isExtraSession
        ? plan.dailyNewTarget
        : math.max(0, plan.dailyNewTarget - completedNewToday);
    List<DailyReviewQueueItem> newQueue = [];
    if (remainingNewBudget > 0) {
      newQueue = await _drawNewQuestionQueue(
        plan: plan,
        count: remainingNewBudget,
        executor: executor,
      );
    }

    // 4. 超额学习巩固机制 (Cram Mode)
    // 当由于今日题量做完导致到期和新题都为空（用户主动点击再学一组继续巩固）：
    bool isCramMode = false;
    if (isExtraSession && dueQueue.isEmpty && newQueue.isEmpty) {
      final cramQueue = await _fetchCramReviewQueue(
        plan: plan,
        limit: plan.dailyNewTarget > 0 ? plan.dailyNewTarget : 20,
        executor: executor,
      );
      if (cramQueue.isNotEmpty) {
        dueQueue = cramQueue;
        isCramMode = true;
      }
    }

    return DailyReviewSession(
      plan: plan,
      date: currentTime,
      dueQueue: dueQueue,
      newQueue: newQueue,
      completedNewToday: completedNewToday,
      completedReviewToday: completedReviewToday,
      isCramMode: isCramMode,
    );
  }

  Future<T> _atomic<T>(
    DatabaseExecutor? executor,
    Future<T> Function(DatabaseExecutor) work,
  ) async {
    final db = executor ?? await _userDbHelper.database;
    if (db is Database) return db.transaction((tx) => work(tx));
    if (db is Transaction) return work(db);
    throw ArgumentError('复习写入需要数据库或事务');
  }

  /// 标记熟练斩题（将记忆项直接归档为 mastered，并在用户库标记 cut_question = '1'）
  Future<void> cutQuestion({
    required String questionId,
    required String bankId,
    String? planId,
    DateTime? now,
    DatabaseExecutor? executor,
  }) async {
    await _atomic(
      executor,
      (tx) => _cutInTransaction(
        questionId: questionId,
        bankId: bankId,
        planId: planId,
        now: now,
        executor: tx,
      ),
    );
    notifyAnswersChanged();
  }

  Future<void> _cutInTransaction({
    required String questionId,
    required String bankId,
    String? planId,
    DateTime? now,
    required DatabaseExecutor executor,
  }) async {
    final currentTime = now ?? DateTime.now();

    // 1. 获取或构建 SpacedReviewItem 并直接标记为 mastered
    var item = await _spacedRepo.getItem(questionId, executor);
    final tombstone = await executor.query(
      'ReviewItemTombstones',
      where: 'item_id=?',
      whereArgs: [questionId],
    );
    if (tombstone.isNotEmpty) throw const ReviewUnavailableException('卡片已删除');
    final wasNew = item?.lastReviewAt == null || item!.lastReviewAt == 0;
    final effectivePlan =
        planId ??
        item?.planId ??
        (await _spacedRepo.getOrCreateActivePlan(executor)).id;
    item =
        (item ??
                SpacedReviewItem(
                  itemId: questionId,
                  itemType: ReviewItemType.question,
                  planId: planId,
                ))
            .copyWith(
              planId: effectivePlan,
              state: ReviewState.mastered,
              extra: {...?item?.extra, 'suspension_reason': 'cut'},
              dueDate: 0,
              lastReviewAt: currentTime.millisecondsSinceEpoch,
              reps: (item?.reps ?? 0) + 1,
            );
    await _spacedRepo.saveItem(item, executor);

    final userDb = executor;
    final isFlashcard = item.itemType == ReviewItemType.flashcard;

    if (!isFlashcard) {
      // 2. 更新用户库为已斩（兼容 SQLite < 3.24）
      final nowMs = currentTime.millisecondsSinceEpoch;
      await userDb.rawInsert(
        '''
        INSERT OR IGNORE INTO Question (id, cut_question, status, updated_at)
        VALUES (?, '1', 1, ?)
      ''',
        [questionId, nowMs],
      );
      await userDb.rawUpdate(
        '''
        UPDATE Question
        SET cut_question = '1',
            status = 1,
            updated_at = ?
        WHERE id = ?
      ''',
        [nowMs, questionId],
      );
    }

    // 3. 记录刷题流水到 Activities
    final activityId = generateSimpleId();
    await userDb.insert('Activities', {
      'id': activityId,
      'title': isFlashcard ? '熟练斩卡' : '熟练斩题',
      'description': isFlashcard ? '在记忆复习中彻底斩除该闪卡' : '在记忆复习中彻底斩除该题',
      'timestamp': currentTime.millisecondsSinceEpoch,
      'bank_id': bankId,
      'question_id': questionId,
      'is_right': '1',
      'duration': 0,
    });
    await userDb.insert('ReviewEvents', {
      'id': activityId,
      'item_id': questionId,
      'plan_id': effectivePlan,
      'kind': isFlashcard ? 'CutFlashcard' : 'CutQuestion',
      'was_new': wasNew ? 1 : 0,
      'duration_ms': 0,
      'timestamp': currentTime.millisecondsSinceEpoch,
    });
  }

  /// 提交作答或复习评分结果
  Future<SpacedReviewItem> submitReviewResult({
    required String questionId,
    required ReviewRating rating,
    int durationSeconds = 0,
    String? userAnswer,
    String? bankId,
    DateTime? now,
    DatabaseExecutor? executor,
    String? eventId,
    String? planId,
    ReviewItemType? expectedItemType,
  }) async {
    final requestId = eventId ?? generateSimpleId();
    if (executor == null && bankId?.isNotEmpty == true) {
      final existing = await _spacedRepo.getItem(questionId);
      if (existing?.itemType != ReviewItemType.flashcard &&
          expectedItemType != ReviewItemType.flashcard) {
        final bank = await _dbManager.openBank(bankId!);
        await ensureQuestionCountProjection(bankId, bankPath: bank.path);
      }
    }
    final result = await _atomic(
      executor,
      (tx) => _submitInTransaction(
        questionId: questionId,
        rating: rating,
        durationSeconds: durationSeconds,
        userAnswer: userAnswer,
        bankId: bankId,
        now: now,
        eventId: requestId,
        planId: planId,
        expectedItemType: expectedItemType,
        executor: tx,
      ),
    );
    notifyAnswersChanged();
    return result;
  }

  Future<SpacedReviewItem> _submitInTransaction({
    required String questionId,
    required ReviewRating rating,
    int durationSeconds = 0,
    String? userAnswer,
    String? bankId,
    DateTime? now,
    required String eventId,
    String? planId,
    ReviewItemType? expectedItemType,
    required DatabaseExecutor executor,
  }) async {
    final currentTime = now ?? DateTime.now();
    final previous = await executor.query(
      'Activities',
      columns: ['question_id'],
      where: 'id=?',
      whereArgs: [eventId],
    );
    if (previous.isNotEmpty) {
      if (previous.single['question_id'] != questionId) {
        throw StateError('复习请求ID与题目不匹配');
      }
      final saved = await _spacedRepo.getItem(questionId, executor);
      if (saved == null) throw StateError('复习项已删除');
      return saved;
    }

    // 1. 获取或构建 SpacedReviewItem
    var item = await _spacedRepo.getItem(questionId, executor);
    await _validateReviewItem(executor, questionId, item, expectedItemType);
    item ??= SpacedReviewItem(
      itemId: questionId,
      itemType: ReviewItemType.question,
      state: ReviewState.learning,
    );

    final wasNew = item.lastReviewAt == 0;
    final effectivePlan =
        planId ??
        item.planId ??
        (await _spacedRepo.getOrCreateActivePlan(executor)).id;
    item = item.copyWith(planId: effectivePlan);
    // 2. 调度算法状态演进
    final updatedItem = _engine.evaluateRating(
      item: item,
      rating: rating,
      now: currentTime,
    );
    await _spacedRepo.saveItem(updatedItem, executor);

    final isFlashcard = item.itemType == ReviewItemType.flashcard;

    // 3. 同步写入用户库作答记录与流水历史 (Activities)
    final userDb = executor;
    final isRight = rating != ReviewRating.again ? '1' : '0';
    final currentStatus = rating != ReviewRating.again ? 1 : 2;

    // 仅针对题库题目（非自制闪卡）更新 user_data.Question，纯背卡片自评不污染原题作答记录
    // 兼容低版本 SQLite (< 3.24 无 UPSERT)
    if (!isFlashcard) {
      final nowMs = currentTime.millisecondsSinceEpoch;
      if (userAnswer != null && userAnswer.isNotEmpty) {
        await userDb.rawInsert(
          '''
          INSERT OR IGNORE INTO Question (id, user_answer, status, cut_question, updated_at)
          VALUES (?, ?, ?, '0', ?)
        ''',
          [questionId, userAnswer, currentStatus, nowMs],
        );
        await userDb.rawUpdate(
          '''
          UPDATE Question
          SET user_answer = ?,
              status = ?,
              updated_at = ?
          WHERE id = ?
        ''',
          [userAnswer, currentStatus, nowMs, questionId],
        );
      } else {
        await userDb.rawInsert(
          '''
          INSERT OR IGNORE INTO Question (id, cut_question, updated_at)
          VALUES (?, '0', ?)
        ''',
          [questionId, nowMs],
        );
        await userDb.rawUpdate(
          '''
          UPDATE Question
          SET updated_at = ?
          WHERE id = ?
        ''',
          [nowMs, questionId],
        );
      }
    }

    // 记录刷题流水到 Activities
    final activityId = eventId;
    final activityTitle = isFlashcard
        ? 'FlashcardReview'
        : (userAnswer != null ? 'ReviewAnswer' : 'ReviewMemory');
    final uqRows = await userDb.query(
      'Question',
      where: 'id=?',
      whereArgs: [questionId],
    );
    final relation = executor is Transaction || executor is Database
        ? await _reviewRelation(userDb, questionId, bankId)
        : <String, dynamic>{};
    await userDb.insert('Activities', {
      'id': activityId,
      'title': activityTitle,
      'description':
          '评级: ${rating.name.toUpperCase()} (间隔: ${updatedItem.interval}天)',
      'timestamp': currentTime.millisecondsSinceEpoch,
      'bank_id': relation['bank_id'] ?? bankId,
      'identity_id': relation['identity_id'],
      'subject_id':
          relation['subject_id'] ??
          (uqRows.isEmpty ? null : uqRows.first['chapter_parent_id']),
      'chapter_id':
          relation['chapter_id'] ??
          (uqRows.isEmpty ? null : uqRows.first['chapter_id']),
      'question_id': questionId,
      'is_right': isRight,
      'duration': Duration(
        seconds: durationSeconds < 0 ? 0 : durationSeconds,
      ).inMilliseconds,
    });

    await userDb.insert('ReviewEvents', {
      'id': eventId,
      'item_id': questionId,
      'plan_id': effectivePlan,
      'kind': activityTitle,
      'was_new': wasNew ? 1 : 0,
      'duration_ms': Duration(
        seconds: durationSeconds < 0 ? 0 : durationSeconds,
      ).inMilliseconds,
      'rating': rating.value,
      'timestamp': currentTime.millisecondsSinceEpoch,
    });
    return updatedItem;
  }

  Future<void> _validateReviewItem(
    DatabaseExecutor tx,
    String id,
    SpacedReviewItem? item,
    ReviewItemType? expected,
  ) async {
    final deleted = await tx.query(
      'ReviewItemTombstones',
      where: 'item_id=?',
      whereArgs: [id],
    );
    if (deleted.isNotEmpty) throw const ReviewUnavailableException('卡片已删除');
    final isFlashcard =
        item?.itemType == ReviewItemType.flashcard ||
        expected == ReviewItemType.flashcard;
    if (isFlashcard && await _spacedRepo.getFlashcard(id, tx) == null) {
      throw const ReviewUnavailableException('卡片已删除');
    }
    if (item?.state == ReviewState.suspended ||
        item?.extra?['suspension_reason'] == 'cut') {
      throw const ReviewUnavailableException('该题已斩或已暂停复习');
    }
    if (!isFlashcard) {
      final rows = await tx.query('Question', where: 'id=?', whereArgs: [id]);
      if (rows.isNotEmpty &&
          (UserQuestion.fromMap(rows.single).isCut ||
              rows.single['status'] == 3)) {
        throw const ReviewUnavailableException('该题已斩');
      }
    }
  }

  Future<Map<String, dynamic>> _reviewRelation(
    DatabaseExecutor db,
    String id,
    String? bankId,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name='QuestionRelations'",
    );
    if (tables.isEmpty) return {};
    final rows = await db.rawQuery(
      'SELECT * FROM QuestionRelations WHERE question_id=? ORDER BY CASE WHEN bank_id=? THEN 0 ELSE 1 END,bank_id LIMIT 1',
      [id, bankId],
    );
    return rows.isEmpty ? {} : Map<String, dynamic>.from(rows.single);
  }

  /// 获取今日学习概览与卡片统计
  Future<DailyReviewSummary> getTodaySummary({
    ReviewPlan? customPlan,
    DateTime? now,
    DatabaseExecutor? executor,
  }) async {
    final currentTime = now ?? DateTime.now();
    final todayStart = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    ).millisecondsSinceEpoch;
    final todayEnd = todayStart + 86400000 - 1;

    final plan =
        customPlan ?? await _spacedRepo.getOrCreateActivePlan(executor);

    final completedNew = await _countCompletedToday(
      todayStart: todayStart,
      todayEnd: todayEnd,
      isNew: true,
      planId: plan.id,
      executor: executor,
    );
    final completedReview = await _countCompletedToday(
      todayStart: todayStart,
      todayEnd: todayEnd,
      isNew: false,
      planId: plan.id,
      executor: executor,
    );

    final rawDueCount = await _spacedRepo.getDueCount(
      planId: plan.id,
      now: currentTime,
      executor: executor,
    );
    final remainingDue = math.min(
      rawDueCount,
      math.max(0, plan.dailyReviewLimit - completedReview),
    );
    final userDb = executor ?? await _userDbHelper.database;
    final coveredSubjects = plan.coveredSubjects;

    final remainingNew = math.max(0, plan.dailyNewTarget - completedNew);

    // 统计题库卡片池分布（错题待攻克、收藏题、笔记卡片、记忆中、已掌握）

    final poolWrong = await _countUserQuestionPool(
      userDb: userDb,
      whereCondition: "status = 2 AND cut_question != '1'",
      coveredSubjects: coveredSubjects,
    );
    final poolCollected = await _countUserQuestionPool(
      userDb: userDb,
      whereCondition: "collection = 1 AND cut_question != '1'",
      coveredSubjects: coveredSubjects,
    );
    final poolNote = await _countNotePool(
      userDb: userDb,
      coveredSubjects: coveredSubjects,
    );
    final poolFlashcard = await _countFlashcardPool(userDb: userDb);
    final poolLearning = await _countSpacedItemState(
      userDb: userDb,
      state: ReviewState.learning.value,
      planId: plan.id,
    );
    final poolMastered = await _countMasteredPool(
      userDb: userDb,
      planId: plan.id,
      coveredSubjects: coveredSubjects,
    );

    final streak = await _calculateStreakDays(userDb, currentTime);

    return DailyReviewSummary(
      planId: plan.id,
      planName: plan.name,
      dailyNewTarget: plan.dailyNewTarget,
      dailyReviewLimit: plan.dailyReviewLimit,
      completedNewToday: completedNew,
      completedReviewToday: completedReview,
      remainingDueCount: remainingDue,
      remainingNewCount: remainingNew,
      streakDays: streak,
      sourceTypes: plan.sourceTypes,
      coveredSubjects: plan.coveredSubjects,
      poolWrongCount: poolWrong,
      poolCollectedCount: poolCollected,
      poolNoteCount: poolNote,
      poolFlashcardCount: poolFlashcard,
      poolLearningCount: poolLearning,
      poolMasteredCount: poolMastered,
    );
  }

  /// 统计自制闪卡总量
  Future<int> _countFlashcardPool({required DatabaseExecutor userDb}) async {
    try {
      final rows = await userDb.rawQuery(
        'SELECT COUNT(*) as count FROM CustomFlashcards',
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 真实计算连续打卡天数（支持跨天平滑过渡，昨天打卡保持连续性，断签归零）
  Future<int> _calculateStreakDays(
    DatabaseExecutor userDb,
    DateTime now,
  ) async {
    try {
      final rows = await userDb.rawQuery('''
        SELECT DISTINCT strftime('%Y-%m-%d', timestamp / 1000, 'unixepoch', 'localtime') as day
        FROM Activities
        WHERE title LIKE '%复习%' OR title LIKE '%斩题%' OR title LIKE '%打卡%' OR duration > 0 OR is_right IS NOT NULL
        ORDER BY day DESC
        LIMIT 60
      ''');
      if (rows.isEmpty) return 0;

      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final days = rows
          .map((r) => r['day']?.toString() ?? '')
          .where((d) => d.isNotEmpty)
          .toList();
      if (days.isEmpty) return 0;

      int streak = 0;
      DateTime checkDate;

      if (days.contains(todayStr)) {
        checkDate = now;
      } else if (days.contains(yesterdayStr)) {
        checkDate = yesterday;
      } else {
        return 0;
      }

      while (true) {
        final dateStr =
            '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
        if (days.contains(dateStr)) {
          streak++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
      return streak;
    } catch (_) {
      return 1;
    }
  }

  // -------------------------------------------------------------
  // 私有内部处理：拉取到期题目、自定义源智能抽题
  // -------------------------------------------------------------

  /// 统计今日已完成的新题或复习题数量
  Future<int> _countCompletedToday({
    required int todayStart,
    int? todayEnd,
    required bool isNew,
    required String planId,
    DatabaseExecutor? executor,
  }) async {
    final userDb = executor ?? await _userDbHelper.database;
    final end = todayEnd ?? (todayStart + 86400000 - 1);
    final rows = await userDb.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM (
        SELECT item_id FROM ReviewEvents
        WHERE timestamp>=? AND timestamp<=? AND (plan_id=? OR plan_id IS NULL)
        GROUP BY item_id HAVING MAX(was_new)=?
        UNION ALL
        SELECT item_id FROM SpacedReviewItem
        WHERE last_review_at>=? AND last_review_at<=? AND state!=0
          AND (plan_id=? OR plan_id IS NULL)
          AND ${isNew ? 'lapses=0 AND reps=1' : '(reps>1 OR lapses>0)'}
          AND NOT EXISTS(SELECT 1 FROM ReviewEvents e WHERE e.item_id=SpacedReviewItem.item_id)
      )
    ''',
      [todayStart, end, planId, isNew ? 1 : 0, todayStart, end, planId],
    );
    // 升级前未保存事件类型，只对无事件的历史记忆项保留原估算；新记录完全按事件统计。
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 拉取到期复习队列，过滤已斩题目，并按覆盖课程筛选
  Future<List<DailyReviewQueueItem>> _fetchDueReviewQueue({
    required ReviewPlan plan,
    required int limit,
    required DateTime now,
    DatabaseExecutor? executor,
  }) async {
    final result = <DailyReviewQueueItem>[];
    SpacedReviewItem? cursor;
    while (result.length < limit) {
      final page = await _spacedRepo.getDueItems(
        planId: plan.id,
        limit: 500,
        now: now,
        executor: executor,
        after: cursor,
      );
      if (page.isEmpty) break;
      cursor = page.last;
      result.addAll(
        await _filterDuePage(
          plan: plan,
          limit: limit - result.length,
          rawDueItems: page,
          executor: executor,
        ),
      );
      if (page.length < 500) break;
    }
    return result;
  }

  Future<List<DailyReviewQueueItem>> _filterDuePage({
    required ReviewPlan plan,
    required int limit,
    required List<SpacedReviewItem> rawDueItems,
    DatabaseExecutor? executor,
  }) async {
    if (rawDueItems.isEmpty) return [];

    final userDb = executor ?? await _userDbHelper.database;
    final itemIds = rawDueItems.map((e) => e.itemId).toList();

    // 批量拉取闪卡实体
    final flashcardIds = rawDueItems
        .where((e) => e.itemType == ReviewItemType.flashcard)
        .map((e) => e.itemId)
        .toList();
    final flashcardsMap = await _spacedRepo.getFlashcardsByIds(
      flashcardIds,
      userDb,
    );

    // 检查已斩题目与所属课程
    final userQuestionsMap = await _loadUserQuestionsByIds(
      itemIds,
      executor: userDb,
    );

    // 查询这些题目中哪些存在用户笔记
    Set<String> noteQuestionIds = {};
    try {
      final noteRows = await userDb.query(
        'Notes',
        columns: ['question_id'],
        where: 'question_id IN (${List.filled(itemIds.length, '?').join(',')})',
        whereArgs: itemIds,
      );
      noteQuestionIds = noteRows
          .map((r) => r['question_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {}

    final sourceTypes = plan.sourceTypes;
    final needFilterSource = !sourceTypes.contains('all');

    final validDueItems = <SpacedReviewItem>[];
    for (final it in rawDueItems) {
      if (it.itemType == ReviewItemType.flashcard) {
        final fc = flashcardsMap[it.itemId];
        if (fc == null) continue;

        if (needFilterSource && !sourceTypes.contains('flashcard')) {
          continue;
        }

        validDueItems.add(it);
        if (validDueItems.length >= limit) break;
        continue;
      }

      final uq = userQuestionsMap[it.itemId];
      if (uq != null && uq.isCut) {
        // 若已斩，自动归档为 mastered
        await _spacedRepo.saveItem(
          it.copyWith(state: ReviewState.mastered),
          executor,
        );
        continue;
      }

      // 若用户仅勾选了闪卡而完全未包含任何题目类来源，则跳过普通题
      final hasQuestionSource =
          sourceTypes.contains('all') ||
          sourceTypes.contains('wrong') ||
          sourceTypes.contains('collected') ||
          sourceTypes.contains('note');
      if (needFilterSource && !hasQuestionSource) {
        continue;
      }

      // 如果设置了覆盖课程，排除未覆盖课程的已做题（若 parentId 为空则放行保底）
      if (plan.coveredSubjects.isNotEmpty) {
        final parentId = uq?.chapterParentId;
        if (parentId != null &&
            parentId.isNotEmpty &&
            !plan.coveredSubjects.contains(parentId)) {
          continue;
        }
      }

      validDueItems.add(it);
      if (validDueItems.length >= limit) break;
    }

    if (validDueItems.isEmpty) return [];

    // 加载 Question 实体（包含关联原题）
    final targetQuestionIds = <String>{};
    for (final item in validDueItems) {
      if (item.itemType != ReviewItemType.flashcard) {
        targetQuestionIds.add(item.itemId);
      } else {
        final fc = flashcardsMap[item.itemId];
        if (fc?.questionId != null && fc!.questionId!.isNotEmpty) {
          targetQuestionIds.add(fc.questionId!);
        }
      }
    }

    final questionsMap = await _loadQuestionsByIds(
      targetQuestionIds.toList(),
      plan: plan,
      executor: executor,
    );

    return validDueItems.map((rev) {
      final qId = rev.itemId;
      final isFc = rev.itemType == ReviewItemType.flashcard;
      final fc = isFc ? flashcardsMap[qId] : null;
      final linkedQuestion = isFc
          ? (fc?.questionId != null ? questionsMap[fc!.questionId] : null)
          : questionsMap[qId];

      return DailyReviewQueueItem(
        questionId: qId,
        itemType: rev.itemType,
        isNew: false,
        question: linkedQuestion,
        userQuestion: userQuestionsMap[qId],
        reviewItem: rev,
        bankId: plan.bankId,
        customFlashcard: fc,
        isFromNote: noteQuestionIds.contains(qId),
      );
    }).toList();
  }

  /// 根据用户自定义抽题源（错题、收藏、笔记、新题）与覆盖课程抽取今日新题
  Future<List<DailyReviewQueueItem>> _drawNewQuestionQueue({
    required ReviewPlan plan,
    required int count,
    DatabaseExecutor? executor,
  }) async {
    final userDb = executor ?? await _userDbHelper.database;
    final sourceTypes = plan.sourceTypes.isEmpty
        ? const ['wrong', 'collected', 'note']
        : plan.sourceTypes;
    final coveredSubjects = plan.coveredSubjects;

    final candidateIds = <String>{};

    // 1. 从错题抽选
    if (sourceTypes.contains('wrong')) {
      final whereParts = ["status = 2", "cut_question != '1'"];
      final whereArgs = <dynamic>[];
      if (coveredSubjects.isNotEmpty) {
        whereParts.add(
          "chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')})",
        );
        whereArgs.addAll(coveredSubjects);
      }
      final rows = await userDb.query(
        'Question',
        columns: ['id'],
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) candidateIds.add(id);
      }
    }

    // 2. 从收藏抽选
    if (sourceTypes.contains('collected')) {
      final whereParts = ["collection = 1", "cut_question != '1'"];
      final whereArgs = <dynamic>[];
      if (coveredSubjects.isNotEmpty) {
        whereParts.add(
          "chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')})",
        );
        whereArgs.addAll(coveredSubjects);
      }
      final rows = await userDb.query(
        'Question',
        columns: ['id'],
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) candidateIds.add(id);
      }
    }

    // 3. 从笔记抽选
    if (sourceTypes.contains('note')) {
      try {
        final whereParts = ["COALESCE(uq.cut_question, '0') != '1'"];
        final whereArgs = <dynamic>[];
        if (coveredSubjects.isNotEmpty) {
          whereParts.add(
            "(uq.chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')}) OR uq.chapter_parent_id IS NULL OR uq.chapter_parent_id = '')",
          );
          whereArgs.addAll(coveredSubjects);
        }
        final rows = await userDb.rawQuery('''
          SELECT DISTINCT n.question_id as id
          FROM Notes n
          LEFT JOIN Question uq ON n.question_id = uq.id
          WHERE ${whereParts.join(' AND ')}
        ''', whereArgs);
        for (final r in rows) {
          final qId = r['id']?.toString();
          if (qId != null && qId.isNotEmpty) {
            candidateIds.add(qId);
          }
        }
      } catch (_) {}
    }

    // 4. 从自制闪卡抽选 (sourceTypes.contains('flashcard'))
    if (sourceTypes.contains('flashcard')) {
      try {
        final rows = await userDb.query('CustomFlashcards', columns: ['id']);
        for (final r in rows) {
          final id = r['id']?.toString();
          if (id != null && id.isNotEmpty) candidateIds.add(id);
        }
      } catch (_) {}
    }

    // 5. 从题库未做新题抽选（若勾选了 'all'）
    if (sourceTypes.contains('all')) {
      final bankNewIds = await _queryBankNewQuestionIds(
        plan: plan,
        count: count * 2,
        coveredSubjects: coveredSubjects,
        executor: userDb,
      );
      candidateIds.addAll(bankNewIds);
    }

    if (candidateIds.isEmpty) return [];

    // 6. 过滤掉已斩题目与已在记忆曲线中（state != 0）的题目
    // 先随机打乱候选池，分批（每批 100 项）检测，凑满 count 个可用新题即可停止，
    // 杜绝万级候选池全量 IN 语句超出 SQLite 999 变量上限
    final candidateList = candidateIds.toList()..shuffle();
    final selectedIds = <String>[];
    const chunkSize = 100;

    for (
      var i = 0;
      i < candidateList.length && selectedIds.length < count;
      i += chunkSize
    ) {
      final end = math.min(i + chunkSize, candidateList.length);
      final chunk = candidateList.sublist(i, end);

      final inReviewRows = await userDb.query(
        'SpacedReviewItem',
        columns: ['item_id'],
        where:
            'item_id IN (${List.filled(chunk.length, '?').join(',')}) AND state != 0',
        whereArgs: chunk,
      );
      final inReviewSet = inReviewRows
          .map((r) => r['item_id'] as String)
          .toSet();

      final cutRows = await userDb.query(
        'Question',
        columns: ['id'],
        where:
            'id IN (${List.filled(chunk.length, '?').join(',')}) AND cut_question = ?',
        whereArgs: [...chunk, '1'],
      );
      final cutIds = cutRows.map((r) => r['id'] as String).toSet();

      for (final id in chunk) {
        if (!inReviewSet.contains(id) && !cutIds.contains(id)) {
          selectedIds.add(id);
          if (selectedIds.length >= count) break;
        }
      }
    }

    if (selectedIds.isEmpty) return [];

    // 批量加载闪卡实体
    final flashcardsMap = await _spacedRepo.getFlashcardsByIds(
      selectedIds,
      userDb,
    );

    // 收集需要加载的题目 ID（包括普通题和闪卡关联题）
    final questionIdsToLoad = <String>{};
    for (final id in selectedIds) {
      final fc = flashcardsMap[id];
      if (fc != null) {
        if (fc.questionId != null && fc.questionId!.isNotEmpty) {
          questionIdsToLoad.add(fc.questionId!);
        }
      } else {
        questionIdsToLoad.add(id);
      }
    }

    // 批量加载题目实体与用户记录
    final questionsMap = await _loadQuestionsByIds(
      questionIdsToLoad.toList(),
      plan: plan,
      executor: userDb,
    );
    final userQuestionsMap = await _loadUserQuestionsByIds(
      selectedIds,
      executor: userDb,
    );

    // 查询抽取的题目中哪些包含笔记
    Set<String> noteQuestionIds = {};
    try {
      final noteRows = await userDb.query(
        'Notes',
        columns: ['question_id'],
        where:
            'question_id IN (${List.filled(selectedIds.length, '?').join(',')})',
        whereArgs: selectedIds,
      );
      noteQuestionIds = noteRows
          .map((r) => r['question_id']?.toString() ?? '')
          .toSet();
    } catch (_) {}

    return selectedIds.map((id) {
      final fc = flashcardsMap[id];
      final isFc = fc != null;
      final initialItem = SpacedReviewItem(
        itemId: id,
        planId: plan.id,
        itemType: isFc ? ReviewItemType.flashcard : ReviewItemType.question,
        state: ReviewState.new_,
      );
      final linkedQuestion = isFc
          ? (fc.questionId != null ? questionsMap[fc.questionId] : null)
          : questionsMap[id];

      return DailyReviewQueueItem(
        questionId: id,
        itemType: isFc ? ReviewItemType.flashcard : ReviewItemType.question,
        isNew: true,
        question: linkedQuestion,
        userQuestion: userQuestionsMap[id],
        reviewItem: initialItem,
        bankId: plan.bankId,
        customFlashcard: fc,
        isFromNote: noteQuestionIds.contains(id),
      );
    }).toList();
  }

  /// 超额学习模式下的巩固复习抽取（在学卡片按上次复习时间正序拉取提前强化）
  Future<List<DailyReviewQueueItem>> _fetchCramReviewQueue({
    required ReviewPlan plan,
    int limit = 20,
    DatabaseExecutor? executor,
  }) async {
    final userDb = executor ?? await _userDbHelper.database;
    final whereParts = <String>['state IN (?, ?)'];
    final whereArgs = <dynamic>[
      ReviewState.learning.value,
      ReviewState.review.value,
    ];
    if (plan.id.isNotEmpty) {
      whereParts.add('(plan_id = ? OR plan_id IS NULL)');
      whereArgs.add(plan.id);
    }

    final rows = await userDb.query(
      'SpacedReviewItem',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'last_review_at ASC, due_date ASC',
      limit: limit * 2,
    );
    if (rows.isEmpty) return [];

    final cramItems = rows.map((r) => SpacedReviewItem.fromMap(r)).toList();
    final itemIds = cramItems.map((e) => e.itemId).toList();

    // 批量加载闪卡实体
    final flashcardIds = cramItems
        .where((e) => e.itemType == ReviewItemType.flashcard)
        .map((e) => e.itemId)
        .toList();
    final flashcardsMap = await _spacedRepo.getFlashcardsByIds(
      flashcardIds,
      userDb,
    );

    final userQuestionsMap = await _loadUserQuestionsByIds(
      itemIds,
      executor: userDb,
    );

    // 查询笔记
    Set<String> noteQuestionIds = {};
    try {
      final noteRows = await userDb.query(
        'Notes',
        columns: ['question_id'],
        where: 'question_id IN (${List.filled(itemIds.length, '?').join(',')})',
        whereArgs: itemIds,
      );
      noteQuestionIds = noteRows
          .map((r) => r['question_id']?.toString() ?? '')
          .toSet();
    } catch (_) {}

    final validItems = <SpacedReviewItem>[];
    for (final it in cramItems) {
      if (it.itemType == ReviewItemType.flashcard) {
        validItems.add(it);
        if (validItems.length >= limit) break;
        continue;
      }
      final uq = userQuestionsMap[it.itemId];
      if (uq != null && uq.isCut) continue;
      if (plan.coveredSubjects.isNotEmpty) {
        final parentId = uq?.chapterParentId;
        if (parentId != null &&
            parentId.isNotEmpty &&
            !plan.coveredSubjects.contains(parentId)) {
          continue;
        }
      }
      validItems.add(it);
      if (validItems.length >= limit) break;
    }

    if (validItems.isEmpty) return [];

    final targetQuestionIds = <String>{};
    for (final item in validItems) {
      if (item.itemType != ReviewItemType.flashcard) {
        targetQuestionIds.add(item.itemId);
      } else {
        final fc = flashcardsMap[item.itemId];
        if (fc?.questionId != null && fc!.questionId!.isNotEmpty) {
          targetQuestionIds.add(fc.questionId!);
        }
      }
    }

    final questionsMap = await _loadQuestionsByIds(
      targetQuestionIds.toList(),
      plan: plan,
      executor: executor,
    );

    return validItems.map((rev) {
      final qId = rev.itemId;
      final isFc = rev.itemType == ReviewItemType.flashcard;
      final fc = isFc ? flashcardsMap[qId] : null;
      final linkedQuestion = isFc
          ? (fc?.questionId != null ? questionsMap[fc!.questionId] : null)
          : questionsMap[qId];

      return DailyReviewQueueItem(
        questionId: qId,
        itemType: rev.itemType,
        isNew: false,
        question: linkedQuestion,
        userQuestion: userQuestionsMap[qId],
        reviewItem: rev,
        bankId: plan.bankId,
        customFlashcard: fc,
        isFromNote: noteQuestionIds.contains(qId),
      );
    }).toList();
  }

  /// 从只读题库中抽选未做新题 ID（针对勾选 'all' 模式）
  Future<List<String>> _queryBankNewQuestionIds({
    required ReviewPlan plan,
    required int count,
    required List<String> coveredSubjects,
    DatabaseExecutor? executor,
  }) async {
    final bankDb = await _getBankDatabase(plan);
    if (bankDb == null || count <= 0) return [];
    final db = executor ?? await _userDbHelper.database;
    final bankId = await _resolveBankId(plan) ?? bankDb.path;
    return UserDatabaseCoordinator.instance.run(() async {
      await db.execute('ATTACH DATABASE ? AS review_draw_bank', [bankDb.path]);
      try {
        final cursorRows = await db.query(
          'ReviewDrawCursor',
          where: 'plan_id=? AND bank_id=?',
          whereArgs: [plan.id, bankId],
        );
        final cursor = cursorRows.isEmpty
            ? ''
            : cursorRows.single['last_id'] as String;
        final hasRelations = (await db.rawQuery(
          "SELECT name FROM review_draw_bank.sqlite_master WHERE name='IdentityQuestion'",
        )).isNotEmpty;
        final coverage = coveredSubjects.isEmpty
            ? ''
            : hasRelations
            ? 'AND EXISTS(SELECT 1 FROM review_draw_bank.IdentityQuestion iq WHERE iq.question_id=q.id AND iq.subject_id IN (${List.filled(coveredSubjects.length, '?').join(',')}))'
            : 'AND q.chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')})';
        Future<List<String>> load(String after, int take) async {
          final rows = await db.rawQuery(
            '''
            SELECT q.id FROM review_draw_bank.Question q
            LEFT JOIN main.Question uq ON uq.id=q.id
            LEFT JOIN main.SpacedReviewItem sr ON sr.item_id=q.id
            WHERE COALESCE(uq.cut_question,'0') NOT IN ('1','cutted') AND COALESCE(uq.status,0)!=3
              AND COALESCE(sr.state,0)=0 AND q.id>? $coverage
            ORDER BY q.id LIMIT ?
          ''',
            [after, ...coveredSubjects, take],
          );
          return rows.map((r) => r['id'] as String).toList();
        }

        final ids = await load(cursor, count);
        if (ids.length < count && cursor.isNotEmpty) {
          final first = await load('', count - ids.length);
          for (final id in first) {
            if (!ids.contains(id)) ids.add(id);
          }
        }
        if (ids.isNotEmpty) {
          await db.insert('ReviewDrawCursor', {
            'plan_id': plan.id,
            'bank_id': bankId,
            'last_id': ids.last,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return ids;
      } finally {
        await db.execute('DETACH DATABASE review_draw_bank');
      }
    });
  }

  /// 批量加载题目实体（严格通过 QuestionBankDatabaseManager 单例连接池复用，杜绝 macOS 6922 锁异常）
  Future<Map<String, Question>> _loadQuestionsByIds(
    List<String> ids, {
    required ReviewPlan plan,
    DatabaseExecutor? executor,
  }) async {
    if (ids.isEmpty) return {};

    // 1. 若测试中由 executor 内存库直接持有 Question（如单元测试桩），优先从 executor 读取
    if (executor != null) {
      try {
        final rows = await executor.query(
          'Question',
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
        if (rows.isNotEmpty && rows.first.containsKey('title')) {
          final map = <String, Question>{};
          for (final r in rows) {
            final q = Question.fromMap(r);
            map[q.id] = q;
          }
          return map;
        }
      } catch (_) {}
    }

    // 2. 真实题库复用连接只读查询
    final bankDb = await _getBankDatabase(plan);
    if (bankDb == null) return {};

    try {
      final rows = await bankDb.query(
        'Question',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
      );

      final map = <String, Question>{};
      for (final r in rows) {
        final q = Question.fromMap(r);
        map[q.id] = q;
      }
      return map;
    } catch (e) {
      debugPrint('[DailyReviewService] Error loading questions from bank: $e');
      return {};
    }
  }

  /// 解析目标题库 ID
  Future<String?> _resolveBankId(ReviewPlan plan) async {
    if (plan.bankId != null && plan.bankId!.isNotEmpty) {
      if (plan.bankId!.endsWith('.sqlite')) {
        return p.basenameWithoutExtension(plan.bankId!);
      }
      return plan.bankId!;
    }
    return await _bankRepo.activeBankId();
  }

  /// 获取题库数据库连接（严格通过 QuestionBankDatabaseManager 复用连接，杜绝多连接导致 macOS 6922 锁异常）
  Future<Database?> _getBankDatabase(ReviewPlan plan) async {
    final bankId = await _resolveBankId(plan);
    if (bankId == null || bankId.isEmpty) return null;

    final bankPath = await _resolveBankPath(plan);
    try {
      return await _dbManager.openBank(
        bankId,
        filePath: bankPath,
        validate: false,
      );
    } catch (e) {
      debugPrint('[DailyReviewService] Error opening bank DB ($bankId): $e');
      return null;
    }
  }

  /// 批量加载用户作答记录
  Future<Map<String, UserQuestion>> _loadUserQuestionsByIds(
    List<String> ids, {
    DatabaseExecutor? executor,
  }) async {
    if (ids.isEmpty) return {};
    final userDb = executor ?? await _userDbHelper.database;
    final rows = await userDb.query(
      'Question',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );

    final map = <String, UserQuestion>{};
    for (final r in rows) {
      final uq = UserQuestion.fromMap(r);
      map[uq.id] = uq;
    }
    return map;
  }

  /// 解析目标题库文件路径
  Future<String?> _resolveBankPath(ReviewPlan plan) async {
    if (_bankPathResolver != null) {
      return await _bankPathResolver(plan);
    }
    if (plan.bankId != null && plan.bankId!.isNotEmpty) {
      if (await File(plan.bankId!).exists()) {
        return plan.bankId!;
      }
      return await _dbManager.pathFor(plan.bankId!);
    }
    // 默认使用当前激活题库
    final activeId = await _bankRepo.activeBankId();
    return await _dbManager.pathFor(activeId);
  }

  Future<int> _countUserQuestionPool({
    required DatabaseExecutor userDb,
    required String whereCondition,
    required List<String> coveredSubjects,
  }) async {
    final whereParts = [whereCondition];
    final whereArgs = <dynamic>[];
    if (coveredSubjects.isNotEmpty) {
      whereParts.add(
        "chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')})",
      );
      whereArgs.addAll(coveredSubjects);
    }
    final rows = await userDb.rawQuery(
      'SELECT COUNT(*) as count FROM Question WHERE ${whereParts.join(' AND ')}',
      whereArgs,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> _countNotePool({
    required DatabaseExecutor userDb,
    required List<String> coveredSubjects,
  }) async {
    try {
      final whereParts = ["COALESCE(uq.cut_question, '0') != '1'"];
      final whereArgs = <dynamic>[];
      if (coveredSubjects.isNotEmpty) {
        whereParts.add(
          "(uq.chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')}) OR uq.chapter_parent_id IS NULL OR uq.chapter_parent_id = '')",
        );
        whereArgs.addAll(coveredSubjects);
      }
      final rows = await userDb.rawQuery('''
        SELECT COUNT(DISTINCT n.question_id) as count
        FROM Notes n
        LEFT JOIN Question uq ON n.question_id = uq.id
        WHERE ${whereParts.join(' AND ')}
      ''', whereArgs);
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 统计熟练掌握/斩题卡片池总量（用户库标记 cut_question = '1' 或 SpacedReviewItem 状态为 mastered 的并集去重）
  Future<int> _countMasteredPool({
    required DatabaseExecutor userDb,
    required String planId,
    required List<String> coveredSubjects,
  }) async {
    try {
      final innerWhere = coveredSubjects.isNotEmpty
          ? "AND (chapter_parent_id IN (${List.filled(coveredSubjects.length, '?').join(',')}) OR chapter_parent_id IS NULL OR chapter_parent_id = '')"
          : '';
      final rows = await userDb.rawQuery('''
        SELECT COUNT(*) as count FROM (
          SELECT id FROM Question WHERE cut_question = '1' $innerWhere
          UNION
          SELECT item_id as id FROM SpacedReviewItem WHERE state = 3
        )
      ''', coveredSubjects.isNotEmpty ? [...coveredSubjects] : []);
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countSpacedItemState({
    required DatabaseExecutor userDb,
    required int state,
    required String planId,
  }) async {
    final whereParts = ['state = ?'];
    final whereArgs = <dynamic>[state];
    if (planId.isNotEmpty) {
      whereParts.add('(plan_id = ? OR plan_id IS NULL)');
      whereArgs.add(planId);
    }
    final rows = await userDb.rawQuery(
      'SELECT COUNT(*) as count FROM SpacedReviewItem WHERE ${whereParts.join(' AND ')}',
      whereArgs,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
