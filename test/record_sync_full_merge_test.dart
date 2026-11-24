import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/record_sync_service.dart';
import 'package:yibubang/services/app_update_service.dart';

Uint8List zipDatabase(List<int> bytes) => Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('user_data.sqlite', bytes.length, bytes)),
      )!,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String previous;
  const pathsChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathsChannel,
      (_) async => Directory.systemTemp.path,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathsChannel, null);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('record_full_merge_');
    await databaseFactory.setDatabasesPath(dir.path);
    final db = await UserDBHelper().database;
    // 写入本地题目与笔记
    await db.insert('Question', {
      'id': 'q_local',
      'status': 1,
      'user_answer': 'A',
      'collection': 1,
      'cut_question': '0',
    });
    await db.insert('Notes', {
      'id': 'n_local',
      'question_id': 'q_local',
      'content': '本地老笔记',
      'imgs': '[]',
      'timestamp': 100,
      'updated_at': 100,
    });
  });

  tearDown(() async {
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });

  test('importMerge 完整合并 Notes、SavedComments 与 CustomFlashcards，新数据与更新无损落盘', () async {
    // 构造一个要导入的独立 SQLite 数据库
    final importDir = await Directory.systemTemp.createTemp('import_src_');
    final importDbPath = p.join(importDir.path, 'src_user_data.sqlite');
    final srcDb = await openDatabase(
      importDbPath,
      version: 25,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE Question (
            id TEXT PRIMARY KEY,
            status INTEGER,
            collection INTEGER,
            cut_question TEXT,
            user_answer TEXT,
            updated_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE Activities (
            id TEXT PRIMARY KEY,
            title TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE Notes (
            id TEXT PRIMARY KEY,
            remote_id TEXT,
            question_id TEXT,
            content TEXT,
            imgs TEXT,
            timestamp INTEGER,
            updated_at INTEGER,
            sync_status INTEGER,
            revision INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE SavedComments (
            id TEXT PRIMARY KEY,
            comment_id TEXT,
            question_id TEXT,
            category TEXT,
            user_id TEXT,
            user_name TEXT,
            content TEXT,
            timestamp INTEGER,
            updated_at INTEGER,
            praise_count INTEGER,
            reply_count INTEGER,
            extra_json TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE CustomFlashcards (
            id TEXT PRIMARY KEY,
            title TEXT,
            front TEXT,
            back TEXT,
            tags TEXT,
            is_mastered INTEGER,
            review_count INTEGER,
            created_at INTEGER,
            updated_at INTEGER,
            question_id TEXT
          )
        ''');
      },
    );

    // 写入源库数据
    await srcDb.insert('Question', {
      'id': 'q_imported',
      'status': 2,
      'collection': 0,
      'cut_question': '1',
      'user_answer': 'B',
      'updated_at': 200,
    });
    // 本地已有题目的笔记做更新
    await srcDb.insert('Notes', {
      'id': 'n_local',
      'question_id': 'q_local',
      'content': '更新后的笔记内容',
      'imgs': '[]',
      'timestamp': 100,
      'updated_at': 300, // 300 > 100, 应覆盖本地
    });
    // 新题目的笔记
    await srcDb.insert('Notes', {
      'id': 'n_new',
      'question_id': 'q_imported',
      'content': '新题目的笔记',
      'imgs': '[]',
      'timestamp': 200,
      'updated_at': 200,
    });
    // 写入点赞和评论
    await srcDb.insert('SavedComments', {
      'id': 'c_1',
      'comment_id': 'cm_101',
      'question_id': 'q_imported',
      'category': 'praise',
      'content': '这是一条神评点赞',
      'timestamp': 150,
      'updated_at': 150,
    });
    // 写入自制闪卡
    await srcDb.insert('CustomFlashcards', {
      'id': 'f_1',
      'title': '闪卡测试',
      'front': '问题面',
      'back': '答案面',
      'question_id': 'q_imported',
      'created_at': 120,
      'updated_at': 120,
    });

    await srcDb.close();
    final rawSqliteBytes = await File(importDbPath).readAsBytes();

    // 1. 验证直接传入原始 SQLite 字节文件（免 zip）也能被正常读取和合并
    final mergedCount = await RecordSyncService.importMerge(rawSqliteBytes);
    expect(mergedCount, greaterThan(0));

    // 2. 验证本地数据库的合并结果
    final localDb = await UserDBHelper().database;

    // 题目合并验证
    final qImported = await localDb.query('Question', where: 'id = ?', whereArgs: ['q_imported']);
    expect(qImported.length, 1);
    expect(qImported.first['status'], 2);
    expect(qImported.first['cut_question'], '1');

    // 笔记合并验证：老笔记被覆盖更新为较新内容，新笔记被插入
    final nLocal = await localDb.query('Notes', where: 'id = ?', whereArgs: ['n_local']);
    expect(nLocal.first['content'], '更新后的笔记内容');

    final nNew = await localDb.query('Notes', where: 'id = ?', whereArgs: ['n_new']);
    expect(nNew.length, 1);
    expect(nNew.first['content'], '新题目的笔记');

    // 我的点赞合并验证
    final savedComments = await localDb.query('SavedComments', where: 'comment_id = ?', whereArgs: ['cm_101']);
    expect(savedComments.length, 1);
    expect(savedComments.first['content'], '这是一条神评点赞');

    // 自制闪卡合并验证
    final flashcards = await localDb.query('CustomFlashcards', where: 'id = ?', whereArgs: ['f_1']);
    expect(flashcards.length, 1);
    expect(flashcards.first['title'], '闪卡测试');

    await importDir.delete(recursive: true);
  });

  test('macOS 端 findRunningMacOSAppPath 正确提取或回退目标路径', () {
    if (Platform.isMacOS) {
      final appPath = AppUpdateService.findRunningMacOSAppPath();
      // 在命令行或测试环境中运行不是 .app 包，返回 null 以回退 /Applications/yibubang.app
      expect(appPath == null || appPath.endsWith('.app'), isTrue);
    }
  });
}
