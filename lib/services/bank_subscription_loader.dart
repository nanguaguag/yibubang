import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../common/github_proxy.dart';
import '../models/bank_source.dart';
import '../models/bank_download_task.dart';
import '../repositories/question_bank_repository.dart';
import 'bank_subscription_service.dart';

class BankSubscriptionDownload {
  final List<Map<String, dynamic>> entries;
  final Map<String, File> artifacts;
  final Directory directory;
  final String? etag, lastModified, transportUrl;
  BankSubscriptionDownload(
    this.entries,
    this.artifacts,
    this.directory, {
    this.etag,
    this.lastModified,
    this.transportUrl,
  });

  Future<void> dispose() => directory.delete(recursive: true);
}

/// Inspects a subscription without installing or writing any live bank.
class BankSubscriptionLoader {
  final http.Client? client;
  BankSubscriptionLoader({this.client});

  Future<BankSource> check(BankSource source) async {
    final connection = client ?? http.Client();
    try {
      final urls = source.official && client == null
          ? await GitHubProxyConfig.getCandidateManifestUrls()
          : [
              client == null
                  ? await GitHubProxyConfig.resolveDownloadUrl(source.url)
                  : source.url,
            ];
      Object? lastError;
      for (final url in urls) {
        try {
          return await _probe(connection, source, url);
        } catch (error) {
          lastError = error;
        }
      }
      throw lastError ?? StateError('来源无法访问');
    } finally {
      if (client == null) connection.close();
    }
  }

