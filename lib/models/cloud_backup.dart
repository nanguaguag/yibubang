/// 云端冷备快照元数据
class BackupSnapshot {
  final String key;
  final String filename;
  final int size;
  final int timestamp;
  final String checksum;

  const BackupSnapshot({
    required this.key,
    required this.filename,
    required this.size,
    required this.timestamp,
    required this.checksum,
  });

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    return BackupSnapshot(
      key: json['key']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      checksum: json['checksum']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'filename': filename,
        'size': size,
        'timestamp': timestamp,
        'checksum': checksum,
      };

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

/// 备份执行结果
class BackupResult {
  final bool success;
  final String message;
  final BackupSnapshot? snapshot;

  const BackupResult({
    required this.success,
    required this.message,
    this.snapshot,
  });
}
