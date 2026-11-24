import 'dart:convert';
import 'user_database_replacement.dart';
import 'user_database_coordinator.dart';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// 做题记录本地手动同步服务。
///
/// 对应 issue #11 的「导出 / 导入文件」方案：
/// - 导出：把 `user_data.sqlite` 打包为 `sqlite.zip`，由用户自行经网盘等
///   渠道在多设备间搬运；
/// - 导入：解压 zip 后按用户选择执行「替换」或「合并」。
///
/// 「替换」用导入文件整体覆盖本地用户库；「合并」只把导入库中的做题记录
/// （Question + Activities）按题目 id 并入本地，不覆盖题库管理配置。
class RecordSyncService {
  static const _sqliteFileName = 'user_data.sqlite';

  @visibleForTesting
  static Future<void> Function()? beforeReplacementOpenForTesting;

  /// 导出做题记录，返回最终保存的文件绝对路径；用户取消返回 `null`。
  ///
  /// 说明：`file_picker` 的 `saveFile` 在各平台行为不一致——
  /// - 桌面端（macOS/Windows/Linux）会**忽略 `bytes` 参数**，只返回用户选择的
  ///   路径而不写文件内容，因此这里拿到路径后自行写入；
  /// - Android 端传 `FileType.custom` 时原生会把 MIME 设成无效的 `"custom"`，
  ///   导致 SAF 保存异常（实测 0 字节），因此移动端改为直接写应用外部存储目录。
  static Future<String?> exportRecords() async {
    final dbPath = p.join(await getDatabasesPath(), _sqliteFileName);
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      debugPrint('[record-sync] 用户库文件不存在：$dbPath');
      return null;
    }

    // 关闭连接前，先触发 checkpoint 截断 WAL，确保所有内存与 sidecar 写入完整合入主 db 文件
    final bytes = await UserDatabaseCoordinator.instance.run(() async {
      try {
        final db = await UserDBHelper().database;
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        debugPrint('[record-sync] 导出 wal_checkpoint 警告: $e');
      }
      await UserDBHelper().close();
      return dbFile.readAsBytes();
    });

