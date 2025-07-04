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
  // 1. 打开两个数据库连接
  final db = await DatabaseHelper().database; // 题库（question_data）
  final udb = await UserDBHelper().database; // 用户数据（user_data）
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';

  // 2. 一次性拿出 user_data 中 selected=1 的记录
  final userRows = await udb.query(
    'IdentitySubject',
    where: 'identity_id = ? AND selected = 1',
    whereArgs: [identityId],
  );
  if (userRows.isEmpty) return [];

  // 3. 提取所有 subject_id，并生成占位符
  final subjectIds = userRows.map((r) => r['subject_id'] as String).toList();
  final placeholders = List.filled(subjectIds.length, '?').join(', ');

  // 4. 在题库里 JOIN 一次拿到 name 和 total
  final mainRows = await db.rawQuery('''
    SELECT
      S.id            AS subject_id,
      S.name          AS subject_name,
      ISUB.total      AS total
    FROM Subject AS S
    JOIN IdentitySubject AS ISUB
      ON S.id = ISUB.subject_id
    WHERE ISUB.identity_id = ?
      AND S.id IN ($placeholders)
  ''', [identityId, ...subjectIds]);

  // 5. 把 mainRows 转成 Map，便于合并
  final mainMap = {
    for (var r in mainRows)
      r['subject_id'] as String: {
        'name': r['subject_name'] as String,
        'total': r['total'] as int,
      }
  };

  // 6. 最终在内存合并成 List<Subject>
  return userRows.map((r) {
    final id = r['subject_id'] as String;
    final userRec = r;
    final mainRec = mainMap[id]!;
    return Subject(
      id: id,
      name: mainRec['name'] as String,
      selected: userRec['selected'] as int,
      correct: userRec['correct'] as int,
      incorrect: userRec['incorrect'] as int,
      total: mainRec['total'] as int,
    );
  }).toList();
}

Future<List<Subject>> getSubjectsByIdentity() async {
  // 1. 打开两个数据库连接
  final db = await DatabaseHelper().database; // 题库（question_data）
  final udb = await UserDBHelper().database; // 用户数据（user_data）

  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId') ?? '30401';

  // 2. 主库中一次 JOIN 拿到 subject_id、name、total
  final mainRows = await db.rawQuery('''
    SELECT
      S.id           AS subject_id,
      S.name         AS subject_name,
      ISUB.total     AS total
    FROM IdentitySubject AS ISUB
    JOIN Subject AS S
      ON S.id = ISUB.subject_id
    WHERE ISUB.identity_id = ?
  ''', [identityId]);

  if (mainRows.isEmpty) return [];

  // 3. 提取所有 subject_id
  final subjectIds = mainRows.map((r) => r['subject_id'] as String).toList();
  final placeholders = List.filled(subjectIds.length, '?').join(', ');

  // 4. 用户库中一次性拿 correct/incorrect/selected
  List<Map<String, dynamic>> userRows = await udb.rawQuery('''
    SELECT subject_id, correct, incorrect, selected
    FROM IdentitySubject
    WHERE identity_id = ?
      AND subject_id IN ($placeholders)
  ''', [identityId, ...subjectIds]);

  // 5. 找出缺失的 subject_id 并批量插入（correct/incorrect/selected 初始为 0）
  final existingIds = userRows.map((r) => r['subject_id'] as String).toSet();
  final missingIds =
      subjectIds.where((id) => !existingIds.contains(id)).toList();

  if (missingIds.isNotEmpty) {
    await Future.microtask(() async {
      await udb.transaction((txn) async {
        final batch = txn.batch();
        for (final id in missingIds) {
          batch.insert('IdentitySubject', {
            'identity_id': identityId,
            'subject_id': id,
            'correct': 0,
            'incorrect': 0,
            'selected': 0,
          });
        }
        await batch.commit(noResult: true);
      });
    });

    // 本地 list 补上初始值，后面合并更方便
    userRows = List<Map<String, dynamic>>.from(userRows);
    userRows.addAll(
      missingIds.map(
        (id) => {
          'subject_id': id,
          'correct': 0,
          'incorrect': 0,
          'selected': 0,
        },
      ),
    );
  }

  // 6. 在内存里合并 mainRows 和 userRows，构造 Subject 对象列表
  //    先把 userRows 转 map
  final userMap = {for (var r in userRows) r['subject_id'] as String: r};

  final List<Subject> subjects = mainRows.map((r) {
    final id = r['subject_id'] as String;
    final mainRec = r;
    final userRec = userMap[id]!;

    return Subject(
      id: id,
      name: mainRec['subject_name'] as String,
      total: mainRec['total'] as int,
      correct: userRec['correct'] as int,
      incorrect: userRec['incorrect'] as int,
      selected: userRec['selected'] as int,
    );
  }).toList();

  return subjects;
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
