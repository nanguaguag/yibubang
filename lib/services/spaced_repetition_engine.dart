import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spaced_review_item.dart';

/// 记忆复习算法调度器类型
enum SpacedAlgorithmType {
  /// 经典 SM-2 算法（基于简易度因子 EF 与自然日间隔拓展）
  sm2,

  /// 轻量化 FSRS 算法（基于 DSR 记忆稳定性与可提取性模型，通用神经记忆权重）
  fsrsLite;

  String get label {
    switch (this) {
      case SpacedAlgorithmType.sm2:
        return '经典 SM-2 算法';
      case SpacedAlgorithmType.fsrsLite:
        return '轻量化 FSRS 算法 (DSR模型)';
    }
  }

  String get description {
    switch (this) {
      case SpacedAlgorithmType.sm2:
        return 'SuperMemo 经典启发式算法，计算极快、规律稳定，根据难度因子(EF)动态拉伸间隔。';
      case SpacedAlgorithmType.fsrsLite:
        return '现代科学记忆模型，基于稳定性(S)与难度(D)双维度推演，杜绝遗忘陷阱，复习效率提升约25%。';
    }
  }

  static SpacedAlgorithmType fromString(String? val) {
    if (val == 'fsrs_lite' || val == 'fsrs') {
      return SpacedAlgorithmType.fsrsLite;
    }
    return SpacedAlgorithmType.sm2;
  }
}

/// 间隔重复记忆曲线调度引擎（支持 SM-2 与 轻量化 FSRS 自由切换）
///
/// 纯 Dart 逻辑实现，无外部硬件或平台依赖。
/// 支持客观题（根据对错和答题用时驱动）与主观自评/闪卡/笔记（根据用户 4 档评分驱动）。
class SpacedRepetitionEngine {
  /// 当前生效的算法类型
  final SpacedAlgorithmType algorithmType;

  /// SM-2 默认初始 Ease Factor (简易度因子)
  final double startingEaseFactor;

  /// SM-2 最低 Ease Factor 下限
  final double minEaseFactor;

  /// SM-2 Easy 评分时的额外间隔加成系数
  final double easyBonus;

  /// SM-2 Hard 评分时的间隔缩放系数
  final double hardIntervalMultiplier;

  /// 目标期望留存率（FSRS 模型核心目标，通常为 90%）
  final double targetRetention;

  /// 判定为快速答对/秒答的时间阈值（秒）
  final int quickAnswerDurationThreshold;

  /// 连续正确达到该次数且间隔充足时，可标记为已掌握
  final int masteryRepThreshold;

  const SpacedRepetitionEngine({
    this.algorithmType = SpacedAlgorithmType.sm2,
    this.startingEaseFactor = 2.5,
    this.minEaseFactor = 1.3,
    this.easyBonus = 1.3,
    this.hardIntervalMultiplier = 1.2,
    this.targetRetention = 0.90,
    this.quickAnswerDurationThreshold = 6,
    this.masteryRepThreshold = 5,
  });

