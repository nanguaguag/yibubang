import 'dart:convert';

/// 记忆复习项目的类型，具备充分的可扩展性（兼容选择题、填空题、主观题、笔记与自制卡片）
enum ReviewItemType {
  /// 客观选择题（单选、多选、A3/A4、B型题）
  question,

  /// 填空题
  fillBlank,

  /// 主观题自评（名词解释、简答、案例分析）
  subjective,

  /// 学习笔记与重点速记
  note,

  /// 自制卡片（正面/反面翻转问答闪卡）
  flashcard;

  String get value {
    switch (this) {
      case ReviewItemType.question:
        return 'question';
      case ReviewItemType.fillBlank:
        return 'fill_blank';
      case ReviewItemType.subjective:
        return 'subjective';
      case ReviewItemType.note:
        return 'note';
      case ReviewItemType.flashcard:
        return 'flashcard';
    }
  }

  static ReviewItemType fromString(String? val) {
    switch (val) {
      case 'fill_blank':
        return ReviewItemType.fillBlank;
      case 'subjective':
        return ReviewItemType.subjective;
      case 'note':
        return ReviewItemType.note;
      case 'flashcard':
        return ReviewItemType.flashcard;
      case 'question':
      default:
        return ReviewItemType.question;
    }
  }
}

/// 记忆生命周期状态
enum ReviewState {
  /// 新加入/未开始
  new_,

  /// 学习中（初期熟悉阶段）
  learning,

  /// 复习中（进入标准间隔重复循环）
  review,

  /// 已完全掌握/斩掉（暂不安排常规复习）
  mastered,

  /// 手动挂起/暂停复习
  suspended;

  int get value {
    switch (this) {
      case ReviewState.new_:
        return 0;
      case ReviewState.learning:
        return 1;
      case ReviewState.review:
        return 2;
      case ReviewState.mastered:
        return 3;
      case ReviewState.suspended:
        return 4;
    }
  }

  static ReviewState fromInt(int? val) {
    switch (val) {
      case 1:
        return ReviewState.learning;
      case 2:
        return ReviewState.review;
      case 3:
        return ReviewState.mastered;
      case 4:
        return ReviewState.suspended;
      case 0:
      default:
        return ReviewState.new_;
    }
  }
}

/// 掌握程度/评分（支持 4 档细粒度评分与 2 档粗粒度简化映射）
enum ReviewRating {
  /// 重来 / 完全生疏 / 答错
  again,

  /// 困难 / 犹豫
  hard,

  /// 良好 / 顺利记起 / 答对
  good,

  /// 简单 / 熟练 / 秒答
  easy;

  int get value {
    switch (this) {
      case ReviewRating.again:
        return 1;
      case ReviewRating.hard:
        return 2;
      case ReviewRating.good:
        return 3;
      case ReviewRating.easy:
        return 4;
    }
  }

  static ReviewRating fromInt(int? val) {
    switch (val) {
      case 1:
        return ReviewRating.again;
      case 2:
        return ReviewRating.hard;
      case 4:
        return ReviewRating.easy;
      case 3:
      default:
        return ReviewRating.good;
    }
  }
}

/// 记忆复习项目的状态实体（对应 SQLite 中 SpacedReviewItem 表）
class SpacedReviewItem {
  /// 项目唯一标识：
  /// - 题库题目：直接使用全局唯一 `question_id`
  /// - 笔记：使用 `note.id`
  /// - 自制卡片：使用 `card.id`
  final String itemId;

  /// 项目内容分类
  final ReviewItemType itemType;

  /// 关联的计划 ID（可选）
  final String? planId;

  /// 当前记忆生命周期阶段
  final ReviewState state;

  /// 连续成功复习次数
  final int reps;

  /// 遗忘/答错次数
  final int lapses;

  /// 当前到下次复习的间隔天数
  final int interval;

  /// SM-2 简易度因子 (Ease Factor，初始通常为 2.5)
  final double easeFactor;

  /// 下一次到期复习时间戳（毫秒）
  final int dueDate;

