import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/cloud_outbox.dart';
import '../models/cloud_backup.dart';
import 'cloud_sync_service.dart';

/// Cloudflare R2 整库冷备快照管理服务
class CloudBackupService extends ChangeNotifier {
  static final CloudBackupService instance = CloudBackupService._internal();
  CloudBackupService._internal();

  static const String keyAutoEnabled = 'cloud_backup_auto_enabled';
  static const String keyMaxRetained = 'cloud_backup_max_retained';
  static const String keyIntervalDays = 'cloud_backup_interval_days';
  static const String keyLastBackupTime = 'cloud_backup_last_time';

  static const int defaultMaxRetained = 10;
  static const int defaultIntervalDays = 7;

  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;

  String? _lastError;
  String? get lastError => _lastError;

  /// 获取自动备份开关（默认不开启）
  Future<bool> getAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyAutoEnabled) ?? false;
  }

  /// 设置自动备份开关
  Future<void> setAutoEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoEnabled, enabled);
    notifyListeners();
  }

  /// 获取保留备份快照数量（默认 10 条）
  Future<int> getMaxRetained() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyMaxRetained) ?? defaultMaxRetained;
  }

  /// 设置保留备份快照数量
  Future<void> setMaxRetained(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyMaxRetained, count.clamp(1, 50));
    notifyListeners();
  }

  /// 获取自动备份周期天数（默认 7 天/每周）
  Future<int> getIntervalDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyIntervalDays) ?? defaultIntervalDays;
  }

  /// 设置自动备份周期天数
  Future<void> setIntervalDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyIntervalDays, days.clamp(1, 30));
    notifyListeners();
  }

  /// 获取上次备份时间戳
  Future<int> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyLastBackupTime) ?? 0;
  }

  /// 检查并按需执行周期性冷备份
  Future<void> checkAndRunAutoBackup() async {
    final autoEnabled = await getAutoEnabled();
    if (!autoEnabled) return;

    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) return;

    final lastTime = await getLastBackupTime();
    final intervalDays = await getIntervalDays();
    final now = DateTime.now().millisecondsSinceEpoch;

    final diffMs = now - lastTime;
    final intervalMs = intervalDays * 24 * 60 * 60 * 1000;

    if (diffMs >= intervalMs) {
      debugPrint('[CloudBackupService] 触发自动周期性 R2 冷备...');
      await createBackup();
    }
  }

  /// 执行整库 SQLite 冷备并上传至 Cloudflare R2
  Future<BackupResult> createBackup() async {
    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) {
      return const BackupResult(success: false, message: '请先登录云同步账号');
    }
    if (_isBackingUp) {
      return const BackupResult(success: false, message: '正在备份中，请稍候');
    }

    _isBackingUp = true;
    _lastError = null;
    notifyListeners();

    try {
      final db = await UserDBHelper().database;
      // 1. 执行 WAL checkpoint 截断，保证所有写入完全落入主 db 文件
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        debugPrint('[CloudBackupService] wal_checkpoint warning: $e');
      }

      // 2. 定位 user_data.sqlite 文件
      final dbDir = await getDatabasesPath();
      final dbFile = File(p.join(dbDir, 'user_data.sqlite'));
      if (!await dbFile.exists()) {
        throw StateError('用户数据库文件不存在');
      }

      final rawBytes = await dbFile.readAsBytes();
      final rawSha256 = sha256.convert(rawBytes).toString();

      // 3. GZip 压缩
      final compressedBytes = GZipEncoder().encode(rawBytes);
      if (compressedBytes == null) {
        throw StateError('数据库压缩失败');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final maxRetained = await getMaxRetained();

      // 4. 上传至 Cloudflare Worker R2 端点 (支持主备容灾轮询)
      final deviceToken = syncService.deviceToken ?? '';
      http.StreamedResponse? streamedResponse;
      String responseBody = '';
      Object? lastEx;

      for (final base in syncService.endpoints) {
        final serverUrl = base.replaceAll(RegExp(r'/+$'), '');
        final uploadUri = Uri.parse('$serverUrl/api/backup/upload');
        final request = http.Request('POST', uploadUri)
          ..headers.addAll({
            'Authorization': 'Bearer $deviceToken',
            'Content-Type': 'application/gzip',
            'X-Backup-Checksum': rawSha256,
            'X-Backup-Timestamp': now.toString(),
            'X-Backup-Size': rawBytes.length.toString(),
            'X-Max-Retained': maxRetained.toString(),
          })
          ..bodyBytes = compressedBytes;

        final client = http.Client();
        try {
          final res = await client.send(request).timeout(const Duration(seconds: 60));
          if (res.statusCode == 200) {
            streamedResponse = res;
            responseBody = await res.stream.bytesToString();
            break;
          } else {
            responseBody = await res.stream.bytesToString();
            String errMsg = '上传备份失败 (HTTP ${res.statusCode})';
            try {
              final errJson = jsonDecode(responseBody);
              if (errJson['message'] != null) errMsg = errJson['message'];
            } catch (_) {}
            lastEx = StateError(errMsg);
          }
        } catch (e) {
          lastEx = e is Exception ? e : Exception(e.toString());
        } finally {
          client.close();
        }
      }

      if (streamedResponse == null) {
        throw lastEx ?? StateError('所有备份端点上传均失败');
      }

      final respJson = jsonDecode(responseBody);
      final data = respJson['data'] as Map<String, dynamic>? ?? {};

      final snapshot = BackupSnapshot(
        key: data['key']?.toString() ?? '',
        filename: data['filename']?.toString() ?? '$now.sqlite.gz',
        size: compressedBytes.length,
        timestamp: now,
        checksum: rawSha256,
      );

      // 5. 记录备份时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keyLastBackupTime, now);

      debugPrint('[CloudBackupService] R2 整库备份成功: ${snapshot.filename} (${snapshot.sizeLabel})');
      return BackupResult(
        success: true,
        message: '备份成功 (${snapshot.sizeLabel})',
        snapshot: snapshot,
      );
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[CloudBackupService] 备份异常: $e');
      return BackupResult(success: false, message: '备份失败: $e');
    } finally {
      _isBackingUp = false;
      notifyListeners();
    }
  }

  /// 获取 R2 云端备份快照列表
  Future<List<BackupSnapshot>> listBackups() async {
    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) return [];

    final deviceToken = syncService.deviceToken ?? '';
    for (final base in syncService.endpoints) {
      final serverUrl = base.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$serverUrl/api/backup/list');
      try {
        final res = await http.get(uri, headers: {
          'Authorization': 'Bearer $deviceToken',
        }).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final json = jsonDecode(utf8.decode(res.bodyBytes));
          final list = json['data']?['backups'] as List? ?? [];
          return list.map((e) => BackupSnapshot.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// 从 R2 下载并整库还原覆盖本地数据库（具有防损回滚保护）
  Future<bool> restoreBackup(String filename) async {
    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) return false;
    if (_isRestoring) return false;

    _isRestoring = true;
    _lastError = null;
    notifyListeners();

    try {
      final deviceToken = syncService.deviceToken ?? '';
      http.Response? res;
      for (final base in syncService.endpoints) {
        final serverUrl = base.replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$serverUrl/api/backup/download/$filename');
        try {
          final resp = await http.get(uri, headers: {
            'Authorization': 'Bearer $deviceToken',
          }).timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200) {
            res = resp;
            break;
          }
        } catch (_) {}
      }

      if (res == null || res.statusCode != 200) {
        throw StateError('下载备份失败');
      }

      final expectedChecksum = res.headers['x-backup-checksum'] ?? '';
      final compressedBytes = res.bodyBytes;

      // 解压
      final decompressedBytes = GZipDecoder().decodeBytes(compressedBytes);
      if (expectedChecksum.isNotEmpty) {
        final actualChecksum = sha256.convert(decompressedBytes).toString();
        if (actualChecksum != expectedChecksum) {
          throw StateError('校验和不匹配，备份文件可能损坏');
        }
      }

      // 关闭数据库并替换
      await UserDBHelper().close();

      final dbDir = await getDatabasesPath();
      final targetPath = p.join(dbDir, 'user_data.sqlite');
      final backupPath = p.join(dbDir, 'user_data.sqlite.restore_bak');

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.copy(backupPath);
      }

      try {
        await targetFile.writeAsBytes(decompressedBytes, flush: true);
        // 清理旧的 wal 和 shm 文件
        final walFile = File('$targetPath-wal');
        final shmFile = File('$targetPath-shm');
        if (await walFile.exists()) await walFile.delete();
        if (await shmFile.exists()) await shmFile.delete();

        // 重新开启数据库并保证结构健康
        final newDb = await UserDBHelper().database;
        await CloudOutbox.install(newDb);
        debugPrint('[CloudBackupService] 整库恢复成功: $filename');
        return true;
      } catch (err) {
        // 回滚
        final bakFile = File(backupPath);
        if (await bakFile.exists()) {
          await bakFile.copy(targetPath);
        }
        rethrow;
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[CloudBackupService] 恢复备份失败: $e');
      return false;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// 删除 R2 云端的指定快照
  Future<bool> deleteBackup(String filename) async {
    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) return false;

    final deviceToken = syncService.deviceToken ?? '';
    for (final base in syncService.endpoints) {
      final serverUrl = base.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$serverUrl/api/backup/$filename');
      try {
        final res = await http.delete(uri, headers: {
          'Authorization': 'Bearer $deviceToken',
        }).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }
}
