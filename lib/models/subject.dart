import 'package:shared_preferences/shared_preferences.dart';
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

Future<List<Subject>> getSelectedSubjects() async {
  final dbh = DatabaseHelper();
  final udbh = UserDBHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';

  // 从 IdentitySubject 中获取 selected=1 的记录
  final subjectUserRecords = await udbh.getByCondition(
    'IdentitySubject',
    'identity_id = ? AND selected = 1',
    [identityId],
  );

  if (subjectUserRecords.isEmpty) return [];

  // 获取所有 subject_id
  final subjectIds =
      subjectUserRecords.map((e) => e['subject_id'].toString()).toList();
  // 获取 Subject 和 IdentitySubject 表中的信息
  final placeholders = List.filled(subjectIds.length, '?').join(', ');
  final subjectInfos = await dbh.getByRawQuery(
    'SELECT * FROM Subject WHERE id IN ($placeholders)',
    subjectIds,
  );
  final subjectRecords = await dbh.getByRawQuery(
    'SELECT * FROM IdentitySubject WHERE identity_id = ? AND subject_id IN ($placeholders)',
    [identityId, ...subjectIds],
  );

  // 转换为 map 以便合并
  final subjectRecordMap = {
    for (var s in subjectRecords) s['subject_id'].toString(): s,
  };
  final subjectUserRecordMap = {
    for (var s in subjectUserRecords) s['subject_id'].toString(): s,
  };

  // 合并 IdentitySubject 和 Subject 表信息
  return subjectInfos.map((e) {
    final record = subjectRecordMap[e['id'].toString()] ?? {};
    final record2 = subjectUserRecordMap[e['id'].toString()] ?? {};
    return Subject(
      id: e['id'],
      name: e['name'] ?? '',
      selected: record2['selected'],
      correct: record2['correct'],
      incorrect: record2['incorrect'],
      total: record['total'],
    );
  }).toList();
}

Future<List<Subject>> getAllSubjects() async {
  final dbh = DatabaseHelper();
  final results = await dbh.getByCondition('Subject', '1=1', []);
  return results
      .map(
        (e) => Subject.fromMap({
          ...e,
          'selected': 0,
          'correct': 0,
          'incorrect': 0,
        }),
      )
      .toList();
}

Future<List<Subject>> getSubjectsByIdentity() async {
  final dbh = DatabaseHelper();
  final udbh = UserDBHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';

  final subjectRecords = await dbh.getByCondition(
    'IdentitySubject',
    'identity_id = ?',
    [identityId],
  );

  List<Map<String, dynamic>> subjectUserRecords = await udbh.getByCondition(
    'IdentitySubject',
    'identity_id = ?',
    [identityId],
  );

  if (subjectRecords.isEmpty) return [];
  final subjectIds =
      subjectRecords.map((e) => e['subject_id'].toString()).toList();
  final placeholders = List.filled(subjectIds.length, '?').join(', ');
  final subjectInfos = await dbh.getByRawQuery(
    'SELECT * FROM Subject WHERE id IN ($placeholders)',
    subjectIds,
  );

  if (subjectUserRecords.length < subjectRecords.length) {
    final existingIds =
        subjectUserRecords.map((e) => e['subject_id'].toString()).toSet();
    final missingIds = subjectIds.where((id) => !existingIds.contains(id));

    for (final id in missingIds) {
      await udbh.insert(
        'IdentitySubject',
        {
          'identity_id': identityId,
          'subject_id': id,
          'correct': 0,
          'incorrect': 0,
          'selected': 0,
        },
      );
    }
    // 重新获取
    subjectUserRecords = await udbh.getByRawQuery(
      'SELECT * FROM IdentitySubject WHERE subject_id IN ($placeholders)',
      subjectIds,
    );
  }

  final subjectRecordMap = {
    for (var s in subjectRecords) s['subject_id'].toString(): s,
  };
  final subjectUserRecordMap = {
    for (var s in subjectUserRecords) s['subject_id'].toString(): s,
  };

  return subjectInfos.map((e) {
    final record = subjectRecordMap[e['id'].toString()] ?? {};
    final record2 = subjectUserRecordMap[e['id'].toString()] ?? {};
    return Subject(
      id: e['id'],
      name: e['name'] ?? '',
      selected: record2['selected'],
      correct: record2['correct'],
      incorrect: record2['incorrect'],
      total: record['total'],
    );
  }).toList();
}

void toggleSubjectSelected(Subject subject) async {
  final udbh = UserDBHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';
  await udbh.update(
    'IdentitySubject',
    {'selected': subject.selected},
    'identity_id = ? AND subject_id = ?',
    [identityId, subject.id.toString()],
  );
}
