import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import 'ykb_crypto.dart';

/// 请求节奏配置：模拟真人刷题，避免批量拉取被风控识别。
class SyncPacing {
  /// 每次请求前附加随机抖动（毫秒）。
  final bool jitterEnabled;
  final int jitterMinMs;
  final int jitterMaxMs;

  /// 章节之间模拟刷题等候（毫秒）。
  final bool pacingEnabled;
  final int pacingMinMs;
  final int pacingMaxMs;

  const SyncPacing({
    this.jitterEnabled = false,
    this.jitterMinMs = 800,
    this.jitterMaxMs = 3000,
    this.pacingEnabled = false,
    this.pacingMinMs = 3000,
    this.pacingMaxMs = 15000,
  });

  Future<void> requestDelay() async {
    if (jitterEnabled && jitterMaxMs > 0) {
      await Future.delayed(
        Duration(milliseconds: _rand(jitterMinMs, jitterMaxMs)),
      );
    }
  }

  Future<void> chapterDelay() async {
    if (pacingEnabled && pacingMaxMs > 0) {
      await Future.delayed(
        Duration(milliseconds: _rand(pacingMinMs, pacingMaxMs)),
      );
    }
  }

  static int _rand(int min, int max) {
    final lo = min < 0 ? 0 : min;
    final hi = max <= lo ? lo + 1 : max;
    return lo + Random().nextInt(hi - lo);
  }
}

/// 单章节题目拉取结果（保留接口 code，供智能同步区分「无权限」与「网络失败」）。
class YkbChapterFetchResult {
  final String code;
  final String message;
  final List<Map<String, dynamic>>? questions;

  const YkbChapterFetchResult({
    required this.code,
    required this.message,
    this.questions,
  });

  bool get isOk => code == '200';

  /// 203 = 警告，无查看权限（会员/题库权限不足），不应反复重试。
  bool get isRestricted => code == '203';
}

/// 从医考帮官方 API 全量构建/更新本地题库。
///
/// 数据链路（与官方 App 抓包对齐，题目数据 DES 解密）：
///   subjectV2 -> 入口 -> chapter -> question/list（逐章全量）。
/// 产出 yibubang schema v1 题库 SQLite，经既有 `QuestionBankRepository.importFile`
/// 校验后原子安装，替换旧题库包。
class YkbBankSyncService {
  /// 同步 [bank] 题库。返回生成的新题库记录。
  ///
  /// [onProgress] 回调（阶段文案, 已完成章节, 章节总数），可为 null。
  static Future<QuestionBank?> syncBank(
    QuestionBank bank, {
    SyncPacing pacing = const SyncPacing(),
    void Function(String stage, int done, int total)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('loggedin') ?? false)) {
      throw StateError('未登录医考帮，请先在「我的」页面登录');
    }

    onProgress?.call('拉取身份树…', 0, 1);

    // 1) 身份树：bank 身份及其刷题入口。
    final identityResp = await basicReq('/allQuestion/question/subjectV2', {
      'user_id': prefs.getString('user_id') ?? '',
    }, method: 'GET');
    final tree = _asList(identityResp['data']);
    final identityNode = _findNode(tree, bank.identityId);
    if (identityNode == null) {
      throw StateError('身份树中找不到 identity ${bank.identityId}');
    }
    final entries = _asList(
      identityNode['children'],
    ).where((c) => (c['identity_id']?.toString() ?? '0') != '0').toList();
    if (entries.isEmpty) {
      throw StateError('身份 ${bank.identityId} 没有可用刷题入口');
    }
    debugPrint('[ykb-bank-sync] ${bank.bankId} 入口数: ${entries.length}');

