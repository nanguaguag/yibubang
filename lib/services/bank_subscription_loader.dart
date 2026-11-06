import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../common/github_proxy.dart';
import '../repositories/question_bank_repository.dart';
import 'bank_subscription_service.dart';

class BankSubscriptionDownload {
  final List<Map<String, dynamic>> entries;
  final Map<String, File> artifacts;
  final Directory directory;
  BankSubscriptionDownload(this.entries, this.artifacts, this.directory);

  Future<void> dispose() => directory.delete(recursive: true);
}

/// Inspects a subscription without installing or writing any live bank.
class BankSubscriptionLoader {
  final http.Client? client;
  BankSubscriptionLoader({this.client});

  Future<BankSubscriptionDownload> load(String url) async {
    final directory = await Directory.systemTemp.createTemp(
      'bank-subscription-',
    );
    final connection = client ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(GitHubProxyConfig.defaultHeaders);
      final response = await connection
          .send(request)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        throw StateError('订阅下载失败（HTTP ${response.statusCode}）');
      }
      final download = File(p.join(directory.path, 'download'));
      final sink = download.openWrite();
      try {
        await sink.addStream(
          response.stream.timeout(const Duration(seconds: 120)),
        );
      } finally {
        await sink.close();
      }
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
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      if (client == null) connection.close();
    }
  }
}
