import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/data_transfer.dart';
import '../db/cloud_outbox.dart';
import '../db/database_helper.dart';

/// 云服务健康检查状态
class HealthCheckResult {
  final bool isHealthy;
  final int latencyMs;
  final String message;

  const HealthCheckResult({
    required this.isHealthy,
    required this.latencyMs,
    required this.message,
  });
}

/// 云同步配对码信息
class PairingCodeInfo {
  final String code;
  final int expiresAt;
  final int expiresInSeconds;

  PairingCodeInfo({
    required this.code,
    required this.expiresAt,
    required this.expiresInSeconds,
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= expiresAt;
}

/// 同步执行结果
class SyncResult {
  final bool success;
  final String? message;
  final int pushedActivities;
  final int pushedQuestions;
  final int pulledActivities;
  final int pulledQuestions;
  final DateTime syncTime;

  SyncResult({
    required this.success,
    this.message,
    this.pushedActivities = 0,
    this.pushedQuestions = 0,
    this.pulledActivities = 0,
    this.pulledQuestions = 0,
    DateTime? syncTime,
  }) : syncTime = syncTime ?? DateTime.now();

  @override
  String toString() {
    if (!success) return '同步失败：$message';
    return '同步完成：上传流水 $pushedActivities 条、题目 $pushedQuestions 道；'
        '拉取流水 $pulledActivities 条、题目 $pulledQuestions 道';
  }
}

/// 做题记录云端增量同步服务 (单例)
class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService instance = CloudSyncService._internal();
  CloudSyncService._internal();

  // 线上端点：主域名 + 备用域名（容灾降级）
  static const String primaryEndpoint = 'https://yibubang.melonhu.com';
  static const String fallbackEndpoint =
      'https://yibubang-sync-server.1448424184.workers.dev';

  // SharedPreferences Keys
  static const String _keyEnabled = 'cloud_sync_enabled';
  static const String _keyUserId = 'cloud_sync_user_id';
  static const String _keyDeviceId = 'cloud_sync_device_id';
  static const String _keyDeviceToken = 'cloud_sync_device_token';
  static const String _keyDeviceName = 'cloud_sync_device_name';
  static const String _keyPassphrase = 'cloud_sync_passphrase';
  static const String _keyLastSyncTime = 'cloud_sync_last_sync_time';
  static const String _keyAutoSync = 'cloud_sync_auto_sync';
  static const String _keyCachedPairCode = 'cloud_sync_cached_pair_code';
  static const String _keyCachedPairExpiresAt =
      'cloud_sync_cached_pair_expires_at';

  bool _initialized = false;
  bool _isSyncing = false;
  String? _lastError;

  bool _enabled = false;
  String? _userId;
  String? _deviceId;
  String? _deviceToken;
  String? _deviceName;
  String? _passphrase;
  int _lastSyncTime = 0;
  bool _autoSync = true;

  bool get isInitialized => _initialized;
  bool get isSyncing => _isSyncing;
  bool get isConfigured =>
      _enabled &&
      _userId != null &&
      _userId!.isNotEmpty &&
      _deviceToken != null &&
      _deviceToken!.isNotEmpty;

  bool get enabled => _enabled;
  String? get userId => _userId;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName ?? _defaultDeviceName();
  String? get passphrase => _passphrase;
  int get lastSyncTime => _lastSyncTime;
  bool get autoSync => _autoSync;
  String? get lastError => _lastError;

  DateTime? get lastSyncDateTime => _lastSyncTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(_lastSyncTime)
      : null;

  /// 初始化并加载本地配置
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _userId = prefs.getString(_keyUserId);
    _deviceId = prefs.getString(_keyDeviceId);
    _deviceToken = prefs.getString(_keyDeviceToken);
    _deviceName = prefs.getString(_keyDeviceName);
    _passphrase = prefs.getString(_keyPassphrase);
    _lastSyncTime = prefs.getInt(_keyLastSyncTime) ?? 0;
    _autoSync = prefs.getBool(_keyAutoSync) ?? true;
    _initialized = true;
    notifyListeners();
  }

