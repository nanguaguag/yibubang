import 'database_helper.dart';

class Subject {
  String id;
  String name;
  int selected;

  Subject({required this.id, required this.name, required this.selected});

  // Convert a Subject to a map
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  // Convert a map to a Subject
  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'],
      name: map['name'],
      selected: map['selected'],
    );
  }
}

void insertSubject(Subject subject) async {
  int id = await DatabaseHelper().insert('Subject', subject.toMap());
  print('Inserted subject with ID: $id');
}

Future<List<Subject>> fetchSelectedSubjects() async {
  List<Map<String, dynamic>> subjectsData =
      await DatabaseHelper().getByCondition('Subject', 'selected = TRUE', []);
  List<Subject> subjects = subjectsData.map((e) => Subject.fromMap(e)).toList();

  // subjects.forEach((subject) {
  //   print('Subject ID: ${subject.id}, Name: ${subject.name}');
  // });

  return subjects;
}

Future<List<Subject>> fetchAllSubjects() async {
  List<Map<String, dynamic>> subjectsData =
      await DatabaseHelper().getAll('Subject');
  List<Subject> subjects = subjectsData.map((e) => Subject.fromMap(e)).toList();

  // subjects.forEach((subject) {
  //   print('Subject ID: ${subject.id}, Name: ${subject.name}');
  // });

  return subjects;
}

void toggleSubjectSelected(String subjectId) async {
  DatabaseHelper databaseHelper = DatabaseHelper();
  List<Map<String, dynamic>> subject =
      await databaseHelper.getByCondition('Subject', 'id = ?', [subjectId]);
  if (subject.isNotEmpty) {
    bool currentSelected = subject.first['selected'] == 1;
    Map<String, dynamic> updatedData = {'selected': currentSelected ? 0 : 1};
    await databaseHelper.update('Subject', updatedData, 'id = ?', [subjectId]);
  } else {
    print("未找到对应的课程 subject_id = " + subjectId);
  }
}
