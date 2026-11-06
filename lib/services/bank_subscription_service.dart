import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import 'bank_subscription_loader.dart';

class BankSubscriptionService {
  static final instance = BankSubscriptionService();
  static const _urlsKey = 'bank_subscription_urls';
  static const _autoKey = 'bank_subscription_auto';
  static const _cacheKey = 'bank_subscription_entries';
  static const _overridesKey = 'bank_subscription_overrides';
  static const _intervalKey = 'bank_subscription_interval_minutes';
  static const _lastCheckKey = 'bank_subscription_last_check';
  final BankSubscriptionLoader loader;
  Timer? _timer;
  bool _running = false;
  int _scheduleRevision = 0;

  BankSubscriptionService({BankSubscriptionLoader? loader})
    : loader = loader ?? BankSubscriptionLoader();

  Future<List<String>> urls() async =>
      (await SharedPreferences.getInstance()).getStringList(_urlsKey) ?? [];

  Future<bool> automatic() async =>
      (await SharedPreferences.getInstance()).getBool(_autoKey) ?? false;

  Future<int> intervalMinutes() async =>
      ((await SharedPreferences.getInstance()).getInt(_intervalKey) ?? 360)
          .clamp(1, 10080);

  Future<Map<String, String>> _overrides() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _overridesKey,
    );
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static String validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的 HTTPS 题库链接或订阅清单地址');
    }
    return uri.toString();
  }

  Future<void> save(List<String> values, bool auto) async {
    await saveSources(values);
    await (await SharedPreferences.getInstance()).setBool(_autoKey, auto);
  }

  Future<void> saveSources(List<String> values) async {
    if (_running) throw StateError('订阅正在检查，请稍后保存');
    final normalized = values.map(validateUrl).toSet().toList();
    final overrides = await _overrides();
    final retained = {...normalized, ...overrides.values};
    final prefs = await SharedPreferences.getInstance();
    final previousEntries = await cached();
    final removed = previousEntries
        .where((entry) => !retained.contains(entry['subscription_url']))
        .toList();
    if (removed.isNotEmpty) {
      await QuestionBankRepository().removeRemoteEntries(removed);
    }
    await prefs.setStringList(_urlsKey, normalized);
    await prefs.setString(
      _cacheKey,
      jsonEncode(
        previousEntries
            .where((entry) => retained.contains(entry['subscription_url']))
            .toList(),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> cached() async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> sourceFor(QuestionBank bank) async {
    final override = (await _overrides())[bank.bankId];
    if (override != null) return override;
    final entries = await cached();
    return entries
            .where((entry) => entry['bank_id'] == bank.bankId)
            .firstOrNull?['subscription_url']
            ?.toString() ??
        bank.remoteUrl;
  }

  /// A per-bank override does not edit other banks from a shared manifest.
  Future<void> setBankSource(QuestionBank bank, String value) async {
    if (_running) throw StateError('订阅正在检查，请稍后修改');
    final url = validateUrl(value);
    _running = true;
    BankSubscriptionDownload? loaded;
    try {
      loaded = await loader.load(url);
      final entry = loaded.entries
          .where((r) => r['bank_id'] == bank.bankId)
          .firstOrNull;
      if (entry == null) throw const FormatException('该链接不包含当前题库，请检查链接是否正确');
      if (bank.isInstalled &&
          entry['identity_id']?.toString() != bank.identityId) {
        throw const FormatException('该链接的学科与当前题库不一致');
      }
      final overrides = await _overrides();
      overrides[bank.bankId] = url;
      final prefs = await SharedPreferences.getInstance();
      final entries = await cached();
      entries.removeWhere((r) => r['bank_id'] == bank.bankId);
      entries.add(entry);
      await QuestionBankRepository().registerRemoteEntries([entry]);
      await prefs.setString(_overridesKey, jsonEncode(overrides));
      await prefs.setString(_cacheKey, jsonEncode(entries));
    } finally {
      if (loaded != null) await loaded.dispose();
      _running = false;
    }
  }

  static List<Map<String, dynamic>> parseManifest(
    Object? value,
    String source,
  ) {
    if (value is! Map) throw const FormatException('订阅内容必须是 JSON 清单');
    final nested = value['question_banks'];
    final raw = value['banks'] ?? (nested is Map ? nested['banks'] : nested);
    if (raw is! List) throw const FormatException('订阅清单缺少题库列表');
    final seen = <String>{};
    return raw.map((item) {
      if (item is! Map) throw const FormatException('题库条目格式无效');
      final entry = Map<String, dynamic>.from(item);
      final id = entry['bank_id']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || !seen.add(id)) {
        throw const FormatException('题库标识非法或重复');
      }
      entry['url'] = validateUrl(entry['url']?.toString() ?? '');
      entry['bank_id'] = id;
      if (entry['identity_id'] == null ||
          !RegExp(r'^\d+$').hasMatch(entry['identity_id'].toString())) {
        throw const FormatException('订阅清单缺少学科编号');
      }
      if (entry['version']?.toString().isNotEmpty != true ||
          int.tryParse('${entry['schema_version'] ?? ''}') != 1) {
        throw const FormatException('订阅题库缺少版本或格式版本不受支持');
      }
      final sqliteHash = entry['sqlite_sha256'];
      if (sqliteHash != null &&
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sqliteHash.toString())) {
        throw const FormatException('题库校验信息无效');
      }
      if (sqliteHash != null) {
        entry['sqlite_sha256'] = sqliteHash.toString().toLowerCase();
      }
      if (!RegExp(
        r'^[a-fA-F0-9]{64}$',
      ).hasMatch(entry['sha256']?.toString() ?? '')) {
        throw const FormatException('订阅题库缺少有效校验信息');
      }
      entry['sha256'] = entry['sha256'].toString().toLowerCase();
      entry['subscription_url'] = source;
      entry['source_type'] = 'manifest';
      return entry;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> refresh({
    bool installUpdates = false,
    String? bankId,
  }) async {
    if (_running) throw StateError('订阅正在更新');
    _running = true;
    final downloads = <String, BankSubscriptionDownload>{};
    try {
      final overrides = await _overrides();
      final sources = {...await urls(), ...overrides.values};
      if (bankId != null) {
        final bank = await QuestionBankRepository().find(bankId);
        if (bank == null) throw StateError('题库不存在');
        final source = await sourceFor(bank);
        if (source == null) throw StateError('尚未设置订阅链接');
        sources.clear();
        sources.add(source);
      }
      final entries = <String, Map<String, dynamic>>{};
      for (final url in sources) {
        final loaded = await loader.load(url);
        downloads[url] = loaded;
        for (final entry in loaded.entries) {
          final id = entry['bank_id'] as String;
          if (bankId != null && id != bankId) continue;
          if (overrides[id] != null && overrides[id] != url) continue;
          if (entries.containsKey(id)) throw FormatException('多个订阅包含相同题库：$id');
          entries[id] = entry;
        }
      }
      if (bankId != null && !entries.containsKey(bankId)) {
        throw const FormatException('订阅链接中未找到该题库');
      }
      final result = entries.values.toList();
      final repository = QuestionBankRepository();
      final previous = await cached();
      if (bankId == null) {
        final removed = previous
            .where((entry) => !entries.containsKey(entry['bank_id']))
            .toList();
        if (removed.isNotEmpty) await repository.removeRemoteEntries(removed);
      }
      await repository.registerRemoteEntries(result);
      final cache = bankId == null
          ? result
          : [
              ...previous.where((entry) => entry['bank_id'] != bankId),
              ...result,
            ];
      await (await SharedPreferences.getInstance()).setString(
        _cacheKey,
        jsonEncode(cache),
      );
      if (installUpdates) {
        for (final entry in result) {
          final bank = await repository.find(entry['bank_id'] as String);
          if (bank == null || !bank.isInstalled) continue;
          // Manual update is explicit even for a previously frozen bank.
          final check = bankId != null
              ? bank.copyWith(updateEnabled: true)
              : bank;
          if (!repository.hasUpdate(check, entry)) continue;
          final artifact =
              downloads[entry['subscription_url']]?.artifacts[bank.bankId];
          if (artifact != null) {
            await repository.importFile(
              artifact.path,
              expectedBankId: bank.bankId,
              expectedIdentityId: bank.identityId,
              expectedSqliteHash: entry['sqlite_sha256'] as String?,
              versionOverride: entry['version']?.toString(),
              updateEnabled: true,
            );
          } else {
            await repository.downloadBank(bank.bankId, remoteEntry: entry);
          }
        }
      }
      return result;
    } finally {
      for (final loaded in downloads.values) {
        await loaded.dispose();
      }
      _running = false;
    }
  }

  Future<void> configureAutomatic(bool enabled, int minutes) async {
    if (minutes < 1 || minutes > 10080) {
      throw const FormatException('检查间隔需为 1～10080 分钟');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, enabled);
    await prefs.setInt(_intervalKey, minutes);
    await _schedule();
  }

  Future<bool> isDue(DateTime now) async {
    final last = (await SharedPreferences.getInstance()).getInt(_lastCheckKey);
    return last == null ||
        now.millisecondsSinceEpoch - last >=
            Duration(minutes: await intervalMinutes()).inMilliseconds;
  }

  /// Timers run while the application is open; startup covers overdue checks.
  void start() => unawaited(_schedule());

  void stop() {
    _scheduleRevision++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _schedule() async {
    final revision = ++_scheduleRevision;
    _timer?.cancel();
    final minutes = await intervalMinutes();
    if (!await automatic() || revision != _scheduleRevision) return;
    unawaited(_checkAutomatically());
    _timer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(_checkAutomatically()),
    );
  }

  Future<void> _checkAutomatically() async {
    if (!await automatic() || _running || !await isDue(DateTime.now())) return;
    if ((await urls()).isEmpty && (await _overrides()).isEmpty) return;
    try {
      await refresh(installUpdates: true);
      await (await SharedPreferences.getInstance()).setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('[bank-subscription] $error');
    }
  }
}
