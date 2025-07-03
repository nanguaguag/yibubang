import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

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
    return _database!;
  }

  // Initialize the database
  _initDB() async {
    String path = join(await getDatabasesPath(), 'question_data.sqlite');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  // Create tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Subject (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Chapter (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Question (
          id TEXT PRIMARY KEY,
          year TEXT,
          unit TEXT,
          title TEXT,
          public_title TEXT,
          title_img TEXT,
          number TEXT,
          public_number TEXT,
          restore TEXT,
          restore_img TEXT,
          explain TEXT,
          explain_img TEXT,
          answer TEXT,
          option TEXT,   -- 存储选项 JSON 数据
          score TEXT,
          score_describe TEXT,
          native_app_id TEXT,
          native_identity_id TEXT,
          app_id TEXT,
          identity_id TEXT,
          chapter_id TEXT,
          chapter_parent_id TEXT,
          type TEXT,
          part_id TEXT,
          part_parent_id TEXT,
          sort_chapter TEXT,
          sort_chapter_am TEXT,
          sort_chapter_pm TEXT,
          outlines TEXT,
          outlines_am TEXT,
          outlines_pm TEXT,
          sort_part TEXT,
          sort_part_am TEXT,
          sort_part_pm TEXT,
          am_pm TEXT,
          high_frequency TEXT,
          is_collection_question TEXT,
          is_real_question TEXT,
          cases_id TEXT,
          cases_parent_id TEXT,
          sort_cases TEXT,
          sort_cases_am TEXT,
          sort_cases_pm TEXT,
          source TEXT,
          source_filter TEXT,
          show_number TEXT,
          created_at TEXT,
          type_str TEXT,
          origin_type TEXT,
          sort TEXT,
          is_new TEXT,
          outlines_mastery TEXT,
          filter_type TEXT,
          cut_question TEXT,
          user_answer TEXT,
          FOREIGN KEY(chapter_id) REFERENCES Chapter(id),
          FOREIGN KEY(chapter_parent_id) REFERENCES Subject(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Comment (
          id TEXT PRIMARY KEY,
          obj_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          content TEXT NOT NULL,
          to_user_id TEXT NOT NULL,
          parent_id TEXT NOT NULL,
          praise_num TEXT NOT NULL,
          floor_num TEXT NOT NULL,
          app_id TEXT NOT NULL,
          module_type TEXT NOT NULL,
          is_read TEXT NOT NULL,
          is_essence TEXT NOT NULL,
          ctime TEXT NOT NULL,
          oppose_num TEXT NOT NULL,
          author_looked TEXT NOT NULL,
          author_id TEXT NOT NULL,
          imgs TEXT NOT NULL,
          replies TEXT NOT NULL,
          number_of_reports TEXT NOT NULL,
          video_id TEXT NOT NULL,
          status TEXT NOT NULL,
          net_approval_number TEXT NOT NULL,
          delete_way TEXT NOT NULL,
          hkb_id TEXT NOT NULL,
          hkb_parent_id TEXT NOT NULL,
          reward_vip TEXT NOT NULL,
          reward_svip TEXT NOT NULL,
          is_logout TEXT NOT NULL,
          nickname TEXT NOT NULL,
          avatar TEXT NOT NULL,
          school TEXT NOT NULL,
          is_anonymous TEXT NOT NULL,
          is_authentication TEXT NOT NULL,
          user_identity TEXT NOT NULL,
          is_vip TEXT NOT NULL,
          is_svip TEXT NOT NULL,
          is_praise TEXT NOT NULL,
          is_oppose TEXT NOT NULL,
          reply_num TEXT NOT NULL,
          ctime_timestamp TEXT NOT NULL,
          delete_skill TEXT NOT NULL,
          is_author TEXT NOT NULL,
          img_watermark TEXT NOT NULL,
          c_imgs TEXT NOT NULL,
          watch_permission TEXT NOT NULL,
          user_identity_color TEXT NOT NULL,
          on_the_top TEXT NOT NULL,
          reply_primary_id TEXT NOT NULL,
          is_hot INTEGER NOT NULL,
          FOREIGN KEY(obj_id) REFERENCES Question(id)
      )
    ''');

    await db.execute('''
    CREATE TRIGGER IF NOT EXISTS update_chapter_after_insert
    AFTER INSERT ON Question
    FOR EACH ROW
    BEGIN
        -- 增加总问题数
        UPDATE IdentityChapter
        SET total = total + 1
        WHERE chapter_id = NEW.chapter_id;
    END;
    ''');

    await db.execute('''
    CREATE TRIGGER IF NOT EXISTS update_subject_after_insert
    AFTER INSERT ON Question
    FOR EACH ROW
    BEGIN
        -- 增加总问题数
        UPDATE IdentitySubject
        SET total = total + 1
        WHERE subject_id = NEW.chapter_parent_id;
    END;
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentitySubject (
        identity_id TEXT,
        subject_id TEXT,
        total INTAGER NOT NULL,
        PRIMARY KEY (identity_id, subject_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (subject_id) REFERENCES Subject(id)
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentityChapter (
        identity_id TEXT,
        chapter_id TEXT,
        total INTAGER NOT NULL,
        PRIMARY KEY (identity_id, chapter_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (chapter_id) REFERENCES Chapter(id)
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentityQuestion (
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        question_id TEXT,
        PRIMARY KEY (identity_id, question_id),
        FOREIGN KEY (identity_id) REFERENCES Identity(id),
        FOREIGN KEY (subject_id) REFERENCES Subject(id),
        FOREIGN KEY (chapter_id) REFERENCES Chapter(id),
        FOREIGN KEY (question_id) REFERENCES Question(id)
    )
    ''');
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
}

class UserDBHelper {
  static final UserDBHelper _instance = UserDBHelper._internal();
  factory UserDBHelper() => _instance;
  UserDBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'user_data.sqlite');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    print("初始化用户数据库...");
    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentitySubject (
        identity_id TEXT,
        subject_id TEXT,
        correct INTAGER DEFAULT 0 NOT NULL,
        incorrect INTAGER DEFAULT 0 NOT NULL,
        selected INTEGER DEFAULT 0 NOT NULL,
        PRIMARY KEY (identity_id, subject_id)
    )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS IdentityChapter (
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        correct INTAGER DEFAULT 0 NOT NULL,
        incorrect INTAGER DEFAULT 0 NOT NULL,
        PRIMARY KEY (identity_id, chapter_id)
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
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS update_chapter_after_update
      AFTER UPDATE ON Question
      FOR EACH ROW
      BEGIN
          -- 如果章节变化，更新章节的正确问题数量
          -- 先减少原章节的correct
          UPDATE IdentityChapter
          SET correct = correct - (CASE WHEN OLD.status = 1 THEN 1 ELSE 0 END)
          WHERE chapter_id = OLD.chapter_id AND identity_id = 30401;

          UPDATE IdentityChapter
          SET incorrect = incorrect - (CASE WHEN OLD.status = 2 THEN 1 ELSE 0 END)
          WHERE chapter_id = OLD.chapter_id AND identity_id = 30401;

          -- 之后增加新章节的correct
          UPDATE IdentityChapter
          SET correct = correct + (CASE WHEN NEW.status = 1 THEN 1 ELSE 0 END)
          WHERE chapter_id = NEW.chapter_id AND identity_id = 30401;

          UPDATE IdentityChapter
          SET incorrect = incorrect + (CASE WHEN NEW.status = 2 THEN 1 ELSE 0 END)
          WHERE chapter_id = NEW.chapter_id AND identity_id = 30401;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS update_subject_after_update
      AFTER UPDATE ON Question
      FOR EACH ROW
      BEGIN
          -- 如果章节变化，更新章节的正确问题数量
          -- 先减少原章节的correct
          UPDATE IdentitySubject
          SET correct = correct - (CASE WHEN OLD.status = 1 THEN 1 ELSE 0 END)
          WHERE subject_id = OLD.chapter_parent_id AND identity_id = 30401;

          UPDATE IdentitySubject
          SET incorrect = incorrect - (CASE WHEN OLD.status = 2 THEN 1 ELSE 0 END)
          WHERE subject_id = OLD.chapter_parent_id AND identity_id = 30401;

          -- 之后增加新章节的correct
          UPDATE IdentitySubject
          SET correct = correct + (CASE WHEN NEW.status = 1 THEN 1 ELSE 0 END)
          WHERE subject_id = NEW.chapter_parent_id AND identity_id = 30401;

          UPDATE IdentitySubject
          SET incorrect = incorrect + (CASE WHEN NEW.status = 2 THEN 1 ELSE 0 END)
          WHERE subject_id = NEW.chapter_parent_id AND identity_id = 30401;
      END;
    ''');
    print("用户数据库初始化完成～");
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
