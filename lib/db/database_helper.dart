import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'question_bank_manager.dart';

String generateSimpleId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = (100000 + (DateTime.now().microsecond % 900000));
  return '$timestamp$random';
}

Future<void> dropAllTriggers(Database db) async {
  final triggers = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'trigger';
    ''');

  for (final row in triggers) {
    final triggerName = row['name'] as String;
    await db.execute('DROP TRIGGER IF EXISTS $triggerName');
    debugPrint(triggerName);
  }
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  // Open the database
  Future<Database> get database async {
    if (_database != null) return _database!;

    // Initialize database if it's not already done
    _database = await _initDB();
    // 由于数据完整性检查会严重影响性能，暂时禁用
    // dropAllTriggers(_database!); // 删除所有触发器
    // await checkDatabaseIntegrity(); // 添加完整性检查
    return _database!;
  }

  // Initialize the database
  Future<Database> _initDB() async {
    final prefs = await SharedPreferences.getInstance();
    final bankId = prefs.getString('activeBankId') ?? 'dental_final';
    final bankManager = QuestionBankDatabaseManager();
    final bankPath = await bankManager.pathFor(bankId);
    if (await File(bankPath).exists()) {
      try {
        return await bankManager.openBank(bankId);
      } catch (error) {
        debugPrint('当前题库校验失败，将尝试旧题库回退：$error');
      }
    }

    // 老版本题库保留为只读回退库，但必须尊重题库管理中的启用状态。
    // 用户明确禁用后不再静默回退，避免页面显示的新题库与实际连接不一致。
    final legacyPath = join(await getDatabasesPath(), 'question_data.sqlite');
    if (await File(legacyPath).exists() && await _legacyFallbackEnabled()) {
      await prefs.setString('activeBankId', 'legacy_combined');
      return openDatabase(legacyPath, readOnly: true, singleInstance: false);
    }
    throw Exception("题库文件不存在或已禁用。请在题库管理中启用、导入或下载题库！");
  }

  Future<bool> _legacyFallbackEnabled() async {
    try {
      final rows = await (await UserDBHelper().database).query(
        'QuestionBank',
        columns: ['enabled'],
        where: 'bank_id = ?',
        whereArgs: ['legacy_combined'],
        limit: 1,
      );
      // 目录初始化失败时没有记录，仍允许老用户安全回退；一旦用户在
      // 管理页面明确关闭，记录值为 0，必须禁止回退。
      return rows.isEmpty || (rows.first['enabled'] as num?) == 1;
    } catch (error) {
      debugPrint('读取旧版题库启用状态失败，保留兼容回退：$error');
      return true;
    }
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) await database.close();
  }

  Future<void> switchBank(String bankId) async {
    final oldDatabase = _database;
    _database = null;
    if (oldDatabase != null && oldDatabase.isOpen) {
      await oldDatabase.close();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeBankId', bankId);
  }

  /// 检查数据库完整性
  Future<void> checkDatabaseIntegrity([Database? db]) async {
    final database = db ?? _database;
    if (database == null) {
      debugPrint('Question data 数据库尚未初始化，跳过完整性检查');
      return;
    }

    try {
      final result = await database.rawQuery('PRAGMA integrity_check;');
      final checkResult = result.first.values.first;
      if (checkResult != 'ok') {
        debugPrint('❌ Question data 数据库完整性检查失败: $checkResult');
        // 你可以选择在这里抛出异常或自动备份、恢复等
      } else {
        debugPrint('✅ Question data 数据库完整性良好');
      }
    } catch (e) {
      debugPrint('⚠️ Question data 执行完整性检查出错: $e');
    }
  }

  // Insert data into table
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  // Get all records from a table
  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final db = await database;
    return await db.query(table);
  }

  // Get records by condition
  Future<List<Map<String, dynamic>>> getByCondition(
      String table, String condition, List<dynamic> args) async {
    final db = await database;
    return await db.query(table, where: condition, whereArgs: args);
  }

  Future<List<Map<String, dynamic>>> getByRawQuery(
    String sql,
    List<dynamic> arguments,
  ) async {
    final db = await database; // 你已经初始化好的数据库
    return await db.rawQuery(sql, arguments);
  }

  Future<int> getCountByCondition(
      String table, String condition, List<dynamic> args) async {
    final db = await database;
    // 使用rawQuery来查询符合条件的记录数
    final count = await db.rawQuery(
      'SELECT COUNT(*) FROM $table WHERE $condition',
      args,
    );
    // 返回查询结果中的第一个值
    return Sqflite.firstIntValue(count) ?? 0;
  }

  // Update a record
  Future<int> update(String table, Map<String, dynamic> data, String condition,
      List<dynamic> args) async {
    final db = await database;
    return await db.update(table, data, where: condition, whereArgs: args);
  }

  // Delete a record
  Future<int> delete(String table, String condition, List<dynamic> args) async {
    final db = await database;
    return await db.delete(table, where: condition, whereArgs: args);
  }

  Future<String> getDatabasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final bankId = prefs.getString('activeBankId') ?? 'dental_final';
    final bankPath = await QuestionBankDatabaseManager().pathFor(bankId);
    if (await File(bankPath).exists()) {
      final validation = await QuestionBankDatabaseManager().validateFile(
        bankPath,
        expectedBankId: bankId,
      );
      if (validation.isValid) return bankPath;
    }
    final legacyPath = join(await getDatabasesPath(), 'question_data.sqlite');
    if (await File(legacyPath).exists() && await _legacyFallbackEnabled()) {
      return legacyPath;
    }
    return bankPath;
  }
}

class UserDBHelper {
  static final UserDBHelper _instance = UserDBHelper._internal();
  factory UserDBHelper() => _instance;
  UserDBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    await checkDatabaseIntegrity(); // 添加完整性检查
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'user_data.sqlite');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.transaction((txn) async {
      if (oldVersion < 2) {
        await _migrateStatisticsTables(txn);
        await _createQuestionBankTable(txn);
        await _createMigrationStateTable(txn);
      }
      if (oldVersion < 3) {
        final columns = await _columns(txn, 'Activities');
        for (final column in const [
          'bank_id',
          'question_id',
          'identity_id',
          'subject_id',
          'chapter_id',
          'is_right',
        ]) {
          if (!columns.contains(column)) {
            await txn.execute('ALTER TABLE Activities ADD COLUMN $column TEXT');
          }
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_activity_bank ON Activities(bank_id)',
        );
      }
      if (oldVersion < 4) {
        final columns = await _columns(txn, 'QuestionBank');
        if (!columns.contains('update_enabled')) {
          await txn.execute(
            'ALTER TABLE QuestionBank ADD COLUMN update_enabled INTEGER NOT NULL DEFAULT 1',
          );
        }
      }
      await _createMigrationStateTable(txn);
    });
  }

  Future<List<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<void> _createQuestionBankTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS QuestionBank (
        bank_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        version TEXT NOT NULL DEFAULT '0.0.0',
        schema_version INTEGER NOT NULL DEFAULT 0,
        local_path TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        size INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        built_in INTEGER NOT NULL DEFAULT 0,
        update_enabled INTEGER NOT NULL DEFAULT 1,
        install_state TEXT NOT NULL DEFAULT 'available',
        remote_url TEXT,
        identity_id TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createMigrationStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MigrationState (
        migration_id TEXT PRIMARY KEY,
        from_version INTEGER NOT NULL,
        to_version INTEGER NOT NULL,
        state TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        finished_at INTEGER NOT NULL DEFAULT 0,
        error TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _migrateStatisticsTables(DatabaseExecutor db) async {
    final subjectColumns = await _columns(db, 'IdentitySubject');
    if (!subjectColumns.contains('bank_id')) {
      await db.execute(
          'ALTER TABLE IdentitySubject RENAME TO IdentitySubject_legacy');
      await db.execute('''
        CREATE TABLE IdentitySubject (
          bank_id TEXT NOT NULL,
          identity_id TEXT NOT NULL,
          subject_id TEXT NOT NULL,
          correct INTEGER DEFAULT 0 NOT NULL,
          incorrect INTEGER DEFAULT 0 NOT NULL,
          selected INTEGER DEFAULT 0 NOT NULL,
          PRIMARY KEY (bank_id, identity_id, subject_id)
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO IdentitySubject
          (bank_id, identity_id, subject_id, correct, incorrect, selected)
        SELECT CASE identity_id
          WHEN '30401' THEN 'dental_final'
          WHEN '20101' THEN 'clinical_final'
          WHEN '11070' THEN 'nursing_final'
          ELSE 'legacy_combined' END,
          identity_id, subject_id, correct, incorrect, selected
        FROM IdentitySubject_legacy
      ''');
      await db.execute('DROP TABLE IdentitySubject_legacy');
    }

    final chapterColumns = await _columns(db, 'IdentityChapter');
    if (!chapterColumns.contains('bank_id')) {
      await db.execute(
          'ALTER TABLE IdentityChapter RENAME TO IdentityChapter_legacy');
      await db.execute('''
        CREATE TABLE IdentityChapter (
          bank_id TEXT NOT NULL,
          identity_id TEXT NOT NULL,
          subject_id TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          correct INTEGER DEFAULT 0 NOT NULL,
          incorrect INTEGER DEFAULT 0 NOT NULL,
          PRIMARY KEY (bank_id, identity_id, subject_id, chapter_id)
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO IdentityChapter
          (bank_id, identity_id, subject_id, chapter_id, correct, incorrect)
        SELECT CASE identity_id
          WHEN '30401' THEN 'dental_final'
          WHEN '20101' THEN 'clinical_final'
          WHEN '11070' THEN 'nursing_final'
          ELSE 'legacy_combined' END,
          identity_id, subject_id, chapter_id, correct, incorrect
        FROM IdentityChapter_legacy
      ''');
      await db.execute('DROP TABLE IdentityChapter_legacy');
    }
  }

  /// 检查数据库完整性
  Future<void> checkDatabaseIntegrity([Database? db]) async {
    final database = db ?? _database;
    if (database == null) {
      debugPrint('User data 数据库尚未初始化，跳过完整性检查');
      return;
    }

    try {
      final result = await database.rawQuery('PRAGMA integrity_check;');
      final checkResult = result.first.values.first;
      if (checkResult != 'ok') {
        debugPrint('❌ User data 数据库完整性检查失败: $checkResult');
        // 你可以选择在这里抛出异常或自动备份、恢复等
      } else {
        debugPrint('✅ User data 数据库完整性良好');
      }
    } catch (e) {
      debugPrint('⚠️ User data 执行完整性检查出错: $e');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint("初始化用户数据库...");
    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentitySubject (
        bank_id TEXT NOT NULL,
        identity_id TEXT,
        subject_id TEXT,
        correct INTEGER DEFAULT 0 NOT NULL,
        incorrect INTEGER DEFAULT 0 NOT NULL,
        selected INTEGER DEFAULT 0 NOT NULL,
        PRIMARY KEY (bank_id, identity_id, subject_id)
    )
    ''');

    // IdentityChapter 的主键不完整
    // 如果同一个 chapter_id 能出现在不同 subject 下 → 数据一定错
    // 正确设计应是：PRIMARY KEY (identity_id, subject_id, chapter_id)
    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentityChapter (
        bank_id TEXT NOT NULL,
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        correct INTEGER DEFAULT 0 NOT NULL,
        incorrect INTEGER DEFAULT 0 NOT NULL,
        PRIMARY KEY (bank_id, identity_id, subject_id, chapter_id)
    )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Question (
        id TEXT PRIMARY KEY,
        chapter_id TEXT,
        chapter_parent_id TEXT,
        cut_question TEXT DEFAULT 0 NOT NULL,
        user_answer TEXT DEFAULT "" NOT NULL,
        status INTEGER DEFAULT 0 NOT NULL,
        collection INTEGER DEFAULT 0 NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Notes (
        id TEXT PRIMARY KEY,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (question_id) REFERENCES questions(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Cards (
        id TEXT PRIMARY KEY,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Activities (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        bank_id TEXT,
        question_id TEXT,
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        is_right TEXT
      )
    ''');

    await _createQuestionBankTable(db);
    await _createMigrationStateTable(db);

    // 给 Question 表按 chapter_id 建表
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_question_chapter
        ON Question(chapter_id);
    ''');

    // 给 Question 表按 chapter_parent_id（subject）建表
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_question_subject
        ON Question(chapter_parent_id);
    ''');

    // （可选）给 Question.status 建表，视你的查询频率决定
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_question_status
        ON Question(status);
    ''');

    debugPrint("用户数据库初始化完成～");
  }

  // Insert data into table
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  // Get all records from a table
  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final db = await database;
    return await db.query(table);
  }

  // Get records by condition
  Future<List<Map<String, dynamic>>> getByCondition(
      String table, String condition, List<dynamic> args) async {
    final db = await database;
    return await db.query(table, where: condition, whereArgs: args);
  }

  Future<List<Map<String, dynamic>>> getByRawQuery(
    String sql,
    List<dynamic> arguments,
  ) async {
    final db = await database; // 你已经初始化好的数据库
    return await db.rawQuery(sql, arguments);
  }

  Future<int> getCountByCondition(
      String table, String condition, List<dynamic> args) async {
    final db = await database;
    // 使用rawQuery来查询符合条件的记录数
    final count = await db.rawQuery(
      'SELECT COUNT(*) FROM $table WHERE $condition',
      args,
    );
    // 返回查询结果中的第一个值
    return Sqflite.firstIntValue(count) ?? 0;
  }

  // Update a record
  Future<int> update(String table, Map<String, dynamic> data, String condition,
      List<dynamic> args) async {
    final db = await database;
    return await db.update(table, data, where: condition, whereArgs: args);
  }

  // Delete a record
  Future<int> delete(String table, String condition, List<dynamic> args) async {
    final db = await database;
    return await db.delete(table, where: condition, whereArgs: args);
  }

  Future<bool> isTableEmpty(String table) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(table, limit: 1);
    return result.isEmpty;
  }
}
