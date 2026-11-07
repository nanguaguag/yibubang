import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../common/github_proxy.dart';
import '../models/bank_source.dart';
import '../repositories/question_bank_repository.dart';

/// Subscription configuration lives in the application's writable metadata.
/// Serialize mutations across services/pages to avoid lost bindings/results.
class BankSourceStore {
  static const key = 'bank_source_catalog_v1';
  static Future<void> _tail = Future.value();

  Future<BankSourceCatalog> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null) {
      return BankSourceCatalog.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    }
    final sources = <String, BankSource>{};
    final bindings = <String, String>{};
    final official = BankSource(
      url: GitHubProxyConfig.rawBaseUrl,
      official: true,
      kind: BankSourceKind.manifest,
      entries: QuestionBankRepository.configuredRemoteBanks.values
          .map((e) => {...e, 'subscription_url': GitHubProxyConfig.rawBaseUrl})
          .toList(),
    );
    sources[official.id] = official;
    for (final entry in official.entries) {
      bindings[entry['bank_id'] as String] = official.id;
    }
    final urls = <String>{
      ...prefs.getStringList('bank_subscription_urls') ?? [],
    };
    final overridesRaw = prefs.getString('bank_subscription_overrides');
    final overrides = overridesRaw == null
        ? <String, String>{}
        : Map<String, String>.from(jsonDecode(overridesRaw) as Map);
    urls.addAll(overrides.values);
    final entriesRaw = prefs.getString('bank_subscription_entries');
    final entries = entriesRaw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(entriesRaw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    for (final entry in entries) {
      final url = entry['subscription_url']?.toString();
      if (url != null) urls.add(url);
    }
    for (final url in urls) {
      final fresh = BankSource.fresh(url);
      if (sources.containsKey(fresh.id)) continue;
      final cached = entries
          .where((e) => e['subscription_url'] == url)
          .toList();
      sources[fresh.id] = BankSource(
        url: fresh.url,
        kind: cached.firstOrNull?['source_type'] == 'file'
            ? BankSourceKind.file
            : fresh.kind,
        entries: cached,
      ); // Old cache is not a new successful network check.
      for (final entry in cached) {
        final id = entry['bank_id'] as String;
        if (overrides[id] == url || !overrides.containsKey(id)) {
          bindings[id] = fresh.id;
        }
      }
    }
    return BankSourceCatalog(sources, bindings, {});
  }

  Future<T> change<T>(T Function(BankSourceCatalog catalog) mutate) {
    final result = _tail.then((_) async {
      final catalog = await read();
      final value = mutate(catalog);
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode(catalog.toJson()),
      );
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