  /// 最近一次复习时间戳（毫秒）
  final int lastReviewAt;

  /// 最近一次评级
  final ReviewRating? lastRating;

  /// 扩展字段（用于自制卡片正反面、笔记快照、标签等 JSON 附加数据）
  final Map<String, dynamic>? extra;

  const SpacedReviewItem({
    required this.itemId,
    this.itemType = ReviewItemType.question,
    this.planId,
    this.state = ReviewState.new_,
    this.reps = 0,
    this.lapses = 0,
    this.interval = 0,
    this.easeFactor = 2.5,
    this.dueDate = 0,
    this.lastReviewAt = 0,
    this.lastRating,
    this.extra,
  });

  /// 是否已经到期需要复习
  bool isDue([DateTime? now]) {
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return dueDate > 0 && dueDate <= current && state != ReviewState.mastered && state != ReviewState.suspended;
  }

  SpacedReviewItem copyWith({
    String? itemId,
    ReviewItemType? itemType,
    String? planId,
    ReviewState? state,
    int? reps,
    int? lapses,
    int? interval,
    double? easeFactor,
    int? dueDate,
    int? lastReviewAt,
    ReviewRating? lastRating,
    Map<String, dynamic>? extra,
  }) {
    return SpacedReviewItem(
      itemId: itemId ?? this.itemId,
      itemType: itemType ?? this.itemType,
      planId: planId ?? this.planId,
      state: state ?? this.state,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      interval: interval ?? this.interval,
      easeFactor: easeFactor ?? this.easeFactor,
      dueDate: dueDate ?? this.dueDate,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      lastRating: lastRating ?? this.lastRating,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_id': itemId,
      'item_type': itemType.value,
      'plan_id': planId,
      'state': state.value,
      'reps': reps,
      'lapses': lapses,
      'interval': interval,
      'ease_factor': easeFactor,
      'due_date': dueDate,
      'last_review_at': lastReviewAt,
      'last_rating': lastRating?.value ?? 0,
      'extra': extra != null ? jsonEncode(extra) : null,
    };
  }

  factory SpacedReviewItem.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parsedExtra;
    final extraStr = map['extra']?.toString();
    if (extraStr != null && extraStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(extraStr);
        if (decoded is Map<String, dynamic>) {
          parsedExtra = decoded;
        }
      } catch (_) {}
    }

    final rawRating = (map['last_rating'] as num?)?.toInt() ?? 0;
    return SpacedReviewItem(
      itemId: map['item_id']?.toString() ?? '',
      itemType: ReviewItemType.fromString(map['item_type']?.toString()),
      planId: map['plan_id']?.toString(),
      state: ReviewState.fromInt((map['state'] as num?)?.toInt()),
      reps: (map['reps'] as num?)?.toInt() ?? 0,
      lapses: (map['lapses'] as num?)?.toInt() ?? 0,
      interval: (map['interval'] as num?)?.toInt() ?? 0,
      easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
      dueDate: (map['due_date'] as num?)?.toInt() ?? 0,
      lastReviewAt: (map['last_review_at'] as num?)?.toInt() ?? 0,
      lastRating: rawRating > 0 ? ReviewRating.fromInt(rawRating) : null,
      extra: parsedExtra,
    );
  }
}

/// 学习计划实体
class ReviewPlan {
  final String id;
  final String name;

  /// 范围类型：'all'(全部题库), 'bank'(指定题库), 'subject'(指定课程), 'custom'(自定义范围)
  final String targetType;
  final String? bankId;
  final String? identityId;
  final String? subjectId;

  /// 自定义抽题来源：'wrong'(错题), 'collected'(收藏), 'note'(笔记), 'all'(包含题库新题)
  final List<String> sourceTypes;

  /// 覆盖的课程 subject_id 列表（为空时表示全部或默认首页所选）
  final List<String> coveredSubjects;

  /// 每日新题目标
  final int dailyNewTarget;

  /// 每日复习上限
  final int dailyReviewLimit;

