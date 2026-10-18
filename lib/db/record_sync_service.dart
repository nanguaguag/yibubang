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

    // 关闭连接，确保 WAL/journal 落盘后再读取文件字节。
    await UserDBHelper().close();
    final bytes = await dbFile.readAsBytes();

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
  static Future<bool> importReplace(Uint8List zipBytes) async {
    final sqliteBytes = _extractSqlite(zipBytes);
    final dbPath = p.join(await getDatabasesPath(), _sqliteFileName);

    await UserDBHelper().close();
    await File(dbPath).writeAsBytes(sqliteBytes, flush: true);
    // 清理 WAL / SHM 残留，避免旧日志污染新库。
    for (final suffix in const ['-wal', '-shm']) {
      try {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      } catch (_) {/* 忽略 */}
    }

    // 重新打开并触发 onCreate/onUpgrade，确保 schema 就绪。
    await UserDBHelper().database;
    return true;
  }

  /// 导入做题记录（合并）。返回合并涉及的题目数量。
  static Future<int> importMerge(Uint8List zipBytes) async {
    final sqliteBytes = _extractSqlite(zipBytes);
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = p.join(
      tmpDir.path,
      'import_${generateSimpleId()}.sqlite',
    );
    await File(tmpPath).writeAsBytes(sqliteBytes, flush: true);

    Database? srcDb;
    try {
      srcDb = await openDatabase(tmpPath, readOnly: true);
      final userDb = await UserDBHelper().database;

      final srcQuestions = await srcDb.query('Question');
      final srcActivities = await srcDb.query('Activities');

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
            batch.insert('Question', rowCopy,
                conflictAlgorithm: ConflictAlgorithm.replace);
            merged++;
            continue;
          }

          final localStatus = (local['status'] as num?)?.toInt() ?? 0;
          final localCollection = (local['collection'] as num?)?.toInt() ?? 0;
          final localCut = (local['cut_question']?.toString()) ?? '0';
          final localIsCut = localCut == '1' || localCut == 'cutted';
          // 收藏 / 斩题取并集。
          final newCollection =
              (localCollection == 1 || srcCollection == 1) ? 1 : 0;
          final newCut = (localIsCut || srcIsCut) ? '1' : '0';
          // 仅补充本地未做的题（保留本地已做结果）。
          final useSrc = localStatus == 0 && srcStatus != 0;
          final newStatus = useSrc ? srcStatus : localStatus;
          final newAnswer =
              useSrc ? srcAnswer : (local['user_answer'] as String? ?? '');

          final srcUpdatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
          final localUpdatedAt = (local['updated_at'] as num?)?.toInt() ?? 0;
          final newUpdatedAt =
              srcUpdatedAt > localUpdatedAt ? srcUpdatedAt : localUpdatedAt;

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
          batch.insert('Activities', row,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        await batch.commit(noResult: true);
      });

      debugPrint('[record-sync] 合并完成：题目 $merged、流水 ${srcActivities.length}');
      return merged;
    } finally {
      if (srcDb != null && srcDb.isOpen) await srcDb.close();
      try {
        if (await File(tmpPath).exists()) await File(tmpPath).delete();
      } catch (_) {/* 忽略 */}
    }
  }

  /// 解压 zip 并取出其中的 SQLite 字节。
  static Uint8List _extractSqlite(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
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
      throw const FormatException('压缩包中未找到做题记录数据库（.sqlite）');
    }
    final content = file.content;
    if (content is! Uint8List) {
      throw const FormatException('压缩包内容读取失败');
    }
    return content;
  }

  static String _defaultFileName() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = DateTime.now();
    return 'yibubang-records-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}.zip';
  }
}
