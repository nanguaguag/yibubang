import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import 'question_bank_repository.dart';

/// 用户题目聚合类型
enum UserQuestionsType {
  collection,
  mistake,
  cut,
}

/// 一次全库题目搜索命中的单条结果。
class QuestionSearchResult {
  final String questionId;
  final String bankId;
  final String bankName;
  final String title;
  final String? publicTitle;
  final String? type;
  final String? typeStr;
  final String? option; // JSON 字符串
  final String? restore;
  final String? explain;
  final String? subjectId;
  final String? year;
  String? subjectName;
  bool collection;
  bool isCut;
  int status;
  int updatedAt;

  QuestionSearchResult({
    required this.questionId,
    required this.bankId,
    required this.bankName,
    required this.title,
    this.publicTitle,
    this.type,
    this.typeStr,
    this.option,
    this.restore,
    this.explain,
    this.subjectId,
    this.year,
    this.subjectName,
    this.collection = false,
    this.isCut = false,
    this.status = 0,
    this.updatedAt = 0,
  });

  factory QuestionSearchResult.fromMap(
    Map<String, dynamic> map,
    String bankId,
    String bankName,
  ) {
    return QuestionSearchResult(
      questionId: map['id'] as String,
      bankId: bankId,
      bankName: bankName,
      title: (map['title'] as String?) ?? '',
      publicTitle: map['public_title'] as String?,
      type: map['type'] as String?,
      typeStr: map['type_str'] as String?,
      option: map['option'] as String?,
      restore: map['restore'] as String?,
      explain: map['explain'] as String?,
      subjectId: map['chapter_parent_id'] as String?,
      year: map['year'] as String?,
    );
  }

  /// 题干优先使用 title，缺失时回退 public_title。
  String get stem => title.isNotEmpty ? title : (publicTitle ?? '');

  /// 题型中文显示。
  String get typeLabel {
    if (typeStr != null && typeStr!.isNotEmpty) return typeStr!;
    switch (type) {
      case '1':
        return '单选题';
      case '2':
        return '多选题';
      case '3':
        return '填空题';
      case '4':
        return '名词解释';
      case '5':
        return '简答题';
      case '6':
        return '论述题';
      case '7':
        return '病例分析';
      case '19':
        return '案例分析题';
      default:
        return type ?? '题目';
    }
  }

  /// 把 option JSON 解析成 "A. xxx\nB. xxx" 这类纯文本。
  String get optionText {
    final raw = option;
    if (raw == null || raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return raw;
      final parts = <String>[];
      for (final item in decoded) {
        if (item is Map) {
          final key = item['key'];
          final title = item['title'];
          if (key != null || title != null) {
            parts.add('${key ?? ''}. ${title ?? ''}'.trim());
          }
        }
      }
      return parts.isNotEmpty ? parts.join('\n') : raw;
    } catch (_) {
      return raw;
    }
  }
}

class QuestionSearchRepository {
  /// 每个题库一次加载的条数，拉到底部会继续加载下一批（无限滚动）。
  static const int pageSize = 80;
  static const String historyKey = 'question_search_history';
  static const int maxHistory = 20;

  /// 返回参与搜索的题库：已安装且启用、且非旧合并题库。
  Future<List<QuestionBank>> listSearchBanks() async {
    final banks = await QuestionBankRepository().listBanks();
    return banks
        .where((bank) =>
            bank.isInstalled &&
            bank.enabled &&
            bank.bankId != 'legacy_combined')
        .toList();
  }