  /// 是否为当前处于激活状态的主计划
  final bool isActive;

  final int createdAt;
  final int updatedAt;

  const ReviewPlan({
    required this.id,
    required this.name,
    this.targetType = 'all',
    this.bankId,
    this.identityId,
    this.subjectId,
    this.sourceTypes = const ['wrong', 'collected', 'note'],
    this.coveredSubjects = const [],
    this.dailyNewTarget = 20,
    this.dailyReviewLimit = 50,
    this.isActive = true,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  ReviewPlan copyWith({
    String? id,
    String? name,
    String? targetType,
    String? bankId,
    String? identityId,
    String? subjectId,
    List<String>? sourceTypes,
    List<String>? coveredSubjects,
    int? dailyNewTarget,
    int? dailyReviewLimit,
    bool? isActive,
    int? createdAt,
    int? updatedAt,
  }) {
    return ReviewPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      targetType: targetType ?? this.targetType,
      bankId: bankId ?? this.bankId,
      identityId: identityId ?? this.identityId,
      subjectId: subjectId ?? this.subjectId,
      sourceTypes: sourceTypes ?? this.sourceTypes,
      coveredSubjects: coveredSubjects ?? this.coveredSubjects,
      dailyNewTarget: dailyNewTarget ?? this.dailyNewTarget,
      dailyReviewLimit: dailyReviewLimit ?? this.dailyReviewLimit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'target_type': targetType,
      'bank_id': bankId,
      'identity_id': identityId,
      'subject_id': subjectId,
      'source_types': sourceTypes.join(','),
      'covered_subjects': coveredSubjects.join(','),
      'daily_new_target': dailyNewTarget,
      'daily_review_limit': dailyReviewLimit,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ReviewPlan.fromMap(Map<String, dynamic> map) {
    final rawSources = map['source_types']?.toString();
    final sources = rawSources != null && rawSources.isNotEmpty
        ? rawSources.split(',').where((s) => s.isNotEmpty).toList()
        : const ['wrong', 'collected', 'note'];

    final rawSubjects = map['covered_subjects']?.toString();
    final subjects = rawSubjects != null && rawSubjects.isNotEmpty
        ? rawSubjects.split(',').where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return ReviewPlan(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      targetType: map['target_type']?.toString() ?? 'all',
      bankId: map['bank_id']?.toString(),
      identityId: map['identity_id']?.toString(),
      subjectId: map['subject_id']?.toString(),
      sourceTypes: sources,
      coveredSubjects: subjects,
      dailyNewTarget: (map['daily_new_target'] as num?)?.toInt() ?? 20,
      dailyReviewLimit: (map['daily_review_limit'] as num?)?.toInt() ?? 50,
      isActive: (map['is_active'] as num?)?.toInt() == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 自制卡片实体（支持自制正反面闪卡）
class CustomFlashcard {
  final String id;
  final String title;
  final String front;
  final String back;
  final String? questionId;
  final String? tags;
  final int createdAt;
  final int updatedAt;

  const CustomFlashcard({
    required this.id,
    this.title = '',
    required this.front,
    required this.back,
    this.questionId,
    this.tags,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title.isNotEmpty
          ? title
          : (front.length > 30 ? '${front.substring(0, 30)}...' : front),
      'front': front,
      'back': back,
      'question_id': questionId,
      'tags': tags,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CustomFlashcard.fromMap(Map<String, dynamic> map) {
    return CustomFlashcard(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      front: map['front']?.toString() ?? '',
      back: map['back']?.toString() ?? '',
      questionId: map['question_id']?.toString(),
      tags: map['tags']?.toString(),
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  CustomFlashcard copyWith({
    String? id,
    String? title,
    String? front,
    String? back,
    String? questionId,
    String? tags,
    int? createdAt,
    int? updatedAt,
  }) {
    return CustomFlashcard(
      id: id ?? this.id,
      title: title ?? this.title,
      front: front ?? this.front,
      back: back ?? this.back,
      questionId: questionId ?? this.questionId,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
