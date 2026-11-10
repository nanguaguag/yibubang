import 'package:sqflite/sqflite.dart';
import '../db/data_transfer.dart';
import '../db/user_database_coordinator.dart';
import '../db/durable_sync_queue.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../services/ykb_sync_service.dart';
import 'answer_statistics.dart';
import 'chapter.dart';

class UserQuestion {
  String id;
  String chapterId;
  String chapterParentId;
  String cutQuestion;
  String userAnswer; // 用户答案
  int status; // 题目状态
  int collection; // 是否收藏

  int updatedAt;

  UserQuestion({
    required this.id,
    required this.chapterId,
    required this.chapterParentId,
    this.cutQuestion = '0',
    required this.userAnswer,
    required this.status,
    required this.collection,
    this.updatedAt = 0,
  });

  bool get isCut => cutQuestion == '1' || cutQuestion == 'cutted';
  set isCut(bool value) => cutQuestion = value ? '1' : '0';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chapter_id': chapterId,
      'chapter_parent_id': chapterParentId,
      'cut_question': isCut ? '1' : '0',
      'user_answer': userAnswer,
      'status': status,
      'collection': collection,
      'updated_at': updatedAt,
    };
  }

  factory UserQuestion.fromMap(Map<String, dynamic> map) {
    final rawCut = map['cut_question']?.toString() ?? '0';
    final isCut = rawCut == '1' || rawCut == 'cutted';
    return UserQuestion(
      id: map['id']?.toString() ?? '',
      chapterId: map['chapter_id']?.toString() ?? '',
      chapterParentId: map['chapter_parent_id']?.toString() ?? '',
      cutQuestion: isCut ? '1' : '0',
      userAnswer: map['user_answer'] ?? '',
      status: map['status'] ?? 0,
      collection: map['collection'] ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class Question {
  /// 本次只读实体加载的真实来源，不写入题库或用户状态主键。
  String? sourceBankId;
  String id;
  String? year; // 年份
  String? unit;
  String? title; // 题目标题
  String? publicTitle;
  String? titleImg; // 标题图片
  String? number;
  String? publicNumber;
  String? restore;
  String? restoreImg;
  String? explain; // 解答
  String? explainImg;
  String? answer;
  String? option; // 选项信息, JSON data stored as a string
  String? score;
  String? scoreDescribe;
  String? nativeAppId;
  String? nativeIdentityId;
  String? appId;
  String? identityId;
  String? chapterId; // Foreign Key
  String? chapterParentId; // Foreign Key
  String? type; // 题目类型（数字）
  String? partId;
  String? partParentId;
  String? sortChapter;
  String? sortChapterAm;
  String? sortChapterPm;
  String? outlines;
  String? outlinesAm;
  String? outlinesPm;
  String? sortPart;
  String? sortPartAm;
  String? sortPartPm;
  String? amPm;
  String? highFrequency;
  String? isCollectionQuestion;
  String? isRealQuestion;
  String? casesId;
  String? casesParentId;
  String? sortCases;
  String? sortCasesAm;
  String? sortCasesPm;
  String? source;
  String? sourceFilter;
  String? showNumber;
  String? createdAt;
  String? typeStr; // 题目类型（字符串）
  String? originType;
  String? sort;
  String? isNew; // 是否为新题
  String? outlinesMastery;
  String? filterType;
  String? cutQuestion; // 是否已斩
  String userAnswer; // 用户答案

  Question({
    required this.id,
    this.year,
    this.unit,
    this.title,
    this.publicTitle,
    this.titleImg,
    this.number,
    this.publicNumber,
    this.restore,
    this.restoreImg,
    this.explain,
    this.explainImg,
    this.answer,
    this.option,
    this.score,
    this.scoreDescribe,
    this.nativeAppId,
    this.nativeIdentityId,
    this.appId,
    this.identityId,
    this.chapterId,
    this.chapterParentId,
    this.type,
    this.partId,
    this.partParentId,
    this.sortChapter,
    this.sortChapterAm,
    this.sortChapterPm,
    this.outlines,
    this.outlinesAm,
    this.outlinesPm,
    this.sortPart,
    this.sortPartAm,
    this.sortPartPm,
    this.amPm,
    this.highFrequency,
    this.isCollectionQuestion,
    this.isRealQuestion,
    this.casesId,
    this.casesParentId,
    this.sortCases,
    this.sortCasesAm,
    this.sortCasesPm,
    this.source,
    this.sourceFilter,
    this.showNumber,
    this.createdAt,
    this.typeStr,
    this.originType,
    this.sort,
    this.isNew,
    this.outlinesMastery,
    this.filterType,
    this.cutQuestion,
    required this.userAnswer,
  });

  // Convert a Question to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'year': year,
      'unit': unit,
      'title': title,
      'public_title': publicTitle,
      'title_img': titleImg,
      'number': number,
      'public_number': publicNumber,
      'restore': restore,
      'restore_img': restoreImg,
      'explain': explain,
      'explain_img': explainImg,
      'answer': answer,
      'option': option,
      'score': score,
      'score_describe': scoreDescribe,
      'native_app_id': nativeAppId,
      'native_identity_id': nativeIdentityId,
      'app_id': appId,
      'identity_id': identityId,
      'chapter_id': chapterId,
      'chapter_parent_id': chapterParentId,
      'type': type,
      'part_id': partId,
      'part_parent_id': partParentId,
      'sort_chapter': sortChapter,
      'sort_chapter_am': sortChapterAm,
      'sort_chapter_pm': sortChapterPm,
      'outlines': outlines,
      'outlines_am': outlinesAm,
      'outlines_pm': outlinesPm,
      'sort_part': sortPart,
      'sort_part_am': sortPartAm,
      'sort_part_pm': sortPartPm,
      'am_pm': amPm,
      'high_frequency': highFrequency,
      'is_collection_question': isCollectionQuestion,
      'is_real_question': isRealQuestion,
      'cases_id': casesId,
      'cases_parent_id': casesParentId,
      'sort_cases': sortCases,
      'sort_cases_am': sortCasesAm,
      'sort_cases_pm': sortCasesPm,
      'source': source,
      'source_filter': sourceFilter,
      'show_number': showNumber,
      'created_at': createdAt,
      'type_str': typeStr,
      'origin_type': originType,
      'sort': sort,
      'is_new': isNew,
      'outlines_mastery': outlinesMastery,
      'filter_type': filterType,
      'cut_question': cutQuestion,
      'user_answer': userAnswer,
    };
  }

  // Convert a map to a Question
  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'],
      year: map['year'],
      unit: map['unit'],
      title: map['title'],
      publicTitle: map['public_title'],
      titleImg: map['title_img'],
      number: map['number'],
      publicNumber: map['public_number'],
      restore: map['restore'],
      restoreImg: map['restore_img'],
      explain: map['explain'],
      explainImg: map['explain_img'],
      answer: map['answer'],
      option: map['option'],
      score: map['score'],
      scoreDescribe: map['score_describe'],
      nativeAppId: map['native_app_id'],
      nativeIdentityId: map['native_identity_id'],
      appId: map['app_id'],
      identityId: map['identity_id'],
      chapterId: map['chapter_id'],
      chapterParentId: map['chapter_parent_id'],
      type: map['type'],
      partId: map['part_id'],
      partParentId: map['part_parent_id'],
      sortChapter: map['sort_chapter'],
      sortChapterAm: map['sort_chapter_am'],
      sortChapterPm: map['sort_chapter_pm'],
      outlines: map['outlines'],
      outlinesAm: map['outlines_am'],
      outlinesPm: map['outlines_pm'],
      sortPart: map['sort_part'],
      sortPartAm: map['sort_part_am'],
      sortPartPm: map['sort_part_pm'],
      amPm: map['am_pm'],
      highFrequency: map['high_frequency'],
      isCollectionQuestion: map['is_collection_question'],
      isRealQuestion: map['is_real_question'],
      casesId: map['cases_id'],
      casesParentId: map['cases_parent_id'],
      sortCases: map['sort_cases'],
      sortCasesAm: map['sort_cases_am'],
      sortCasesPm: map['sort_cases_pm'],
      source: map['source'],
      sourceFilter: map['source_filter'],
      showNumber: map['show_number'],
      createdAt: map['created_at'],
      typeStr: map['type_str'],
      originType: map['origin_type'],
      sort: map['sort'],
      isNew: map['is_new'],
      outlinesMastery: map['outlines_mastery'],
      filterType: map['filter_type'],
      cutQuestion: map['cut_question']?.toString(),
      userAnswer: map['user_answer'] ?? '',
    );
  }

  bool get isCut => cutQuestion == '1' || cutQuestion == 'cutted';
  set isCut(bool value) => cutQuestion = value ? '1' : '0';

  /// 获取题目类型的友好中文名称
  String get typeLabel {
    if (typeStr != null && typeStr!.trim().isNotEmpty) {
      return typeStr!.trim();
    }
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
        return '其他题型';
    }
  }

  /// 判断当前题目是否属于主观题/非选择题（无标准选项）
  bool get isSubjective {
    final rawOption = option;
    if (rawOption != null && rawOption.isNotEmpty && rawOption != '[]') {
      try {
        final decoded = jsonDecode(rawOption);
        if (decoded is List && decoded.isNotEmpty) {
          return false;
        }
      } catch (_) {}
    }
    if (type == '3' ||
        type == '4' ||
        type == '5' ||
        type == '6' ||
        type == '7') {
      return true;
    }
    return type != '1' && type != '2';
  }
}