  Future<BankSource> _probe(
    http.Client connection,
    BankSource source,
    String url,
  ) async {
    final headers = <String, String>{...GitHubProxyConfig.defaultHeaders};
    if (source.transportUrl == url) {
      if (source.etag != null) {
        headers['If-None-Match'] = source.etag!;
      } else if (source.lastModified != null) {
        headers['If-Modified-Since'] = source.lastModified!;
      }
    }
    Future<http.StreamedResponse> send(String method) async {
      final request = http.Request(method, Uri.parse(url))
        ..headers.addAll(headers);
      return connection.send(request).timeout(const Duration(seconds: 20));
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    BankSource ready({
      List<Map<String, dynamic>>? entries,
      http.StreamedResponse? response,
      BankSourceKind? kind,
    }) => BankSource(
      url: source.url,
      official: source.official,
      kind: kind ?? source.kind,
      status: BankSourceStatus.ready,
      entries: entries ?? source.entries,
      checkedAt: now,
      successAt: now,
      etag: response?.headers['etag'] ?? source.etag,
      lastModified: response?.headers['last-modified'] ?? source.lastModified,
      transportUrl: url,
    );
    BankSource needs() => BankSource(
      url: source.url,
      official: source.official,
      kind: BankSourceKind.file,
      status: BankSourceStatus.needsDownload,
      entries: source.entries,
      checkedAt: now,
      successAt: source.successAt,
      etag: source.etag,
      lastModified: source.lastModified,
      transportUrl: source.transportUrl,
    );
    Future<void> discard(http.StreamedResponse response) =>
        response.stream.listen((_) {}).cancel();
    if (source.kind != BankSourceKind.manifest) {
      final head = await send('HEAD');
      await discard(head);
      if (head.statusCode == 304 && source.entries.isNotEmpty) return ready();
      if (head.statusCode == 200) {
        final type = head.headers['content-type'] ?? '';
        if (source.kind == BankSourceKind.file ||
            type.contains('zip') ||
            type.contains('sqlite') ||
            type.contains('octet-stream')) {
          final same =
              source.transportUrl == url &&
              source.entries.isNotEmpty &&
              ((source.etag != null && head.headers['etag'] == source.etag) ||
                  (source.etag == null &&
                      source.lastModified != null &&
                      head.headers['last-modified'] == source.lastModified));
          return same ? ready() : needs();
        }
      } else if (head.statusCode != 405 && head.statusCode != 501) {
        throw StateError('来源检查失败（HTTP ${head.statusCode}）');
      }
    }
    final response = await send('GET');
    if (response.statusCode == 304) {
      await discard(response);
      if (source.entries.isEmpty) {
        throw const FormatException('没有可复用的订阅清单，请重新检查');
      }
      return ready();
    }
    if (response.statusCode != 200) {
      await discard(response);
      throw StateError('来源检查失败（HTTP ${response.statusCode}）');
    }
    final type = response.headers['content-type'] ?? '';
    if (source.kind == BankSourceKind.file ||
        type.contains('zip') ||
        type.contains('sqlite') ||
        type.contains('octet-stream')) {
      await discard(response);
      return needs();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      // Unknown response signatures must not turn a check into a full download.
      if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
        return needs();
      }
      if (bytes.length >= 16 &&
          latin1.decode(bytes.take(16).toList()) == 'SQLite format 3\u0000') {
        return needs();
      }
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('订阅清单过大，请使用题库下载入口');
      }
    }
    final value = jsonDecode(utf8.decode(bytes));
    Object? manifest = value;
    if (source.official && value is Map) {
      final nested = value['question_banks'];
      final items =
          value['banks'] ?? (nested is Map ? nested['banks'] : nested);
      if (items is List) {
        manifest = {
          'banks': [
            for (final item in items.whereType<Map>())
              {
                ...QuestionBankRepository
                        .configuredRemoteBanks[item['bank_id']] ??
                    {},
                ...item,
              },
          ],
        };
      }
    }
    final entries = BankSubscriptionService.parseManifest(manifest, source.url);
    return ready(
      entries: entries,
      response: response,
      kind: BankSourceKind.manifest,
    );
  }

  Future<BankSubscriptionDownload> load(
    String url, {
    DownloadProgressCallback? onProgress,
    BankDownloadTask? task,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'bank-subscription-',
    );
    final connection = client ?? http.Client();
    try {
      final transportUrl = client == null
          ? await GitHubProxyConfig.resolveDownloadUrl(url)
          : url;
      final request = http.Request('GET', Uri.parse(transportUrl));
      request.headers.addAll(GitHubProxyConfig.defaultHeaders);
      task?.checkCancelled();
      task?.report('正在下载');
      final pending = connection
          .send(request)
          .timeout(const Duration(seconds: 120));
      final response = await (task == null ? pending : task.wait(pending));
      if (response.statusCode != 200) {
        throw StateError('订阅下载失败（HTTP ${response.statusCode}）');
      }
      final download = File(p.join(directory.path, 'download'));
      final sink = download.openWrite();
      var received = 0;
      onProgress?.call(0, response.contentLength);
      task?.report('正在下载', bytes: 0, size: response.contentLength);
      final stream = StreamIterator(
        response.stream.timeout(const Duration(seconds: 120)),
      );
      try {
        while (await (task == null
            ? stream.moveNext()
            : task.wait(stream.moveNext()))) {
          final chunk = stream.current;
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, response.contentLength);
          task?.report('正在下载', bytes: received, size: response.contentLength);
        }
      } finally {
        await stream.cancel();
        await sink.close();
      }
      task?.checkCancelled();
      task?.report('正在校验题库');
      final handle = await download.open();
      late List<int> signature;
      try {
        signature = await handle.read(16);
      } finally {
        await handle.close();
      }
      final zip =
          signature.length >= 4 && signature[0] == 0x50 && signature[1] == 0x4b;
      final sqlite = latin1.decode(signature) == 'SQLite format 3\u0000';
      if (!zip && !sqlite) {
        try {
          final entries = BankSubscriptionService.parseManifest(
            jsonDecode(utf8.decode(await download.readAsBytes())),
            url,
          );
          return BankSubscriptionDownload(entries, {}, directory);
        } on FormatException {
          throw const FormatException(
            '该地址未返回有效题库。请使用 ZIP、SQLite 下载链接或 JSON 订阅清单。',
          );
        }
      }
      final artifact = await download.rename(
        p.join(directory.path, zip ? 'bank.zip' : 'bank.sqlite'),
      );
      File content = artifact;
      if (zip) {
        final archive = ZipDecoder().decodeBytes(await artifact.readAsBytes());
        final candidates = archive
            .where(
              (item) =>
                  item.isFile &&
                  p.extension(item.name).toLowerCase() == '.sqlite',
            )
            .toList();
        if (candidates.length != 1) {
          throw const FormatException('ZIP 中应包含一个 SQLite 题库文件');
        }
        content = File(p.join(directory.path, 'content.sqlite'));
        await content.writeAsBytes(candidates.single.content as List<int>);
      }
      final validation = await QuestionBankRepository().validatePath(
        content.path,
      );
      if (!validation.isValid || validation.metadata == null) {
        throw FormatException(validation.message);
      }
      final meta = validation.metadata!;
      final contentHash = (await sha256.bind(content.openRead()).first)
          .toString();
      final official =
          QuestionBankRepository.configuredRemoteBanks[meta['bank_id']];
      final entry = <String, dynamic>{
        ...meta,
        'url': url,
        'subscription_url': url,
        'source_type': 'file',
        'size': await artifact.length(),
        'sha256': (await sha256.bind(artifact.openRead()).first).toString(),
        'sqlite_sha256': contentHash,
        if (official?['sqlite_sha256'] == contentHash)
          'version': official!['version'],
      };
      return BankSubscriptionDownload(
        [entry],
        {meta['bank_id'] as String: artifact},
        directory,
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
        transportUrl: transportUrl,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      if (client == null) connection.close();
    }
  }
}
