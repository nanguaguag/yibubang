import 'package:sqflite/sqflite.dart';

/// 只读题库权威关系的用户库投影。Question.id 保持全局单列主键。
/// OLD/NEW 状态差值由 SQLite 触发器在写入事务内应用，覆盖云同步、复习及跨库重做。
class QuestionProjection {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS QuestionRelations(
      bank_id TEXT NOT NULL, question_id TEXT NOT NULL, identity_id TEXT NOT NULL,
      subject_id TEXT NOT NULL, chapter_id TEXT NOT NULL,
      PRIMARY KEY(bank_id,question_id,identity_id,subject_id,chapter_id))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_question_relations_id ON QuestionRelations(question_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS QuestionProjectionState(bank_id TEXT PRIMARY KEY, source_stamp TEXT NOT NULL)',
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      final ref = event == 'DELETE' ? 'OLD' : 'NEW';
      final dc = event == 'INSERT'
          ? '(CASE WHEN NEW.status=1 THEN 1 ELSE 0 END)'
          : event == 'DELETE'
          ? '-(CASE WHEN OLD.status=1 THEN 1 ELSE 0 END)'
          : '(CASE WHEN NEW.status=1 THEN 1 ELSE 0 END)-(CASE WHEN OLD.status=1 THEN 1 ELSE 0 END)';
      final di = event == 'INSERT'
          ? '(CASE WHEN NEW.status=2 THEN 1 ELSE 0 END)'
          : event == 'DELETE'
          ? '-(CASE WHEN OLD.status=2 THEN 1 ELSE 0 END)'
          : '(CASE WHEN NEW.status=2 THEN 1 ELSE 0 END)-(CASE WHEN OLD.status=2 THEN 1 ELSE 0 END)';
      final condition = event == 'UPDATE'
          ? 'WHEN OLD.status IS NOT NEW.status'
          : '';
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS question_projection_${event.toLowerCase()}
        AFTER $event ON Question $condition BEGIN
        INSERT OR IGNORE INTO IdentitySubject(bank_id,identity_id,subject_id,correct,incorrect,selected)
          SELECT DISTINCT bank_id,identity_id,subject_id,0,0,0 FROM QuestionRelations WHERE question_id=$ref.id;
        INSERT OR IGNORE INTO IdentityChapter(bank_id,identity_id,subject_id,chapter_id,correct,incorrect)
          SELECT DISTINCT bank_id,identity_id,subject_id,chapter_id,0,0 FROM QuestionRelations WHERE question_id=$ref.id;
        UPDATE IdentitySubject SET correct=MAX(0,correct+($dc)),incorrect=MAX(0,incorrect+($di))
          WHERE rowid IN (SELECT c.rowid FROM QuestionRelations r JOIN IdentitySubject c
            ON c.bank_id=r.bank_id AND c.identity_id=r.identity_id AND c.subject_id=r.subject_id WHERE r.question_id=$ref.id);
        UPDATE IdentityChapter SET correct=MAX(0,correct+($dc)),incorrect=MAX(0,incorrect+($di))
          WHERE rowid IN (SELECT c.rowid FROM QuestionRelations r JOIN IdentityChapter c
            ON c.bank_id=r.bank_id AND c.identity_id=r.identity_id AND c.subject_id=r.subject_id AND c.chapter_id=r.chapter_id WHERE r.question_id=$ref.id);
        END''',
      );
    }
  }

  static Future<void> refresh(
    DatabaseExecutor tx,
    String bankId,
    String alias,
    String stamp,
  ) async {
    await tx.delete(
      'QuestionRelations',
      where: 'bank_id=?',
      whereArgs: [bankId],
    );
    await tx.rawInsert(
      '''INSERT OR IGNORE INTO QuestionRelations
      SELECT ?,question_id,identity_id,subject_id,chapter_id FROM $alias.IdentityQuestion''',
      [bankId],
    );
    await tx.insert('QuestionProjectionState', {
      'bank_id': bankId,
      'source_stamp': stamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
