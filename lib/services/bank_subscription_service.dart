import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/question_bank_repository.dart';

class BankSubscriptionService {
  static final instance = BankSubscriptionService();
  static const _urlsKey = 'bank_subscription_urls';
  static const _autoKey = 'bank_subscription_auto';
  static const _cacheKey = 'bank_subscription_entries';
  Timer? _timer;
  bool _running = false;

  Future<List<String>> urls() async =>
      (await SharedPreferences.getInstance()).getStringList(_urlsKey) ?? [];

  Future<bool> automatic() async =>
      (await SharedPreferences.getInstance()).getBool(_autoKey) ?? false;

  static String validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的 HTTPS 订阅清单地址');
    }
    return uri.toString();
  }

  Future<void> save(List<String> values, bool auto) async {
    final normalized = values.map(validateUrl).toSet().toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_urlsKey, normalized);
    await prefs.setBool(_autoKey, auto);
    // Removed subscriptions must not leave cached download entries behind.
    await prefs.remove(_cacheKey);
  }

  Future<List<Map<String, dynamic>>> cached() async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> parseManifest(Object? value, String source) {
    if (value is! Map) throw const FormatException('订阅内容必须是 JSON 清单');
    final nested = value['question_banks'];
    final raw = value['banks'] ?? (nested is Map ? nested['banks'] : nested);
    if (raw is! List) throw const FormatException('订阅清单缺少 banks');
    final seen = <String>{};
    return raw.map((item) {
      if (item is! Map) throw const FormatException('题库条目格式无效');
      final entry = Map<String, dynamic>.from(item);
      final id = entry['bank_id']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || !seen.add(id)) {
        throw const FormatException('题库标识非法或重复');
      }
      validateUrl(entry['url']?.toString() ?? '');
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry['sha256']?.toString() ?? '')) {
        throw const FormatException('订阅题库缺少有效 SHA-256');
      }
      entry['sha256'] = entry['sha256'].toString().toLowerCase();
      entry['subscription_url'] = source;
      return entry;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> refresh({bool installUpdates = false}) async {
    if (_running) throw StateError('订阅正在更新');
    _running = true;
    try {
      final entries = <String, Map<String, dynamic>>{};
      for (final url in await urls()) {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) throw StateError('订阅请求失败：HTTP ${response.statusCode}');
        for (final entry in parseManifest(jsonDecode(utf8.decode(response.bodyBytes)), url)) {
          final id = entry['bank_id'] as String;
          if (entries.containsKey(id)) throw FormatException('多个订阅包含相同题库：$id');
          entries[id] = entry;
        }
      }
      final result = entries.values.toList();
      final repository = QuestionBankRepository();
      await repository.registerRemoteEntries(result);
      await (await SharedPreferences.getInstance()).setString(_cacheKey, jsonEncode(result));
      if (installUpdates) {
        for (final entry in result) {
          final bank = await repository.find(entry['bank_id'] as String);
          if (bank != null && bank.isInstalled && repository.hasUpdate(bank, entry)) {
            await repository.downloadBank(bank.bankId, remoteEntry: entry);
          }
        }
      }
      return result;
    } finally {
      _running = false;
    }
  }

  /// Timers run while the application is open; startup covers overdue checks.
  void start() {
    _timer?.cancel();
    unawaited(_checkAutomatically());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(_checkAutomatically()));
  }

  Future<void> _checkAutomatically() async {
    if (!await automatic() || _running) return;
    try {
      await refresh(installUpdates: true);
    } catch (error) {
      debugPrint('[bank-subscription] $error');
    }
  }
}
