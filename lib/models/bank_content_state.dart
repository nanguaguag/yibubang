import 'dart:convert';
import 'package:crypto/crypto.dart';

class BankRelease {
  const BankRelease({
    required this.sourceId,
    required this.version,
    required this.releaseId,
    required this.packageHash,
    this.sqliteHash,
  });
  final String sourceId, version, releaseId, packageHash;
  final String? sqliteHash;
  factory BankRelease.fromEntry(String sourceId, Map<String, dynamic> entry) {
    final version = '${entry['version']}';
    final packageHash = '${entry['sha256']}';
    final sqliteHash = entry['sqlite_sha256']?.toString();
    return BankRelease(
      sourceId: sourceId,
      version: version,
      packageHash: packageHash,
      sqliteHash: sqliteHash,
      releaseId: sha256
          .convert(
            utf8.encode(
              jsonEncode([
                version,
                entry['content_revision'],
                sqliteHash ?? packageHash,
              ]),
            ),
          )
          .toString(),
    );
  }
}

/// Upstream history is independent from the mutable installed file fingerprint.
/// Lives in user_data.sqlite, never in exported question bank content.
class BankContentState {
  const BankContentState({
    required this.bankId,
    this.sourceId = '',
    this.baseVersion = '',
    this.baseRelease = '',
    this.baseHash = '',
    this.localRevision = 0,
    this.installedHash = '',
  });
  final String bankId,
      sourceId,
      baseVersion,
      baseRelease,
      baseHash,
      installedHash;
  final int localRevision;
  bool get hasBaseline => baseRelease.isNotEmpty;
  bool hasLocalChanges(String hash) =>
      localRevision > 0 || (installedHash.isNotEmpty && installedHash != hash);
  factory BankContentState.fromMap(Map<String, dynamic> row) =>
      BankContentState(
        bankId: row['bank_id'] as String,
        sourceId: row['source_id'] as String? ?? '',
        baseVersion: row['base_version'] as String? ?? '',
        baseRelease: row['base_release'] as String? ?? '',
        baseHash: row['base_hash'] as String? ?? '',
        installedHash: row['installed_hash'] as String? ?? '',
        localRevision: row['local_revision'] as int? ?? 0,
      );
  Map<String, dynamic> toMap() => {
    'bank_id': bankId,
    'source_id': sourceId,
    'base_version': baseVersion,
    'base_release': baseRelease,
    'base_hash': baseHash,
    'local_revision': localRevision,
    'installed_hash': installedHash,
  };
  BankContentState installed(
    String hash, {
    BankRelease? release,
    bool merged = false,
  }) => BankContentState(
    bankId: bankId,
    sourceId: release?.sourceId ?? sourceId,
    baseVersion: release?.version ?? baseVersion,
    baseRelease: release?.releaseId ?? baseRelease,
    baseHash: release?.sqliteHash ?? (release == null ? baseHash : ''),
    installedHash: hash,
    localRevision: release != null
        ? (merged ? (localRevision > 0 ? localRevision : 1) : 0)
        : (installedHash.isNotEmpty && installedHash != hash
              ? localRevision + 1
              : localRevision),
  );
}
