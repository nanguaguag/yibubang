import 'question.dart';
import 'spaced_review_item.dart';

/// 每日抽题刷题队列中的单项
class DailyReviewQueueItem {
  /// 唯一标识（对于题库题目为全局唯一 question_id）
  final String questionId;

  /// 内容类型（选择题、填空题、主观题、笔记、自制闪卡）
  final ReviewItemType itemType;

  /// 是否为今日新抽取的题目（true: 今日新学, false: 到期复习）
  final bool isNew;

  /// 题目详情实体（若为题库题目）
  final Question? question;

  /// 用户作答记录（user_data.Question）
  final UserQuestion? userQuestion;

  /// 记忆曲线调度状态（SpacedReviewItem）
  final SpacedReviewItem? reviewItem;

  /// 所属题库 ID
  final String? bankId;

  /// 自制卡片数据（若为 flashcard）
  final CustomFlashcard? customFlashcard;

  /// 是否包含个人笔记/由笔记来源抽取
  final bool isFromNote;

  const DailyReviewQueueItem({
    required this.questionId,
    this.itemType = ReviewItemType.question,
    required this.isNew,
    this.question,
    this.userQuestion,
    this.reviewItem,
    this.bankId,
    this.customFlashcard,
    this.isFromNote = false,
  });

  DailyReviewQueueItem copyWith({
    String? questionId,
    ReviewItemType? itemType,
    bool? isNew,
    Question? question,
    UserQuestion? userQuestion,
    SpacedReviewItem? reviewItem,
    String? bankId,
    CustomFlashcard? customFlashcard,
    bool? isFromNote,
  }) {
    return DailyReviewQueueItem(
      questionId: questionId ?? this.questionId,
      itemType: itemType ?? this.itemType,
      isNew: isNew ?? this.isNew,
      question: question ?? this.question,
      userQuestion: userQuestion ?? this.userQuestion,
      reviewItem: reviewItem ?? this.reviewItem,
      bankId: bankId ?? this.bankId,
      customFlashcard: customFlashcard ?? this.customFlashcard,
      isFromNote: isFromNote ?? this.isFromNote,
    );
  }
}

/// 每日抽题与记忆复习会话
class DailyReviewSession {
  /// 当前激活的计划
  final ReviewPlan plan;

  /// 会话所属日期
  final DateTime date;

  /// 今日到期复习队列（复习优先）
  final List<DailyReviewQueueItem> dueQueue;

  /// 今日新抽题目队列
  final List<DailyReviewQueueItem> newQueue;

  /// 今日已学新题数
  final int completedNewToday;

  /// 今日已复习题数
  final int completedReviewToday;

  /// 是否为超额提前巩固模式（新题与到期复习均已完成，提前强化在学卡片）
  final bool isCramMode;

  const DailyReviewSession({
    required this.plan,
    required this.date,
    required this.dueQueue,
    required this.newQueue,
    this.completedNewToday = 0,
    this.completedReviewToday = 0,
    this.isCramMode = false,
  });

  /// 完整待刷队列（默认按百词斩模式：先复习、后新学）
  List<DailyReviewQueueItem> get allItems => [...dueQueue, ...newQueue];

  /// 今日剩余待刷总题量
  int get totalRemaining => dueQueue.length + newQueue.length;

  /// 今日计划是否全部完成
  bool get isFinishedToday => totalRemaining == 0;
}

/// 今日学习概要（用于「每日计划」Tab 卡片展示）
class DailyReviewSummary {
  final String planId;
  final String planName;
  final int dailyNewTarget;
  final int dailyReviewLimit;
  final int completedNewToday;
  final int completedReviewToday;
  final int remainingDueCount;
  final int remainingNewCount;
  final int streakDays;
  final List<String> sourceTypes;
  final List<String> coveredSubjects;
  final int poolWrongCount;
  final int poolCollectedCount;
  final int poolNoteCount;
  final int poolFlashcardCount;
  final int poolLearningCount;
  final int poolMasteredCount;

  const DailyReviewSummary({
    required this.planId,
    required this.planName,
    required this.dailyNewTarget,
    required this.dailyReviewLimit,
    required this.completedNewToday,
    required this.completedReviewToday,
    required this.remainingDueCount,
    required this.remainingNewCount,
    this.streakDays = 1,
    this.sourceTypes = const ['wrong', 'collected', 'note'],
    this.coveredSubjects = const [],
    this.poolWrongCount = 0,
    this.poolCollectedCount = 0,
    this.poolNoteCount = 0,
    this.poolFlashcardCount = 0,
    this.poolLearningCount = 0,
    this.poolMasteredCount = 0,
  });

  int get totalRemaining => remainingDueCount + remainingNewCount;
  bool get isCompleted => totalRemaining == 0;
}
