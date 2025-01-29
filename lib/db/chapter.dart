import 'database_helper.dart';

class Chapter {
  String id;
  String name;
  String? subjectId; // This is a foreign key reference to Subject table

  Chapter({required this.id, required this.name, this.subjectId});

  // Convert a Chapter to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject_id': subjectId,
    };
  }

  // Convert a map to a Chapter
  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'],
      name: map['name'],
      subjectId: map['subject_id'],
    );
  }
}

void sortChaptersById(List<Chapter> chapters) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  chapters.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

Future<List<Chapter>> fetchChaptersBySubjectId(String subjectId) async {
  List<Map<String, dynamic>> chaptersData = await DatabaseHelper()
      .getByCondition('Chapter', 'subject_id = ?', [subjectId]);
  List<Chapter> chapters = chaptersData.map((e) => Chapter.fromMap(e)).toList();

  sortChaptersById(chapters);

  return chapters;
}
