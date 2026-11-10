import 'package:sqflite/sqflite.dart';

class NoteSyncStore {
  static Future<void> install(DatabaseExecutor db) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(Notes)',
    )).map((r) => r['name']).toSet();
    if (!columns.contains('revision')) {
      await db.execute(
        'ALTER TABLE Notes ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS note_revision AFTER UPDATE ON Notes
      WHEN (NEW.content IS NOT OLD.content OR NEW.imgs IS NOT OLD.imgs) AND NEW.revision<=OLD.revision
      BEGIN UPDATE Notes SET revision=OLD.revision+1 WHERE id=NEW.id; END''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS NoteTombstones (
      local_id TEXT NOT NULL, owner_user_id TEXT NOT NULL, remote_id TEXT,
      question_id TEXT NOT NULL, content TEXT NOT NULL, imgs TEXT NOT NULL,
      PRIMARY KEY(local_id,owner_user_id)
    )''');
  }
}