  /// 服务端健康检查探针
  Future<HealthCheckResult> checkHealth() async {
    final sw = Stopwatch()..start();
    try {
      final res = await _request('/api/health', method: 'GET');
      sw.stop();
      final status = res['status']?.toString();
      if (status == 'ok') {
        return HealthCheckResult(
          isHealthy: true,
          latencyMs: sw.elapsedMilliseconds,
          message: '运行正常 (${sw.elapsedMilliseconds}ms)',
        );
      }
      return HealthCheckResult(
        isHealthy: false,
        latencyMs: sw.elapsedMilliseconds,
        message: '状态异常: $status',
      );
    } catch (e) {
      sw.stop();
      return HealthCheckResult(
        isHealthy: false,
        latencyMs: sw.elapsedMilliseconds,
        message: '连接失败: $e',
      );
    }
  }

  /// 设置自动同步开关
  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, value);
    notifyListeners();
  }

  /// 修改本地设备名称
  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceName, name);
    notifyListeners();
  }

  /// 首次启用云同步：注册当前设备为新用户（主设备）
  Future<bool> registerCurrentDevice({String? deviceName}) async {
    final dName = deviceName ?? _deviceName ?? _defaultDeviceName();
    try {
      final res = await _request(
        '/api/device/register',
        method: 'POST',
        body: {'device_name': dName},
      );

      final data = res['data'] as Map<String, dynamic>;
      _userId = data['user_id'] as String?;
      _deviceId = data['device_id'] as String?;
      _deviceToken = data['device_token'] as String?;
      _passphrase = data['sync_passphrase'] as String?;
      _deviceName = dName;
      _enabled = true;
      _lastSyncTime = 0; // 重置游标，以便初次把本地做题记录完整推送到云端
      _lastError = null;

      await _persistConfig();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 生成临时 6 位数字配对码 (有效时限 10 分钟)
  Future<PairingCodeInfo> createPairingCode() async {
    if (!isConfigured) {
      throw StateError('当前设备尚未绑定云同步，无法生成配对码');
    }

    final res = await _request('/api/pair/create', method: 'POST', auth: true);

    final data = res['data'] as Map<String, dynamic>;
    final info = PairingCodeInfo(
      code: data['code'].toString(),
      expiresAt: (data['expires_at'] as num).toInt(),
      expiresInSeconds: (data['expires_in_seconds'] as num?)?.toInt() ?? 600,
    );

    // 持久化保存到本地，退出重进页面不丢失
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCachedPairCode, info.code);
    await prefs.setInt(_keyCachedPairExpiresAt, info.expiresAt);

    return info;
  }

  /// 获取当前活跃且未过期的配对码（优先本地持久化，辅以服务端回查）
  Future<PairingCodeInfo?> getActivePairingCode() async {
    if (!isConfigured) return null;
    final prefs = await SharedPreferences.getInstance();
    final cachedCode = prefs.getString(_keyCachedPairCode);
    final cachedExpiresAt = prefs.getInt(_keyCachedPairExpiresAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedCode != null && cachedCode.isNotEmpty && cachedExpiresAt > now) {
      final remaining = ((cachedExpiresAt - now) / 1000).ceil();
      return PairingCodeInfo(
        code: cachedCode,
        expiresAt: cachedExpiresAt,
        expiresInSeconds: remaining,
      );
    }

    // 若本地没有，向服务端查询当前设备签发的活跃配对码
    try {
      final res = await _request('/api/pair/active', method: 'GET', auth: true);
      final data = res['data'];
      if (data != null && data is Map<String, dynamic>) {
        final info = PairingCodeInfo(
          code: data['code'].toString(),
          expiresAt: (data['expires_at'] as num).toInt(),
          expiresInSeconds: (data['expires_in_seconds'] as num).toInt(),
        );
        await prefs.setString(_keyCachedPairCode, info.code);
        await prefs.setInt(_keyCachedPairExpiresAt, info.expiresAt);
        return info;
      }
    } catch (_) {}

    return null;
  }

  /// 新设备输入配对码进行认领兑换
  Future<bool> claimPairingCode(String code, {String? deviceName}) async {
    final dName = deviceName ?? _deviceName ?? _defaultDeviceName();
    try {
      final res = await _request(
        '/api/pair/claim',
        method: 'POST',
        body: {'code': code.trim(), 'device_name': dName},
      );

      final data = res['data'] as Map<String, dynamic>;
      _userId = data['user_id'] as String?;
      _deviceId = data['device_id'] as String?;
      _deviceToken = data['device_token'] as String?;
      _passphrase = data['sync_passphrase'] as String?;
      _deviceName = dName;
      _enabled = true;
      _lastSyncTime = 0; // 从 0 开始同步，完整拉取主设备的做题记录
      _lastError = null;

      await _persistConfig();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 使用备份恢复口令恢复绑定并找回进度
  Future<bool> restoreWithPassphrase(
    String passphrase, {
    String? deviceName,
  }) async {
    final dName = deviceName ?? _deviceName ?? _defaultDeviceName();
    try {
      final res = await _request(
        '/api/pair/restore-passphrase',
        method: 'POST',
        body: {
          'passphrase': passphrase.trim().toUpperCase(),
          'device_name': dName,
        },
      );

      final data = res['data'] as Map<String, dynamic>;
      _userId = data['user_id'] as String?;
      _deviceId = data['device_id'] as String?;
      _deviceToken = data['device_token'] as String?;
      _passphrase = data['sync_passphrase'] as String?;
      _deviceName = dName;
      _enabled = true;
      _lastSyncTime = 0;
      _lastError = null;

      await _persistConfig();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 执行双向增量同步 (Push & Pull)
  Future<SyncResult> sync({bool force = false}) async {
    if (!isConfigured) {
      return SyncResult(success: false, message: '未开启云同步');
    }
    if (_isSyncing) {
      return SyncResult(success: false, message: '正在同步中，请稍候');
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final userDb = await UserDBHelper().database;
      final prefs = await SharedPreferences.getInstance();

      // 上传只使用事务内变更序号；服务端时间只用于展示/旧拉取协议。
      final owner = _userId!;
      await CloudOutbox.bind(userDb, owner);
      var cursor = await CloudOutbox.pullCursor(userDb, owner, reset: force);
      final entries = await CloudOutbox.snapshot(userDb, owner);
      final totalQuestions = entries
          .where((e) => e['kind'] == 'question')
          .length;
      final totalActivities = entries.length - totalQuestions;
      const batchChunkSize = 500;
      final totalBatches = max(
        1,
        (entries.length + batchChunkSize - 1) ~/ batchChunkSize,
      );
      int serverTime = 0;
      final allPullActivities = <Map<String, dynamic>>[];
      final allPullQuestions = <Map<String, dynamic>>[];
      for (var i = 0; i < totalBatches; i++) {
        final chunk = entries
            .skip(i * batchChunkSize)
            .take(batchChunkSize)
            .toList();
        final mutations = <Map<String, Object?>>[];
        for (final entry in chunk) {
          mutations.add(await CloudOutbox.mutation(userDb, entry));
        }
        final res = await _request(
          '/api/sync',
          method: 'POST',
          auth: true,
          timeout: const Duration(seconds: 45),
          body: {'protocol': 2, 'pull_cursor': cursor, 'mutations': mutations},
        );
        final data = res['data'] as Map<String, dynamic>;
        if (data['protocol'] != 2 || data['accepted_seqs'] is! List) {
          throw const FormatException('云同步服务需升级至协议 v2，待上传数据已保留');
        }
        serverTime = (data['server_time'] as num).toInt();
        await userDb.transaction(
          (tx) => CloudOutbox.acknowledge(
            tx,
            owner,
            chunk.map((e) => e['seq'] as int).toList(),
            data['accepted_seqs'] as List,
          ),
        );
        await CloudOutbox.mergePage(userDb, owner, data, cursor);
        cursor = data['next_cursor'] as int;
        while (data['has_more'] == true) {
          final response = await _request(
            '/api/sync',
            method: 'POST',
            auth: true,
            timeout: const Duration(seconds: 45),
            body: {
              'protocol': 2,
              'mutations': [],
              'pull_cursor': cursor,
              'high_watermark': data['high_watermark'],
            },
          );
          final page = response['data'] as Map<String, dynamic>;
          await CloudOutbox.mergePage(userDb, owner, page, cursor);
          cursor = page['next_cursor'] as int;
          allPullActivities.addAll(
            (page['pull_activities'] as List).cast<Map<String, dynamic>>(),
          );
          allPullQuestions.addAll(
            (page['pull_questions'] as List).cast<Map<String, dynamic>>(),
          );
          data['has_more'] = page['has_more'];
        }
        allPullActivities.addAll(
          (data['pull_activities'] as List? ?? []).cast<Map<String, dynamic>>(),
        );
        allPullQuestions.addAll(
          (data['pull_questions'] as List? ?? []).cast<Map<String, dynamic>>(),
        );
      }

      // 数据已逐页原子合并；章节投影仍通过 ATTACH 聚合重算。
      if (allPullActivities.isNotEmpty || allPullQuestions.isNotEmpty) {
        final affectedBankIds = allPullActivities
            .map((a) => a['bank_id']?.toString())
            .whereType<String>()
            .toSet();
        final banks = await userDb.query('QuestionBank', columns: ['bank_id']);
        affectedBankIds.addAll(banks.map((b) => b['bank_id'] as String));
        final active = prefs.getString('activeBankId');
        if (active != null && active.isNotEmpty) affectedBankIds.add(active);
        for (final bank in affectedBankIds) {
          try {
            await rebuildQuestionCount(bankId: bank);
          } catch (e) {
            debugPrint('[cloud-sync] 重算题库 $bank 统计跳过: $e');
          }
        }
      }

      // 5. 更新本地同步游标
      _lastSyncTime = serverTime;
      await prefs.setInt(_keyLastSyncTime, _lastSyncTime);

      final result = SyncResult(
        success: true,
        pushedActivities: totalActivities,
        pushedQuestions: totalQuestions,
        pulledActivities: allPullActivities.length,
        pulledQuestions: allPullQuestions.length,
        syncTime: DateTime.fromMillisecondsSinceEpoch(
          serverTime > 0 ? serverTime : DateTime.now().millisecondsSinceEpoch,
        ),
      );

      debugPrint('[cloud-sync] $result');
      return result;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[cloud-sync] 同步异常: $e');
      return SyncResult(success: false, message: e.toString());
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 重置拉取游标重新对齐云端；已确认的本地变更不重复上传。
  Future<void> resetSyncCursor() async {
    _lastSyncTime = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSyncTime);
    if (_userId != null) {
      await CloudOutbox.pullCursor(
        await UserDBHelper().database,
        _userId!,
        reset: true,
      );
    }
    notifyListeners();
  }

  /// 解绑当前设备云同步
  Future<void> unbind() async {
    _enabled = false;
    _userId = null;
    _deviceId = null;
    _deviceToken = null;
    _passphrase = null;
    _lastSyncTime = 0;
    _lastError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyDeviceToken);
    await prefs.remove(_keyPassphrase);
    await prefs.remove(_keyLastSyncTime);
    await prefs.remove(_keyCachedPairCode);
    await prefs.remove(_keyCachedPairExpiresAt);

    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 内部辅助方法
  // ------------------------------------------------------------------
  Future<void> _persistConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _enabled);
    if (_userId != null) await prefs.setString(_keyUserId, _userId!);
    if (_deviceId != null) await prefs.setString(_keyDeviceId, _deviceId!);
    if (_deviceToken != null) {
      await prefs.setString(_keyDeviceToken, _deviceToken!);
    }
    if (_deviceName != null) {
      await prefs.setString(_keyDeviceName, _deviceName!);
    }
    if (_passphrase != null) {
      await prefs.setString(_keyPassphrase, _passphrase!);
    }
    await prefs.setInt(_keyLastSyncTime, _lastSyncTime);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final endpoints = [primaryEndpoint, fallbackEndpoint];
    Exception? lastEx;

    for (final base in endpoints) {
      final sw = Stopwatch()..start();
      final uri = Uri.parse('$base$path');
      try {
        debugPrint(
          '[cloud-sync] 发起请求: $method $uri (超时设置: ${timeout.inSeconds}s)',
        );
        final headers = <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
        };
        if (auth && _deviceToken != null) {
          headers['Authorization'] = 'Bearer $_deviceToken';
        }

        final http.Response res;
        final client = http.Client();
        try {
          if (method == 'POST') {
            res = await client
                .post(
                  uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null,
                )
                .timeout(timeout);
          } else {
            res = await client.get(uri, headers: headers).timeout(timeout);
          }
        } finally {
          client.close();
        }

        sw.stop();
        debugPrint(
          '[cloud-sync] 请求完成: $method $uri [${res.statusCode}] 耗时 ${sw.elapsedMilliseconds}ms',
        );

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          throw const FormatException('服务端返回的非有效 JSON 格式');
        } else {
          final rawBody = utf8.decode(res.bodyBytes);
          debugPrint(
            '[cloud-sync] 服务端响应非 2xx: HTTP ${res.statusCode}, 原始内容: $rawBody',
          );
          try {
            final errJson = jsonDecode(rawBody);
            final msg = errJson['message'] ?? errJson['error'] ?? rawBody;
            throw HttpException('HTTP ${res.statusCode}: $msg');
          } catch (e) {
            if (e is HttpException) rethrow;
            throw HttpException('请求失败: HTTP ${res.statusCode} ($rawBody)');
          }
        }
      } on HttpException catch (e) {
        sw.stop();
        // 关键：服务端明确返回了 HTTP 状态码（如 401 鉴权失败、500 服务端报错等）
        // 此时表明主节点网络连通正常，重试备用节点（同一个服务）毫无意义且会导致国内长时间挂起超时
        debugPrint(
          '[cloud-sync] 服务端响应错误 ($uri, 耗时 ${sw.elapsedMilliseconds}ms): $e',
        );
        rethrow;
      } on SocketException catch (e) {
        sw.stop();
        lastEx = e;
        debugPrint(
          '[cloud-sync] 网络连接异常 ($uri, 耗时 ${sw.elapsedMilliseconds}ms): $e',
        );
        continue;
      } on TimeoutException catch (e) {
        sw.stop();
        lastEx = e;
        debugPrint(
          '[cloud-sync] 请求超时 ($uri, 耗时 ${sw.elapsedMilliseconds}ms): $e',
        );
        continue;
      } catch (e) {
        sw.stop();
        lastEx = e is Exception ? e : Exception(e.toString());
        debugPrint(
          '[cloud-sync] 未知异常 ($uri, 耗时 ${sw.elapsedMilliseconds}ms): $e',
        );
        continue;
      }
    }

    throw lastEx ?? const HttpException('无法连接到云同步服务器，请检查网络设置');
  }

  static String _defaultDeviceName() {
    if (Platform.isAndroid) return 'Android 设备';
    if (Platform.isIOS) return 'iPhone / iPad';
    if (Platform.isMacOS) return 'Mac 设备';
    if (Platform.isWindows) return 'Windows 电脑';
    if (Platform.isLinux) return 'Linux 电脑';
    return '我的设备';
  }
}
