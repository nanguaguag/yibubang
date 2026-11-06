import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import 'question_bank_file_service.dart';
import 'ykb_bank_sync_service.dart';

class BankExportService {
  static Future<File> prepare(QuestionBank bank, Directory directory, {String? rootId}) async {
    final legacy = bank.bankId == 'legacy_combined';
    final id = legacy ? 'legacy_$rootId' : bank.bankId;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || (legacy && rootId == null)) {
      throw const FormatException('导出题库标识无效');
    }
    final output = File(p.join(directory.path, '$id.sqlite'));
    if (!legacy) await File(bank.localPath).copy(output.path);
    final db = await openDatabase(output.path, singleInstance: false);
    try {
      if (legacy) {
        await YkbBankSyncService.createSchema(db);
        await db.execute('ATTACH DATABASE ? AS original', [bank.localPath]);
        await db.transaction((txn) async {
          await txn.execute('''
            WITH RECURSIVE subtree(id) AS (
              SELECT id FROM original.Identity WHERE id = ?
              UNION SELECT i.id FROM original.Identity i JOIN subtree s ON i.parent_id = s.id
            ) INSERT INTO Identity SELECT id, parent_id, name FROM original.Identity
              WHERE id IN (SELECT id FROM subtree)
          ''', [rootId]);
          await txn.update('Identity', {'parent_id': '-1'}, where: 'id = ?', whereArgs: [rootId]);
          await txn.execute('''
            INSERT OR IGNORE INTO IdentityQuestion
            SELECT identity_id, subject_id, chapter_id, question_id FROM original.IdentityQuestion
            WHERE identity_id IN (SELECT id FROM Identity)
          ''');
          for (final table in ['Subject', 'Chapter', 'Question']) {
            final column = table == 'Subject' ? 'subject_id' : table == 'Chapter' ? 'chapter_id' : 'question_id';
            final columns = (await txn.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).join(',');
            await txn.execute('INSERT INTO $table ($columns) SELECT $columns FROM original.$table WHERE id IN (SELECT $column FROM IdentityQuestion)');
          }
          await txn.execute('INSERT INTO IdentitySubject SELECT DISTINCT identity_id, subject_id, 0 FROM IdentityQuestion');
          await txn.execute('INSERT INTO IdentityChapter SELECT DISTINCT identity_id, subject_id, chapter_id, 0 FROM IdentityQuestion');
          await txn.insert('BankMeta', {'bank_id': id, 'name': bank.name, 'version': '1.0.0', 'schema_version': 1,
            'generated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'source': 'legacy-export'});
        });
        await db.execute('DETACH DATABASE original');
      }
      final columns = (await db.rawQuery('PRAGMA table_info(Question)')).map((r) => r['name']).toSet();
      await db.update('Question', {
        if (columns.contains('user_answer')) 'user_answer': '',
        if (columns.contains('cut_question')) 'cut_question': '0',
        if (columns.contains('is_collection_question')) 'is_collection_question': '0',
      });
      // Only content tables belong in a portable bank, never device/user data.
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      const content = {'BankMeta', 'Identity', 'Subject', 'Chapter', 'Question', 'IdentitySubject', 'IdentityChapter', 'IdentityQuestion'};
      for (final row in tables) {
        final table = row['name'] as String;
        if (!content.contains(table) && !table.startsWith('sqlite_')) {
          await db.execute('DROP TABLE "${table.replaceAll('"', '""')}"');
        }
      }
      await QuestionBankFileService.recount(db, version: legacy ? '1.0.0' : bank.version);
      // Rebuild pages so deleted account values cannot remain in free pages.
      await db.execute('VACUUM');
    } finally {
      await db.close();
    }
    final validation = await QuestionBankDatabaseManager().validateFile(output.path, expectedBankId: id);
    if (!validation.isValid) throw FormatException(validation.message);
    return output;
  }

  static Future<File> zip(File sqlite, Directory directory) async {
    final bytes = await sqlite.readAsBytes();
    final db = await openDatabase(sqlite.path, readOnly: true, singleInstance: false);
    late Map<String, dynamic> meta;
    late String root;
    try {
      meta = (await db.query('BankMeta')).single;
      root = (await db.query('Identity', where: 'parent_id = ?', whereArgs: ['-1'])).single['id'] as String;
    } finally {
      await db.close();
    }
    final manifest = utf8.encode(jsonEncode({'manifest_version': 1, 'schema_version': 1, 'banks': [{
      ...meta, 'identity_id': root, 'file': p.basename(sqlite.path), 'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(), 'sqlite_sha256': sha256.convert(bytes).toString(),
    }]}));
    final archive = Archive()
      ..addFile(ArchiveFile(p.basename(sqlite.path), bytes.length, bytes))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('ZIP 打包失败');
    return File(p.join(directory.path, '${p.basename(sqlite.path)}.zip'))..writeAsBytesSync(encoded, flush: true);
  }

  static Future<String?> save(QuestionBank bank, {required bool asZip, String? rootId}) async {
    final directory = await Directory.systemTemp.createTemp('bank-export-');
    try {
      final sqlite = await prepare(bank, directory, rootId: rootId);
      final file = asZip ? await zip(sqlite, directory) : sqlite;
      String? destination;
      if (Platform.isAndroid || Platform.isIOS) {
        final target = Platform.isAndroid ? await getExternalStorageDirectory() : null;
        final documents = target ?? await getApplicationDocumentsDirectory();
        destination = p.join(documents.path, p.basename(file.path));
      } else {
        destination = await FilePicker.platform.saveFile(dialogTitle: '导出题库',
          fileName: p.basename(file.path), type: FileType.custom,
          allowedExtensions: [asZip ? 'zip' : 'sqlite']);
      }
      if (destination == null || destination.isEmpty) return null;
      if (p.equals(p.normalize(destination), p.normalize(bank.localPath))) {
        throw StateError('不能覆盖正在使用的题库文件');
      }
      await file.copy(destination);
      return destination;
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
