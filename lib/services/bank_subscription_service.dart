import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question_bank.dart';
import '../models/bank_source.dart';
import 'bank_source_store.dart';
import '../repositories/question_bank_repository.dart';
import 'bank_subscription_loader.dart';
import 'bank_artifact_cache.dart';
import 'question_bank_file_service.dart';

class BankSubscriptionService {
  static final instance = BankSubscriptionService();
  static const _urlsKey = 'bank_subscription_urls';
  static const _autoKey = 'bank_subscription_auto';
  static const _cacheKey = 'bank_subscription_entries';
  static const _overridesKey = 'bank_subscription_overrides';
  static const _intervalKey = 'bank_subscription_interval_minutes';
  static const _lastCheckKey = 'bank_subscription_last_check';
  final BankSubscriptionLoader loader;
  final store = BankSourceStore();
  final _checks = <String, Future<BankSource>>{};
  late final BankArtifactCache artifacts = BankArtifactCache(loader: loader);
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

  static String validateUrl(String value) => normalizeBankSourceUrl(value);

  Future<List<BankSource>> sources() async =>
      (await store.read()).sources.values.toList();

  Future<void> proposeBankSource(QuestionBank bank, String value) async {
    final source = BankSource.fresh(value);
    await store.change((catalog) {
      catalog.sources.putIfAbsent(source.id, () => source);
      catalog.pending[bank.bankId] = source.id;
    });
  }

  Future<void> selectSource(QuestionBank bank, String sourceId) async {
    final source = (await store.read()).sources[sourceId];
    final entry = source?.entry(bank.bankId);
    if (source == null ||
        source.status != BankSourceStatus.ready ||
        entry == null) {
      throw StateError('请先检查该来源');
    }
    if (bank.isInstalled &&
        entry['identity_id']?.toString() != bank.identityId) {
      throw const FormatException('来源学科与当前题库不一致');
    }
    await store.change((catalog) {
      catalog.bindings[bank.bankId] = sourceId;
      catalog.pending.remove(bank.bankId);
    });
    await QuestionBankRepository().registerRemoteEntries([entry]);
  }

  Future<List<BankSource>> check({String? bankId, String? sourceId}) async {
    final catalog = await store.read();
    final selectedId =
        sourceId ??
        (bankId == null
            ? null
            : catalog.pending[bankId] ?? catalog.bindings[bankId]);
    final selected = selectedId == null && bankId == null
        ? catalog.sources.values.toList()
        : [
            if (catalog.sources[selectedId] != null)
              catalog.sources[selectedId]!,
          ];
    final results = <BankSource>[];
    for (final source in selected) {
      final future = _checks.putIfAbsent(source.id, () => _checkSource(source));
      try {
        results.add(await future);
      } finally {
        if (identical(_checks[source.id], future)) _checks.remove(source.id);
      }
    }
    return results;
  }

  Future<BankSource> _checkSource(BankSource source) async {
    late BankSource result;
    try {
      result = await loader.check(source);
      await store.change((catalog) {
        if (!catalog.sources.containsKey(source.id)) return;
        catalog.sources[source.id] = result;
        for (final entry in result.entries) {
          catalog.bindings.putIfAbsent(
            entry['bank_id'] as String,
            () => source.id,
          );
        }
      });
      final catalog = await store.read();
      for (final entry in result.entries) {
        final id = entry['bank_id'] as String;
        if (catalog.pending[id] == source.id &&
            result.status == BankSourceStatus.ready) {
          final bank = await QuestionBankRepository().find(id);
          if (bank != null) await selectSource(bank, source.id);
        }
      }
      await QuestionBankRepository().registerRemoteEntries(
        result.entries
            .where((e) => catalog.bindings[e['bank_id'] as String] == source.id)
            .toList(),
      );
    } catch (error) {
      result = BankSource(
        url: source.url,
        official: source.official,
        kind: source.kind,
        status: BankSourceStatus.failed,
        entries: source.entries,
        checkedAt: DateTime.now().millisecondsSinceEpoch,
        successAt: source.successAt,
        error: error.toString(),
        etag: source.etag,
        lastModified: source.lastModified,
        transportUrl: source.transportUrl,
      );
      await store.change((catalog) {
        if (catalog.sources.containsKey(source.id)) {
          catalog.sources[source.id] = result;
        }
      });
    }
    return result;
  }

  Future<BankUpdateInfo> updateInfo(QuestionBank bank) async =>
      BankUpdateInfo.compare(bank, (await store.read()).sourceFor(bank.bankId));

