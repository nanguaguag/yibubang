import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'identity.dart';

class Subject {
  String id;
  String name;
  int selected;
  int correct;
  int incorrect;
  int total;
  String? identityId;

  Subject({
    required this.id,
    required this.name,
    required this.selected,
    required this.correct,
    required this.incorrect,
    required this.total,
    this.identityId,
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
      'identity_id': identityId,
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
      identityId: map['identity_id'] as String?,
    );
  }
}

/// 按题库 Identity 树组织课程。每个 Identity 节点只包含该节点关联的课程，
/// 子 Identity 通过 children 保留，因此不依赖固定的层级深度。
class SubjectTreeNode {
  final Identity identity;
  final List<Subject> subjects;
  final List<SubjectTreeNode> children;

  const SubjectTreeNode({
    required this.identity,
    required this.subjects,
    required this.children,
  });

  SubjectTreeNode copyWith({
    List<Subject>? subjects,
    List<SubjectTreeNode>? children,
  }) {
    return SubjectTreeNode(
      identity: identity,
      subjects: subjects ?? this.subjects,
      children: children ?? this.children,
    );
  }

  bool get hasSubjectsInSubtree =>
      subjects.isNotEmpty ||
      children.any((child) => child.hasSubjectsInSubtree);
}

/// 读取当前题库中当前专业及其所有后代 Identity，并将课程挂到对应节点。
///
/// 题库库中的 IdentitySubject 是课程归属关系，用户库中的 IdentitySubject
/// 只保存选择状态，两个表通过 bank_id、identity_id、subject_id 合并。
Future<List<SubjectTreeNode>> getSubjectTreeByIdentity() async {
  final db = await DatabaseHelper().database;
  final udb = await UserDBHelper().database;
  final prefs = await SharedPreferences.getInstance();
  final identityId = prefs.getString('identityId');
  final bankId = prefs.getString('activeBankId');
  if (bankId == null || bankId.isEmpty) return [];

  final identityRows = await db.query(
    'Identity',
    columns: ['id', 'parent_id', 'name'],
  );
  final identities = identityRows.map(Identity.fromMap).toList();
  final identityById = {
    for (final identity in identities) identity.id: identity,
  };
  final childrenByParent = <String, List<Identity>>{};
  for (final identity in identities) {
    childrenByParent
        .putIfAbsent(identity.parentId, () => <Identity>[])
        .add(identity);
  }
  for (final children in childrenByParent.values) {
    children.sort((a, b) {
      final nameCompare = a.name.compareTo(b.name);
      if (nameCompare != 0) return nameCompare;
      return a.id.compareTo(b.id);
    });
  }

  // 根节点直接从 Identity.parent_id = -1 推导，不依赖具体 identity ID。
  // 旧版合并题库可能有多个顶层专业，因此保留全部顶层身份树；正式
  // 独立题库必须只有一个根，若遇到其他数据则优先使用当前选择的身份。
  final topLevelIdentities =
      identities.where((identity) => identity.parentId == '-1').toList();
  final selectedRoot = identityById[identityId];
  final rootIdentities = bankId == 'legacy_combined'
      ? topLevelIdentities
      : topLevelIdentities.length == 1
          ? topLevelIdentities
          : selectedRoot == null
              ? topLevelIdentities
              : [selectedRoot];
  if (rootIdentities.isEmpty) return [];

  final subtreeIds = <String>[];
  final visited = <String>{};
  void collectDescendants(String currentId) {
    if (!visited.add(currentId)) return;
    subtreeIds.add(currentId);
    for (final child in childrenByParent[currentId] ?? const <Identity>[]) {
      collectDescendants(child.id);
    }
  }

  for (final rootIdentity in rootIdentities) {
    collectDescendants(rootIdentity.id);
  }
  final placeholders = List.filled(subtreeIds.length, '?').join(', ');
  final initialMainRows = await db.rawQuery('''
    SELECT
      ISUB.identity_id AS identity_id,
      S.id AS subject_id,
      S.name AS subject_name,
      ISUB.total AS total
    FROM IdentitySubject AS ISUB
    JOIN Subject AS S ON S.id = ISUB.subject_id
    WHERE ISUB.identity_id IN ($placeholders)
    ORDER BY S.name, S.id
  ''', subtreeIds);
  // sqflite 的只读数据库会返回不可变 QueryResultSet，复制后才能追加兼容数据。
  final mainRows = <Map<String, dynamic>>[...initialMainRows];

  if (mainRows.isEmpty) return [];

  final subjectIds =
      mainRows.map((row) => row['subject_id'] as String).toSet().toList();
  final subjectPlaceholders = List.filled(subjectIds.length, '?').join(', ');
  List<Map<String, dynamic>> userRows = await udb.rawQuery('''
    SELECT identity_id, subject_id, correct, incorrect, selected
    FROM IdentitySubject
    WHERE bank_id = ?
      AND identity_id IN ($placeholders)
      AND subject_id IN ($subjectPlaceholders)
  ''', [bankId, ...subtreeIds, ...subjectIds]);

  String recordKey(String currentIdentityId, String subjectId) =>
      '$currentIdentityId\u0000$subjectId';

  final existingKeys = userRows
      .map((row) => recordKey(
            row['identity_id'] as String,
            row['subject_id'] as String,
          ))
      .toSet();
  final missingRecords = <Map<String, String>>[];
  for (final row in mainRows) {
    final currentIdentityId = row['identity_id'] as String;
    final subjectId = row['subject_id'] as String;
    if (existingKeys.add(recordKey(currentIdentityId, subjectId))) {
      missingRecords.add({
        'identity_id': currentIdentityId,
        'subject_id': subjectId,
      });
    }
  }

  if (missingRecords.isNotEmpty) {
    await udb.transaction((txn) async {
      final batch = txn.batch();
      for (final record in missingRecords) {
        batch.insert('IdentitySubject', {
          'bank_id': bankId,
          'identity_id': record['identity_id'],
          'subject_id': record['subject_id'],
          'correct': 0,
          'incorrect': 0,
          'selected': 0,
        });
      }
      await batch.commit(noResult: true);
    });
    userRows = [
      ...userRows,
      ...missingRecords.map(
        (record) => <String, dynamic>{
          'identity_id': record['identity_id'],
          'subject_id': record['subject_id'],
          'correct': 0,
          'incorrect': 0,
          'selected': 0,
        },
      ),
    ];
  }

  final userMap = {
    for (final row in userRows)
      recordKey(row['identity_id'] as String, row['subject_id'] as String): row,
  };
  final subjectsByIdentity = <String, List<Subject>>{};
  for (final row in mainRows) {
    final currentIdentityId = row['identity_id'] as String;
    final subjectId = row['subject_id'] as String;
    final userRow = userMap[recordKey(currentIdentityId, subjectId)]!;
    subjectsByIdentity.putIfAbsent(currentIdentityId, () => <Subject>[]).add(
          Subject(
            id: subjectId,
            name: row['subject_name'] as String,
            total: (row['total'] as num?)?.toInt() ?? 0,
            correct: (userRow['correct'] as num?)?.toInt() ?? 0,
            incorrect: (userRow['incorrect'] as num?)?.toInt() ?? 0,
            selected: (userRow['selected'] as num?)?.toInt() ?? 0,
            identityId: currentIdentityId,
          ),
        );
  }

  SubjectTreeNode buildNode(Identity identity) {
    final childNodes = (childrenByParent[identity.id] ?? const <Identity>[])
        .map(buildNode)
        .where((node) => node.hasSubjectsInSubtree)
        .toList();
    final nodeSubjects = subjectsByIdentity[identity.id] ?? const <Subject>[];
    return SubjectTreeNode(
      identity: identity,
      subjects: nodeSubjects,
      children: childNodes,
    );
  }

  final rootNodes = rootIdentities
      .map(buildNode)
      .where((node) => node.hasSubjectsInSubtree)
      .toList();

  // 保留每个根节点本身的课程关系。正式题库的关系可能集中挂在根
  // identity 上，即使其子 identity 没有对应的 IdentitySubject 行，也不能
  // 因为“隐藏根节点”而丢失课程；所有后代仍按 Identity 树递归展示。
  return rootNodes;
}

Future<List<Subject>> getSelectedSubjects() async {
  final tree = await getSubjectTreeByIdentity();
  final selectedSubjects = <Subject>[];

  void collectSubjects(SubjectTreeNode node) {
    selectedSubjects.addAll(
      node.subjects.where((subject) => subject.selected == 1),
    );
    for (final child in node.children) {
      collectSubjects(child);
    }
  }

  for (final root in tree) {
    collectSubjects(root);
  }
  return selectedSubjects;
}

Future<void> toggleSubjectSelected(Subject subject) async {
  final udbh = UserDBHelper();
  final prefs = await SharedPreferences.getInstance();
  final identityId = subject.identityId ?? prefs.getString('identityId');
  final bankId = prefs.getString('activeBankId');
  if (identityId == null ||
      identityId.isEmpty ||
      bankId == null ||
      bankId.isEmpty) {
    throw StateError('题库身份尚未初始化');
  }
  await udbh.update(
    'IdentitySubject',
    {'selected': subject.selected},
    'bank_id = ? AND identity_id = ? AND subject_id = ?',
    [bankId, identityId, subject.id.toString()],
  );
}
