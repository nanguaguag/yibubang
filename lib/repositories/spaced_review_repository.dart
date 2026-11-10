import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/spaced_review_item.dart';

/// 记忆复习与计划持久化数据仓库
class SpacedReviewRepository {
  final UserDBHelper _dbHelper;

  SpacedReviewRepository({UserDBHelper? dbHelper})
    : _dbHelper = dbHelper ?? UserDBHelper();

  Future<DatabaseExecutor> _getExecutor([DatabaseExecutor? custom]) async {
    return custom ?? await _dbHelper.database;
  }

  // -------------------------------------------------------------
  // 1. 计划管理 (ReviewPlans)
  // -------------------------------------------------------------

  /// 获取当前激活的学习计划（若无则返回 null）
  Future<ReviewPlan?> getActivePlan([DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query(
      'ReviewPlans',
      where: 'is_active = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReviewPlan.fromMap(rows.first);
  }

  /// 获取当前激活的学习计划（若无则创建并返回默认计划）
  Future<ReviewPlan> getOrCreateActivePlan([DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query(
      'ReviewPlans',
      where: 'is_active = 1',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ReviewPlan.fromMap(rows.first);
    }

    // 默认计划
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultPlan = ReviewPlan(
      id: 'default_plan',
      name: '默认每日刷题计划',
      targetType: 'all',
      dailyNewTarget: 20,
      dailyReviewLimit: 50,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    await savePlan(defaultPlan, db);
    return defaultPlan;
  }

  /// 获取指定 ID 的计划
  Future<ReviewPlan?> getPlan(
    String planId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query(
      'ReviewPlans',
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReviewPlan.fromMap(rows.first);
  }

  /// 获取所有计划
  Future<List<ReviewPlan>> getAllPlans([DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query('ReviewPlans', orderBy: 'created_at ASC');
    return rows.map((r) => ReviewPlan.fromMap(r)).toList();
  }

  /// 保存或更新学习计划
  Future<void> savePlan(ReviewPlan plan, [DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    try {
      await db.insert(
        'ReviewPlans',
        plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (e.toString().contains('no column named')) {
        // 自动补充 ReviewPlans 所有可能缺失的扩展字段并重试
        for (final col in const [
          'bank_id TEXT',
          'identity_id TEXT',
          'subject_id TEXT',
          "source_types TEXT DEFAULT 'wrong,collected,note'",
          "covered_subjects TEXT DEFAULT ''",
        ]) {
          try {
            await db.execute("ALTER TABLE ReviewPlans ADD COLUMN $col");
          } catch (_) {}
        }
        await db.insert(
          'ReviewPlans',
          plan.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }
      rethrow;
    }
  }

  /// 设置激活计划（并将其他计划置为非激活）
  Future<void> setActivePlan(
    String planId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    if (db is Database) {
      await db.transaction((txn) async {
        await txn.update('ReviewPlans', {'is_active': 0});
        await txn.update(
          'ReviewPlans',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [planId],
        );
      });
    } else {
      await db.update('ReviewPlans', {'is_active': 0});
      await db.update(
        'ReviewPlans',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [planId],
      );
    }
  }

  /// 删除计划
  Future<void> deletePlan(String planId, [DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    await db.delete('ReviewPlans', where: 'id = ?', whereArgs: [planId]);
  }

  // -------------------------------------------------------------
  // 2. 题目/卡片/笔记记忆状态 (SpacedReviewItem)
  // -------------------------------------------------------------

  /// 查询特定项的记忆状态
  Future<SpacedReviewItem?> getItem(
    String itemId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query(
      'SpacedReviewItem',
      where: 'item_id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SpacedReviewItem.fromMap(rows.first);
  }

  /// 保存单个记忆项状态
  Future<void> saveItem(
    SpacedReviewItem item, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    await db.insert(
      'SpacedReviewItem',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存/更新记忆项
  Future<void> batchSaveItems(
    List<SpacedReviewItem> items, [
    DatabaseExecutor? executor,
  ]) async {
    if (items.isEmpty) return;
    final db = await _getExecutor(executor);

    Future<void> perform(DatabaseExecutor tx) async {
      final batch = tx.batch();
      for (final item in items) {
        batch.insert(
          'SpacedReviewItem',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }

    if (db is Database) {
      await db.transaction((txn) => perform(txn));
    } else {
      await perform(db);
    }
  }

  /// 查询待复习的到期题目数量
  Future<int> getDueCount({
    String? planId,
    DateTime? now,
    DatabaseExecutor? executor,
  }) async {
    final db = await _getExecutor(executor);
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch;

    final whereParts = <String>[
      'due_date > 0',
      'due_date <= ?',
      'state NOT IN (?, ?)',
    ];
    final whereArgs = <dynamic>[
      current,
      ReviewState.mastered.value,
      ReviewState.suspended.value,
    ];

    if (planId != null && planId.isNotEmpty) {
      whereParts.add('(plan_id = ? OR plan_id IS NULL)');
      whereArgs.add(planId);
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM SpacedReviewItem WHERE ${whereParts.join(' AND ')}',
      whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 拉取待复习的到期项目列表
  Future<List<SpacedReviewItem>> getDueItems({
    String? planId,
    int limit = 50,
    DateTime? now,
    DatabaseExecutor? executor,
  }) async {
    final db = await _getExecutor(executor);
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch;

    final whereParts = <String>[
      'due_date > 0',
      'due_date <= ?',
      'state NOT IN (?, ?)',
    ];
    final whereArgs = <dynamic>[
      current,
      ReviewState.mastered.value,
      ReviewState.suspended.value,
    ];

    if (planId != null && planId.isNotEmpty) {
      whereParts.add('(plan_id = ? OR plan_id IS NULL)');
      whereArgs.add(planId);
    }

    final rows = await db.query(
      'SpacedReviewItem',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'due_date ASC, reps ASC',
      limit: limit,
    );
    return rows.map((r) => SpacedReviewItem.fromMap(r)).toList();
  }

  /// 获取指定状态的项目数量（如学习中、复习中、已熟记）
  Future<int> getReviewStateCount({
    String? planId,
    required ReviewState state,
    DatabaseExecutor? executor,
  }) async {
    final db = await _getExecutor(executor);
    final whereParts = <String>['state = ?'];
    final whereArgs = <dynamic>[state.value];

    if (planId != null && planId.isNotEmpty) {
      whereParts.add('(plan_id = ? OR plan_id IS NULL)');
      whereArgs.add(planId);
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM SpacedReviewItem WHERE ${whereParts.join(' AND ')}',
      whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 获取未来 N 天的待复习量预估（返回形如 {'2026-11-08': 15, '2026-11-09': 8, ...} 的未来记忆负荷分布）
  Future<Map<String, int>> getDueForecast({
    String? planId,
    int days = 7,
    DateTime? now,
    DatabaseExecutor? executor,
  }) async {
    final db = await _getExecutor(executor);
    final baseDate = now ?? DateTime.now();
    final forecast = <String, int>{};

    for (int i = 0; i < days; i++) {
      final targetDay = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
      ).add(Duration(days: i));
      final nextDay = targetDay.add(const Duration(days: 1));
      final dayKey =
          '${targetDay.year.toString().padLeft(4, '0')}-'
          '${targetDay.month.toString().padLeft(2, '0')}-'
          '${targetDay.day.toString().padLeft(2, '0')}';

      final whereParts = <String>[
        'due_date >= ?',
        'due_date < ?',
        'state NOT IN (?, ?)',
      ];
      final whereArgs = <dynamic>[
        targetDay.millisecondsSinceEpoch,
        nextDay.millisecondsSinceEpoch,
        ReviewState.mastered.value,
        ReviewState.suspended.value,
      ];

      if (planId != null && planId.isNotEmpty) {
        whereParts.add('(plan_id = ? OR plan_id IS NULL)');
        whereArgs.add(planId);
      }

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM SpacedReviewItem WHERE ${whereParts.join(' AND ')}',
        whereArgs,
      );
      forecast[dayKey] = Sqflite.firstIntValue(result) ?? 0;
    }

    return forecast;
  }

  // -------------------------------------------------------------
  // 3. 自制卡片管理 (CustomFlashcards)
  // -------------------------------------------------------------

  /// 保存自制卡片（同时初始化或关联一条 SpacedReviewItem 记录）
  Future<void> saveFlashcard(
    CustomFlashcard card, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    Future<void> perform(DatabaseExecutor tx) async {
      await tx.delete(
        'ReviewItemTombstones',
        where: 'item_id=?',
        whereArgs: [card.id],
      );
      await tx.insert(
        'CustomFlashcards',
        card.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 检查复习项是否存在
      final existing = await tx.query(
        'SpacedReviewItem',
        where: 'item_id = ?',
        whereArgs: [card.id],
        limit: 1,
      );
      if (existing.isEmpty) {
        final item = SpacedReviewItem(
          itemId: card.id,
          itemType: ReviewItemType.flashcard,
          state: ReviewState.new_,
          extra: {
            'title': card.title,
            'front': card.front,
            'back': card.back,
            'tags': card.tags,
            if (card.questionId != null) 'question_id': card.questionId,
          },
        );
        await tx.insert('SpacedReviewItem', item.toMap());
      } else {
        // 同步更新 extra 缓存
        final existingItem = SpacedReviewItem.fromMap(existing.first);
        final extraMap = Map<String, dynamic>.from(existingItem.extra ?? {});
        extraMap['title'] = card.title;
        extraMap['front'] = card.front;
        extraMap['back'] = card.back;
        extraMap['tags'] = card.tags;
        if (card.questionId != null) {
          extraMap['question_id'] = card.questionId;
        }
        await tx.update(
          'SpacedReviewItem',
          {'extra': jsonEncode(extraMap)},
          where: 'item_id = ?',
          whereArgs: [card.id],
        );
      }
    }

    if (db is Database) {
      await db.transaction((txn) => perform(txn));
    } else {
      await perform(db);
    }
  }

  /// 获取自制卡片
  Future<CustomFlashcard?> getFlashcard(
    String id, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query(
      'CustomFlashcards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CustomFlashcard.fromMap(rows.first);
  }

  /// 批量根据 ID 获取自制卡片
  Future<Map<String, CustomFlashcard>> getFlashcardsByIds(
    List<String> ids, [
    DatabaseExecutor? executor,
  ]) async {
    if (ids.isEmpty) return {};
    final db = await _getExecutor(executor);
    final map = <String, CustomFlashcard>{};
    const chunkSize = 100;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = math.min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      final rows = await db.query(
        'CustomFlashcards',
        where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final r in rows) {
        final card = CustomFlashcard.fromMap(r);
        map[card.id] = card;
      }
    }
    return map;
  }

  /// 根据关联原题 ID 获取所有闪卡
  Future<List<CustomFlashcard>> getFlashcardsByQuestionId(
    String questionId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    try {
      final rows = await db.query(
        'CustomFlashcards',
        where: 'question_id = ?',
        whereArgs: [questionId],
        orderBy: 'created_at DESC',
      );
      return rows.map((r) => CustomFlashcard.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取所有自制卡片
  Future<List<CustomFlashcard>> getAllFlashcards([
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    final rows = await db.query('CustomFlashcards', orderBy: 'created_at DESC');
    return rows.map((r) => CustomFlashcard.fromMap(r)).toList();
  }

  /// 获取所有自制卡片的去重标签列表（按字母排序）
  Future<List<String>> getAllFlashcardTags([DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    try {
      final rows = await db.rawQuery(
        "SELECT DISTINCT tags FROM CustomFlashcards WHERE tags IS NOT NULL AND tags != ''",
      );
      final Set<String> tagSet = {};
      for (final r in rows) {
        final raw = r['tags'] as String?;
        if (raw == null) continue;
        final parts = raw
            .split(RegExp(r'[,，\s]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);
        tagSet.addAll(parts);
      }
      final list = tagSet.toList();
      list.sort();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 条件检索闪卡（支持关键字、标签筛选）
  Future<List<CustomFlashcard>> searchFlashcards({
    String? query,
    String? tag,
    DatabaseExecutor? executor,
  }) async {
    final db = await _getExecutor(executor);
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      whereParts.add('(front LIKE ? OR back LIKE ? OR title LIKE ?)');
      whereArgs.addAll([q, q, q]);
    }

    if (tag != null && tag.trim().isNotEmpty && tag != '全部') {
      whereParts.add('tags LIKE ?');
      whereArgs.add('%${tag.trim()}%');
    }

    final rows = await db.query(
      'CustomFlashcards',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => CustomFlashcard.fromMap(r)).toList();
  }

  /// 切换闪卡斩卡状态（在 mastered 与在学 review 状态间切换）
  Future<bool> toggleFlashcardMastered(
    String id, [
    DatabaseExecutor? executor,
  ]) async {
    final db = await _getExecutor(executor);
    Future<bool> perform(DatabaseExecutor tx) async {
      final item = await getItem(id, tx);
      if (item == null || await getFlashcard(id, tx) == null) return false;
      final isMastered = item.state == ReviewState.mastered;
      final extra = Map<String, dynamic>.from(item.extra ?? {});
      if (isMastered) {
        extra.remove('suspension_reason');
      } else {
        extra['suspension_reason'] = 'cut';
      }
      await saveItem(
        item.copyWith(
          state: isMastered ? ReviewState.review : ReviewState.mastered,
          extra: extra,
          dueDate: isMastered ? DateTime.now().millisecondsSinceEpoch : 0,
        ),
        tx,
      );
      return !isMastered;
    }

    return db is Database ? db.transaction(perform) : perform(db);
  }

  /// 删除自制卡片及对应的复习状态
  Future<void> deleteFlashcard(String id, [DatabaseExecutor? executor]) async {
    final db = await _getExecutor(executor);
    Future<void> perform(DatabaseExecutor tx) async {
      await tx.insert('ReviewItemTombstones', {
        'item_id': id,
        'item_type': 'flashcard',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete('CustomFlashcards', where: 'id = ?', whereArgs: [id]);
      await tx.delete(
        'SpacedReviewItem',
        where: 'item_id = ?',
        whereArgs: [id],
      );
    }

    if (db is Database) {
      await db.transaction((txn) => perform(txn));
    } else {
      await perform(db);
    }
  }
}
