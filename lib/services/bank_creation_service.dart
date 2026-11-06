import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../models/bank_progress.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import 'question_bank_file_service.dart';
import 'ykb_bank_sync_service.dart';

typedef BankApiRequest = Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> params);
typedef BankChapterFetcher = Future<YkbChapterFetchResult> Function(Map<String, dynamic> entry, String chapterId);

class BankIdentityNode {
  final Map<String, dynamic> data;
  final List<BankIdentityNode> children;
  String get id => data['identity_id']?.toString() ?? '';
  String get name => data['title']?.toString() ?? id;

  BankIdentityNode(this.data, this.children);

  static List<BankIdentityNode> parse(Object? value) => value is List
      ? value.whereType<Map>().expand((r) {
          final data = Map<String, dynamic>.from(r);
          final node = BankIdentityNode(data, parse(data['children']));
          // Nonselectable grouping nodes can still contain valid identities.
          return node.id.isEmpty || node.id == '0' ? node.children : [node];
        }).toList()
      : [];

  static BankIdentityNode? find(List<BankIdentityNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final match = find(node.children, id);
      if (match != null) return match;
    }
    return null;
  }

  List<BankIdentityNode> selectedRoots(Set<String> selected) {
    if (selected.contains(id)) return [this];
    return children.expand((n) => n.selectedRoots(selected)).toList();
  }
}

class BankCreationService {
  final BankApiRequest request;
  final BankChapterFetcher fetchChapter;
  BankCreationService({BankApiRequest? request, BankChapterFetcher? fetchChapter})
      : request = request ?? ((path, params) => basicReq(path, params)),
        fetchChapter = fetchChapter ?? ((entry, chapterId) => YkbBankSyncService.fetchChapterQuestionsResult(
          identityId: entry['identity_id'].toString(),
          appId: (entry['app_id'] ?? '40').toString(),
          moduleType: (entry['module_type'] ?? '1').toString(),
          chapterId: chapterId,
        ));

