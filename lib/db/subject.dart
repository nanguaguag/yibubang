import 'database_helper.dart';

class Subject {
  String id;
  String name;

  Subject({required this.id, required this.name});

  // Convert a Subject to a map
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  // Convert a map to a Subject
  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'],
      name: map['name'],
    );
  }
}

void insertSubject() async {
  var subject = Subject(id: '1', name: 'Mathematics');
  int id = await DatabaseHelper().insert('Subject', subject.toMap());
  print('Inserted subject with ID: $id');
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