String getLastAnswer(String userAnswer) {
  /// userAnswer 格式：
  /// - 最后一次答案是DC：AB;ABC;DC
  /// - 还没做：AB;ABC;
  List<String> answers = userAnswer.split(';');
  return answers.last;
}

String changeLastAnswer(String userAnswer, String lastAnswer) {
  List<String> answers = userAnswer.split(';');
  answers.last = lastAnswer;
  return answers.join(';');
}

/// 将字符串按字符排序，用于多选题答案比较，忽略选项顺序。
String sortString(String str) {
  final List<String> chars = str.split('')..sort();
  return chars.join();
}

/// 测试模式交卷判分：把遗留的「待提交」(status==4) 题目按答案批改为正确/错误并落库。
/// 返回本次判分的题数与答对题数。
Future<MapEntry<int, int>> gradePendingQuestions(
  List<Question> questions,
  List<UserQuestion> userQuestions, {
  String? bankId,
}) async {
  final db = await UserDBHelper().database;
  final timeRows = await db.query('QuestionTestTime');
  final times = {
    for (final row in timeRows)
      row['question_id'] as String: row['duration_ms'] as int,
  };
  int graded = 0;
  int correct = 0;
  for (int i = 0; i < questions.length && i < userQuestions.length; i++) {
    final UserQuestion uq = UserQuestion.fromMap(userQuestions[i].toMap());
    if (uq.status != 4) continue;
    final Question q = questions[i];
    final String ans = getLastAnswer(uq.userAnswer);
    if (q.isSubjective) {
      uq.status = (ans == '已掌握' || ans == '正确' || ans == '1' || uq.status == 1)
          ? 1
          : 2;
    } else {
      final String correctAns = q.answer ?? '';
      uq.status =
          (correctAns.isNotEmpty && sortString(ans) == sortString(correctAns))
          ? 1
          : 2;
    }
    if (uq.status == 1) correct++;
    graded++;
    await updateQuestion(uq, q, durationMs: times[uq.id] ?? 0, bankId: bankId);
    userQuestions[i].status = uq.status;
    await db.delete(
      'QuestionTestTime',
      where: 'question_id=?',
      whereArgs: [uq.id],
    );
  }
  return MapEntry(graded, correct);
}

