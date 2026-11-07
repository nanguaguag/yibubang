import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum BankImportMode { merge, replace }

class BankImportCancelled implements Exception {}

class BankContentDiff {
  const BankContentDiff(
    this.added,
    this.changed,
    this.removed,
    this.localExtras,
  );
  final int added, changed, removed, localExtras;
}

/// Only edits a disposable copy; both input files remain unchanged.
class QuestionBankFileService {
  /// Native ATTACH comparison; no question lists are joined in Dart memory.
  static Future<BankContentDiff> diff(
    String localPath,
    String incomingPath,
  ) async {
    final db = await openDatabase(
      localPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      await db.execute('ATTACH DATABASE ? AS incoming', [incomingPath]);
      final fields = await db.rawQuery('PRAGMA table_info(Question)');
      final other = (await db.rawQuery(
        'PRAGMA incoming.table_info(Question)',
      )).map((r) => r['name']).toSet();
      final comparisons = fields
          .map((r) => r['name'] as String)
          .where(
            (name) =>
                other.contains(name) &&
                ![
                  'id',
                  'cut_question',
                  'user_answer',
                  'is_collection_question',
                ].contains(name),
          )
          .map((name) {
            final q = '"${name.replaceAll('"', '""')}"';
            return 'l.$q IS NOT r.$q';
          })
          .join(' OR ');
      final added =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM incoming.Question r WHERE NOT EXISTS (SELECT 1 FROM Question l WHERE l.id = r.id)',
            ),
          ) ??
          0;
      final extras =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM Question l WHERE NOT EXISTS (SELECT 1 FROM incoming.Question r WHERE r.id = l.id)',
            ),
          ) ??
          0;
      final changed = comparisons.isEmpty
          ? 0
          : Sqflite.firstIntValue(
                  await db.rawQuery(
                    'SELECT COUNT(*) FROM Question l JOIN incoming.Question r ON l.id = r.id WHERE $comparisons',
                  ),
                ) ??
                0;
      return BankContentDiff(added, changed, extras, extras);
    } finally {
      await db.close();
    }
  }

  static Future<int> countNewQuestions(
    String localPath,
    String incomingPath,
  ) async {
    final db = await openDatabase(
      localPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      await db.execute('ATTACH DATABASE ? AS incoming', [incomingPath]);
      return Sqflite.firstIntValue(
            await db.rawQuery('''
        SELECT COUNT(*) FROM incoming.Question r
        WHERE NOT EXISTS (SELECT 1 FROM Question l WHERE l.id = r.id)
      '''),
          ) ??
          0;
    } finally {
      await db.close();
    }
  }

  static Future<bool> hasChanges(String localPath, String incomingPath) async {
    final db = await openDatabase(
      localPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      await db.execute('ATTACH DATABASE ? AS incoming', [incomingPath]);
      for (final table in [
        'Question',
        'Identity',
        'Subject',
        'Chapter',
        'IdentityQuestion',
      ]) {
        final localColumns = await db.rawQuery('PRAGMA table_info($table)');
        final incomingColumns = await db.rawQuery(
          'PRAGMA incoming.table_info($table)',
        );
        final names = incomingColumns.map((r) => r['name']).toSet();
        final columns = localColumns
            .map((r) => r['name'] as String)
            .where(
              (name) =>
                  names.contains(name) &&
                  name != 'cut_question' &&
                  name != 'user_answer' &&
                  name != 'is_collection_question',
            )
            .map((name) => '"${name.replaceAll('"', '""')}"')
            .join(',');
        final changes = await db.rawQuery('''
          SELECT $columns FROM incoming.$table
          EXCEPT SELECT $columns FROM $table LIMIT 1
        ''');
        if (changes.isNotEmpty) return true;
      }
      return false;
    } finally {
      await db.close();
    }
  }

  static String nextVersion(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return '1.0.0';
    return '${match[1]}.${match[2]}.${int.parse(match[3]!) + 1}';
  }

  static Future<File> merge({
    required String localPath,
    required String incomingPath,
    required Directory temporaryDirectory,
    required String version,
  }) async {
    final output = File(p.join(temporaryDirectory.path, 'merged.sqlite'));
    await File(localPath).copy(output.path);
    final db = await openDatabase(output.path, singleInstance: false);
    var attached = false;
    try {
      await db.execute('ATTACH DATABASE ? AS incoming', [incomingPath]);
      attached = true;
      final conflictingParents = await db.rawQuery('''
        SELECT l.id FROM Identity l JOIN incoming.Identity r ON l.id = r.id
        WHERE COALESCE(l.parent_id, '') != COALESCE(r.parent_id, '') LIMIT 1
      ''');
      if (conflictingParents.isNotEmpty) {
        throw const FormatException('相同 identity 的父节点不同，无法安全合并');
      }
      await db.transaction((txn) async {
        for (final table in ['Identity', 'Subject', 'Chapter', 'Question']) {
          final localColumns = await txn.rawQuery('PRAGMA table_info($table)');
          final incomingColumns = await txn.rawQuery(
            'PRAGMA incoming.table_info($table)',
          );
          final names = incomingColumns.map((r) => r['name']).toSet();
          final columns = localColumns
              .map((r) => r['name'] as String)
              .where(names.contains)
              .toList();
          // Names originate from SQLite schema; quote identifiers explicitly.
          String quoted(String name) => '"${name.replaceAll('"', '""')}"';
          final fields = columns.map(quoted).join(',');
          final values = columns
              .map((name) {
                if (table == 'Question' && name == 'cut_question') return "'0'";
                if (table == 'Question' && name == 'user_answer') return "''";
                if (table == 'Question' && name == 'is_collection_question') {
                  return "'0'";
                }
                return quoted(name);
              })
              .join(',');
          final assignments = columns
              .where((name) => name != 'id')
              .map((name) => '${quoted(name)} = excluded.${quoted(name)}')
              .join(',');
          await txn.execute('''
            INSERT INTO $table ($fields)
            SELECT $values FROM incoming.$table WHERE 1
            ON CONFLICT(id) DO ${assignments.isEmpty ? 'NOTHING' : 'UPDATE SET $assignments'}
          ''');
        }
        for (final table in ['IdentitySubject', 'IdentityChapter']) {
          final keys = table == 'IdentitySubject'
              ? 'identity_id, subject_id'
              : 'identity_id, subject_id, chapter_id';
          await txn.execute('''
            INSERT OR IGNORE INTO $table ($keys, total)
            SELECT $keys, 0 FROM incoming.$table
          ''');
        }
        await txn.execute('''
          INSERT OR IGNORE INTO IdentityQuestion
            (identity_id, subject_id, chapter_id, question_id)
          SELECT identity_id, subject_id, chapter_id, question_id
          FROM incoming.IdentityQuestion
        ''');
        await recount(txn, version: version);
      });
      return output;
    } finally {
      if (attached) await db.execute('DETACH DATABASE incoming');
      await db.close();
    }
  }

  /// Counts describe stored entities/relationships, never network totals.
  static Future<void> recount(
    DatabaseExecutor db, {
    required String version,
  }) async {
    await db.execute('''
      UPDATE IdentitySubject SET total = (
        SELECT COUNT(*) FROM IdentityQuestion iq
        WHERE iq.identity_id = IdentitySubject.identity_id
          AND iq.subject_id = IdentitySubject.subject_id)
    ''');
    await db.execute('''
      UPDATE IdentityChapter SET total = (
        SELECT COUNT(*) FROM IdentityQuestion iq
        WHERE iq.identity_id = IdentityChapter.identity_id
          AND iq.subject_id = IdentityChapter.subject_id
          AND iq.chapter_id = IdentityChapter.chapter_id)
    ''');
    await db.rawUpdate(
      '''
      UPDATE BankMeta SET version = ?, generated_at = ?,
        question_count = (SELECT COUNT(*) FROM Question),
        subject_count = (SELECT COUNT(*) FROM Subject),
        chapter_count = (SELECT COUNT(*) FROM Chapter),
        relation_count = (SELECT COUNT(*) FROM IdentityQuestion)
    ''',
      [version, DateTime.now().millisecondsSinceEpoch ~/ 1000],
    );
  }
}
