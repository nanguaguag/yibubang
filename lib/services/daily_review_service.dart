import 'package:shared_preferences/shared_preferences.dart';
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
  final Future<Map<String, String>> Function(ReviewPlan plan)?
  _bankPathsResolver;

  DailyReviewService({
    SpacedReviewRepository? spacedRepo,
    QuestionBankRepository? bankRepo,
    QuestionBankDatabaseManager? dbManager,
    SpacedRepetitionEngine? engine,
    UserDBHelper? userDbHelper,
    Future<String?> Function(ReviewPlan plan)? bankPathResolver,
    Future<Map<String, String>> Function(ReviewPlan plan)? bankPathsResolver,
  }) : _spacedRepo = spacedRepo ?? SpacedReviewRepository(),
       _bankRepo = bankRepo ?? QuestionBankRepository(),
       _dbManager = dbManager ?? QuestionBankDatabaseManager(),
       _engine = engine ?? const SpacedRepetitionEngine(),
       _userDbHelper = userDbHelper ?? UserDBHelper(),
       _bankPathResolver = bankPathResolver,
       _bankPathsResolver = bankPathsResolver;

  /// 组装今日刷题会话（到期复习队列 + 今日新题队列）
  /// [isExtraSession] 为 true 时表示用户主动“再学一组”，无视今日已完成目标限制，直接按 dailyNewTarget 抽取新卡片
  Future<DailyReviewSession> buildDailySession({
    ReviewPlan? customPlan,
    DateTime? now,
    DatabaseExecutor? executor,
    bool isExtraSession = false,
  }) async {
    final currentTime = (now ?? DateTime.now()).toLocal();
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
    final currentTime = (now ?? DateTime.now()).toLocal();

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
    final currentTime = (now ?? DateTime.now()).toLocal();
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
    final currentTime = (now ?? DateTime.now()).toLocal();
    final todayStart = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    ).millisecondsSinceEpoch;
    final todayEnd =
        DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day + 1,
        ).millisecondsSinceEpoch -
        1;

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

    final userDb = executor ?? await _userDbHelper.database;
    final remainingDue = (await _fetchDueReviewQueue(
      plan: plan,
      limit: math.max(0, plan.dailyReviewLimit - completedReview),
      now: currentTime,
      executor: userDb,
    )).length;
    final remainingNew = math.max(0, plan.dailyNewTarget - completedNew);
    final pools = await _scopePoolCounts(userDb, plan);
    final poolWrong = pools['wrong'] ?? 0;
    final poolCollected = pools['collected'] ?? 0;
    final poolNote = pools['notes'] ?? 0;
    final poolFlashcard = await _countFlashcardPool(userDb: userDb);
    final poolLearning = pools['learning'] ?? 0;
    final poolMastered = pools['mastered'] ?? 0;

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
      final yesterday = DateTime(now.year, now.month, now.day - 1);
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
          checkDate = DateTime(
            checkDate.year,
            checkDate.month,
            checkDate.day - 1,
          );
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
    final localStart = DateTime.fromMillisecondsSinceEpoch(todayStart);
    final end =
        todayEnd ??
        (DateTime(
              localStart.year,
              localStart.month,
              localStart.day + 1,
            ).millisecondsSinceEpoch -
            1);
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
      final noteRows = await _noteRows(userDb, itemIds);
      noteQuestionIds = noteRows
          .map((r) => r['question_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {}

    final actualQuestions = await _loadQuestionsByIds(
      {
        ...itemIds,
        ...flashcardsMap.values.map((fc) => fc.questionId).whereType<String>(),
      }.toList(),
      plan: plan,
      executor: userDb,
    );
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

      if (!actualQuestions.containsKey(it.itemId)) continue;

      validDueItems.add(it);
      if (validDueItems.length >= limit) break;
    }

    if (validDueItems.isEmpty) return [];

    final questionsMap = actualQuestions;

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
        bankId: linkedQuestion?.sourceBankId ?? plan.bankId,
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

    // 3. 从笔记抽选；课程范围由只读题库的真实关系验证。
    if (sourceTypes.contains('note')) {
      final rows = await userDb.rawQuery("""
        SELECT DISTINCT n.question_id AS id FROM Notes n
        LEFT JOIN Question uq ON uq.id=n.question_id
        WHERE COALESCE(uq.cut_question,'0') NOT IN ('1','cutted')
      """);
      candidateIds.addAll(rows.map((r) => r['id'] as String));
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

      final entities = await _loadQuestionsByIds(
        chunk,
        plan: plan,
        executor: userDb,
      );
      final cards = await _spacedRepo.getFlashcardsByIds(chunk, userDb);
      for (final id in chunk) {
        if (!inReviewSet.contains(id) &&
            !cutIds.contains(id) &&
            (entities.containsKey(id) || cards.containsKey(id))) {
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
      final noteRows = await _noteRows(userDb, selectedIds);
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
        bankId: linkedQuestion?.sourceBankId ?? plan.bankId,
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
      final noteRows = await _noteRows(userDb, itemIds);
      noteQuestionIds = noteRows
          .map((r) => r['question_id']?.toString() ?? '')
          .toSet();
    } catch (_) {}

    final actualQuestions = await _loadQuestionsByIds(
      {
        ...itemIds,
        ...flashcardsMap.values.map((fc) => fc.questionId).whereType<String>(),
      }.toList(),
      plan: plan,
      executor: userDb,
    );
    final validItems = <SpacedReviewItem>[];
    for (final it in cramItems) {
      if (it.itemType == ReviewItemType.flashcard) {
        if (!flashcardsMap.containsKey(it.itemId)) continue;
        validItems.add(it);
        if (validItems.length >= limit) break;
        continue;
      }
      final uq = userQuestionsMap[it.itemId];
      if (uq != null && uq.isCut) continue;
      if (!actualQuestions.containsKey(it.itemId)) continue;
      validItems.add(it);
      if (validItems.length >= limit) break;
    }

    if (validItems.isEmpty) return [];

    final questionsMap = actualQuestions;

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
        bankId: linkedQuestion?.sourceBankId ?? plan.bankId,
        customFlashcard: fc,
        isFromNote: noteQuestionIds.contains(qId),
      );
    }).toList();
  }

  /// 从只读题库中抽选未做新题 ID（针对勾选 'all' 模式）
  Future<Map<String, Database>> _scopeBanks(ReviewPlan plan) async {
    final result = <String, Database>{};
    if (_bankPathsResolver != null) {
      final paths = await _bankPathsResolver(plan);
      for (final entry in paths.entries) {
        if (plan.bankId?.isNotEmpty == true && entry.key != plan.bankId) {
          continue;
        }
        result[entry.key] = await _dbManager.openBank(
          entry.key,
          filePath: entry.value,
          validate: false,
        );
      }
      return result;
    }
    if (plan.bankId?.isNotEmpty == true || _bankPathResolver != null) {
      final bank = await _getBankDatabase(plan);
      if (bank != null) {
        result[await _resolveBankId(plan) ??
                p.basenameWithoutExtension(bank.path)] =
            bank;
      }
      return result;
    }
    final banks = (await _bankRepo.listBanks())
        .where((b) => b.enabled && b.isInstalled)
        .toList();
    final active = (await SharedPreferences.getInstance()).getString(
      'activeBankId',
    );
    banks.sort(
      (a, b) => a.bankId == b.bankId
          ? 0
          : a.bankId == active
          ? -1
          : b.bankId == active
          ? 1
          : a.bankId.compareTo(b.bankId),
    );
    for (final bank in banks) {
      if (await File(bank.localPath).exists()) {
        result[bank.bankId] = await _dbManager.openBank(
          bank.bankId,
          filePath: bank.localPath,
          validate: false,
        );
      }
    }
    return result;
  }

  /// 课程集合放用户连接的临时表；题库只参与 ATTACH SELECT。
  Future<T> _withScopeBank<T>(
    DatabaseExecutor db,
    Database bank,
    ReviewPlan plan,
    Future<T> Function(
      String from,
      String filter,
      List<Object?> args,
      bool relations,
    )
    work,
  ) => UserDatabaseCoordinator.instance.run(() async {
    await db.execute(
      'CREATE TEMP TABLE review_scope_subjects(id TEXT PRIMARY KEY)',
    );
    var attached = false;
    try {
      final batch = db.batch();
      for (final id in plan.coveredSubjects.toSet()) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO temp.review_scope_subjects VALUES (?)',
          [id],
        );
      }
      await batch.apply(noResult: true);
      await db.execute('ATTACH DATABASE ? AS review_scope_bank', [bank.path]);
      attached = true;
      final hasRelations = (await db.rawQuery(
        "SELECT name FROM review_scope_bank.sqlite_master WHERE name='IdentityQuestion'",
      )).isNotEmpty;
      final from = hasRelations
          ? 'review_scope_bank.Question q JOIN review_scope_bank.IdentityQuestion iq ON iq.question_id=q.id'
          : 'review_scope_bank.Question q';
      final subject = hasRelations ? 'iq.subject_id' : 'q.chapter_parent_id';
      final conditions = <String>['1=1'];
      final args = <Object?>[];
      if (plan.coveredSubjects.isNotEmpty) {
        conditions.add(
          'EXISTS(SELECT 1 FROM temp.review_scope_subjects s WHERE s.id=$subject)',
        );
      }
      if (plan.subjectId?.isNotEmpty == true) {
        conditions.add('$subject=?');
        args.add(plan.subjectId);
      }
      if (hasRelations && plan.identityId?.isNotEmpty == true) {
        conditions.add('iq.identity_id=?');
        args.add(plan.identityId);
      }
      return await work(from, conditions.join(' AND '), args, hasRelations);
    } finally {
      if (attached) await db.execute('DETACH DATABASE review_scope_bank');
      await db.execute('DROP TABLE temp.review_scope_subjects');
    }
  });

  Future<List<String>> _queryBankNewQuestionIds({
    required ReviewPlan plan,
    required int count,
    required List<String> coveredSubjects,
    DatabaseExecutor? executor,
  }) async {
    if (count <= 0) return [];
    final db = executor ?? await _userDbHelper.database;
    final candidates = <String>{};
    for (final entry in (await _scopeBanks(plan)).entries) {
      final ids = await _withScopeBank(db, entry.value, plan, (
        from,
        filter,
        args,
        relations,
      ) async {
        final cursorRows = await db.query(
          'ReviewDrawCursor',
          where: 'plan_id=? AND bank_id=?',
          whereArgs: [plan.id, entry.key],
        );
        final cursor = cursorRows.isEmpty
            ? ''
            : cursorRows.single['last_id'] as String;
        Future<List<String>> load(String after, int take) async {
          final rows = await db.rawQuery(
            "SELECT DISTINCT q.id FROM $from LEFT JOIN main.Question uq ON uq.id=q.id LEFT JOIN main.SpacedReviewItem sr ON sr.item_id=q.id WHERE $filter AND COALESCE(uq.cut_question,'0') NOT IN ('1','cutted') AND COALESCE(uq.status,0)!=3 AND COALESCE(sr.state,0)=0 AND q.id>? ORDER BY q.id LIMIT ?",
            [...args, after, take],
          );
          return rows.map((r) => r['id'] as String).toList();
        }

        final found = await load(cursor, count);
        if (found.length < count && cursor.isNotEmpty) {
          for (final id in await load('', count - found.length)) {
            if (!found.contains(id)) found.add(id);
          }
        }
        if (found.isNotEmpty) {
          await db.insert('ReviewDrawCursor', {
            'plan_id': plan.id,
            'bank_id': entry.key,
            'last_id': found.last,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return found;
      });
      candidates.addAll(ids);
    }
    return candidates.toList();
  }

  /// 批量加载题目实体（严格通过 QuestionBankDatabaseManager 单例连接池复用，杜绝 macOS 6922 锁异常）
  Future<Map<String, Question>> _loadQuestionsByIds(
    List<String> ids, {
    required ReviewPlan plan,
    DatabaseExecutor? executor,
  }) async {
    if (ids.isEmpty) return {};
    final db = executor ?? await _userDbHelper.database;
    final result = <String, Question>{};
    final banks = await _scopeBanks(plan);
    for (final bank in banks.entries) {
      await _withScopeBank(db, bank.value, plan, (
        from,
        filter,
        args,
        relations,
      ) async {
        for (var i = 0; i < ids.length; i += 500) {
          final chunk = ids.sublist(i, math.min(i + 500, ids.length));
          final contextColumns = relations
              ? ',iq.subject_id AS scope_subject,iq.chapter_id AS scope_chapter,iq.identity_id AS scope_identity'
              : '';
          final rows = await db.rawQuery(
            "SELECT q.* $contextColumns FROM $from WHERE $filter AND q.id IN (${List.filled(chunk.length, '?').join(',')}) ORDER BY q.id",
            [...args, ...chunk],
          );
          for (final row in rows) {
            final q = Question.fromMap(row)..sourceBankId = bank.key;
            if (relations) {
              q.chapterParentId = row['scope_subject'] as String?;
              q.chapterId = row['scope_chapter'] as String?;
              q.identityId = row['scope_identity'] as String?;
            }
            result.putIfAbsent(q.id, () => q);
          }
        }
      });
    }
    return result;
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
    final map = <String, UserQuestion>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, math.min(i + 500, ids.length));
      for (final row in await userDb.query(
        'Question',
        where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      )) {
        final uq = UserQuestion.fromMap(row);
        map[uq.id] = uq;
      }
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

  Future<List<Map<String, Object?>>> _noteRows(
    DatabaseExecutor db,
    List<String> ids,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, math.min(i + 500, ids.length));
      rows.addAll(
        await db.query(
          'Notes',
          columns: ['question_id'],
          where: 'question_id IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: chunk,
        ),
      );
    }
    return rows;
  }

  Future<Map<String, int>> _scopePoolCounts(
    DatabaseExecutor db,
    ReviewPlan plan,
  ) async {
    final banks = await _scopeBanks(plan);
    return UserDatabaseCoordinator.instance.run(() async {
      await db.execute(
        'CREATE TEMP TABLE review_pool_ids(id TEXT PRIMARY KEY)',
      );
      try {
        for (final bank in banks.values) {
          await _withScopeBank(
            db,
            bank,
            plan,
            (from, filter, args, relations) => db.rawInsert(
              'INSERT OR IGNORE INTO temp.review_pool_ids SELECT DISTINCT q.id FROM $from WHERE $filter',
              args,
            ),
          );
        }
        final counts = (await db.rawQuery(
          "SELECT SUM(CASE WHEN uq.status=2 THEN 1 ELSE 0 END) AS wrong,SUM(CASE WHEN uq.collection=1 THEN 1 ELSE 0 END) AS collected FROM main.Question uq JOIN temp.review_pool_ids p ON p.id=uq.id WHERE COALESCE(uq.cut_question,'0') NOT IN ('1','cutted')",
        )).single;
        final noteRows = await db.rawQuery(
          "SELECT COUNT(DISTINCT n.question_id) FROM main.Notes n JOIN temp.review_pool_ids p ON p.id=n.question_id LEFT JOIN main.Question uq ON uq.id=n.question_id WHERE COALESCE(uq.cut_question,'0') NOT IN ('1','cutted')",
        );
        final learning = await db.rawQuery(
          "SELECT COUNT(*) FROM main.SpacedReviewItem s WHERE s.state=1 AND (s.plan_id=? OR s.plan_id IS NULL) AND (s.item_type='flashcard' OR s.item_id IN (SELECT id FROM temp.review_pool_ids))",
          [plan.id],
        );
        final mastered = await db.rawQuery(
          "SELECT COUNT(*) FROM (SELECT uq.id FROM main.Question uq JOIN temp.review_pool_ids p ON p.id=uq.id WHERE uq.cut_question IN ('1','cutted') UNION SELECT s.item_id AS id FROM main.SpacedReviewItem s WHERE s.state=3 AND (s.plan_id=? OR s.plan_id IS NULL) AND (s.item_type='flashcard' OR s.item_id IN (SELECT id FROM temp.review_pool_ids)))",
          [plan.id],
        );
        return {
          'wrong': (counts['wrong'] as num?)?.toInt() ?? 0,
          'collected': (counts['collected'] as num?)?.toInt() ?? 0,
          'notes': Sqflite.firstIntValue(noteRows) ?? 0,
          'learning': Sqflite.firstIntValue(learning) ?? 0,
          'mastered': Sqflite.firstIntValue(mastered) ?? 0,
        };
      } finally {
        await db.execute('DROP TABLE temp.review_pool_ids');
      }
    });
  }
}
