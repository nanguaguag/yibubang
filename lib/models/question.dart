import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'chapter.dart';
import 'package:flutter/foundation.dart';

class UserQuestion {
  String id;
  String chapterId;
  String chapterParentId;
  String cutQuestion;
  String userAnswer; // 用户答案
  int status; // 题目状态
  int collection; // 是否收藏

  UserQuestion({
    required this.id,
    required this.chapterId,
    required this.chapterParentId,
    required this.cutQuestion,
    required this.userAnswer,
    required this.status,
    required this.collection,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chapter_id': chapterId,
      'chapter_parent_id': chapterParentId,
      'cut_question': cutQuestion,
      'user_answer': userAnswer,
      'status': status,
      'collection': collection,
    };
  }

  factory UserQuestion.fromMap(Map<String, dynamic> map) {
    return UserQuestion(
      id: map['id'],
      chapterId: map['chapter_id'],
      chapterParentId: map['chapter_parent_id'],
      cutQuestion: map['cut_question'],
      userAnswer: map['user_answer'] ?? '',
      status: map['status'] ?? 0,
      collection: map['collection'] ?? 0,
    );
  }
}

class Question {
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
      cutQuestion: map['cut_question'],
      userAnswer: map['user_answer'] ?? '',
    );
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

Future<List<Question>> getQuestionsFromChapter(Chapter chapter) async {
  final dbh = DatabaseHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';

  // 用一次 JOIN+ORDER BY 直接拿到所有需要的 Question
  final rows = await dbh.getByRawQuery(
    '''
    SELECT q.*
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
  final udb = await UserDBHelper().database;

  // 1. 取出所有题目 ID
  final questions = await questionsFuture;
  final ids = questions.map((q) => q.id).toList();

  // 2. 一次性查询已存在的 UserQuestion
  final existingRows = await udb.query(
    'Question',
    where: 'id IN (${List.filled(ids.length, '?').join(',')})',
    whereArgs: ids,
  );
  // 把已存在的 id 收集到一个 Set 里
  final existingIds = existingRows.map((r) => r['id'] as String).toSet();

  // 3. 准备缺失的记录和最终返回列表
  List<UserQuestion> resultList = [];
  List<UserQuestion> toInsert = [];

  for (final q in questions) {
    if (existingIds.contains(q.id)) {
      // 已有，直接构造
      final row = existingRows.firstWhere((r) => r['id'] == q.id);
      resultList.add(UserQuestion.fromMap(row));
    } else {
      // 缺失，先放到待插入列表
      final uq = UserQuestion(
        id: q.id,
        chapterId: q.chapterId ?? 'default_chapter_id',
        chapterParentId: q.chapterParentId ?? 'default_subject_id',
        cutQuestion: '',
        userAnswer: '',
        status: 0,
        collection: 0,
      );
      toInsert.add(uq);
      resultList.add(uq);
    }
  }

  // 4. 如果有缺失，就在一个事务里批量插入
  if (toInsert.isNotEmpty) {
    await Future.microtask(() async {
      await udb.transaction((txn) async {
        final batch = txn.batch();
        for (final uq in toInsert) {
          batch.insert('Question', uq.toMap());
        }
        await batch.commit(noResult: true);
      });
    });
  }

  return resultList;
}

Future<void> updateQuestion(
  UserQuestion uq,
  Question q, {
  bool prevCorrect = true,
}) async {
  final db = await DatabaseHelper().database;
  final userDb = await UserDBHelper().database;

  // 1. 查出所有相关 identity/subject/chapter
  final iqRows = await db.query(
    'IdentityQuestion',
    columns: ['identity_id', 'subject_id', 'chapter_id'],
    where: 'question_id = ?',
    whereArgs: [uq.id],
  );

  // 2. 对每一行做 UPSERT
  final batch = userDb.batch();
  for (final row in iqRows) {
    final String identityId = row['identity_id'] as String;
    final String subjectId = row['subject_id'] as String;
    final String chapterId = row['chapter_id'] as String;
    final int deltaCorrect;
    final int deltaIncorrect;

    if (uq.status == 1) {
      // 新增：做对一次
      deltaCorrect = 1;
      deltaIncorrect = 0;
    } else if (uq.status == 2) {
      // 新增：做错一次
      deltaCorrect = 0;
      deltaIncorrect = 1;
    } else if (uq.status == 0) {
      // 撤回：根据 prevCorrect 决定撤回哪一类
      deltaCorrect = prevCorrect ? -1 : 0;
      deltaIncorrect = prevCorrect ? 0 : -1;
    } else {
      // 其他：不处理
      deltaCorrect = 0;
      deltaIncorrect = 0;
    }

    debugPrint(
      "Updating for identity $identityId, subject $subjectId, chapter $chapterId: "
      "deltaCorrect=$deltaCorrect, deltaIncorrect=$deltaIncorrect",
    );

    //// 2.1 IdentitySubject 的 UPSERT
    if (uq.status == 1 || uq.status == 2) {
      // 2.1 新增作答：UPSERT（用 delta 变量更清晰）
      batch.rawInsert('''
        INSERT INTO IdentitySubject(identity_id, subject_id, correct, incorrect, selected)
        VALUES(?, ?, ?, ?, COALESCE((SELECT selected FROM IdentitySubject WHERE identity_id=? AND subject_id=?), 0))
        ON CONFLICT(identity_id, subject_id) DO UPDATE SET
          correct   = correct + excluded.correct,
          incorrect = incorrect + excluded.incorrect;
      ''', [
        identityId,
        subjectId,
        deltaCorrect,
        deltaIncorrect,
        identityId,
        subjectId,
      ]);
    } else if (uq.status == 0) {
      // 2.2 撤回作答：只 UPDATE（避免“撤回但记录不存在”导致插入奇怪数据）
      // 并且把结果截断到 >=0，防止撤回过头出现负数
      batch.rawUpdate('''
        UPDATE IdentitySubject
        SET
          correct   = CASE WHEN correct + ? < 0 THEN 0 ELSE correct + ? END,
          incorrect = CASE WHEN incorrect + ? < 0 THEN 0 ELSE incorrect + ? END
        WHERE identity_id = ? AND subject_id = ?;
      ''', [
        deltaCorrect,
        deltaCorrect,
        deltaIncorrect,
        deltaIncorrect,
        identityId,
        subjectId,
      ]);
    }

    // 2.2 IdentityChapter 的 UPSERT
    if (uq.status == 1 || uq.status == 2) {
      // 新增作答：UPSERT（插入或累加）
      batch.rawInsert('''
        INSERT INTO IdentityChapter(identity_id, subject_id, chapter_id, correct, incorrect)
        VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(identity_id, chapter_id) DO UPDATE SET
          correct   = correct + excluded.correct,
          incorrect = incorrect + excluded.incorrect;
      ''', [
        identityId,
        subjectId,
        chapterId,
        deltaCorrect,
        deltaIncorrect,
      ]);
    } else if (uq.status == 0) {
      // 撤回作答：只 UPDATE，且截断到 >=0，避免负数
      batch.rawUpdate('''
        UPDATE IdentityChapter
        SET
          correct   = CASE WHEN correct + ? < 0 THEN 0 ELSE correct + ? END,
          incorrect = CASE WHEN incorrect + ? < 0 THEN 0 ELSE incorrect + ? END
        WHERE identity_id = ? AND chapter_id = ?;
      ''', [
        deltaCorrect,
        deltaCorrect,
        deltaIncorrect,
        deltaIncorrect,
        identityId,
        chapterId,
      ]);
    }
  }

  // 3. 更新 UserDB 中的 Question 表
  batch.update(
    'Question',
    {
      'status': uq.status,
      'collection': uq.collection,
      'user_answer': uq.userAnswer,
    },
    where: 'id = ?',
    whereArgs: [uq.id],
  );

  // 3. UserDB Activity 表中插入记录
  final int isCorrect = 2 - uq.status; // 1 -> 1, 2 -> 0
  batch.insert(
    'Activities',
    {
      'id': generateSimpleId(),
      'title': 'NewAnswer',
      'description': '''{
        "paper_id": "0",
        "identity_id": "${q.identityId}",
        "chapter_id": "${q.chapterId}",
        "collection_id": "",
        "category_id": "",
        "chapter_parent_id": "${q.chapterParentId}",
        "answer": "${getLastAnswer(uq.userAnswer)}",
        "question_id": ${q.id},
        "is_right": "$isCorrect",
        "app_id": "${q.nativeAppId}",
        "duration": "10",
        "subject_id": "20101"
      }''',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    },
  );
  // 一次性提交
  await batch.commit(noResult: true);
}