Future<List<Question>> getQuestionsFromChapter(Chapter chapter) async {
  final dbh = DatabaseHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = chapter.identityId ?? prefs.getString('identityId');
  if (identityId == null || identityId.isEmpty) return [];

  // IdentityQuestion 的 identity_id 是题库关系表中的精确归属，不能用
  // Question.identity_id 或父级 Identity 链扩大章节结果集。
  final rows = await dbh.getByRawQuery(
    '''
    SELECT DISTINCT q.*
      FROM Question AS q
      JOIN IdentityQuestion AS iq
        ON q.id = iq.question_id
     WHERE iq.identity_id = ?
       AND iq.subject_id = ?
       AND iq.chapter_id = ?
     ORDER BY q.id
    ''',
    [identityId, chapter.subjectId, chapter.id],
  );

  // 直接映射成对象列表返回
  return rows.map((e) => Question.fromMap(e)).toList();
}

Future<List<UserQuestion>> getUserQuestions(
  Future<List<Question>> questionsFuture,
) async {
  final questions = await questionsFuture;
  if (questions.isEmpty) return [];
  final db = await UserDBHelper().database;
  return db.transaction((tx) async {
    final batch = tx.batch();
    for (final q in questions) {
      batch.insert('Question', {
        'id': q.id,
        'chapter_id': q.chapterId ?? '',
        'chapter_parent_id': q.chapterParentId ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    final rows = <String, Map<String, Object?>>{};
    final ids = questions.map((q) => q.id).toSet().toList();
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 < ids.length ? i + 500 : ids.length);
      final found = await tx.query(
        'Question',
        where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in found) {
        rows[row['id'] as String] = row;
      }
    }
    return questions.map((q) => UserQuestion.fromMap(rows[q.id]!)).toList();
  });
}

Future<void> updateQuestionSimple(
  UserQuestion uq,
  Question q, {
  required Set<String> fields,
}) async {
  const allowed = {'status', 'user_answer', 'collection', 'cut_question'};
  if (fields.isEmpty || !allowed.containsAll(fields)) {
    throw ArgumentError('无效题目字段更新');
  }
  final snapshot = uq.toMap();
  final patch = <String, Object?>{
    for (final field in fields) field: snapshot[field],
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };
  final userDb = await UserDBHelper().database;
  await userDb.transaction((tx) async {
    await tx.rawInsert(
      'INSERT OR IGNORE INTO Question(id,chapter_id,chapter_parent_id) VALUES (?,?,?)',
      [
        snapshot['id'],
        q.chapterId ?? snapshot['chapter_id'],
        q.chapterParentId ?? snapshot['chapter_parent_id'],
      ],
    );
    await tx.update(
      'Question',
      patch,
      where: 'id=?',
      whereArgs: [snapshot['id']],
    );
    if (fields.contains('cut_question') && snapshot['cut_question'] == '0') {
      await tx.rawUpdate(
        "UPDATE Question SET status=0 WHERE id=? AND status=3",
        [snapshot['id']],
      );
      final items = await tx.query(
        'SpacedReviewItem',
        where: 'item_id=?',
        whereArgs: [snapshot['id']],
      );
      if (items.isNotEmpty) {
        final extra = items.first['extra'] == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(
                jsonDecode(items.first['extra'] as String) as Map,
              );
        if (extra['suspension_reason'] == 'cut') {
          extra.remove('suspension_reason');
          await tx.update(
            'SpacedReviewItem',
            {
              'state': 2,
              'due_date': DateTime.now().millisecondsSinceEpoch,
              'extra': jsonEncode(extra),
            },
            where: 'item_id=?',
            whereArgs: [snapshot['id']],
          );
        }
      }
    }
  });
}

Future<void> updateQuestion(
  UserQuestion uq,
  Question q, {
  bool prevCorrect = true,
  int durationMs = 0,
  String? bankId,
  Chapter? chapter,
}) async {
  // 在第一个 await 前固定作答快照，后续页面选择不能改变本次提交。
  uq = UserQuestion.fromMap(uq.toMap());
  final prefs = await SharedPreferences.getInstance();
  final resolvedBankId = bankId ?? prefs.getString('activeBankId');
  if (resolvedBankId == null || resolvedBankId.isEmpty) {
    throw StateError('当前题库尚未初始化');
  }
  // 按题目所属题库打开，而不是依赖当前激活题库，
  // 避免跨库搜索后作答时查错 IdentityQuestion 造成统计丢失。
  final db = await QuestionBankDatabaseManager().openBank(resolvedBankId);
  final userDb = await UserDBHelper().database;
  await ensureQuestionCountProjection(resolvedBankId, bankPath: db.path);
  // 题库关系只读获取；状态、投影差值和流水写入同一用户库事务。
  final iqRows = await db.query(
    'IdentityQuestion',
    columns: ['identity_id', 'subject_id', 'chapter_id'],
    where: 'question_id=?',
    whereArgs: [uq.id],
  );
  String? resolvedSubjectId;
  String? resolvedChapterId;
  String? resolvedIdentityId;
  await userDb.transaction((tx) async {
    final batch = tx.batch();
    batch.rawInsert(
      'INSERT OR IGNORE INTO Question(id,chapter_id,chapter_parent_id) VALUES (?,?,?)',
      [uq.id, q.chapterId, q.chapterParentId],
    );
    // 3. 更新 UserDB 中的 Question 表
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    uq.updatedAt = nowMs;
    batch.update(
      'Question',
      {'status': uq.status, 'user_answer': uq.userAnswer, 'updated_at': nowMs},
      where: 'id = ?',
      whereArgs: [uq.id],
    );

    // 提取真正的 subjectId, chapterId, identityId
    if (iqRows.isNotEmpty) {
      resolvedSubjectId = iqRows.first['subject_id'] as String?;
      resolvedChapterId = iqRows.first['chapter_id'] as String?;
      resolvedIdentityId = iqRows.first['identity_id'] as String?;
    }
    resolvedSubjectId ??= chapter?.subjectId;
    resolvedChapterId ??= chapter?.id;
    resolvedIdentityId ??= chapter?.identityId;

    resolvedSubjectId ??= q.chapterParentId;
    resolvedChapterId ??= q.chapterId;
    resolvedIdentityId ??= q.identityId;

    // 3. UserDB Activity 表中插入记录
    final int isCorrect = 2 - uq.status; // 1 -> 1, 2 -> 0
    // 只有在真正作答（status 1/2）时才把时长计入统计；撤题/测试模式记为 0。
    final int recordedDuration = (uq.status == 1 || uq.status == 2)
        ? durationMs
        : 0;
    final int recordedDurationSec = (recordedDuration / 1000).round();
    final resolvedAppId = (q.nativeAppId?.isNotEmpty == true)
        ? q.nativeAppId!
        : (q.appId?.isNotEmpty == true ? q.appId! : '12');

    batch.insert('Activities', {
      'id': generateSimpleId(),
      'title': 'NewAnswer',
      'description':
          '''{
        "paper_id": "0",
        "identity_id": "${resolvedIdentityId ?? q.identityId ?? ''}",
        "chapter_id": "${resolvedChapterId ?? q.chapterId ?? ''}",
        "collection_id": "",
        "category_id": "",
        "chapter_parent_id": "${q.chapterParentId ?? resolvedSubjectId ?? ''}",
        "answer": "${getLastAnswer(uq.userAnswer)}",
        "question_id": ${q.id},
        "is_right": "$isCorrect",
        "app_id": "$resolvedAppId",
        "duration": "$recordedDurationSec",
        "subject_id": "${resolvedSubjectId ?? q.chapterParentId ?? ''}"
      }''',
      'bank_id': resolvedBankId,
      'question_id': q.id,
      'identity_id': resolvedIdentityId ?? q.identityId,
      'subject_id': resolvedSubjectId ?? q.chapterParentId,
      'chapter_id': resolvedChapterId ?? q.chapterId,
      'is_right': '$isCorrect',
      'duration': recordedDuration,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // 一次性提交
    await batch.commit(noResult: true);
  });
  notifyAnswersChanged();

  if (uq.status == 1 || uq.status == 2) {
    unawaited(
      YkbSyncService.instance.syncAnswer(
        question: q,
        userQuestion: uq,
        durationMs: durationMs,
        subjectId: resolvedSubjectId,
        chapterId: resolvedChapterId,
        identityId: resolvedIdentityId,
        chapterParentId: q.chapterParentId,
      ),
    );
  }
}

/// 固定题目范围在一个事务集合重置；SQLite 触发器更新所有已建立关系投影的题库。
Future<int> resetQuestionAnswers({
  required List<String> questionIds,
  required String bankId,
  required Chapter chapter,
  bool wrongOnly = false,
  String? appId,
}) async {
  final ids = questionIds.toSet().toList();
  if (ids.isEmpty) return 0;
  final bank = await QuestionBankDatabaseManager().openBank(bankId);
  final redoTask = wrongOnly
      ? null
      : await YkbSyncService.instance.prepareRedoChapter(
          chapter: chapter,
          appId: appId,
        );
  final result = await UserDatabaseCoordinator.instance.run(() async {
    await ensureQuestionCountProjection(bankId, bankPath: bank.path);
    final db = await UserDBHelper().database;
    return db.transaction((tx) async {
      var changed = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(
          i,
          i + 500 < ids.length ? i + 500 : ids.length,
        );
        changed += await tx.rawUpdate(
          "UPDATE Question SET user_answer=COALESCE(user_answer,'')||';',status=0,updated_at=? WHERE status ${wrongOnly ? '=2' : 'IN (1,2)'} AND id IN (${List.filled(chunk.length, '?').join(',')})",
          [now, ...chunk],
        );
      }
      if (changed > 0) {
        if (redoTask != null) {
          await DurableSyncQueue.enqueue(
            'YkbSyncQueue',
            redoTask,
            executor: tx,
          );
        }
        await tx.insert('Activities', {
          'id': generateSimpleId(),
          'title': 'RedoChapter',
          'description': jsonEncode({
            'wrong_only': wrongOnly,
            'count': changed,
          }),
          'bank_id': bankId,
          'subject_id': chapter.subjectId,
          'chapter_id': chapter.id,
          'identity_id': chapter.identityId,
          'timestamp': now,
          'duration': 0,
          'is_right': 'redo',
        });
      }
      return changed;
    });
  });
  notifyAnswersChanged();
  if (redoTask != null) unawaited(YkbSyncService.instance.processQueue());
  return result;
}