    // 2) 逐入口拉章节（明文）。
    final subjects = <Map<String, dynamic>>[];
    final chapters = <Map<String, dynamic>>[];
    for (final entry in entries) {
      await pacing.requestDelay();
      final entryId = entry['identity_id'].toString();
      final chapterResp = await basicReq('/allquestion/question/chapter', {
        'identity_id': entryId,
        'category': 'chapter',
        'type': 'all',
        'module_type': (entry['module_type'] ?? '1').toString(),
        'am_pm': '',
        'search_where': '[]',
        'app_id': (entry['app_id'] ?? '40').toString(),
      });
      for (final node in _asList(chapterResp['data'])) {
        _collectChapterTree(node, subjects, chapters);
      }
    }
    if (chapters.isEmpty) {
      throw StateError('章节列表为空，无法构建题库');
    }
    debugPrint(
      '[ykb-bank-sync] subjects=${subjects.length}, chapters=${chapters.length}',
    );

    // 3) 逐章拉题（解密）并写库。
    final tmpDir = await getTemporaryDirectory();
    final stagingPath = p.join(
      tmpDir.path,
      'ykb_sync_${bank.bankId}_${DateTime.now().millisecondsSinceEpoch}.sqlite',
    );
    final db = await openDatabase(stagingPath);
    var questionCount = 0;
    var relationCount = 0;
    final total = chapters.length;
    try {
      await _createSchema(db);
      await db.transaction((txn) async {
        // BankMeta 先插占位，收尾更新计数。
        await txn.insert('BankMeta', {
          'bank_id': bank.bankId,
          'name': bank.name,
          'version': 'sync-${DateTime.now().millisecondsSinceEpoch}',
          'schema_version': 1,
          'generated_at': DateTime.now().millisecondsSinceEpoch,
          'source': 'ykb-api-sync',
          'question_count': 0,
          'subject_count': 0,
          'chapter_count': 0,
          'relation_count': 0,
        });

        // Identity：根身份 + 入口。
        await txn.insert('Identity', {
          'id': bank.identityId,
          'parent_id': '-1',
          'name': identityNode['title']?.toString() ?? bank.identityId,
        });
        for (final entry in entries) {
          await txn.insert('Identity', {
            'id': entry['identity_id'].toString(),
            'parent_id': bank.identityId,
            'name': entry['title']?.toString() ?? '',
          });
        }

        for (final subject in subjects) {
          await txn.insert('Subject', {
            'id': subject['id'].toString(),
            'name': subject['title']?.toString() ?? '',
          });
        }
        for (final chapter in chapters) {
          await txn.insert('Chapter', {
            'id': chapter['id'].toString(),
            'name': chapter['title']?.toString() ?? '',
          });
        }
        // 章节统计占位表（题库库内为 (identity_id, subject_id, total) 结构）
        for (final subject in subjects) {
          await txn.insert('IdentitySubject', {
            'identity_id': bank.identityId,
            'subject_id': subject['id'].toString(),
            'total': 0,
          });
        }
        for (final chapter in chapters) {
          await txn.insert('IdentityChapter', {
            'identity_id': bank.identityId,
            'subject_id': chapter['parentId'].toString(),
            'chapter_id': chapter['id'].toString(),
            'total': 0,
          });
        }
      });

      for (var i = 0; i < total; i++) {
        final chapter = chapters[i];
        onProgress?.call('拉取章节题目', i + 1, total);
        await pacing.requestDelay();
        final listResp = await _fetchChapterQuestions(
          entries,
          chapter['id'].toString(),
        );
        if (listResp == null) continue;

        final batch = db.batch();
        for (final q in listResp) {
          final row = questionRow(q, bank.identityId, chapter);
          batch.insert(
            'Question',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          batch.insert('IdentityQuestion', {
            'identity_id': bank.identityId,
            'subject_id': chapter['parentId'].toString(),
            'chapter_id': chapter['id'].toString(),
            'question_id': row['id'] as String,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          questionCount++;
          relationCount++;
        }
        await batch.commit(noResult: true);
        await pacing.chapterDelay();
      }
      debugPrint(
        '[ykb-bank-sync] questions=$questionCount, relations=$relationCount',
      );

      // 更新 BankMeta 计数 + 章节统计。
      await db.transaction((txn) async {
        await txn.update(
          'BankMeta',
          {
            'question_count': questionCount,
            'subject_count': subjects.length,
            'chapter_count': chapters.length,
            'relation_count': relationCount,
          },
          where: 'bank_id = ?',
          whereArgs: [bank.bankId],
        );
        // IdentitySubject/IdentityChapter 的计数按实际分布回填。
        await txn.rawUpdate('''
          UPDATE IdentitySubject SET total = (
            SELECT COUNT(*) FROM IdentityQuestion iq
            WHERE iq.identity_id = IdentitySubject.identity_id
              AND iq.subject_id = IdentitySubject.subject_id)
        ''');
        await txn.rawUpdate('''
          UPDATE IdentityChapter SET total = (
            SELECT COUNT(*) FROM IdentityQuestion iq
            WHERE iq.identity_id = IdentityChapter.identity_id
              AND iq.subject_id = IdentityChapter.subject_id
              AND iq.chapter_id = IdentityChapter.chapter_id)
        ''');
      });
    } catch (e) {
      await db.close();
      try {
        if (await File(stagingPath).exists()) await File(stagingPath).delete();
      } catch (_) {}
      rethrow;
    }
    await db.close();

    onProgress?.call('校验并安装题库', total, total);

    // 4) 通过既有校验/安装流程原子替换。
    final installed = await QuestionBankRepository().importFile(
      stagingPath,
      expectedBankId: bank.bankId,
      updateEnabled: true,
    );
    try {
      if (await File(stagingPath).exists()) await File(stagingPath).delete();
    } catch (_) {}
    debugPrint('[ykb-bank-sync] 安装完成: ${installed.bankId}');
    return installed;
  }

  /// 拉取某章节的题目（解密）。失败重试一次，仍失败返回 null 并跳过。
  static Future<List<Map<String, dynamic>>?> _fetchChapterQuestions(
    List<Map<String, dynamic>> entries,
    String chapterId,
  ) {
    // 各入口共享章节归属，取第一个入口即可（身份树中入口 category=chapter）。
    final entry = entries.first;
    return fetchChapterQuestions(
      identityId: entry['identity_id'].toString(),
      appId: (entry['app_id'] ?? '40').toString(),
      moduleType: (entry['module_type'] ?? '1').toString(),
      chapterId: chapterId,
    );
  }

  /// 拉取指定入口/章节的题目，保留接口 code/message（不重试）。
  ///
  /// 供智能增量同步判断 203（无权限）与 309/网络错误。
  static Future<YkbChapterFetchResult> fetchChapterQuestionsResult({
    required String identityId,
    required String appId,
    required String moduleType,
    required String chapterId,
  }) async {
    try {
      final resp = await basicReq('/allquestion/question/list', {
        'identity_id': identityId,
        'primary_id': chapterId,
        'category': 'chapter',
        'type': 'all',
        'module_type': moduleType,
        'am_pm': '',
        'app_id': appId,
      });
      final code = resp['code']?.toString() ?? '';
      final message = resp['message']?.toString() ?? '';
      if (code != '200') {
        return YkbChapterFetchResult(code: code, message: message);
      }
      final data = resp['data'];
      if (data is String) {
        final decoded = YkbCrypto.decryptJson(data);
        return YkbChapterFetchResult(
          code: code,
          message: message,
          questions: _asList(decoded['list']),
        );
      }
      return YkbChapterFetchResult(
        code: code,
        message: message,
        questions: _asList(data),
      );
    } catch (e) {
      return YkbChapterFetchResult(code: 'ERR', message: e.toString());
    }
  }

  /// 拉取指定入口/章节的题目（解密）。非 203 错误重试一次，仍失败返回 null。
  ///
  /// 供完整重建与「智能增量同步」共用，避免两套解密/请求逻辑漂移。
  static Future<List<Map<String, dynamic>>?> fetchChapterQuestions({
    required String identityId,
    required String appId,
    required String moduleType,
    required String chapterId,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await fetchChapterQuestionsResult(
        identityId: identityId,
        appId: appId,
        moduleType: moduleType,
        chapterId: chapterId,
      );
      if (result.isOk) return result.questions;
      if (result.isRestricted) {
        debugPrint('[ykb-bank-sync] 章节 $chapterId 无查看权限(203)，跳过');
        return null;
      }
      debugPrint(
        '[ykb-bank-sync] 章节 $chapterId 拉取失败(第${attempt + 1}次): '
        '${result.code} ${result.message}',
      );
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  /// 章节树 -> Subject(顶层) 与 Chapter(叶子，附 parentId)。
  static void _collectChapterTree(
    Map<String, dynamic> node,
    List<Map<String, dynamic>> subjects,
    List<Map<String, dynamic>> chapters,
  ) {
    final children = _asList(node['children']);
    final id = (node['id'] ?? node['chapter_id'])?.toString() ?? '';
    final title = node['title']?.toString() ?? '';
    if (children.isEmpty) {
      final parentId =
          (node['parent_id'] ?? node['chapter_parent_id'])?.toString() ?? '';
      if (id.isNotEmpty) {
        chapters.add({'id': id, 'title': title, 'parentId': parentId});
      }
      return;
    }
    if (id.isNotEmpty) {
      subjects.add({'id': id, 'title': title});
    }
    for (final child in children) {
      _collectChapterTree(child, subjects, chapters);
    }
  }

  /// 官方题目字段 -> 本地题库 Question 行（忽略超出 schema 的新字段）。
  static Map<String, dynamic> questionRow(
    Map<String, dynamic> q,
    String identityId,
    Map<String, dynamic> chapter,
  ) {
    String normText(dynamic v) =>
        v == null ? '' : (v is String ? v : jsonEncode(v));

    return {
      'id': q['id']?.toString() ?? '',
      'year': normText(q['year']),
      'unit': normText(q['unit']),
      'title': normText(q['title']),
      'public_title': normText(q['public_title']),
      'title_img': normText(q['title_img']),
      'number': normText(q['number']),
      'public_number': normText(q['public_number']),
      'restore': normText(q['restore']),
      'restore_img': normText(q['restore_img']),
      'explain': normText(q['explain']),
      'explain_img': normText(q['explain_img']),
      'answer': normText(q['answer']),
      'option': normText(q['option']),
      'score': normText(q['score']),
      'score_describe': normText(q['score_describe']),
      'native_app_id': normText(q['native_app_id']),
      'native_identity_id': normText(q['native_identity_id']),
      'app_id': normText(q['app_id']),
      'identity_id': identityId,
      'chapter_id': chapter['id'],
      'chapter_parent_id': chapter['parentId'],
      'type': normText(q['type']),
      'part_id': normText(q['part_id']),
      'part_parent_id': normText(q['part_parent_id']),
      'sort_chapter': normText(q['sort_chapter']),
      'sort_chapter_am': normText(q['sort_chapter_am']),
      'sort_chapter_pm': normText(q['sort_chapter_pm']),
      'outlines': normText(q['outlines']),
      'outlines_am': normText(q['outlines_am']),
      'outlines_pm': normText(q['outlines_pm']),
      'sort_part': normText(q['sort_part']),
      'sort_part_am': normText(q['sort_part_am']),
      'sort_part_pm': normText(q['sort_part_pm']),
      'am_pm': normText(q['am_pm']),
      'high_frequency': normText(q['high_frequency']),
      'is_collection_question': normText(q['is_collection_question']),
      'is_real_question': normText(q['is_real_question']),
      'cases_id': normText(q['cases_id']),
      'cases_parent_id': normText(q['cases_parent_id']),
      'sort_cases': normText(q['sort_cases']),
      'sort_cases_am': normText(q['sort_cases_am']),
      'sort_cases_pm': normText(q['sort_cases_pm']),
      'source': normText(q['source']),
      'source_filter': normText(q['source_filter']),
      'show_number': normText(q['show_number']),
      'created_at': normText(q['created_at']),
      'type_str': normText(q['type_str']),
      'origin_type': normText(q['origin_type']),
      'sort': normText(q['sort']),
      'is_new': normText(q['is_new']),
      'outlines_mastery': normText(q['outlines_mastery']),
      'filter_type': normText(q['filter_type']),
      'cut_question': normText(q['cut_question']),
      'user_answer': normText(q['user_answer']),
    };
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE BankMeta (
        bank_id TEXT PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL,
        schema_version INTEGER NOT NULL, generated_at INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT '', question_count INTEGER NOT NULL DEFAULT 0,
        subject_count INTEGER NOT NULL DEFAULT 0,
        chapter_count INTEGER NOT NULL DEFAULT 0,
        relation_count INTEGER NOT NULL DEFAULT 0)
    ''');
    await db.execute(
      'CREATE TABLE Identity (id TEXT PRIMARY KEY, parent_id TEXT, name TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE Subject (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE Chapter (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute('''
      CREATE TABLE Question (
        id TEXT PRIMARY KEY, year TEXT, unit TEXT, title TEXT, public_title TEXT,
        title_img TEXT, number TEXT, public_number TEXT,
        restore TEXT, restore_img TEXT, explain TEXT, explain_img TEXT,
        answer TEXT, option TEXT, score TEXT, score_describe TEXT,
        native_app_id TEXT, native_identity_id TEXT, app_id TEXT, identity_id TEXT,
        chapter_id TEXT, chapter_parent_id TEXT, type TEXT,
        part_id TEXT, part_parent_id TEXT, sort_chapter TEXT, sort_chapter_am TEXT,
        sort_chapter_pm TEXT, outlines TEXT, outlines_am TEXT, outlines_pm TEXT,
        sort_part TEXT, sort_part_am TEXT, sort_part_pm TEXT, am_pm TEXT,
        high_frequency TEXT, is_collection_question TEXT, is_real_question TEXT,
        cases_id TEXT, cases_parent_id TEXT, sort_cases TEXT, sort_cases_am TEXT,
        sort_cases_pm TEXT, source TEXT, source_filter TEXT, show_number TEXT,
        created_at TEXT, type_str TEXT, origin_type TEXT, sort TEXT, is_new TEXT,
        outlines_mastery TEXT, filter_type TEXT, cut_question TEXT, user_answer TEXT)
    ''');
    await db.execute('CREATE TABLE Comment (id TEXT PRIMARY KEY)');
    await db.execute('''
      CREATE TABLE IdentityQuestion (
        identity_id TEXT NOT NULL, subject_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL, question_id TEXT NOT NULL,
        PRIMARY KEY (identity_id, subject_id, chapter_id, question_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (subject_id) REFERENCES Subject(id),
        FOREIGN KEY (chapter_id) REFERENCES Chapter(id),
        FOREIGN KEY (question_id) REFERENCES Question(id))
    ''');
    await db.execute('''
      CREATE TABLE IdentitySubject (
        identity_id TEXT NOT NULL, subject_id TEXT NOT NULL,
        total INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (identity_id, subject_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (subject_id) REFERENCES Subject(id))
    ''');
    await db.execute('''
      CREATE TABLE IdentityChapter (
        identity_id TEXT NOT NULL, subject_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL, total INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (identity_id, subject_id, chapter_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (subject_id) REFERENCES Subject(id),
        FOREIGN KEY (chapter_id) REFERENCES Chapter(id))
    ''');
  }

  static Map<String, dynamic>? _findNode(
    List<Map<String, dynamic>> tree,
    String id,
  ) {
    for (final node in tree) {
      if (node['identity_id']?.toString() == id) return node;
      final children = _asList(node['children']);
      if (children.isNotEmpty) {
        final found = _findNode(children, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}
