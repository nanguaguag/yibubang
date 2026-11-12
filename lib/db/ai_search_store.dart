import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/ai_search.dart';
import 'database_helper.dart';

/// AI conversations are local user data, never written to a question bank.
class AiSearchStore {
  final Future<Database> Function() database;
  AiSearchStore({Future<Database> Function()? database})
    : database = database ?? (() => UserDBHelper().database);
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS AiSearchSessions(
      id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS AiSearchTurns(
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, position INTEGER NOT NULL,
      payload TEXT NOT NULL, FOREIGN KEY(session_id) REFERENCES AiSearchSessions(id) ON DELETE CASCADE,
      UNIQUE(session_id,position))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_sessions_updated ON AiSearchSessions(updated_at)',
    );
  }

  Future<List<AiSession>> sessions() async {
    final db = await database();
    final rows = await db.query('AiSearchSessions', orderBy: 'updated_at DESC');
    return rows
        .map(
          (r) => AiSession(
            id: r['id'] as String,
            title: r['title'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              r['updated_at'] as int,
            ),
          ),
        )
        .toList();
  }

  Future<void> create(AiSession session) async {
    final db = await database();
    await db.insert('AiSearchSessions', {
      'id': session.id,
      'title': session.title,
      'created_at': session.createdAt.millisecondsSinceEpoch,
      'updated_at': session.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<List<AiTurn>> turns(String sessionId) async {
    final db = await database();
    final rows = await db.query(
      'AiSearchTurns',
      where: 'session_id=?',
      whereArgs: [sessionId],
      orderBy: 'position',
    );
    return rows.map((r) {
      final turn = AiTurn.fromJson(jsonDecode(r['payload'] as String));
      if (turn.status == 'pending' || turn.status == 'streaming') {
        turn.status = 'interrupted';
      }
      return turn;
    }).toList();
  }

  Future<void> save(
    String sessionId,
    AiTurn turn,
    int position,
    String title,
  ) async {
    final db = await database();
    await db.transaction((tx) async {
      await tx.insert('AiSearchTurns', {
        'id': turn.id,
        'session_id': sessionId,
        'position': position,
        'payload': jsonEncode(turn.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'AiSearchSessions',
        {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> truncate(String sessionId, int position) async {
    final db = await database();
    await db.delete(
      'AiSearchTurns',
      where: 'session_id=? AND position>=?',
      whereArgs: [sessionId, position],
    );
  }

  Future<void> delete(String id) async {
    final db = await database();
    await db.transaction((tx) async {
      await tx.delete('AiSearchTurns', where: 'session_id=?', whereArgs: [id]);
      await tx.delete('AiSearchSessions', where: 'id=?', whereArgs: [id]);
    });
  }
}