  /// 按关键词搜索题库，返回每个题库在给定偏移之后的一批（pageSize 条）。
  /// [offsets]：bankId -> 该库已加载条数；返回的 Map 只包含本次查到结果的题库。
  /// 若某个题库返回的条数 < pageSize，说明该库已加载完。
  Future<Map<String, List<QuestionSearchResult>>> loadPage(
    String keyword,
    Map<String, int> offsets,
  ) async {
    final term = keyword.trim();
    final pattern = '%$term%';
    final manager = QuestionBankDatabaseManager();
    final banks = offsets.keys.toList();

    final page = <String, List<QuestionSearchResult>>{};
    final allResults = <QuestionSearchResult>[];
    for (final bankId in banks) {
      try {
        final db = await manager.openBank(bankId);
        final rows = await db.rawQuery('''
          SELECT id, public_title, title, type, type_str, option, restore,
                 explain, chapter_parent_id, year
            FROM Question
           WHERE title LIKE ?
              OR public_title LIKE ?
              OR option LIKE ?
              OR restore LIKE ?
              OR explain LIKE ?
           ORDER BY id
           LIMIT ? OFFSET ?
        ''', [
          pattern,
          pattern,
          pattern,
          pattern,
          pattern,
          pageSize,
          offsets[bankId] ?? 0,
        ]);

        if (rows.isEmpty) continue;

        final subjectIds = <String>{
          for (final row in rows)
            if ((row['chapter_parent_id'] as String?)?.isNotEmpty == true)
              row['chapter_parent_id'] as String,
        }.toList();
        final subjectNames = <String, String>{};
        if (subjectIds.isNotEmpty) {
          final placeholders = List.filled(subjectIds.length, '?').join(',');
          final subjectRows = await db.query(
            'Subject',
            columns: ['id', 'name'],
            where: 'id IN ($placeholders)',
            whereArgs: subjectIds,
          );
          for (final s in subjectRows) {
            final sid = s['id'] as String;
            final name = s['name'] as String? ?? '';
            subjectNames[sid] = name;
          }
        }

        final results = <QuestionSearchResult>[];
        for (final row in rows) {
          final result = QuestionSearchResult.fromMap(
            row,
            bankId,
            _bankCache[bankId]?.name ?? '',
          );
          if (result.subjectId != null) {
            result.subjectName = subjectNames[result.subjectId];
          }
          results.add(result);
        }
        page[bankId] = results;
        allResults.addAll(results);
      } catch (error) {
        debugPrint('搜索题库 $bankId 失败：$error');
      }
    }

    // 批量补收藏状态。
    if (allResults.isNotEmpty) {
      final userDb = await UserDBHelper().database;
      final ids = allResults.map((r) => r.questionId).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await userDb.query(
        'Question',
        columns: ['id', 'collection'],
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      final collectionMap = <String, bool>{
        for (final row in rows)
          row['id'] as String: (row['collection'] as num? ?? 0) == 1,
      };
      for (final result in allResults) {
        result.collection = collectionMap[result.questionId] ?? false;
      }
    }
    return page;
  }

  // 已初始化题库的缓存，供 loadPage 获取题库名称。
  static Map<String, QuestionBank> _bankCache = <String, QuestionBank>{};

  /// 供页面在首次搜索时初始化题库名称缓存。
  Future<void> warmBankCache() async {
    final banks = await listSearchBanks();
    _bankCache = {
      for (final bank in banks) bank.bankId: bank,
    };
  }

  /// 切换某道题的收藏状态，返回最新值。
  Future<bool> setCollection(String questionId, bool value) async {
    final userDb = await UserDBHelper().database;
    final collection = value ? 1 : 0;
    final rows = await userDb.query(
      'Question',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (rows.isEmpty) {
      await userDb.insert('Question', {
        'id': questionId,
        'chapter_id': '',
        'chapter_parent_id': '',
        'cut_question': '0',
        'user_answer': '',
        'status': 0,
        'collection': collection,
        'updated_at': now,
      });
    } else {
      await userDb.update(
        'Question',
        {
          'collection': collection,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );
    }
    return value;
  }

  /// 按题库与题目 id 读取完整题目（用于跳转详情页）。
  Future<Question?> getQuestionById(String bankId, String questionId) async {
    final db = await QuestionBankDatabaseManager().openBank(bankId);
    final rows = await db.query(
      'Question',
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Question.fromMap(rows.first);
  }

  /// 读取用户维度的题目记录（收藏/状态），不存在时返回 null。
  Future<UserQuestion?> getUserQuestionById(String questionId) async {
    final userDb = await UserDBHelper().database;
    final rows = await userDb.query(
      'Question',
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserQuestion.fromMap(rows.first);
  }

  Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(historyKey) ?? <String>[];
  }

  Future<List<String>> addHistory(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return loadHistory();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(historyKey) ?? <String>[];
    list.removeWhere((e) => e == trimmed);
    list.insert(0, trimmed);
    if (list.length > maxHistory) {
      list.removeRange(maxHistory, list.length);
    }
    await prefs.setStringList(historyKey, list);
    return list;
  }

  Future<List<String>> removeHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(historyKey) ?? <String>[];
    list.remove(term);
    await prefs.setStringList(historyKey, list);
    return list;
  }

  Future<List<String>> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(historyKey);
    return <String>[];
  }

  /// 获取“我的页”各功能项统计数量
  Future<Map<String, int>> getUserDataCounts() async {
    final userDb = await UserDBHelper().database;
    final colResult = Sqflite.firstIntValue(
      await userDb.rawQuery('SELECT COUNT(*) FROM Question WHERE collection = 1'),
    ) ?? 0;
    final mistakeResult = Sqflite.firstIntValue(
      await userDb.rawQuery('SELECT COUNT(*) FROM Question WHERE status = 2'),
    ) ?? 0;
    final cutResult = Sqflite.firstIntValue(
      await userDb.rawQuery("SELECT COUNT(*) FROM Question WHERE cut_question = '1' OR cut_question = 'cutted'"),
    ) ?? 0;
    final notesResult = Sqflite.firstIntValue(
      await userDb.rawQuery('SELECT COUNT(*) FROM Notes'),
    ) ?? 0;
    return {
      'collection': colResult,
      'mistake': mistakeResult,
      'cut': cutResult,
      'notes': notesResult,
    };
  }

  /// 按类型加载用户的所有收藏 / 错题 / 已斩题目
  Future<List<QuestionSearchResult>> loadUserQuestions(
    UserQuestionsType type,
  ) async {
    final userDb = await UserDBHelper().database;
    String whereClause;
    switch (type) {
      case UserQuestionsType.collection:
        whereClause = 'collection = 1';
        break;
      case UserQuestionsType.mistake:
        whereClause = 'status = 2';
        break;
      case UserQuestionsType.cut:
        whereClause = "cut_question = '1' OR cut_question = 'cutted'";
        break;
    }

    final userRows = await userDb.query(
      'Question',
      where: whereClause,
      orderBy: 'updated_at DESC',
    );

    if (userRows.isEmpty) return <QuestionSearchResult>[];

    final questionIds = userRows
        .map((r) => r['id']?.toString())
        .whereType<String>()
        .toList();

    final userMap = <String, Map<String, dynamic>>{
      for (final r in userRows) (r['id']?.toString() ?? ''): r,
    };

    final banks = await listSearchBanks();
    final prefs = await SharedPreferences.getInstance();
    final activeBankId = prefs.getString('activeBankId');
    if (activeBankId != null && activeBankId.isNotEmpty) {
      final activeIdx = banks.indexWhere((b) => b.bankId == activeBankId);
      if (activeIdx > 0) {
        final b = banks.removeAt(activeIdx);
        banks.insert(0, b);
      }
    }

    final manager = QuestionBankDatabaseManager();
    final foundMap = <String, QuestionSearchResult>{};
    final remainingIds = Set<String>.from(questionIds);

    for (final bank in banks) {
      if (remainingIds.isEmpty) break;
      try {
        final db = await manager.openBank(bank.bankId);
        final currentBankBatch = remainingIds.toList();
        for (var i = 0; i < currentBankBatch.length; i += 200) {
          final batchIds = currentBankBatch.sublist(
            i,
            i + 200 > currentBankBatch.length ? currentBankBatch.length : i + 200,
          );
          final placeholders = List.filled(batchIds.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT id, public_title, title, type, type_str, option, restore,
                   explain, chapter_parent_id, year
              FROM Question
             WHERE id IN ($placeholders)
          ''', batchIds);

          if (rows.isEmpty) continue;

          final subjectIds = <String>{
            for (final r in rows)
              if ((r['chapter_parent_id'] as String?)?.isNotEmpty == true)
                r['chapter_parent_id'] as String,
          }.toList();

          final subjectNames = <String, String>{};
          if (subjectIds.isNotEmpty) {
            final sPlaceholders = List.filled(subjectIds.length, '?').join(',');
            final sRows = await db.query(
              'Subject',
              columns: ['id', 'name'],
              where: 'id IN ($sPlaceholders)',
              whereArgs: subjectIds,
            );
            for (final s in sRows) {
              subjectNames[s['id'] as String] = s['name'] as String? ?? '';
            }
          }

          for (final row in rows) {
            final qid = row['id'] as String;
            final userRow = userMap[qid];
            final result = QuestionSearchResult.fromMap(
              row,
              bank.bankId,
              bank.name,
            );
            if (result.subjectId != null) {
              result.subjectName = subjectNames[result.subjectId];
            }
            if (userRow != null) {
              result.collection = (userRow['collection'] as num? ?? 0) == 1;
              final cut = userRow['cut_question']?.toString() ?? '0';
              result.isCut = cut == '1' || cut == 'cutted';
              result.status = (userRow['status'] as num? ?? 0).toInt();
              result.updatedAt = (userRow['updated_at'] as num? ?? 0).toInt();
            }
            foundMap[qid] = result;
            remainingIds.remove(qid);
          }
        }
      } catch (e) {
        debugPrint('题库 ${bank.bankId} 查询题目失败: $e');
      }
    }

    final orderedResults = <QuestionSearchResult>[];
    for (final qid in questionIds) {
      final res = foundMap[qid];
      if (res != null) {
        orderedResults.add(res);
      }
    }
    return orderedResults;
  }

  /// 根据题目 ID 全局查找单道题目及其所在题库
  Future<QuestionSearchResult?> findQuestion(String questionId) async {
    final banks = await listSearchBanks();
    final prefs = await SharedPreferences.getInstance();
    final activeBankId = prefs.getString('activeBankId');
    if (activeBankId != null && activeBankId.isNotEmpty) {
      final activeIdx = banks.indexWhere((b) => b.bankId == activeBankId);
      if (activeIdx > 0) {
        final b = banks.removeAt(activeIdx);
        banks.insert(0, b);
      }
    }

    final manager = QuestionBankDatabaseManager();
    for (final bank in banks) {
      try {
        final db = await manager.openBank(bank.bankId);
        final rows = await db.query(
          'Question',
          where: 'id = ?',
          whereArgs: [questionId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final result = QuestionSearchResult.fromMap(
            rows.first,
            bank.bankId,
            bank.name,
          );
          if (result.subjectId != null && result.subjectId!.isNotEmpty) {
            final sRows = await db.query(
              'Subject',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [result.subjectId],
              limit: 1,
            );
            if (sRows.isNotEmpty) {
              result.subjectName = sRows.first['name'] as String?;
            }
          }
          final userQ = await getUserQuestionById(questionId);
          result.collection = (userQ?.collection ?? 0) == 1;
          result.isCut = userQ?.isCut ?? false;
          result.status = userQ?.status ?? 0;
          result.updatedAt = userQ?.updatedAt ?? 0;
          return result;
        }
      } catch (e) {
        debugPrint('在题库 ${bank.bankId} 查找题目失败: $e');
      }
    }
    return null;
  }

  /// 切换某道题的斩题状态
  Future<bool> setCutQuestion(String questionId, bool value) async {
    final userDb = await UserDBHelper().database;
    final cutVal = value ? '1' : '0';
    final rows = await userDb.query(
      'Question',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (rows.isEmpty) {
      await userDb.insert('Question', {
        'id': questionId,
        'chapter_id': '',
        'chapter_parent_id': '',
        'cut_question': cutVal,
        'user_answer': '',
        'status': 0,
        'collection': 0,
        'updated_at': now,
      });
    } else {
      await userDb.update(
        'Question',
        {
          'cut_question': cutVal,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );
    }
    return value;
  }
}