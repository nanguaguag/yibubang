import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 负责独立题库 SQLite 的路径、只读连接和格式校验。
/// 页面和题目模型不应自行拼接题库文件路径。
class QuestionBankDatabaseManager {
  static final QuestionBankDatabaseManager _instance =
      QuestionBankDatabaseManager._internal();
  factory QuestionBankDatabaseManager() => _instance;
  QuestionBankDatabaseManager._internal();

  final Map<String, Database> _databases = {};
  final Map<String, _ValidationCacheEntry> _validationCache = {};
  final Map<String, Future<BankFileValidation>> _validationFutures = {};

  Future<String> get rootPath async =>
      p.join(await getDatabasesPath(), 'QuestionBank');

  Future<String> pathFor(String bankId) async =>
      p.join(await rootPath, bankId, '$bankId.sqlite');

  Future<Database> openBank(String bankId, {String? filePath}) async {
    final cached = _databases[bankId];
    if (cached != null && cached.isOpen) return cached;

    final path = filePath ?? await pathFor(bankId);
    final validation = await validateFile(path, expectedBankId: bankId);
    if (!validation.isValid) {
      throw FormatException(validation.message);
    }

    final database = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
    _databases[bankId] = database;
    return database;
  }

  Future<void> closeBank(String bankId) async {
    final database = _databases.remove(bankId);
    if (database != null && database.isOpen) await database.close();
  }

  Future<void> closeAll() async {
    for (final database in _databases.values) {
      if (database.isOpen) await database.close();
    }
    _databases.clear();
  }

  Future<BankFileValidation> validateFile(
    String filePath, {
    String? expectedBankId,
  }) async {
    final file = File(filePath);
    final cacheKey = '$filePath|${expectedBankId ?? ''}';
    if (!await file.exists()) {
      _validationCache.remove(cacheKey);
      return const BankFileValidation.invalid('题库文件不存在');
    }

    final stat = await file.stat();
    final cached = _validationCache[cacheKey];
    if (cached != null && cached.matches(stat)) {
      return cached.result;
    }

    final running = _validationFutures[cacheKey];
    if (running != null) return running;

    final future = _validateFileUncached(
      filePath,
      expectedBankId: expectedBankId,
    ).then((result) {
      _validationCache[cacheKey] = _ValidationCacheEntry(
        size: stat.size,
        modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
        result: result,
      );
      return result;
    });
    _validationFutures[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_validationFutures[cacheKey], future)) {
        _validationFutures.remove(cacheKey);
      }
    }
  }

  /// 执行一次完整 SQLite 校验。结果由 validateFile 按文件指纹缓存，
  /// 从而避免题库目录初始化和首屏打开活动题库重复扫描同一个文件。
  Future<BankFileValidation> _validateFileUncached(
    String filePath, {
    String? expectedBankId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const BankFileValidation.invalid('题库文件不存在');
    }

    Database? database;
    try {
      database = await openDatabase(
        filePath,
        readOnly: true,
        singleInstance: false,
      );
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((row) => row['name'] as String).toSet();
      const requiredTables = {
        'BankMeta',
        'Identity',
        'Subject',
        'Chapter',
        'Question',
        'IdentitySubject',
        'IdentityChapter',
        'IdentityQuestion',
      };
      final missing = requiredTables.difference(tableNames);
      if (missing.isNotEmpty) {
        return BankFileValidation.invalid('题库缺少必要数据表：${missing.join('、')}');
      }

      final metaRows = await database.query('BankMeta', limit: 1);
      if (metaRows.length != 1) {
        return const BankFileValidation.invalid('题库 BankMeta 元数据缺失');
      }
      final meta = metaRows.first;
      final bankId = meta['bank_id'] as String?;
      final schemaVersion = (meta['schema_version'] as num?)?.toInt() ?? 0;
      if (bankId == null || bankId.isEmpty) {
        return const BankFileValidation.invalid('题库 bank_id 为空');
      }
      if (expectedBankId != null && bankId != expectedBankId) {
        return BankFileValidation.invalid(
          '题库标识不匹配：文件为 $bankId，目标为 $expectedBankId',
        );
      }
      if (schemaVersion < 1 || schemaVersion > 1) {
        return BankFileValidation.invalid('不支持的题库结构版本：$schemaVersion');
      }

      final integrity = await database.rawQuery('PRAGMA integrity_check');
      final integrityResult = integrity.first.values.first?.toString();
      if (integrityResult != 'ok') {
        return BankFileValidation.invalid('SQLite 完整性检查失败：$integrityResult');
      }

      final rootRows = await database.query(
        'Identity',
        columns: ['id'],
        where: 'parent_id = ?',
        whereArgs: ['-1'],
      );
      if (rootRows.length != 1) {
        return const BankFileValidation.invalid('题库必须且只能包含一个根 identity');
      }
      final foreignKeyErrors =
          await database.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeyErrors.isNotEmpty) {
        return const BankFileValidation.invalid('题库存在无效的数据关系引用');
      }

      final relationCount = Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM IdentityQuestion',
          )) ??
          0;
      final questionCount = Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM Question',
          )) ??
          0;
      final subjectCount = Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM Subject',
          )) ??
          0;
      final chapterCount = Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM Chapter',
          )) ??
          0;
      final declaredQuestionCount = (meta['question_count'] as num?)?.toInt();
      final declaredRelationCount = (meta['relation_count'] as num?)?.toInt();
      final declaredSubjectCount = (meta['subject_count'] as num?)?.toInt();
      final declaredChapterCount = (meta['chapter_count'] as num?)?.toInt();
      if ((declaredQuestionCount != null &&
              declaredQuestionCount != questionCount) ||
          (declaredRelationCount != null &&
              declaredRelationCount != relationCount) ||
          (declaredSubjectCount != null &&
              declaredSubjectCount != subjectCount) ||
          (declaredChapterCount != null &&
              declaredChapterCount != chapterCount)) {
        return const BankFileValidation.invalid('题库元数据统计与实际内容不一致');
      }
      if (relationCount == 0 || questionCount == 0) {
        return const BankFileValidation.invalid('题库没有可用题目');
      }
      return BankFileValidation.valid({
        ...meta,
        'identity_id': rootRows.first['id'],
      });
    } catch (error) {
      debugPrint('题库校验失败：$error');
      return BankFileValidation.invalid('无法读取题库 SQLite：$error');
    } finally {
      if (database != null && database.isOpen) await database.close();
    }
  }
}

class _ValidationCacheEntry {
  final int size;
  final int modifiedMilliseconds;
  final BankFileValidation result;

  const _ValidationCacheEntry({
    required this.size,
    required this.modifiedMilliseconds,
    required this.result,
  });

  bool matches(FileStat stat) =>
      size == stat.size &&
      modifiedMilliseconds == stat.modified.millisecondsSinceEpoch;
}

class BankFileValidation {
  final bool isValid;
  final String message;
  final Map<String, dynamic>? metadata;

  const BankFileValidation._(this.isValid, this.message, this.metadata);

  const BankFileValidation.invalid(String message)
      : this._(false, message, null);

  const BankFileValidation.valid(Map<String, dynamic> metadata)
      : this._(true, '', metadata);
}
