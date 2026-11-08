import 'dart:math' as math;
import '../models/spaced_review_item.dart';

/// 艾宾浩斯 / SM-2 间隔重复调度引擎
///
/// 纯 Dart 逻辑实现，无外部硬件或平台依赖。
/// 支持客观题（根据对错和答题用时驱动）与主观自评/闪卡/笔记（根据用户 4 档或 2 档评分驱动）。
class SpacedRepetitionEngine {
  /// 默认初始 Ease Factor (简易度因子)
  final double startingEaseFactor;

  /// 最低 Ease Factor 下限（避免跌入永久重现陷阱）
  final double minEaseFactor;

  /// Easy 评分时的额外间隔加成系数
  final double easyBonus;

  /// Hard 评分时的间隔缩放系数
  final double hardIntervalMultiplier;

  /// 判定为快速答对/秒答的时间阈值（秒）
  final int quickAnswerDurationThreshold;

  /// 连续正确达到该次数且间隔充足时，可标记为已掌握
  final int masteryRepThreshold;

  const SpacedRepetitionEngine({
    this.startingEaseFactor = 2.5,
    this.minEaseFactor = 1.3,
    this.easyBonus = 1.3,
    this.hardIntervalMultiplier = 1.2,
    this.quickAnswerDurationThreshold = 6,
    this.masteryRepThreshold = 5,
  });

  /// 对指定时间按本地自然日对齐至当天 00:00:00
  static DateTime startOfDay(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// 计算下次到期日（按自然日顺延，保证同一天到期的题目在当天零点统一就绪）
  static int calculateDueDate(DateTime baseDate, int intervalDays) {
    final sod = startOfDay(baseDate);
    final due = sod.add(Duration(days: math.max(1, intervalDays)));
    return due.millisecondsSinceEpoch;
  }

  /// 根据用户的显式评分（Again / Hard / Good / Easy）演进记忆状态
  SpacedReviewItem evaluateRating({
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
        // 遗忘/重来：重置连续正确次数，增加失误计数，EF 适度衰减，间隔回退至 1 天
        newReps = 0;
        newLapses += 1;
        newInterval = 1;
        newEaseFactor = math.max(minEaseFactor, item.easeFactor - 0.20);
        newState = ReviewState.learning;
        break;

      case ReviewRating.hard:
        // 较难/犹豫：连续次数 +1，间隔增长放缓，EF 略微降低
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
        // 良好/顺利记起：标准 SM-2 迭代
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
        // Good 评级维持稳定 EF
        newState = ReviewState.review;
        break;

      case ReviewRating.easy:
        // 简单/太熟：跨越式增大间隔，增加 EF
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

    // 检查是否达到完全熟记/斩题阶段（连续正确 >= masteryRepThreshold 且间隔超过 30 天）
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

  /// 针对常规选择题等客观题的简易驱动：
  /// - 答错：自动视作 `again`；
  /// - 答对：若答题用时很短（<= quickAnswerDurationThreshold），自动视作 `easy`；否则为 `good`。
  SpacedReviewItem evaluateObjectiveAnswer({
    required SpacedReviewItem item,
    required bool isCorrect,
    int durationSeconds = 0,
    DateTime? now,
  }) {
    if (!isCorrect) {
      return evaluateRating(
        item: item,
        rating: ReviewRating.again,
        now: now,
      );
    }

    final ReviewRating rating;
    if (durationSeconds > 0 && durationSeconds <= quickAnswerDurationThreshold) {
      rating = ReviewRating.easy;
    } else {
      rating = ReviewRating.good;
    }

    return evaluateRating(
      item: item,
      rating: rating,
      now: now,
    );
  }

  /// 预估每个评分按钮将产生的下次复习间隔天数（用于在做题 UI 按钮上标注：如「重来(1天) / 较难(2天) / 良好(6天) / 简单(10天)」）
  Map<ReviewRating, int> previewNextIntervals(SpacedReviewItem item) {
    final now = DateTime.now();
    return {
      ReviewRating.again: evaluateRating(item: item, rating: ReviewRating.again, now: now).interval,
      ReviewRating.hard: evaluateRating(item: item, rating: ReviewRating.hard, now: now).interval,
      ReviewRating.good: evaluateRating(item: item, rating: ReviewRating.good, now: now).interval,
      ReviewRating.easy: evaluateRating(item: item, rating: ReviewRating.easy, now: now).interval,
    };
  }
}
