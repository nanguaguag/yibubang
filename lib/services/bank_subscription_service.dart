import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question_bank.dart';
import '../models/bank_source.dart';
import '../models/bank_content_state.dart';
import '../models/bank_download_task.dart';
import 'bank_source_store.dart';
import '../repositories/question_bank_repository.dart';
import 'bank_subscription_loader.dart';
import 'bank_artifact_cache.dart';
import 'question_bank_file_service.dart';

class BankSubscriptionService extends ChangeNotifier {
  static final instance = BankSubscriptionService();
  static const _urlsKey = 'bank_subscription_urls';
  static const _autoKey = 'bank_subscription_auto';
  static const _autoInstallKey = 'bank_subscription_auto_install';
  static const _intervalKey = 'bank_subscription_interval_minutes';
  static const _lastCheckKey = 'bank_subscription_last_check';
  final BankSubscriptionLoader loader;
  final store = BankSourceStore();
  final _checks = <String, Future<BankSource>>{};
  late final BankArtifactCache artifacts;
  Timer? _timer;
  bool _running = false;
  int _scheduleRevision = 0;

  BankSubscriptionService({
    BankSubscriptionLoader? loader,
    BankArtifactCache? cache,
  }) : loader = loader ?? BankSubscriptionLoader() {
    artifacts = cache ?? BankArtifactCache(loader: this.loader);
  }

  Future<List<String>> urls() async => (await sources())
      .where((source) => !source.official)
      .map((source) => source.url)
      .toList();

  Future<bool> automatic() async =>
      (await SharedPreferences.getInstance()).getBool(_autoKey) ?? false;

  Future<bool> automaticInstallation() async =>
      (await SharedPreferences.getInstance()).getBool(_autoInstallKey) ?? false;

  Future<int> intervalMinutes() async =>
      ((await SharedPreferences.getInstance()).getInt(_intervalKey) ?? 360)
          .clamp(1, 10080);

  static String validateUrl(String value) => normalizeBankSourceUrl(value);

  Future<List<BankSource>> sources() async =>
      (await store.read()).sources.values.where((s) => s.active).toList();

  Future<bool> addSource(String value) async {
    final source = BankSource.fresh(value);
    final added = await store.change((catalog) {
      if (catalog.sources[source.id]?.active == true) return false;
      catalog.sources[source.id] = source;
      return true;
    });
    if (added) notifyListeners();
    return added;
  }

  Future<void> editSource(BankSource source, String value) async {
    final replacement = BankSource.fresh(value);
    if (replacement.id == source.id) return;
    await store.change((catalog) {
      if (catalog.sources[replacement.id]?.active != true) {
        catalog.sources[replacement.id] = replacement;
      }
      for (final bankId in catalog.bindings.keys) {
        if (catalog.bindings[bankId] == source.id) {
          catalog.pending[bankId] = replacement.id;
        }
      }
      if (!catalog.bindings.containsValue(source.id)) {
        catalog.sources[source.id] = BankSource.fromJson({
          ...source.toJson(),
          'active': false,
        });
      }
    });
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    final active = await sources();
    await saveSources(
      active.where((s) => !s.official && s.id != id).map((s) => s.url).toList(),
    );
  }

  Future<void> proposeBankSource(QuestionBank bank, String value) async {
    final source = BankSource.fresh(value);
    await store.change((catalog) {
      if (catalog.sources[source.id]?.active != true) {
        catalog.sources[source.id] = source;
      }
      catalog.pending[bank.bankId] = source.id;
    });
    notifyListeners();
  }

  Future<void> selectSource(QuestionBank bank, String sourceId) async {
    final source = (await store.read()).sources[sourceId];
    final entry = source?.entry(bank.bankId);
    if (source == null ||
        !source.active ||
        source.status != BankSourceStatus.ready ||
        entry == null) {
      throw StateError('请先检查该来源');
    }
    final current = await QuestionBankRepository().find(bank.bankId) ?? bank;
    if (current.isInstalled &&
        entry['identity_id']?.toString() != current.identityId) {
      throw const FormatException('来源学科与当前题库不一致');
    }
    await store.change((catalog) {
      catalog.bindings[bank.bankId] = sourceId;
      catalog.pending.remove(bank.bankId);
    });
    await QuestionBankRepository().registerRemoteEntries([entry]);
    notifyListeners();
  }