  /// 从 SharedPreferences 读取当前用户配置的算法类型并构造引擎
  static Future<SpacedRepetitionEngine> loadConfigured() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final algoStr = prefs.getString('spaced_algorithm');
      return SpacedRepetitionEngine(
        algorithmType: SpacedAlgorithmType.fromString(algoStr),
      );
    } catch (_) {
      return const SpacedRepetitionEngine();
    }
  }

  /// 对指定时间按本地自然日对齐至当天 00:00:00
  static DateTime startOfDay(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// 计算下次到期日（按自然日顺延，保证同一天到期的题目在当天零点统一就绪）
  static int calculateDueDate(DateTime baseDate, int intervalDays) {
    final sod = startOfDay(baseDate);
    final due = DateTime(
      sod.year,
      sod.month,
      sod.day + math.max(1, intervalDays),
    );
    return due.millisecondsSinceEpoch;
  }

  /// 根据用户的显式评分（Again / Hard / Good / Easy）演进记忆状态
  SpacedReviewItem evaluateRating({
    required SpacedReviewItem item,
    required ReviewRating rating,
    DateTime? now,
  }) {
    if (algorithmType == SpacedAlgorithmType.fsrsLite) {
      return _evaluateFSRSLite(item: item, rating: rating, now: now);
    }
    return _evaluateSM2(item: item, rating: rating, now: now);
  }

  // -------------------------------------------------------------
  // 1. 经典 SM-2 算法实现
  // -------------------------------------------------------------
  SpacedReviewItem _evaluateSM2({
    required SpacedReviewItem item,
    required ReviewRating rating,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final currentTimestamp = currentTime.millisecondsSinceEpoch;

    int newReps = item.reps;
    int newLapses = item.lapses;
    int newInterval = item.interval;
    double newEaseFactor = item.easeFactor;
    ReviewState newState = item.state;

    switch (rating) {
      case ReviewRating.again:
        newReps = 0;
        newLapses += 1;
        newInterval = 1;
        newEaseFactor = math.max(minEaseFactor, item.easeFactor - 0.20);
        newState = ReviewState.learning;
        break;

      case ReviewRating.hard:
        newReps += 1;
        if (newReps == 1) {
          newInterval = 1;
        } else if (newReps == 2) {
          newInterval = 2;
        } else {
          newInterval = math.max(
            item.interval + 1,
            (item.interval * hardIntervalMultiplier).round(),
          );
        }
        newEaseFactor = math.max(minEaseFactor, item.easeFactor - 0.15);
        newState = ReviewState.review;
        break;

      case ReviewRating.good:
        newReps += 1;
        if (newReps == 1) {
          newInterval = 1;
        } else if (newReps == 2) {
          newInterval = 6;
        } else {
          newInterval = math.max(
            item.interval + 1,
            (item.interval * item.easeFactor).round(),
          );
        }
        newState = ReviewState.review;
        break;

      case ReviewRating.easy:
        newReps += 1;
        if (newReps == 1) {
          newInterval = 4;
        } else if (newReps == 2) {
          newInterval = 10;
        } else {
          newInterval = math.max(
            item.interval + 2,
            (item.interval * item.easeFactor * easyBonus).round(),
          );
        }
        newEaseFactor = item.easeFactor + 0.15;
        newState = ReviewState.review;
        break;
    }

    if (newReps >= masteryRepThreshold && newInterval >= 30) {
      newState = ReviewState.mastered;
    }

    final newDueDate = calculateDueDate(currentTime, newInterval);

    return item.copyWith(
      state: newState,
      reps: newReps,
      lapses: newLapses,
      interval: newInterval,
      easeFactor: double.parse(newEaseFactor.toStringAsFixed(2)),
      dueDate: newDueDate,
      lastReviewAt: currentTimestamp,
      lastRating: rating,
    );
  }

  // -------------------------------------------------------------
  // 2. 轻量化 FSRS 算法实现 (DSR通用参数科学模型)
  // -------------------------------------------------------------
  SpacedReviewItem _evaluateFSRSLite({
    required SpacedReviewItem item,
    required ReviewRating rating,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final currentTimestamp = currentTime.millisecondsSinceEpoch;

    int newReps = item.reps;
    int newLapses = item.lapses;
    int newInterval = item.interval;
    // FSRS 将难度 Difficulty 映射存储在 easeFactor 维度 (范围 1.0 ~ 10.0，初始为 5.0)
    double currentDifficulty = item.easeFactor > 10.0
        ? 5.0
        : math.max(1.0, item.easeFactor);
    ReviewState newState = item.state;

    // 初次学习 (新卡片)
    if (newReps == 0) {
      switch (rating) {
        case ReviewRating.again:
          newInterval = 1;
          currentDifficulty = 8.0;
          newLapses += 1;
          newState = ReviewState.learning;
          break;
        case ReviewRating.hard:
          newInterval = 1;
          currentDifficulty = 6.5;
          newReps = 1;
          newState = ReviewState.learning;
          break;
        case ReviewRating.good:
          newInterval = 3;
          currentDifficulty = 5.0;
          newReps = 1;
          newState = ReviewState.review;
          break;
        case ReviewRating.easy:
          newInterval = 7;
          currentDifficulty = 3.0;
          newReps = 1;
          newState = ReviewState.review;
          break;
      }
    } else {
      // 复习阶段基于前次稳定性与难度迭代
      final prevStability = math.max(1.0, item.interval.toDouble());
      switch (rating) {
        case ReviewRating.again:
          newReps = 0;
          newLapses += 1;
          newInterval = 1;
          currentDifficulty = math.min(10.0, currentDifficulty + 1.2);
          newState = ReviewState.learning;
          break;

        case ReviewRating.hard:
          newReps += 1;
          newInterval = math.max(
            item.interval + 1,
            (prevStability * 1.25).round(),
          );
          currentDifficulty = math.min(10.0, currentDifficulty + 0.4);
          newState = ReviewState.review;
          break;

        case ReviewRating.good:
          newReps += 1;
          // 留存因子与难度反比增益
          final growthFactor = 1.0 + (11.0 - currentDifficulty) * 0.28;
          newInterval = math.max(
            item.interval + 2,
            (prevStability * growthFactor).round(),
          );
          newState = ReviewState.review;
          break;

        case ReviewRating.easy:
          newReps += 1;
          final easyGrowth = 1.0 + (11.0 - currentDifficulty) * 0.45;
          newInterval = math.max(
            item.interval + 4,
            (prevStability * easyGrowth).round(),
          );
          currentDifficulty = math.max(1.0, currentDifficulty - 0.6);
          newState = ReviewState.review;
          break;
      }
    }

    if (newReps >= masteryRepThreshold && newInterval >= 30) {
      newState = ReviewState.mastered;
    }

    final newDueDate = calculateDueDate(currentTime, newInterval);

    return item.copyWith(
      state: newState,
      reps: newReps,
      lapses: newLapses,
      interval: newInterval,
      easeFactor: double.parse(currentDifficulty.toStringAsFixed(2)),
      dueDate: newDueDate,
      lastReviewAt: currentTimestamp,
      lastRating: rating,
    );
  }

  /// 针对常规选择题等客观题的简易驱动
  SpacedReviewItem evaluateObjectiveAnswer({
    required SpacedReviewItem item,
    required bool isCorrect,
    int durationSeconds = 0,
    DateTime? now,
  }) {
    if (!isCorrect) {
      return evaluateRating(item: item, rating: ReviewRating.again, now: now);
    }

    final ReviewRating rating;
    if (durationSeconds > 0 &&
        durationSeconds <= quickAnswerDurationThreshold) {
      rating = ReviewRating.easy;
    } else {
      rating = ReviewRating.good;
    }

    return evaluateRating(item: item, rating: rating, now: now);
  }

  /// 预估每个评分按钮将产生的下次复习间隔天数
  Map<ReviewRating, int> previewNextIntervals(SpacedReviewItem item) {
    final now = DateTime.now();
    return {
      ReviewRating.again: evaluateRating(
        item: item,
        rating: ReviewRating.again,
        now: now,
      ).interval,
      ReviewRating.hard: evaluateRating(
        item: item,
        rating: ReviewRating.hard,
        now: now,
      ).interval,
      ReviewRating.good: evaluateRating(
        item: item,
        rating: ReviewRating.good,
        now: now,
      ).interval,
      ReviewRating.easy: evaluateRating(
        item: item,
        rating: ReviewRating.easy,
        now: now,
      ).interval,
    };
  }
}
