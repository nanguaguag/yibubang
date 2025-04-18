import '../db/database_helper.dart';
import 'chapter.dart';

class UserQuestion {
  String id;
  String? chapterId;
  String? chapterParentId;
  String cutQuestion;
  String userAnswer; // 用户答案
  int status; // 题目状态
  int collection; // 是否收藏

  UserQuestion({
    required this.id,
    this.chapterId,
    this.chapterParentId,
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

void sortQuestionsById(List<Question> questions) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  questions.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

void sortUserQuestionsById(List<UserQuestion> questions) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  questions.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

Future<List<Question>> getQuestionsFromChapter(Chapter chapter) async {
  List<Map<String, dynamic>> questionsData =
      await DatabaseHelper().getByCondition(
    'Question',
    'chapter_parent_id = ? AND chapter_id = ?',
    [chapter.subjectId, chapter.id],
  );
  List<Question> questions =
      questionsData.map((e) => Question.fromMap(e)).toList();

  sortQuestionsById(questions);

  return questions;
}

Future<List<UserQuestion>> getUserQuestionsFromChapter(Chapter chapter) async {
  List<Map<String, dynamic>> questionsData =
      await UserDBHelper().getByCondition(
    'Question',
    'chapter_parent_id = ? AND chapter_id = ?',
    [chapter.subjectId, chapter.id],
  );
  List<UserQuestion> questions =
      questionsData.map((e) => UserQuestion.fromMap(e)).toList();

  sortUserQuestionsById(questions);

  return questions;
}

Future<void> updateQuestion(UserQuestion question) async {
  // 更新问题状态和用户答案
  await UserDBHelper().update(
    'Question',
    {
      'status': question.status,
      'collection': question.collection,
      'user_answer': question.userAnswer,
    },
    'id = ?',
    [question.id],
  );
}
