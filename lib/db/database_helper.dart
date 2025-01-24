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
        name TEXT NOT NULL,
        selected BOOL NOT NULL
    );
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS Chapter (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        subject_id TEXT,
        FOREIGN KEY(subject_id) REFERENCES Subject(id)
    );
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
        option TEXT,
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
    );
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
