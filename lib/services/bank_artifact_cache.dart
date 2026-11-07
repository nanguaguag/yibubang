import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../repositories/question_bank_repository.dart';
import 'bank_subscription_loader.dart';

/// A lease protects a validated download from LRU cleanup until installation ends.
class BankArtifactLease {
  BankArtifactLease(
    this.entry,
    this.file,
    this.etag,
    this.lastModified,
    this._release,
  );
  final Map<String, dynamic> entry;
  final File file;
  final String? etag, lastModified;
  final Future<void> Function() _release;
  bool _closed = false;
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _release();
  }
}

/// Writable application cache, outside live QuestionBank files. Every reuse
/// verifies the persisted bytes; changing HTTP validators never validates a DB.
class BankArtifactCache {
  BankArtifactCache({
    BankSubscriptionLoader? loader,
    this.root,
    this.maxBytes = 256 * 1024 * 1024,
  }) : loader = loader ?? BankSubscriptionLoader();
  final BankSubscriptionLoader loader;
  final Directory? root;
  final int maxBytes;
  static Future<void> _tail = Future.value();
  static final _leases = <String, int>{};

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Directory> _directory() async {
    final directory =
        root ?? Directory(p.join(await getDatabasesPath(), 'BankDownloads'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<BankArtifactLease> acquire(
    String url, {
    Map<String, dynamic>? expected,
    bool refresh = false,
    DownloadProgressCallback? onProgress,
  }) => _exclusive(() async {
    final directory = await _directory();
    Map<String, dynamic>? row;
    final records = await _records(directory);
    for (final candidate in records.reversed) {
      if (candidate['url'] == url &&
          (!refresh || expected != null) &&
          (expected == null ||
              (candidate['entry'] as Map)['sha256'] == expected['sha256'])) {
        final file = File(p.join(directory.path, candidate['file'] as String));
        if (await file.exists() && await _hash(file) == candidate['hash']) {
          row = candidate;
          break;
        }
      }
    }
    if (row == null) {
      final loaded = await loader.load(url, onProgress: onProgress);
      try {
        if (loaded.entries.length != 1 || loaded.artifacts.length != 1) {
          throw const FormatException('请使用 ZIP 或 SQLite 题库文件链接；订阅清单请添加为来源');
        }
        final entry = loaded.entries.single;
        final artifact = loaded.artifacts.values.single;
        _match(entry, expected);
        final hash = await _hash(artifact);
        final name = '$hash${p.extension(artifact.path)}';
        final persisted = File(p.join(directory.path, name));
        if (!await persisted.exists() || await _hash(persisted) != hash) {
          // A partial copy is never a published cache record.
          final staging = File('${persisted.path}.part');
          await artifact.copy(staging.path);
          await staging.rename(persisted.path);
        }
        row = {
          'url': url,
          'file': name,
          'hash': hash,
          'size': await persisted.length(),
          'entry': entry,
          'etag': loaded.etag,
          'last_modified': loaded.lastModified,
        };
      } finally {
        await loaded.dispose();
      }
    }
    final entry = Map<String, dynamic>.from(row['entry'] as Map);
    _match(entry, expected);
    row['used_at'] = DateTime.now().microsecondsSinceEpoch;
    final file = File(p.join(directory.path, row['file'] as String));
    final record = File(
      p.join(
        directory.path,
        '${sha256.convert(utf8.encode('$url:${row['hash']}'))}.json',
      ),
    );
    await record.writeAsString(jsonEncode(row), flush: true);
    _leases.update(file.path, (count) => count + 1, ifAbsent: () => 1);
    await _prune(directory);
    onProgress?.call(await file.length(), await file.length());
    return BankArtifactLease(
      entry,
      file,
      row['etag'] as String?,
      row['last_modified'] as String?,
      () => _exclusive(() async {
        final count = (_leases[file.path] ?? 1) - 1;
        if (count <= 0) {
          _leases.remove(file.path);
        } else {
          _leases[file.path] = count;
        }
        await _prune(directory);
      }),
    );
  });

  static void _match(
    Map<String, dynamic> actual,
    Map<String, dynamic>? expected,
  ) {
    if (expected == null) return;
    for (final key in ['bank_id', 'identity_id', 'sha256', 'sqlite_sha256']) {
      if (expected[key] != null && '${actual[key]}' != '${expected[key]}') {
        throw FormatException(
          key == 'identity_id' ? '下载题库的学科与来源不一致' : '下载题库与发布清单不一致（$key）',
        );
      }
    }
    final size = int.tryParse('${expected['size']}');
    if (size != null && size > 0 && size != actual['size']) {
      throw const FormatException('下载文件大小校验失败');
    }
  }

  Future<List<Map<String, dynamic>>> _records(Directory directory) async {
    final result = <Map<String, dynamic>>[];
    await for (final file in directory.list()) {
      if (file is! File || p.extension(file.path) != '.json') continue;
      try {
        final row = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
        if (p.basename('${row['file']}') != row['file']) continue;
        result.add({...row, '_record': file.path});
      } on FormatException {
        await file.delete();
      }
    }
    result.sort(
      (a, b) =>
          (a['used_at'] as int? ?? 0).compareTo(b['used_at'] as int? ?? 0),
    );
    return result;
  }

  Future<void> _prune(Directory directory) async {
    final records = await _records(directory);
    final files = <String, int>{};
    for (final row in records) {
      files[row['file'] as String] = row['size'] as int;
    }
    var total = files.values.fold(0, (a, b) => a + b);
    for (final row in records) {
      if (total <= maxBytes) break;
      final name = row['file'] as String;
      final file = File(p.join(directory.path, name));
      if (_leases.containsKey(file.path)) continue;
      for (final related in records.where((r) => r['file'] == name)) {
        final record = File(related['_record'] as String);
        if (await record.exists()) await record.delete();
      }
      if (await file.exists()) await file.delete();
      total -= files.remove(name) ?? 0;
    }
    // Remove interrupted downloads and unreferenced artifacts after restart.
    final retained = (await _records(directory)).map((r) => r['file']).toSet();
    await for (final file in directory.list()) {
      if (file is File &&
          p.extension(file.path) != '.json' &&
          !retained.contains(p.basename(file.path)) &&
          !_leases.containsKey(file.path)) {
        await file.delete();
      }
    }
  }

  Future<void> prune() => _exclusive(() async => _prune(await _directory()));
  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
