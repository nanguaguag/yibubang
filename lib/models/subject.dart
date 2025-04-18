import '../db/database_helper.dart';

class Subject {
  String id;
  String name;
  int selected;
  int correct;
  int incorrect;
  int total;

  Subject({
    required this.id,
    required this.name,
    required this.selected,
    required this.correct,
    required this.incorrect,
    required this.total,
  });

  // Convert a Subject to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'selected': selected,
      'correct': correct,
      'incorrect': incorrect,
      'total': total,
    };
  }

  // Convert a map to a Subject
  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'],
      name: map['name'],
      selected: map['selected'],
      correct: map['correct'],
      incorrect: map['incorrect'],
      total: map['total'],
    );
  }
}

Future<List<Subject>> fetchSelectedSubjects() async {
  List<Map<String, dynamic>> subjectsData = await UserDBHelper().getByCondition(
    'Subject',
    'selected = TRUE',
    [],
  );
  List<Subject> subjects = subjectsData.map((e) => Subject.fromMap(e)).toList();

  return subjects;
}

Future<List<Subject>> fetchAllSubjects() async {
  List<Map<String, dynamic>> subjectsData =
      await UserDBHelper().getAll('Subject');
  List<Subject> subjects = subjectsData.map((e) => Subject.fromMap(e)).toList();

  return subjects;
}

void toggleSubjectSelected(String subjectId) async {
  UserDBHelper dbh = UserDBHelper();
  List<Map<String, dynamic>> subject =
      await dbh.getByCondition('Subject', 'id = ?', [subjectId]);
  if (subject.isNotEmpty) {
    bool currentSelected = subject.first['selected'] == 1;
    Map<String, dynamic> updatedData = {'selected': currentSelected ? 0 : 1};
    await dbh.update('Subject', updatedData, 'id = ?', [subjectId]);
  } else {
    print("未找到对应的课程 subject_id = " + subjectId);
  }
}
