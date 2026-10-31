import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'question_bank_manager.dart';

final Random _secureRandom = Random.secure();
int _simpleIdSequence = 0;

/// 生成高并发防碰撞唯一主键 ID。
///
/// 结合微秒级时间戳、进程内自增序数与安全随机数：
/// 1. `DateTime.now().microsecondsSinceEpoch`: 微秒级时间基准；
/// 2. `_simpleIdSequence`: 循环递增计数器 (0~999)，彻底解决单 CPU 紧密循环 (如批量修复或导入) 同微秒内碰撞；
/// 3. `_secureRandom`: 6 位安全随机数 (100000~999999)，防止多实例或跨设备同时间戳碰撞。
String generateSimpleId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  _simpleIdSequence = (_simpleIdSequence + 1) % 1000;
  final seq = _simpleIdSequence.toString().padLeft(3, '0');
  final random = _secureRandom.nextInt(900000) + 100000;
  return '$timestamp$seq$random';
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
    String table,
    String condition,
    List<dynamic> args,
  ) async {
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
    String table,
    String condition,
    List<dynamic> args,
  ) async {
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
  Future<int> update(
    String table,
    Map<String, dynamic> data,
    String condition,
    List<dynamic> args,
  ) async {
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
    // 完整性检查是全库扫描，不能放在每次启动首次打开数据库的关键路径。
    // 需要诊断时仍可显式调用 checkDatabaseIntegrity()。
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'user_data.sqlite');
    return await openDatabase(
      path,
      version: 11,
      onConfigure: (db) async {
        // 用户库为高频写库：WAL 提升并发写性能，同时保证导出前关闭连接即可完整落盘。
        await db.execute('PRAGMA journal_mode = WAL');
        // 显式开启外键约束（Android 上 SQLite 默认关闭）：
        // 否则 Notes.question_id -> Question.id 的 FOREIGN KEY 形同虚设。
        // 写入侧已配合在 saveNote 中先补 Question 兜底行。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 关闭并释放当前用户库连接（置空缓存）。
  ///
  /// 用于「做题记录导入（替换）」：替换 `user_data.sqlite` 文件前必须关闭
  /// 连接，让 WAL/journal 落盘，避免覆盖时文件被占用或数据不完整。
  /// 关闭后下次访问 `database` 会自动重新打开。
  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  @visibleForTesting
  Future<void> upgradeForTesting(Database db, int oldVersion) =>
      _onUpgrade(db, oldVersion, 11);

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.transaction((txn) async {
      if (oldVersion < 2) {
        await _migrateStatisticsTables(txn);
        await _createQuestionBankTable(txn);
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
      if (oldVersion < 5) {
        final activityColumns = await _columns(txn, 'Activities');
        if (!activityColumns.contains('duration')) {
          await txn.execute(
            'ALTER TABLE Activities ADD COLUMN duration INTEGER NOT NULL DEFAULT 0',
          );
        }
        // 为刷题统计提供快速按时间+题库聚合的索引。
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_activity_time_bank '
          'ON Activities(bank_id, timestamp)',
        );
      }
      if (oldVersion < 6) {
        // 清洗历史 cut_question 状态，统一为 '1' (已斩) 和 '0' (未斩)
        await txn.execute(
          "UPDATE Question SET cut_question = '1' WHERE cut_question = 'cutted'",
        );
        await txn.execute(
          "UPDATE Question SET cut_question = '0' WHERE cut_question = '' OR cut_question IS NULL",
        );
      }
      if (oldVersion < 7) {
        final questionColumns = await _columns(txn, 'Question');
        if (!questionColumns.contains('updated_at')) {
          await txn.execute(
            'ALTER TABLE Question ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
          );
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_question_updated ON Question(updated_at)',
        );
      }
      if (oldVersion < 8) {
        final noteColumns = await _columns(txn, 'Notes');
        if (!noteColumns.contains('remote_id')) {
          await txn.execute('ALTER TABLE Notes ADD COLUMN remote_id TEXT');
        }
        if (!noteColumns.contains('updated_at')) {
          await txn.execute(
            'ALTER TABLE Notes ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!noteColumns.contains('sync_status')) {
          await txn.execute(
            'ALTER TABLE Notes ADD COLUMN sync_status INTEGER NOT NULL DEFAULT 0',
          );
        }
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_question ON Notes(question_id)',
        );
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS NoteSyncQueue (
            id TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            note_id TEXT,
            question_id TEXT NOT NULL,
            payload TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_error TEXT
          )
        ''');
      }
      if (oldVersion < 9) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS YkbSyncQueue (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            item_id TEXT,
            payload TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_error TEXT
          )
        ''');
      }
      if (oldVersion < 10) {
        final noteCols = await _columns(txn, 'NoteSyncQueue');
        if (!noteCols.contains('last_response')) {
          await txn.execute(
            'ALTER TABLE NoteSyncQueue ADD COLUMN last_response TEXT',
          );
        }
        final ykbCols = await _columns(txn, 'YkbSyncQueue');
        if (!ykbCols.contains('last_response')) {
          await txn.execute(
            'ALTER TABLE YkbSyncQueue ADD COLUMN last_response TEXT',
          );
        }
      }
      if (oldVersion < 11) {
        await _createBankSmartSyncTables(txn);
      }
      await _createMigrationStateTable(txn);
    });
  }

  /// 医考帮题库「智能增量同步」状态表（v11）。
  ///
  /// 只记录同步游标/哈希/远端章节到本地章节的映射，不改变题库内容表。
  Future<void> _createBankSmartSyncTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS YkbBankSyncState (
        bank_id TEXT PRIMARY KEY,
        manifest_hash TEXT NOT NULL DEFAULT '',
        manifest_fetched_at INTEGER NOT NULL DEFAULT 0,
        manifest_json TEXT,
        pending_json TEXT,
        last_sync_at INTEGER NOT NULL DEFAULT 0,
        last_success_at INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        last_bank_hash TEXT NOT NULL DEFAULT '',
        installed_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS YkbBankChapterState (
        bank_id TEXT NOT NULL,
        remote_chapter_id TEXT NOT NULL,
        remote_identity_id TEXT NOT NULL DEFAULT '',
        remote_subject_id TEXT NOT NULL DEFAULT '',
        remote_title TEXT NOT NULL DEFAULT '',
        remote_count INTEGER NOT NULL DEFAULT 0,
        remote_updated_at TEXT NOT NULL DEFAULT '',
        remote_hash TEXT NOT NULL DEFAULT '',
        local_chapter_id TEXT NOT NULL DEFAULT '',
        local_subject_id TEXT NOT NULL DEFAULT '',
        local_title TEXT NOT NULL DEFAULT '',
        match_method TEXT NOT NULL DEFAULT '',
        extra_count INTEGER NOT NULL DEFAULT 0,
        last_synced_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (bank_id, remote_chapter_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ykb_bank_chapter_state_local
        ON YkbBankChapterState(bank_id, local_chapter_id)
    ''');
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
        'ALTER TABLE IdentitySubject RENAME TO IdentitySubject_legacy',
      );
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
        'ALTER TABLE IdentityChapter RENAME TO IdentityChapter_legacy',
      );
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
        cut_question TEXT DEFAULT '0' NOT NULL,
        user_answer TEXT DEFAULT "" NOT NULL,
        status INTEGER DEFAULT 0 NOT NULL,
        collection INTEGER DEFAULT 0 NOT NULL,
        updated_at INTEGER DEFAULT 0 NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_question_updated
        ON Question(updated_at);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Notes (
        id TEXT PRIMARY KEY,
        remote_id TEXT,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (question_id) REFERENCES Question(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notes_question
        ON Notes(question_id);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS NoteSyncQueue (
        id TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        note_id TEXT,
        question_id TEXT NOT NULL,
        payload TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_error TEXT,
        last_response TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS YkbSyncQueue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        item_id TEXT,
        payload TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_error TEXT,
        last_response TEXT
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
        is_right TEXT,
        duration INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createQuestionBankTable(db);
    await _createBankSmartSyncTables(db);
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

    // 为刷题统计提供快速按时间+题库聚合的索引。
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_time_bank
        ON Activities(bank_id, timestamp);
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
    String table,
    String condition,
    List<dynamic> args,
  ) async {
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
    String table,
    String condition,
    List<dynamic> args,
  ) async {
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
  Future<int> update(
    String table,
    Map<String, dynamic> data,
    String condition,
    List<dynamic> args,
  ) async {
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
