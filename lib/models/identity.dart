import 'package:sqflite/sqflite.dart';

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

Future<List<Identity>> getIdentities() async {
  Database db = await DatabaseHelper().database;
  List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT DISTINCT i.id, i.name
    FROM IdentitySubject ic
    JOIN Identity i ON ic.identity_id = i.id
  ''');
  return result.map((e) => Identity.fromMap(e)).toList();
}
