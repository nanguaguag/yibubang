import '../db/database_helper.dart';

class Identity {
  String id;
  String parentId;
  String name;

  Identity({
    required this.id,
    required this.parentId,
    required this.name,
  });

  // Convert a Identity to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'parent_id': parentId,
      'name': name,
    };
  }

  // Convert a map to a Identity
  factory Identity.fromMap(Map<String, dynamic> map) {
    return Identity(
      id: map['id'],
      parentId: map['parent_id'],
      name: map['name'],
    );
  }
}

void sortIdentitiesById(List<Identity> identities) {
  // 将一个 List<Chapter> 按照 id 转成数字后的大小排序
  identities.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
}

Future<List<Identity>> getChildrenIdentities(String parentId) async {
  DatabaseHelper dbh = DatabaseHelper();
  final result = await dbh.getByRawQuery('''
    SELECT id, parent_id, name
    FROM Identity
    WHERE parent_id = ?
    ORDER BY name
  ''', [parentId]);
  List<Identity> identities = result.map((e) => Identity.fromMap(e)).toList();
  sortIdentitiesById(identities);
  return identities;
}
