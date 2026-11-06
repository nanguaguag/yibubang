import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/services/question_bank_file_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String localPath;
  late String incomingPath;

  Future<void> fixture(String path, List<String> ids, String title) async {
    final db = await openDatabase(path);
    await db.execute(
      'CREATE TABLE Identity (id TEXT PRIMARY KEY, parent_id TEXT, name TEXT)',
    );
    await db.execute('CREATE TABLE Subject (id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE Chapter (id TEXT PRIMARY KEY, name TEXT)');
    await db.execute(
      'CREATE TABLE Question (id TEXT PRIMARY KEY, title TEXT, user_answer TEXT, cut_question TEXT)',
    );
    await db.execute(
      'CREATE TABLE IdentitySubject (identity_id TEXT, subject_id TEXT, total INTEGER, PRIMARY KEY(identity_id,subject_id))',
    );
    await db.execute(
      'CREATE TABLE IdentityChapter (identity_id TEXT, subject_id TEXT, chapter_id TEXT, total INTEGER, PRIMARY KEY(identity_id,subject_id,chapter_id))',
    );
    await db.execute(
      'CREATE TABLE IdentityQuestion (identity_id TEXT, subject_id TEXT, chapter_id TEXT, question_id TEXT, PRIMARY KEY(identity_id,subject_id,chapter_id,question_id))',
    );
    await db.execute(
      'CREATE TABLE BankMeta (bank_id TEXT PRIMARY KEY, version TEXT, generated_at INTEGER, question_count INTEGER, subject_count INTEGER, chapter_count INTEGER, relation_count INTEGER)',
    );
    await db.insert('BankMeta', {'bank_id': 'bank', 'version': '1.0.0'});
    await db.insert('Identity', {'id': '38', 'parent_id': '-1', 'name': '专业'});
    await db.insert('Subject', {'id': '1', 'name': '科目'});
    await db.insert('Chapter', {'id': '10', 'name': '章节'});
    await db.insert('IdentitySubject', {
      'identity_id': '38',
      'subject_id': '1',
      'total': 0,
    });
    await db.insert('IdentityChapter', {
      'identity_id': '38',
      'subject_id': '1',
      'chapter_id': '10',
      'total': 0,
    });
    for (final id in ids) {
      await db.insert('Question', {
        'id': id,
        'title': title,
        'user_answer': 'A',
        'cut_question': '1',
      });
      await db.insert('IdentityQuestion', {
        'identity_id': '38',
        'subject_id': '1',
        'chapter_id': '10',
        'question_id': id,
      });
    }
    await db.close();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bank-file-test-');
    localPath = p.join(directory.path, 'local.sqlite');
    incomingPath = p.join(directory.path, 'incoming.sqlite');
    await fixture(localPath, ['1', '2'], '本地');
    await fixture(incomingPath, ['2', '3'], '新内容');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'merge preserves extra questions, updates shared content and keeps inputs intact',
    () async {
      final original = await File(localPath).readAsBytes();
      final imported = await File(incomingPath).readAsBytes();
    expect(await QuestionBankFileService.countNewQuestions(localPath, incomingPath), 1);
      final output = await QuestionBankFileService.merge(
        localPath: localPath,
        incomingPath: incomingPath,
        temporaryDirectory: await Directory(
          p.join(directory.path, 'output'),
        ).create(),
        version: '1.0.1',
      );
      final db = await openDatabase(output.path, readOnly: true);
      final rows = await db.query('Question', orderBy: 'id');
      expect(rows.map((r) => r['id']), ['1', '2', '3']);
      expect(rows[1]['title'], '新内容');
      expect(rows[1]['user_answer'], '');
      expect(rows[1]['cut_question'], '0');
      expect((await db.query('BankMeta')).single['question_count'], 3);
      expect((await db.query('BankMeta')).single['relation_count'], 3);
      expect((await db.query('BankMeta')).single['version'], '1.0.1');
      expect((await db.query('IdentitySubject')).single['total'], 3);
      await db.close();
      expect(await File(localPath).readAsBytes(), original);
      expect(await File(incomingPath).readAsBytes(), imported);
    },
  );

  test(
    'identity parent conflict fails without changing original bank',
    () async {
      final original = await File(localPath).readAsBytes();
      final incoming = await openDatabase(incomingPath);
      await incoming.update('Identity', {'parent_id': '99'});
      await incoming.close();
      await expectLater(
        QuestionBankFileService.merge(
          localPath: localPath,
          incomingPath: incomingPath,
          temporaryDirectory: await Directory(
            p.join(directory.path, 'output'),
          ).create(),
          version: '1.0.1',
        ),
        throwsFormatException,
      );
      expect(await File(localPath).readAsBytes(), original);
    },
  );

  test('version increments patch independently of old delta metadata', () {
    expect(QuestionBankFileService.nextVersion('3.0.4+delta.123'), '3.0.5');
    expect(QuestionBankFileService.nextVersion('sync-123'), '1.0.0');
  });

  test('no-op detection ignores account state and retains local extra questions', () async {
    expect(await QuestionBankFileService.hasChanges(localPath, incomingPath), isTrue);
    final incoming = await openDatabase(incomingPath);
    await incoming.delete('IdentityQuestion', where: 'question_id = ?', whereArgs: ['3']);
    await incoming.delete('Question', where: 'id = ?', whereArgs: ['3']);
    await incoming.update('Question', {'title': '本地', 'user_answer': '', 'cut_question': '0'});
    await incoming.close();
    expect(await QuestionBankFileService.hasChanges(localPath, incomingPath), isFalse);
  });
}