  Future<List<BankSource>> check({String? bankId, String? sourceId}) async {
    final catalog = await store.read();
    final selectedId =
        sourceId ??
        (bankId == null
            ? null
            : catalog.pending[bankId] ?? catalog.bindings[bankId]);
    final selected = selectedId == null && bankId == null
        ? catalog.sources.values.where((s) => s.active).toList()
        : [
            if (catalog.sources[selectedId]?.active == true)
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
        if (catalog.sources[source.id]?.active != true) return;
        catalog.sources[source.id] = result;
        for (final entry in result.entries) {
          catalog.bindings.putIfAbsent(
            entry['bank_id'] as String,
            () => source.id,
          );
        }
      });
      final catalog = await store.read();
      await QuestionBankRepository().registerRemoteEntries(
        result.entries
            .where((e) => catalog.bindings[e['bank_id'] as String] == source.id)
            .toList(),
      );
    } catch (error, trace) {
      debugPrint('[bank-check] ${source.name}: $error\n$trace');
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
        if (catalog.sources[source.id]?.active == true) {
          catalog.sources[source.id] = result;
        }
      });
    }
    notifyListeners();
    return result;
  }

  Future<BankUpdateInfo> updateInfo(QuestionBank bank) async {
    final source = (await store.read()).sourceFor(bank.bankId);
    var state = await QuestionBankRepository().contentState(bank.bankId);
    final entry = source?.entry(bank.bankId);
    if (bank.isInstalled &&
        entry != null &&
        entry['sqlite_sha256'] == bank.contentHash &&
        !state.hasBaseline) {
      await QuestionBankRepository().establishBaseline(
        bank,
        BankRelease.fromEntry(source!.id, entry),
      );
      state = await QuestionBankRepository().contentState(bank.bankId);
    }
    final info = BankUpdateInfo.compare(bank, source, content: state);
    return BankUpdateInfo(
      info.status,
      source: source,
      entry: info.entry,
      message: info.message,
      content: state,
    );
  }

  /// Explicit full download to identify a file source, never called by check().
  Future<BankSource> confirmSource(
    String sourceId, {
    DownloadProgressCallback? onProgress,
    BankDownloadTask? task,
  }) async {
    final source = (await store.read()).sources[sourceId];
    if (source == null || !source.active) throw StateError('来源已移除');
    final lease = await artifacts.acquire(
      source.url,
      refresh: source.status != BankSourceStatus.ready,
      onProgress: onProgress,
      task: task,
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
      transportUrl: lease.transportUrl ?? source.url,
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
    notifyListeners();
    return result;
  }

  Future<QuestionBank> importLink(
    String value, {
    required bool subscribe,
    Future<BankImportMode?> Function(QuestionBank existing)? onConflict,
    DownloadProgressCallback? onProgress,
    BankDownloadTask? task,
  }) async {
    final url = validateUrl(value);
    final lease = await artifacts.acquire(
      url,
      refresh: true,
      onProgress: onProgress,
      task: task,
    );
    try {
      final entry = lease.entry;
      final bank = await QuestionBankRepository().importFile(
        lease.file.path,
        expectedBankId: entry['bank_id'] as String,
        expectedIdentityId: entry['identity_id']?.toString(),
        expectedSqliteHash: entry['sqlite_sha256'] as String?,
        versionOverride: entry['version']?.toString(),
        upstream: subscribe
            ? BankRelease.fromEntry(BankSource.fresh(url).id, entry)
            : null,
        onConflict: onConflict,
        onInstallReady: task?.beginInstallation,
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
    Future<BankImportMode?> Function(
      QuestionBank existing,
      BankUpdateInfo info,
      BankContentDiff diff,
    )?
    onResolve,
    DownloadProgressCallback? onProgress,
    BankDownloadTask? task,
    bool redownload = false,
    bool automatic = false,
  }) async {
    var source = (await store.read()).sourceFor(bankId);
    if (source == null) throw StateError('尚未设置题库来源');
    BankArtifactLease? confirmedLease;
    if (source.kind == BankSourceKind.file &&
        source.status != BankSourceStatus.ready) {
      confirmedLease = await artifacts.acquire(
        source.url,
        refresh: true,
        onProgress: onProgress,
        task: task,
      );
      try {
        source = await _publishArtifact(source, confirmedLease);
      } catch (_) {
        await confirmedLease.dispose();
        rethrow;
      }
    }
    final entry = source.entry(bankId);
    if (entry == null) {
      await confirmedLease?.dispose();
      throw const FormatException('来源中未找到该题库');
    }
    final existing = await QuestionBankRepository().find(bankId);
    if (existing?.isInstalled == true &&
        entry['identity_id']?.toString() != existing!.identityId) {
      await confirmedLease?.dispose();
      throw const FormatException('来源学科与已安装题库不一致');
    }
    final lease =
        confirmedLease ??
        await artifacts.acquire(
          entry['url'] as String,
          expected: entry,
          refresh: redownload,
          onProgress: onProgress,
          task: task,
        );
    try {
      task?.checkCancelled();
      final repository = QuestionBankRepository();
      final current = await repository.find(bankId);
      final upstream = BankRelease.fromEntry(source.id, entry);
      final release = BankRelease(
        sourceId: upstream.sourceId,
        version: upstream.version,
        releaseId: upstream.releaseId,
        packageHash: upstream.packageHash,
        sqliteHash: lease.entry['sqlite_sha256'] as String?,
      );
      if (current?.isInstalled == true && !redownload) {
        final state = await repository.contentState(bankId);
        if (state.baseRelease == release.releaseId ||
            current!.contentHash == release.sqliteHash) {
          if (!state.hasBaseline) {
            await repository.establishBaseline(current!, release);
          }
          return current!;
        }
      }
      final installed = await QuestionBankRepository().importFile(
        lease.file.path,
        expectedBankId: bankId,
        expectedIdentityId: entry['identity_id']?.toString(),
        expectedSqliteHash: entry['sqlite_sha256'] as String?,
        versionOverride: entry['version']?.toString(),
        updateEnabled: true,
        upstream: release,
        onInstallReady: task?.beginInstallation,
        onConflict: (existing) async {
          task?.checkCancelled();
          if (entry['identity_id']?.toString() != existing.identityId) {
            throw const FormatException('来源学科与已安装题库不一致');
          }
          final state = await repository.contentState(bankId);
          final info = BankUpdateInfo.compare(existing, source, content: state);
          final unsafe =
              state.hasLocalChanges(existing.contentHash) ||
              [
                BankUpdateStatus.needsComparison,
                BankUpdateStatus.changed,
                BankUpdateStatus.rollback,
              ].contains(info.status);
          if (unsafe) {
            if (automatic) throw StateError('该题库需要手动处理本地内容或来源变更');
            if (onResolve != null) {
              task?.report('等待确认更新');
              final choice = await onResolve(
                existing,
                info,
                await _diff(existing, lease),
              );
              task?.checkCancelled();
              return choice;
            }
            if (onConflict != null) return onConflict(existing);
            throw StateError('请确认合并或替换后再更新');
          }
          return BankImportMode.replace;
        },
      );
      notifyListeners();
      return installed;
    } finally {
      await lease.dispose();
    }
  }

  Future<BankContentDiff> _diff(
    QuestionBank bank,
    BankArtifactLease lease,
  ) async {
    if (lease.file.path.endsWith('.sqlite')) {
      return QuestionBankFileService.diff(bank.localPath, lease.file.path);
    }
    final directory = await Directory.systemTemp.createTemp('bank-diff-');
    try {
      final archive = ZipDecoder().decodeBytes(await lease.file.readAsBytes());
      final content = archive
          .where(
            (entry) =>
                entry.isFile &&
                p.extension(entry.name).toLowerCase() == '.sqlite',
          )
          .single;
      final file = File(p.join(directory.path, 'incoming.sqlite'));
      await file.writeAsBytes(content.content as List<int>);
      return await QuestionBankFileService.diff(bank.localPath, file.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> save(List<String> values, bool auto) async {
    await saveSources(values);
    await (await SharedPreferences.getInstance()).setBool(_autoKey, auto);
  }

  Future<void> saveSources(List<String> values) async {
    if (_running) throw StateError('订阅正在检查，请稍后保存');
    final normalized = values.map(validateUrl).toSet().toList();
    final removed = <Map<String, dynamic>>[];
    await store.change((catalog) {
      final wanted = normalized.map((url) => BankSource.fresh(url)).toList();
      final retainedIds = wanted.map((s) => s.id).toSet();
      final removedIds = catalog.sources.values
          .where((s) => s.active && !s.official && !retainedIds.contains(s.id))
          .map((s) => s.id)
          .toSet();
      for (final id in removedIds) {
        final source = catalog.sources[id]!;
        removed.addAll(
          source.entries.where((e) => catalog.bindings[e['bank_id']] == id),
        );
        catalog.sources[id] = BankSource.fromJson({
          ...source.toJson(),
          'active': false,
        });
      }
      for (final id in catalog.bindings.keys.toList()) {
        if (removedIds.contains(catalog.bindings[id])) {
          catalog.bindings[id] = '';
        }
      }
      catalog.pending.removeWhere(
        (_, sourceId) => removedIds.contains(sourceId),
      );
      for (final source in wanted) {
        final existing = catalog.sources[source.id];
        catalog.sources[source.id] = existing == null
            ? source
            : BankSource.fromJson({...existing.toJson(), 'active': true});
      }
    });
    if (removed.isNotEmpty) {
      await QuestionBankRepository().removeRemoteEntries(removed);
    }
    await (await SharedPreferences.getInstance()).setStringList(
      _urlsKey,
      normalized,
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> cached() async {
    final catalog = await store.read();
    return [
      for (final source in catalog.sources.values.where((s) => s.active))
        for (final entry in source.entries)
          if (catalog.bindings[entry['bank_id']] == source.id) entry,
    ];
  }

  Future<String?> sourceFor(QuestionBank bank) async {
    final catalog = await store.read();
    return catalog.sourceFor(bank.bankId)?.url;
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

  Future<void> configureAutomatic(
    bool enabled,
    int minutes, {
    bool? install,
  }) async {
    if (minutes < 1 || minutes > 10080) {
      throw const FormatException('检查间隔需为 1～10080 分钟');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, enabled);
    await prefs.setInt(_intervalKey, minutes);
    if (install != null) await prefs.setBool(_autoInstallKey, install);
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
    unawaited(checkAutomatically());
    _timer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(checkAutomatically()),
    );
  }

  Future<void> checkAutomatically() async {
    if (!await automatic() || _running || !await isDue(DateTime.now())) return;
    _running = true;
    try {
      await check();
      if (await automaticInstallation()) {
        final repository = QuestionBankRepository();
        for (final bank in await repository.listBanks()) {
          if (!bank.isInstalled || !bank.updateEnabled) continue;
          final state = await repository.contentState(bank.bankId);
          if (!state.hasBaseline || state.hasLocalChanges(bank.contentHash)) {
            continue;
          }
          try {
            final info = await updateInfo(bank);
            if (info.status == BankUpdateStatus.available ||
                info.status == BankUpdateStatus.needsDownload) {
              await install(bank.bankId, automatic: true);
            }
          } catch (error) {
            debugPrint('[bank-auto-install] ${bank.bankId}: $error');
          }
        }
      }
      await (await SharedPreferences.getInstance()).setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('[bank-subscription] $error');
    } finally {
      _running = false;
    }
  }
}
