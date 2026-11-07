import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../common/github_proxy.dart';
import '../models/question_bank.dart';
import '../common/version_utils.dart';
import 'bank_content_state.dart';

enum BankSourceKind { unknown, manifest, file }

enum BankSourceStatus { unchecked, ready, needsDownload, failed }

enum BankUpdateStatus {
  unchecked,
  current,
  available,
  needsDownload,
  needsComparison,
  changed,
  rollback,
  failed,
}

String normalizeBankSourceUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('请输入有效的 HTTPS 链接');
  }
  // Preserve path case and signed query parameters; fragments are not sent.
  return uri
      .replace(scheme: 'https', host: uri.host.toLowerCase())
      .removeFragment()
      .toString();
}

class BankSource {
  BankSource({
    required this.url,
    this.official = false,
    this.kind = BankSourceKind.unknown,
    this.status = BankSourceStatus.unchecked,
    this.entries = const [],
    this.checkedAt = 0,
    this.successAt = 0,
    this.error,
    this.etag,
    this.lastModified,
    this.transportUrl,
  });
  final String url;
  final bool official;
  final BankSourceKind kind;
  final BankSourceStatus status;
  final List<Map<String, dynamic>> entries;
  final int checkedAt, successAt;
  final String? error, etag, lastModified, transportUrl;
  String get id => sha256.convert(utf8.encode(url)).toString();
  String get name => official ? '官方题库' : Uri.parse(url).host;
  String get statusLabel => switch (status) {
    BankSourceStatus.unchecked => '待检查',
    BankSourceStatus.ready => '${entries.length} 个题库',
    BankSourceStatus.needsDownload => '需下载确认',
    BankSourceStatus.failed => '检查失败',
  };
  Map<String, dynamic>? entry(String bankId) =>
      entries.where((e) => e['bank_id'] == bankId).firstOrNull;
  Map<String, dynamic> toJson() => {
    'url': url,
    'official': official,
    'kind': kind.name,
    'status': status.name,
    'entries': entries,
    'checked_at': checkedAt,
    'success_at': successAt,
    'error': error,
    'etag': etag,
    'last_modified': lastModified,
    'transport_url': transportUrl,
  };
  factory BankSource.fromJson(Map<String, dynamic> row) => BankSource(
    url: normalizeBankSourceUrl(row['url'] as String),
    official: row['official'] == true,
    kind: BankSourceKind.values.firstWhere(
      (v) => v.name == row['kind'],
      orElse: () => BankSourceKind.unknown,
    ),
    status: BankSourceStatus.values.firstWhere(
      (v) => v.name == row['status'],
      orElse: () => BankSourceStatus.unchecked,
    ),
    entries: (row['entries'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    checkedAt: row['checked_at'] as int? ?? 0,
    successAt: row['success_at'] as int? ?? 0,
    error: row['error'] as String?,
    etag: row['etag'] as String?,
    lastModified: row['last_modified'] as String?,
    transportUrl: row['transport_url'] as String?,
  );
  static BankSource fresh(String url, {bool official = false}) {
    final normalized = normalizeBankSourceUrl(url);
    final path = Uri.parse(normalized).path.toLowerCase();
    return BankSource(
      url: normalized,
      official: official,
      kind: path.endsWith('.json')
          ? BankSourceKind.manifest
          : path.endsWith('.zip') ||
                path.endsWith('.sqlite') ||
                path.endsWith('.db')
          ? BankSourceKind.file
          : BankSourceKind.unknown,
    );
  }
}

class BankSourceCatalog {
  BankSourceCatalog(this.sources, this.bindings, this.pending);
  final Map<String, BankSource> sources;

  /// Empty bindings explicitly mean unsubscribed; do not fall back to old URLs.
  final Map<String, String> bindings, pending;
  BankSource? sourceFor(String bankId) => sources[bindings[bankId]];
  List<BankSource> candidates(String bankId) =>
      sources.values.where((s) => s.entry(bankId) != null).toList();
  Map<String, dynamic> toJson() => {
    'sources': sources.map((id, source) => MapEntry(id, source.toJson())),
    'bindings': bindings,
    'pending': pending,
  };
  factory BankSourceCatalog.fromJson(Map<String, dynamic> row) =>
      BankSourceCatalog(
        (row['sources'] as Map).map(
          (id, source) => MapEntry(
            id.toString(),
            BankSource.fromJson(Map<String, dynamic>.from(source as Map)),
          ),
        ),
        Map<String, String>.from(row['bindings'] as Map? ?? {}),
        Map<String, String>.from(row['pending'] as Map? ?? {}),
      );
  static String get officialId =>
      BankSource.fresh(GitHubProxyConfig.rawBaseUrl).id;
}

class BankUpdateInfo {
  const BankUpdateInfo(
    this.status, {
    this.source,
    this.entry,
    this.message,
    this.content,
  });
  final BankUpdateStatus status;
  final BankSource? source;
  final Map<String, dynamic>? entry;
  final String? message;
  final BankContentState? content;
  String get label => switch (status) {
    BankUpdateStatus.unchecked => '待检查',
    BankUpdateStatus.current => '已是最新',
    BankUpdateStatus.available => '有更新',
    BankUpdateStatus.needsDownload => '需下载确认',
    BankUpdateStatus.needsComparison => '待比较',
    BankUpdateStatus.changed => '来源内容变更',
    BankUpdateStatus.rollback => '来源版本回退',
    BankUpdateStatus.failed => '检查失败',
  };
  // Detection is independent of permission to automatically install content.
  static BankUpdateInfo compare(
    QuestionBank bank,
    BankSource? source, {
    BankContentState? content,
  }) {
    if (source == null || source.status == BankSourceStatus.unchecked) {
      return BankUpdateInfo(BankUpdateStatus.unchecked, source: source);
    }
    if (source.status == BankSourceStatus.failed) {
      return BankUpdateInfo(
        BankUpdateStatus.failed,
        source: source,
        message: source.error,
      );
    }
    final entry = source.entry(bank.bankId);
    if (source.status == BankSourceStatus.needsDownload) {
      return BankUpdateInfo(
        BankUpdateStatus.needsDownload,
        source: source,
        entry: entry,
      );
    }
    if (entry == null) {
      return BankUpdateInfo(
        BankUpdateStatus.failed,
        source: source,
        message: '来源中已没有该题库',
      );
    }
    if (!bank.isInstalled) {
      return BankUpdateInfo(
        BankUpdateStatus.available,
        source: source,
        entry: entry,
      );
    }
    final hash = entry['sqlite_sha256']?.toString();
    final release = BankRelease.fromEntry(source.id, entry);
    if (content?.hasBaseline == true &&
        content!.baseRelease == release.releaseId) {
      return BankUpdateInfo(
        BankUpdateStatus.current,
        source: source,
        entry: entry,
        content: content,
      );
    }
    if (hash != null && hash == bank.contentHash) {
      return BankUpdateInfo(
        BankUpdateStatus.current,
        source: source,
        entry: entry,
      );
    }
    final order = VersionUtils.compareVersions(
      '${entry['version']}',
      content?.hasBaseline == true ? content!.baseVersion : bank.version,
    );
    return BankUpdateInfo(
      content?.hasBaseline != true
          ? BankUpdateStatus.needsComparison
          : order > 0
          ? BankUpdateStatus.available
          : order < 0
          ? BankUpdateStatus.rollback
          : BankUpdateStatus.changed,
      source: source,
      entry: entry,
      content: content,
    );
  }
}
