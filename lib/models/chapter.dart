import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/models/subject.dart';
import '../db/database_helper.dart';

class Chapter {
  String id;
  String name;
  String subjectId;
  int correct;
  int incorrect;
  int total;
  String? identityId;

  Chapter({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.correct,
    required this.incorrect,
    required this.total,
    this.identityId,
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
      'identity_id': identityId,
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
      identityId: map['identity_id'] as String?,
    );
  }
}

void sortChaptersById(List<Chapter> chapters) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  chapters.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

Future<List<Chapter>> getChaptersBySubject(Subject subject) async {
  final db = await DatabaseHelper().database;
  final userDb = await UserDBHelper().database;
  final prefs = await SharedPreferences.getInstance();
  final identityId = subject.identityId ?? prefs.getString('identityId');
  final bankId = prefs.getString('activeBankId');
  if (identityId == null ||
      identityId.isEmpty ||
      bankId == null ||
      bankId.isEmpty) {
    return [];
  }

  List<Map<String, dynamic>> mainRows = await db.rawQuery('''
    SELECT C.id       AS chapter_id,
           C.name     AS chapter_name,
           IC.total   AS total
    FROM IdentityChapter AS IC
    JOIN Chapter AS C
      ON C.id = IC.chapter_id
    WHERE IC.identity_id = ?
      AND IC.subject_id  = ?
  ''', [identityId, subject.id]);

  if (mainRows.isEmpty) return [];

  // 提取所有 chapter_id
  final chapterIds = mainRows.map((r) => r['chapter_id'] as String).toList();

  // 占位符串 "?, ?, …"
  final placeholders = List.filled(chapterIds.length, '?').join(', ');

  // 2. 一次性拿 user_data 的 correct/incorrect
  List<Map<String, dynamic>> userRows = await userDb.rawQuery('''
    SELECT chapter_id, correct, incorrect
    FROM IdentityChapter
    WHERE bank_id = ?
      AND identity_id = ?
      AND subject_id = ?
      AND chapter_id IN ($placeholders)
  ''', [bankId, identityId, subject.id, ...chapterIds]);

  // 3. 如果有缺失的，就在一个事务里批量插入
  final existingIds = userRows.map((r) => r['chapter_id'] as String).toSet();
  final missingIds =
      chapterIds.where((id) => !existingIds.contains(id)).toList();

  if (missingIds.isNotEmpty) {
    await userDb.transaction((txn) async {
      final batch = txn.batch();
      for (final id in missingIds) {
        batch.insert('IdentityChapter', {
          'bank_id': bankId,
          'identity_id': identityId,
          'subject_id': subject.id,
          'chapter_id': id,
          'correct': 0,
          'incorrect': 0,
        });
      }
      await batch.commit(noResult: true);
    });

    // 本地也补上 0/0 的记录，方便后面合并
    userRows = List<Map<String, dynamic>>.from(userRows);
    userRows.addAll(
      missingIds.map(
        (id) => {
          'bank_id': bankId,
          'subject_id': subject.id,
          'chapter_id': id,
          'correct': 0,
          'incorrect': 0,
        },
      ),
    );
  }

  // 4. 在内存中把主数据和用户数据合并，构造 Chapter 对象列表
  final List<Chapter> chapters = mainRows.map((r) {
    final cid = r['chapter_id'] as String;
    final userRec = userRows.firstWhere((u) => u['chapter_id'] == cid);
    return Chapter(
      id: cid,
      name: r['chapter_name'] as String,
      subjectId: subject.id,
      total: r['total'] as int,
      correct: userRec['correct'] as int,
      incorrect: userRec['incorrect'] as int,
      identityId: identityId,
    );
  }).toList();

  // 5. 排序（如果需要）
  sortChaptersById(chapters);

  return chapters;
}
