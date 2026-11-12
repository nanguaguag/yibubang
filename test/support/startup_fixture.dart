import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/data_transfer.dart';
import 'package:yibubang/db/question_bank_manager.dart';

/// 真实临时用户库与创建后只读的题库；不接触实机数据。
class StartupFixture {
  final Directory directory;
  final String previousPath;
  final Database userDb;
  StartupFixture._(this.directory, this.previousPath, this.userDb);

  static Future<StartupFixture> create() async {
    SharedPreferences.setMockInitialValues({
      'activeBankId': 'fixture',
      'identityId': 'i',
      'autoResume': false,
      'cloud_sync_enabled': true,
      'cloud_sync_user_id': 'u',
      'cloud_sync_device_token': 't',
      'accept_update': false,
    });
    final previous = await getDatabasesPath();
    final dir = await Directory.systemTemp.createTemp('startup_fixture_');
    await databaseFactory.setDatabasesPath(dir.path);
    final userDb = await UserDBHelper().database;
    final manager = QuestionBankDatabaseManager();
    final path = await manager.pathFor('fixture');
    await Directory(p.dirname(path)).create(recursive: true);
    final writer = await openDatabase(path);
    await writer.transaction((tx) async {
      for (final sql in [
        'CREATE TABLE Identity(id TEXT PRIMARY KEY,parent_id TEXT,name TEXT)',
        'CREATE TABLE Subject(id TEXT PRIMARY KEY,name TEXT)',
        'CREATE TABLE Chapter(id TEXT PRIMARY KEY,name TEXT)',
        'CREATE TABLE Question(id TEXT PRIMARY KEY,title TEXT,chapter_id TEXT,chapter_parent_id TEXT,answer TEXT,type TEXT)',
        'CREATE TABLE IdentitySubject(identity_id TEXT,subject_id TEXT,total INTEGER)',
        'CREATE TABLE IdentityChapter(identity_id TEXT,subject_id TEXT,chapter_id TEXT,total INTEGER)',
        'CREATE TABLE IdentityQuestion(question_id TEXT,identity_id TEXT,subject_id TEXT,chapter_id TEXT)',
        'CREATE TABLE BankMeta(bank_id TEXT,schema_version INTEGER,question_count INTEGER,relation_count INTEGER,subject_count INTEGER,chapter_count INTEGER)',
        "INSERT INTO Identity VALUES ('i','-1','专业')",
        "INSERT INTO Subject VALUES ('s','启动课程')",
        "INSERT INTO Chapter VALUES ('c','启动章节')",
        "INSERT INTO Question VALUES ('q','测试题','c','s','A','1')",
        "INSERT INTO IdentitySubject VALUES ('i','s',1)",
        "INSERT INTO IdentityChapter VALUES ('i','s','c',1)",
        "INSERT INTO IdentityQuestion VALUES ('q','i','s','c')",
        "INSERT INTO BankMeta VALUES ('fixture',1,1,1,1,1)",
      ]) {
        await tx.execute(sql);
      }
    });
    await writer.close();
    final bank = await manager.openBank('fixture', validate: false);
    DatabaseHelper.setDatabaseForTesting(bank);
    await userDb.insert('Question', {
      'id': 'q',
      'status': 1,
      'user_answer': 'A',
    });
    await ensureQuestionCountProjection('fixture', bankPath: path);
    await userDb.update('IdentitySubject', {'selected': 1});
    await userDb.insert('QuestionBank', {
      'bank_id': 'fixture',
      'name': '测试题库',
      'version': '1.0.0',
      'schema_version': 1,
      'local_path': path,
      'enabled': 1,
      'install_state': 'installed',
      'identity_id': 'i',
    });
    return StartupFixture._(dir, previous, userDb);
  }

  Future<void> close() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  }
}

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), true);
}

Future<void> pumpReady(WidgetTester tester, Finder ready) =>
    pumpUntil(tester, () => ready.evaluate().isNotEmpty);
