import 'package:yibubang/models/subject.dart';

import '../common/app_strings.dart';
import '../db/database_helper.dart';

class Chapter {
  String id;
  String name;
  String subjectId;
  int correct;
  int incorrect;
  int total;

  Chapter({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.correct,
    required this.incorrect,
    required this.total,
  });

  // Convert a Chapter to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject_id': subjectId,
      'correct': correct,
      'incorrect': incorrect,
      'total': total,
    };
  }

  // Convert a map to a Chapter
  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'],
      name: map['name'],
      subjectId: map['subject_id'],
      correct: map['correct'],
      incorrect: map['incorrect'],
      total: map['total'],
    );
  }
}

void sortChaptersById(List<Chapter> chapters) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  chapters.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

Future<List<Chapter>> getChaptersBySubject(Subject subject) async {
  final dbh = DatabaseHelper();
  final udbh = UserDBHelper();
  final identityId = AppStrings.identity_id;

  // Step 1: 获取 IdentityChapter 表中的 total 信息（主数据库）
  final chapterRecords = await dbh.getByCondition(
    'IdentityChapter',
    'identity_id = ? AND subject_id = ?',
    [identityId, subject.id],
  );

  if (chapterRecords.isEmpty) return [];
  // 提取所有 chapter_id
  final chapterIds =
      chapterRecords.map((e) => e['chapter_id'].toString()).toList();

  // Step 2: 获取 Chapter 表信息（主数据库）
  final placeholders = List.filled(chapterIds.length, '?').join(', ');
  final chapterInfos = await dbh.getByRawQuery(
    'SELECT * FROM Chapter WHERE id IN ($placeholders)',
    chapterIds,
  );
  // Step 3: 获取 UserDBHelper 中的 correct、incorrect 信息（用户数据库）
  List<Map<String, dynamic>> chapterUserRecords = await udbh.getByRawQuery(
    'SELECT * FROM IdentityChapter WHERE identity_id = ? AND chapter_id IN ($placeholders)',
    [identityId, ...chapterIds],
  );
  if (chapterUserRecords.isEmpty) {
    // 在userdb里面创建并初始化
    for (final id in chapterIds) {
      await udbh.insert(
        'IdentityChapter',
        {
          'identity_id': identityId,
          'subject_id': subject.id,
          'chapter_id': id,
          'correct': 0,
          'incorrect': 0,
        },
      );
    }
    // 重新获取
    chapterUserRecords = await udbh.getByRawQuery(
      'SELECT * FROM IdentityChapter WHERE identity_id = ? AND chapter_id IN ($placeholders)',
      [identityId, ...chapterIds],
    );
  }

  // Step 4: 转换为 Map，方便合并
  final chapterRecordMap = {
    for (var s in chapterRecords) s['chapter_id'].toString(): s,
  };
  final chapterUserRecordMap = {
    for (var s in chapterUserRecords) s['chapter_id'].toString(): s,
  };

  // Step 5: 合并所有数据
  final List<Chapter> chapters = chapterInfos.map((e) {
    final record = chapterRecordMap[e['id'].toString()] ?? {};
    final record2 = chapterUserRecordMap[e['id'].toString()] ?? {};
    return Chapter(
      id: e['id'],
      name: e['name'] ?? '',
      subjectId: subject.id,
      correct: record2['correct'],
      incorrect: record2['incorrect'],
      total: record['total'],
    );
  }).toList();

  // Step 6: 排序（如果你已有排序逻辑）
  sortChaptersById(chapters);

  return chapters;
}