  Future<List<BankIdentityNode>> identities() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('loggedin') ?? false)) throw StateError('请先登录医考帮');
    final response = await basicReq('/allQuestion/question/subjectV2', {
      'user_id': prefs.getString('user_id') ?? '',
    }, method: 'GET').timeout(const Duration(seconds: 30));
    if (response['code']?.toString() != '200') throw StateError('身份目录获取失败');
    return BankIdentityNode.parse(response['data']);
  }

  /// Builds a complete single-root artifact. No installation on failed chapters.
  Future<File> build({
    required BankIdentityNode root,
    required String bankId,
    required String name,
    required String version,
    required Directory directory,
    BankTaskCancellation? cancellation,
    void Function(BankProgress)? onProgress,
    SyncPacing pacing = const SyncPacing(),
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(bankId)) throw const FormatException('题库标识无效');
    final identities = <Map<String, dynamic>>[];
    final entries = <BankIdentityNode>[];
    final visited = <String>{};
    void collect(BankIdentityNode node, String parent) {
      if (!visited.add(node.id)) throw const FormatException('身份树包含重复节点');
      identities.add({'id': node.id, 'parent_id': parent, 'name': node.name});
      if (node.children.isEmpty) {
        if ((node.data['category'] ?? 'chapter') == 'chapter') entries.add(node);
      } else {
        for (final child in node.children) { collect(child, node.id); }
      }
    }
    collect(root, '-1');
    if (entries.isEmpty) throw StateError('所选身份没有章节刷题入口');
    final chapters = <_BuildChapter>[];
    onProgress?.call(const BankProgress(stage: '读取课程目录'));
    for (final entry in entries) {
      cancellation?.check();
      await pacing.requestDelay();
      final response = await request('/allquestion/question/chapter', {
        'identity_id': entry.id,
        'category': 'chapter', 'type': 'all', 'search_where': '[]',
        'module_type': (entry.data['module_type'] ?? '1').toString(),
        'app_id': (entry.data['app_id'] ?? '40').toString(),
        'am_pm': (entry.data['am_pm'] ?? '').toString(),
      }).timeout(const Duration(seconds: 30));
      if (response['code']?.toString() != '200') throw StateError('${entry.name}目录获取失败');
      final nodes = response['data'];
      if (nodes is! List) throw const FormatException('课程目录格式无效');
      for (final raw in nodes.whereType<Map>()) {
        final subject = Map<String, dynamic>.from(raw);
        final subjectId = (subject['chapter_id'] ?? subject['id'] ?? '').toString();
        if (subjectId.isEmpty) throw const FormatException('课程 ID 为空');
        void collectChapter(Map<String, dynamic> node, List<String> ancestors) {
          final id = (node['chapter_id'] ?? node['id'] ?? '').toString();
          final title = node['title']?.toString() ?? id;
          final children = node['children'];
          if (children is List && children.isNotEmpty) {
            for (final child in children.whereType<Map>()) {
              collectChapter(Map<String, dynamic>.from(child), [...ancestors, title]);
            }
          } else {
            if (id.isEmpty) throw const FormatException('章节 ID 为空');
            chapters.add(_BuildChapter(entry, subjectId,
              subject['title']?.toString() ?? subjectId, id,
              [...ancestors, title].join(' · '), int.tryParse('${node['count'] ?? ''}')));
          }
        }
        final children = subject['children'];
        if (children is List && children.isNotEmpty) {
          for (final child in children.whereType<Map>()) { collectChapter(Map<String, dynamic>.from(child), []); }
        } else {
          collectChapter(subject, []);
        }
      }
    }
    if (chapters.isEmpty) throw StateError('没有可用章节');
    final totalQuestions = chapters.every((c) => c.count != null)
        ? chapters.fold<int>(0, (sum, c) => sum + c.count!) : 0;
    final output = File(p.join(directory.path, '$bankId.sqlite'));
    if (await output.exists()) throw StateError('暂存输出文件已存在');
    final db = await openDatabase(output.path, singleInstance: false);
    var fetchedQuestions = 0;
    try {
      await YkbBankSyncService.createSchema(db);
      await db.rawQuery('PRAGMA foreign_keys = ON');
      await db.insert('BankMeta', {
        'bank_id': bankId, 'name': name, 'version': version, 'schema_version': 1,
        'generated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'source': 'ykb-created',
      });
      for (final row in identities) { await db.insert('Identity', row); }
      for (var i = 0; i < chapters.length; i++) {
        cancellation?.check();
        final chapter = chapters[i];
        onProgress?.call(BankProgress(stage: '抓取题目', chapter: '${chapter.entry.name} · ${chapter.title}',
          completed: i, total: chapters.length, questions: fetchedQuestions, expectedQuestions: totalQuestions));
        await pacing.requestDelay();
        var result = await fetchChapter(chapter.entry.data, chapter.id)
            .timeout(const Duration(seconds: 45));
        if (!result.isOk && !result.isRestricted && result.code != '309') {
          onProgress?.call(BankProgress(stage: '章节请求失败，正在重试',
            chapter: '${chapter.entry.name} · ${chapter.title}', completed: i,
            total: chapters.length, questions: fetchedQuestions, expectedQuestions: totalQuestions));
          cancellation?.check();
          await pacing.requestDelay();
          result = await fetchChapter(chapter.entry.data, chapter.id)
              .timeout(const Duration(seconds: 45));
        }
        cancellation?.check();
        if (!result.isOk || result.questions == null) {
          throw StateError('${chapter.title}抓取失败：${result.code} ${result.message}');
        }
        final questions = result.questions!;
        if (chapter.count != null && questions.length != chapter.count) {
          throw StateError('${chapter.title}题量不完整：${questions.length}/${chapter.count}');
        }
        await db.transaction((txn) async {
          await txn.insert('Subject', {'id': chapter.subjectId, 'name': chapter.subjectName}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.insert('Chapter', {'id': chapter.id, 'name': chapter.title}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.insert('IdentitySubject', {'identity_id': chapter.entry.id, 'subject_id': chapter.subjectId, 'total': 0}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.insert('IdentityChapter', {'identity_id': chapter.entry.id, 'subject_id': chapter.subjectId, 'chapter_id': chapter.id, 'total': 0}, conflictAlgorithm: ConflictAlgorithm.ignore);
          for (final question in questions) {
            final row = YkbBankSyncService.questionRow(question, chapter.entry.id, {'id': chapter.id, 'parentId': chapter.subjectId});
            if ((row['id'] as String).isEmpty) throw const FormatException('题目 ID 为空');
            row['user_answer'] = ''; row['cut_question'] = '0';
            row['is_collection_question'] = '0';
            await txn.insert('Question', row, conflictAlgorithm: ConflictAlgorithm.ignore);
            await txn.insert('IdentityQuestion', {'identity_id': chapter.entry.id, 'subject_id': chapter.subjectId,
              'chapter_id': chapter.id, 'question_id': row['id']}, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        });
        fetchedQuestions += questions.length;
        await pacing.chapterDelay();
      }
      cancellation?.check();
      onProgress?.call(BankProgress(stage: '重算与校验', completed: chapters.length, total: chapters.length,
        questions: fetchedQuestions, expectedQuestions: totalQuestions));
      await db.transaction((txn) => QuestionBankFileService.recount(txn, version: version));
      if ((await db.rawQuery('PRAGMA integrity_check')).first.values.first != 'ok' ||
          (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('生成题库校验失败');
      }
    } catch (_) {
      await db.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await db.close();
    return output;
  }

  Future<QuestionBank> create(BankIdentityNode root, {
    void Function(BankProgress)? onProgress,
    BankTaskCancellation? cancellation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('loggedin') ?? false)) throw StateError('请先登录医考帮');
    final directory = await Directory.systemTemp.createTemp('bank-create-');
    final id = 'custom_${root.id}_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final file = await build(root: root, bankId: id, name: root.name, version: '1.0.0', directory: directory,
        onProgress: onProgress, cancellation: cancellation,
        pacing: SyncPacing(jitterEnabled: prefs.getBool('sync_ykb_jitter_enabled') ?? false));
      cancellation?.check();
      onProgress?.call(const BankProgress(stage: '安装题库'));
      final installed = await QuestionBankRepository().importFile(file.path, expectedBankId: id, updateEnabled: false);
      onProgress?.call(const BankProgress(stage: '创建完成', finished: true));
      return installed;
    } finally {
      await directory.delete(recursive: true);
    }
  }
}

class _BuildChapter {
  final BankIdentityNode entry;
  final String subjectId, subjectName, id, title;
  final int? count;
  _BuildChapter(this.entry, this.subjectId, this.subjectName, this.id, this.title, this.count);
}