  /// Explicit full download to identify a file source, never called by check().
  Future<BankSource> confirmSource(
    String sourceId, {
    DownloadProgressCallback? onProgress,
  }) async {
    final source = (await store.read()).sources[sourceId];
    if (source == null) throw StateError('来源已移除');
    final lease = await artifacts.acquire(
      source.url,
      refresh: source.status != BankSourceStatus.ready,
      onProgress: onProgress,
    );
    try {
      return await _publishArtifact(source, lease);
    } finally {
      await lease.dispose();
    }
  }

  Future<BankSource> _publishArtifact(
    BankSource source,
    BankArtifactLease lease,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = BankSource(
      url: source.url,
      official: source.official,
      kind: BankSourceKind.file,
      status: BankSourceStatus.ready,
      entries: [
        {...lease.entry, 'subscription_url': source.url},
      ],
      checkedAt: now,
      successAt: now,
      etag: lease.etag,
      lastModified: lease.lastModified,
      transportUrl: source.url,
    );
    await store.change((catalog) {
      if (!catalog.sources.containsKey(source.id)) return;
      catalog.sources[source.id] = result;
      catalog.bindings.putIfAbsent(
        lease.entry['bank_id'] as String,
        () => source.id,
      );
    });
    final catalog = await store.read();
    if (catalog.bindings[lease.entry['bank_id']] == source.id) {
      await QuestionBankRepository().registerRemoteEntries(result.entries);
    }
    return result;
  }

  Future<QuestionBank> importLink(
    String value, {
    required bool subscribe,
    Future<BankImportMode?> Function(QuestionBank existing)? onConflict,
    DownloadProgressCallback? onProgress,
  }) async {
    final url = validateUrl(value);
    final lease = await artifacts.acquire(
      url,
      refresh: true,
      onProgress: onProgress,
    );
    try {
      final entry = lease.entry;
      final bank = await QuestionBankRepository().importFile(
        lease.file.path,
        expectedBankId: entry['bank_id'] as String,
        expectedIdentityId: entry['identity_id']?.toString(),
        expectedSqliteHash: entry['sqlite_sha256'] as String?,
        versionOverride: entry['version']?.toString(),
        onConflict: onConflict,
      );
      if (subscribe) {
        final fresh = BankSource.fresh(url);
        await store.change(
          (catalog) => catalog.sources.putIfAbsent(fresh.id, () => fresh),
        );
        await _publishArtifact(fresh, lease);
        await selectSource(bank, fresh.id);
      }
      return bank;
    } finally {
      await lease.dispose();
    }
  }

  Future<QuestionBank> install(
    String bankId, {
    Future<BankImportMode?> Function(QuestionBank existing)? onConflict,
    DownloadProgressCallback? onProgress,
  }) async {
    var source = (await store.read()).sourceFor(bankId);
    if (source == null) throw StateError('尚未设置题库来源');
    if (source.kind == BankSourceKind.file &&
        source.status != BankSourceStatus.ready) {
      source = await confirmSource(source.id, onProgress: onProgress);
    }
    final entry = source.entry(bankId);
    if (entry == null) throw const FormatException('来源中未找到该题库');
    final lease = await artifacts.acquire(
      entry['url'] as String,
      expected: entry,
      onProgress: onProgress,
    );
    try {
      return await QuestionBankRepository().importFile(
        lease.file.path,
        expectedBankId: bankId,
        expectedIdentityId: entry['identity_id']?.toString(),
        expectedSqliteHash: entry['sqlite_sha256'] as String?,
        versionOverride: entry['version']?.toString(),
        updateEnabled: true,
        onConflict: onConflict,
      );
    } finally {
      await lease.dispose();
    }
  }

  Future<void> save(List<String> values, bool auto) async {
    await saveSources(values);
    await (await SharedPreferences.getInstance()).setBool(_autoKey, auto);
  }

  Future<void> saveSources(List<String> values) async {
    if (_running) throw StateError('订阅正在检查，请稍后保存');
    final normalized = values.map(validateUrl).toSet().toList();
    await store.change((catalog) {
      final wanted = normalized.map((url) => BankSource.fresh(url)).toList();
      final retainedIds = wanted.map((s) => s.id).toSet();
      final removedIds = catalog.sources.values
          .where(
            (s) =>
                !s.official &&
                !retainedIds.contains(s.id) &&
                !catalog.pending.containsValue(s.id),
          )
          .map((s) => s.id)
          .toSet();
      catalog.sources.removeWhere((id, _) => removedIds.contains(id));
      for (final id in catalog.bindings.keys.toList()) {
        if (removedIds.contains(catalog.bindings[id])) {
          catalog.bindings[id] = '';
        }
      }
      for (final source in wanted) {
        catalog.sources.putIfAbsent(source.id, () => source);
      }
    });
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
      await check();
      await (await SharedPreferences.getInstance()).setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('[bank-subscription] $error');
    }
  }
}
