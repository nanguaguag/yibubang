import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// 内置题库的稳定标识。题库文件和用户统计都以 bankId 为边界。
class QuestionBankDefaults {
  static const dental = QuestionBankSpec(
    bankId: 'dental_final',
    name: '口腔期末',
    identityId: '30401',
    description: '口腔医学期末题库',
    icon: Symbols.dentistry_rounded,
  );
  static const clinical = QuestionBankSpec(
    bankId: 'clinical_final',
    name: '临床期末',
    identityId: '20101',
    description: '临床医学期末题库',
    icon: Symbols.health_metrics,
  );
  static const nursing = QuestionBankSpec(
    bankId: 'nursing_final',
    name: '护理期末',
    identityId: '11070',
    description: '护理学期末题库',
    icon: Symbols.bloodtype_rounded,
  );

  static const all = <QuestionBankSpec>[dental, clinical, nursing];

  static QuestionBankSpec? byId(String bankId) {
    for (final spec in all) {
      if (spec.bankId == bankId) return spec;
    }
    return null;
  }
}

class QuestionBankSpec {
  final String bankId;
  final String name;
  final String identityId;
  final String description;
  final IconData icon;

  const QuestionBankSpec({
    required this.bankId,
    required this.name,
    required this.identityId,
    required this.description,
    required this.icon,
  });
}

class QuestionBank {
  final String bankId;
  final String name;
  final String description;
  final String version;
  final int schemaVersion;
  final String localPath;
  final String contentHash;
  final int size;
  final bool enabled;
  final bool builtIn;
  final bool updateEnabled;
  final String installState;
  final String? remoteUrl;
  final String identityId;
  final int updatedAt;

  const QuestionBank({
    required this.bankId,
    required this.name,
    required this.description,
    required this.version,
    required this.schemaVersion,
    required this.localPath,
    required this.contentHash,
    required this.size,
    required this.enabled,
    required this.builtIn,
    required this.updateEnabled,
    required this.installState,
    required this.remoteUrl,
    required this.identityId,
    required this.updatedAt,
  });

  bool get isInstalled => installState == 'installed' && localPath.isNotEmpty;

  QuestionBank copyWith({
    String? name,
    String? description,
    String? version,
    int? schemaVersion,
    String? localPath,
    String? contentHash,
    int? size,
    bool? enabled,
    bool? builtIn,
    bool? updateEnabled,
    String? installState,
    String? remoteUrl,
    String? identityId,
    int? updatedAt,
  }) {
    return QuestionBank(
      bankId: bankId,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      localPath: localPath ?? this.localPath,
      contentHash: contentHash ?? this.contentHash,
      size: size ?? this.size,
      enabled: enabled ?? this.enabled,
      builtIn: builtIn ?? this.builtIn,
      updateEnabled: updateEnabled ?? this.updateEnabled,
      installState: installState ?? this.installState,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      identityId: identityId ?? this.identityId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory QuestionBank.fromMap(Map<String, dynamic> map) {
    final spec = QuestionBankDefaults.byId(map['bank_id'] as String? ?? '');
    return QuestionBank(
      bankId: map['bank_id'] as String,
      name: map['name'] as String? ?? spec?.name ?? '未命名题库',
      description: map['description'] as String? ?? spec?.description ?? '',
      version: map['version'] as String? ?? '0.0.0',
      schemaVersion: (map['schema_version'] as num?)?.toInt() ?? 0,
      localPath: map['local_path'] as String? ?? '',
      contentHash: map['content_hash'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      enabled: (map['enabled'] as num?)?.toInt() == 1,
      builtIn: (map['built_in'] as num?)?.toInt() == 1,
      updateEnabled: (map['update_enabled'] as num?)?.toInt() != 0,
      installState: map['install_state'] as String? ?? 'available',
      remoteUrl: map['remote_url'] as String?,
      identityId: map['identity_id'] as String? ?? spec?.identityId ?? '',
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'bank_id': bankId,
        'name': name,
        'description': description,
        'version': version,
        'schema_version': schemaVersion,
        'local_path': localPath,
        'content_hash': contentHash,
        'size': size,
        'enabled': enabled ? 1 : 0,
        'built_in': builtIn ? 1 : 0,
        'update_enabled': updateEnabled ? 1 : 0,
        'install_state': installState,
        'remote_url': remoteUrl,
        'identity_id': identityId,
        'updated_at': updatedAt,
      };
}