    final archive = Archive();
    archive.addFile(ArchiveFile(_sqliteFileName, bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      debugPrint('[record-sync] zip 编码失败');
      return null;
    }
    final zipBytes = Uint8List.fromList(encoded);
    final fileName = _defaultFileName();

    final String? savedPath;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动端：直接写应用外部存储（Android）或文档目录（iOS），绕开
      // file_picker saveFile 的 bytes/MIME 兼容问题。
      Directory? dir = await getExternalStorageDirectory();
      dir ??= await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(zipBytes, flush: true);
      savedPath = file.path;
    } else {
      // 桌面端：saveFile 仅用于让用户选择保存位置（其 bytes 参数被忽略），
      // 拿到路径后自行写入文件内容。
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出做题记录',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (path == null || path.isEmpty) {
        debugPrint('[record-sync] 用户取消导出');
        return null;
      }
      await File(path).writeAsBytes(zipBytes, flush: true);
      savedPath = path;
    }

    debugPrint('[record-sync] 导出成功：$savedPath（${zipBytes.length} 字节）');
    return savedPath;
  }

  /// 导入做题记录（替换）。返回是否成功。
  static Future<bool> importReplace(
    Uint8List zipBytes,
  ) => UserDatabaseCoordinator.instance.run(() async {
    final sqliteBytes = _extractSqlite(zipBytes);
    final dbPath = p.join(await getDatabasesPath(), _sqliteFileName);

    final staged = File('$dbPath.importing');
    final helper = UserDBHelper();
    try {
      await staged.writeAsBytes(sqliteBytes, flush: true);
      await helper.prepareImportedDatabase(staged.path);
      // 排空并落盘后才开始文件替换。全程持有共享维护锁。
      final db = await helper.database;
      final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.first.values.first != 0) throw StateError('用户库正被占用，请稍后重试');
      final journalMode = await db.rawQuery('PRAGMA journal_mode = DELETE');
      if (journalMode.single.values.single.toString().toLowerCase() != 'delete') {
        throw StateError('用户库无法生成独立快照');
      }
      await helper.close();
      final original = File(dbPath), backup = File('$dbPath.backup');
      if (await backup.exists()) await backup.delete();
      final journal = File('$dbPath.replace.json');
      await File('${journal.path}.tmp').writeAsString(
        jsonEncode({'had_original': await original.exists()}),
        flush: true,
      );
      await File('${journal.path}.tmp').rename(journal.path);
      if (await original.exists()) await original.rename(backup.path);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final file = File('$dbPath$suffix');
        if (await file.exists()) await file.delete();
      }
      await staged.rename(dbPath);
      // 通过同一开库逻辑核验，但此处暂不触发恢复日志。
      await helper.prepareImportedDatabase(dbPath);
      await beforeReplacementOpenForTesting?.call();
      await helper.activateImportedDatabase(dbPath);
      await journal.delete();
    } catch (_) {
      await helper.close();
      await recoverUserDatabaseReplacement(dbPath);
      rethrow;
    } finally {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${staged.path}$suffix');
        if (await file.exists()) await file.delete();
      }
    }
    return true;
  });

  /// 导入做题记录（合并）。返回合并涉及的题目与个人数据总数量。
  static Future<int> importMerge(Uint8List zipBytes) async {
    final sqliteBytes = _extractSqlite(zipBytes);
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = p.join(tmpDir.path, 'import_${generateSimpleId()}.sqlite');
    await File(tmpPath).writeAsBytes(sqliteBytes, flush: true);

    Database? srcDb;
    try {
      final sourceDb = await openDatabase(tmpPath, readOnly: true);
      srcDb = sourceDb;
      final userDb = await UserDBHelper().database;

      final srcQuestions = await sourceDb.query('Question');
      final srcActivities = await sourceDb.query('Activities');

      final localRows = await userDb.query('Question');
      final localMap = <String, Map<String, dynamic>>{
        for (final r in localRows) r['id'] as String: r,
      };

      var merged = 0;
      await userDb.transaction((txn) async {
        final batch = txn.batch();

        // 1) 合并题目进度：本地优先，仅当本地「未做」而导入「已做」时采用导入状态。
        for (final row in srcQuestions) {
          final id = row['id'] as String;
          final srcStatus = (row['status'] as num?)?.toInt() ?? 0;
          final srcCollection = (row['collection'] as num?)?.toInt() ?? 0;
          final srcCut = (row['cut_question']?.toString()) ?? '0';
          final srcAnswer = (row['user_answer'] as String?) ?? '';
          final srcIsCut = srcCut == '1' || srcCut == 'cutted';

          final local = localMap[id];
          if (local == null) {
            final rowCopy = Map<String, dynamic>.from(row);
            rowCopy['cut_question'] = srcIsCut ? '1' : '0';
            batch.insert(
              'Question',
              rowCopy,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            merged++;
            continue;
          }

          final localStatus = (local['status'] as num?)?.toInt() ?? 0;
          final localCollection = (local['collection'] as num?)?.toInt() ?? 0;
          final localCut = (local['cut_question']?.toString()) ?? '0';
          final localIsCut = localCut == '1' || localCut == 'cutted';
          // 收藏 / 斩题取并集。
          final newCollection = (localCollection == 1 || srcCollection == 1)
              ? 1
              : 0;
          final newCut = (localIsCut || srcIsCut) ? '1' : '0';
          // 仅补充本地未做的题（保留本地已做结果）。
          final useSrc = localStatus == 0 && srcStatus != 0;
          final newStatus = useSrc ? srcStatus : localStatus;
          final newAnswer = useSrc
              ? srcAnswer
              : (local['user_answer'] as String? ?? '');

          final srcUpdatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
          final localUpdatedAt = (local['updated_at'] as num?)?.toInt() ?? 0;
          final newUpdatedAt = srcUpdatedAt > localUpdatedAt
              ? srcUpdatedAt
              : localUpdatedAt;

          batch.update(
            'Question',
            {
              'status': newStatus,
              'collection': newCollection,
              'cut_question': newCut,
              'user_answer': newAnswer,
              'updated_at': newUpdatedAt,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          merged++;
        }

        // 2) 合并作答流水：按主键 id 去重追加，重复的忽略。
        for (final row in srcActivities) {
          batch.insert(
            'Activities',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        // 3) 合并个人笔记（Notes）
        if (await _hasTable(sourceDb, 'Notes') && await _hasTable(txn, 'Notes')) {
          final srcNotes = await sourceDb.query('Notes');
          final localNotes = await txn.query('Notes');
          final localNoteColumns = (await txn.rawQuery("PRAGMA table_info(Notes)"))
              .map((r) => r['name'] as String)
              .toSet();
          final localNoteMap = <String, Map<String, dynamic>>{
            for (final n in localNotes) n['id'].toString(): n,
          };
          for (final note in srcNotes) {
            final id = note['id'].toString();
            final sanitized = _sanitizeRow(note, localNoteColumns, const {
              'sync_status': 0,
              'revision': 0,
              'imgs': '[]',
              'updated_at': 0,
            });
            final local = localNoteMap[id];
            if (local == null) {
              batch.insert(
                'Notes',
                sanitized,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              merged++;
            } else {
              final srcUpdated = (note['updated_at'] as num?)?.toInt() ??
                  (note['timestamp'] as num?)?.toInt() ??
                  0;
              final localUpdated = (local['updated_at'] as num?)?.toInt() ??
                  (local['timestamp'] as num?)?.toInt() ??
                  0;
              if (srcUpdated > localUpdated) {
                batch.update(
                  'Notes',
                  sanitized,
                  where: 'id = ?',
                  whereArgs: [id],
                );
                merged++;
              }
            }
          }
        }

        // 4) 合并我的点赞与我的评论（SavedComments）
        if (await _hasTable(sourceDb, 'SavedComments') &&
            await _hasTable(txn, 'SavedComments')) {
          final srcComments = await sourceDb.query('SavedComments');
          final localComments = await txn.query('SavedComments');
          final localCommentColumns =
              (await txn.rawQuery("PRAGMA table_info(SavedComments)"))
                  .map((r) => r['name'] as String)
                  .toSet();
          final localCommentMap = <String, Map<String, dynamic>>{
            for (final c in localComments)
              '${c['comment_id']}_${c['category']}': c,
          };
          for (final comment in srcComments) {
            final key = '${comment['comment_id']}_${comment['category']}';
            final sanitized = _sanitizeRow(comment, localCommentColumns, const {
              'praise_count': 0,
              'reply_count': 0,
              'updated_at': 0,
              'extra_json': '{}',
            });
            final local = localCommentMap[key];
            if (local == null) {
              batch.insert(
                'SavedComments',
                sanitized,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              merged++;
            } else {
              final srcUpdated = (comment['updated_at'] as num?)?.toInt() ??
                  (comment['timestamp'] as num?)?.toInt() ??
                  0;
              final localUpdated = (local['updated_at'] as num?)?.toInt() ??
                  (local['timestamp'] as num?)?.toInt() ??
                  0;
              if (srcUpdated > localUpdated) {
                batch.update(
                  'SavedComments',
                  sanitized,
                  where: 'comment_id = ? AND category = ?',
                  whereArgs: [comment['comment_id'], comment['category']],
                );
                merged++;
              }
            }
          }
        }

        // 5) 合并自制闪卡（CustomFlashcards）
        if (await _hasTable(sourceDb, 'CustomFlashcards') &&
            await _hasTable(txn, 'CustomFlashcards')) {
          final srcCards = await sourceDb.query('CustomFlashcards');
          final localCards = await txn.query('CustomFlashcards');
          final localCardColumns =
              (await txn.rawQuery("PRAGMA table_info(CustomFlashcards)"))
                  .map((r) => r['name'] as String)
                  .toSet();
          final localCardMap = <String, Map<String, dynamic>>{
            for (final c in localCards) c['id'].toString(): c,
          };
          for (final card in srcCards) {
            final id = card['id'].toString();
            final sanitized = _sanitizeRow(card, localCardColumns, const {
              'is_mastered': 0,
              'review_count': 0,
              'tags': '[]',
              'updated_at': 0,
            });
            final local = localCardMap[id];
            if (local == null) {
              batch.insert(
                'CustomFlashcards',
                sanitized,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              merged++;
            } else {
              final srcUpdated = (card['updated_at'] as num?)?.toInt() ?? 0;
              final localUpdated = (local['updated_at'] as num?)?.toInt() ?? 0;
              if (srcUpdated > localUpdated) {
                batch.update(
                  'CustomFlashcards',
                  sanitized,
                  where: 'id = ?',
                  whereArgs: [id],
                );
                merged++;
              }
            }
          }
        }

        // 6) 合并间隔复习状态（SpacedReviewItem）
        if (await _hasTable(sourceDb, 'SpacedReviewItem') &&
            await _hasTable(txn, 'SpacedReviewItem')) {
          final srcItems = await sourceDb.query('SpacedReviewItem');
          final localItems = await txn.query('SpacedReviewItem');
          final localItemMap = <String, Map<String, dynamic>>{
            for (final item in localItems)
              item['question_id']?.toString() ?? item['id'].toString(): item,
          };
          for (final item in srcItems) {
            final qid = item['question_id']?.toString() ?? item['id'].toString();
            final local = localItemMap[qid];
            if (local == null) {
              batch.insert(
                'SpacedReviewItem',
                item,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              merged++;
            } else {
              final srcReps = (item['reps'] as num?)?.toInt() ?? 0;
              final localReps = (local['reps'] as num?)?.toInt() ?? 0;
              if (localReps == 0 && srcReps > 0) {
                batch.update(
                  'SpacedReviewItem',
                  item,
                  where: 'id = ?',
                  whereArgs: [local['id']],
                );
                merged++;
              }
            }
          }
        }

        // 7) 合并答题计时（QuestionTestTime）
        if (await _hasTable(sourceDb, 'QuestionTestTime') &&
            await _hasTable(txn, 'QuestionTestTime')) {
          final srcTimes = await sourceDb.query('QuestionTestTime');
          final localTimes = await txn.query('QuestionTestTime');
          final localTimeMap = <String, Map<String, dynamic>>{
            for (final t in localTimes) t['question_id'].toString(): t,
          };
          for (final t in srcTimes) {
            final qid = t['question_id'].toString();
            final local = localTimeMap[qid];
            if (local == null) {
              batch.insert(
                'QuestionTestTime',
                t,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } else {
              final srcDuration = (t['duration_ms'] as num?)?.toInt() ?? 0;
              final localDuration = (local['duration_ms'] as num?)?.toInt() ?? 0;
              if (srcDuration > localDuration) {
                batch.update(
                  'QuestionTestTime',
                  {'duration_ms': srcDuration},
                  where: 'question_id = ?',
                  whereArgs: [qid],
                );
              }
            }
          }
        }

        await batch.commit(noResult: true);
      });

      debugPrint('[record-sync] 合并完成：共合并/更新 $merged 项记录、流水 ${srcActivities.length}');
      return merged;
    } finally {
      if (srcDb != null && srcDb.isOpen) await srcDb.close();
      try {
        if (await File(tmpPath).exists()) await File(tmpPath).delete();
      } catch (_) {
        /* 忽略 */
      }
    }
  }

  static Future<bool> _hasTable(DatabaseExecutor db, String tableName) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [tableName],
    );
    return res.isNotEmpty;
  }

  /// 解压 zip 并取出其中的 SQLite 字节，或直接识别已有的 SQLite 数据库字节。
  static Uint8List _extractSqlite(Uint8List bytes) {
    if (bytes.length > 512 * 1024 * 1024) {
      throw const FormatException('做题记录文件过大');
    }
    // 检查是否本身就是有效的 SQLite 数据库文件（魔数: "SQLite format 3\0"）
    if (bytes.length >= 16) {
      final header = String.fromCharCodes(bytes.sublist(0, 15));
      if (header == 'SQLite format 3' && bytes[15] == 0) {
        return bytes;
      }
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (n, f) => n + f.size) > 512 * 1024 * 1024) {
      throw const FormatException('做题记录解压内容过大');
    }
    ArchiveFile? file = archive.findFile(_sqliteFileName);
    if (file == null) {
      for (final f in archive.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.sqlite')) {
          file = f;
          break;
        }
      }
    }
    if (file == null) {
      throw const FormatException('文件/压缩包中未找到做题记录数据库（.sqlite）');
    }
    if (!file.isFile || file.size > 512 * 1024 * 1024) {
      throw const FormatException('做题记录数据库文件无效或过大');
    }
    final content = file.content;
    if (content is! Uint8List) {
      throw const FormatException('做题记录内容读取失败');
    }
    return content;
  }

  static Map<String, dynamic> _sanitizeRow(
    Map<String, dynamic> row,
    Set<String> validColumns,
    Map<String, dynamic> defaults,
  ) {
    final sanitized = <String, dynamic>{};
    for (final col in validColumns) {
      if (row.containsKey(col) && row[col] != null) {
        sanitized[col] = row[col];
      } else if (defaults.containsKey(col)) {
        sanitized[col] = defaults[col];
      }
    }
    return sanitized;
  }

  static String _defaultFileName() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = DateTime.now();
    return 'yibubang-records-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}.zip';
  }
}
