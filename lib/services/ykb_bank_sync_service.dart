import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../models/question_bank.dart';
import '../models/bank_progress.dart';
import 'bank_creation_service.dart';
import 'question_bank_file_service.dart';
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
    void Function(BankProgress)? onBankProgress,
    BankCreationService? creationService,
  }) async {
    final creation = creationService ?? BankCreationService();
    void report(BankProgress progress) {
      onProgress?.call(progress.stage, progress.completed, progress.total);
      onBankProgress?.call(progress);
    }
    report(const BankProgress(stage: '拉取身份树'));
    final nodes = await creation.identities();
    final root = BankIdentityNode.find(nodes, bank.identityId);
    if (root == null) throw StateError('身份树中找不到 identity ${bank.identityId}');
    final directory = await Directory.systemTemp.createTemp('bank-rebuild-');
    try {
      final file = await creation.build(
        root: root, bankId: bank.bankId, name: bank.name,
        version: QuestionBankFileService.nextVersion(bank.version),
        directory: directory, pacing: pacing, onProgress: report,
      );
      report(const BankProgress(stage: '校验并安装题库'));
      final installed = await QuestionBankRepository().importFile(
        file.path, expectedBankId: bank.bankId, updateEnabled: false,
      );
      report(const BankProgress(stage: '重建完成', finished: true));
      return installed;
    } finally {
      await directory.delete(recursive: true);
    }
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

  /// Creates content tables in a new disposable database, never a live bank.
  static Future<void> createSchema(Database db) async {
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
    await db.execute('CREATE INDEX idx_identity_question_question ON IdentityQuestion(question_id)');
    await db.execute('CREATE INDEX idx_identity_question_chapter ON IdentityQuestion(identity_id, subject_id, chapter_id)');
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
