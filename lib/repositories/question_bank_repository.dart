import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/github_proxy.dart';
import '../common/version_utils.dart';
import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';

typedef DownloadProgressCallback = void Function(
  int receivedBytes,
  int? totalBytes,
);

class QuestionBankRepository {
  static const int supportedSchemaVersion = 1;
  // 应用更新清单同时承载 question_banks 字段，题库仓库会读取其中的多题库信息。
  static const String remoteManifestUrl =
      'https://files.melonhu.cn/yibubang/yibubang_update.json';

  // 当前三个题库已经发布到 Gitee，但暂时没有单独发布 manifest 文件。
  // 保留内置清单作为 manifest 请求失败时的安全兜底；以后远程 manifest
  // 可覆盖这里的版本和下载信息，而不需要再次发布 App。
  static const Map<String, Map<String, dynamic>> configuredRemoteBanks = {
    'dental_final': {
      'bank_id': 'dental_final',
      'name': '口腔期末',
      'version': '3.0.0',
      'schema_version': 1,
      'identity_id': '30401',
      'url':
          'https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/dental_final.sqlite.zip',
      'size': 32563857,
      'sha256':
          'cb9870e6e77e1875a0f73530ec7e9c897c4ee0a435e13d39b6543719ff33f76f',
      'sqlite_sha256':
          '574aaa4cb8e443f25661581594272a92e6b997199afd19f5faf90ffe247ce536',
    },
    'clinical_final': {
      'bank_id': 'clinical_final',
      'name': '临床期末',
      'version': '3.0.0',
      'schema_version': 1,
      'identity_id': '20101',
      'url':
          'https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/clinical_final.sqlite.zip',
      'size': 25939926,
      'sha256':
          '3db37a844ec0f8ac3688a7fcf7967de1a8adf8f787a3e4801dd1276893383061',
      'sqlite_sha256':
          '893100264187b49a57a802cba3933b02b121f566378f43c5f5625df380ff5eb2',
    },
    'nursing_final': {
      'bank_id': 'nursing_final',
      'name': '护理期末',
      'version': '3.0.0',
      'schema_version': 1,
      'identity_id': '11070',
      'url':
          'https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/nursing_final.sqlite.zip',
      'size': 24184056,
      'sha256':
          'd23ac8b8b49083fb912749d21633bccc7f79bb60213ac6e4982d189c9bf7fa33',
      'sqlite_sha256':
          'e0b0b5ab40f7d6f9718c1962282c36b479161112ec0bb77fe330acfedd0384f8',
    },
  };

  static final QuestionBankRepository _instance =
      QuestionBankRepository._internal();
  factory QuestionBankRepository() => _instance;
  QuestionBankRepository._internal();

  final QuestionBankDatabaseManager _databaseManager =
      QuestionBankDatabaseManager();
  Future<void>? _initializationFuture;

  /// 初始化题库目录只允许同时执行一次，避免启动入口和页面重复扫描题库。
  /// 初始化失败时清空 Future，后续进入题库管理页面仍可以重试。
  Future<void> initialize() {
    return _initializationFuture ??= _initializeInternal().catchError(
      (Object error, StackTrace stackTrace) {
        _initializationFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> _initializeInternal() async {
    await _backupLegacyFiles();
    final userDb = await UserDBHelper().database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final swTotal = Stopwatch()..start();
    for (final spec in QuestionBankDefaults.all) {
      final swBank = Stopwatch()..start();
      final path = await _databaseManager.pathFor(spec.bankId);
      final backupPath = '$path.bak';
      var fileExists = await File(path).exists();
      if (!fileExists && await File(backupPath).exists()) {
        await File(backupPath).rename(path);
        fileExists = true;
      }
      var validation = fileExists
          ? await validatePath(path, expectedBankId: spec.bankId)
          : null;
      debugPrint(
          '[bank-scan] 题库 ${spec.bankId} 校验阶段耗时 ${swBank.elapsedMilliseconds}ms');
      if (fileExists &&
          validation != null &&
          !validation.isValid &&
          await File(backupPath).exists()) {
        final backupValidation =
            await validatePath(backupPath, expectedBankId: spec.bankId);
        if (backupValidation.isValid) {
          await File(path).delete();
          await File(backupPath).rename(path);
          validation = backupValidation;
        }
      }
      final fileIsValid = validation?.isValid == true;
      final existing = await userDb.query(
        'QuestionBank',
        where: 'bank_id = ?',
        whereArgs: [spec.bankId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await userDb.insert('QuestionBank', {
          'bank_id': spec.bankId,
          'name': spec.name,
          'description': spec.description,
          'version': fileIsValid ? '1.0.0' : '0.0.0',
          'schema_version': fileIsValid ? 1 : 0,
          'local_path': fileIsValid ? path : '',
          'content_hash': '',
          'size': 0,
          'enabled': 1,
          'built_in': 1,
          'update_enabled': 1,
          'install_state': fileIsValid ? 'installed' : 'available',
          'remote_url': null,
          'identity_id': spec.identityId,
          'updated_at': now,
        });
      } else if (fileExists && !fileIsValid) {
        await userDb.update(
          'QuestionBank',
          {
            'install_state': 'broken',
            'local_path': path,
          },
          where: 'bank_id = ?',
          whereArgs: [spec.bankId],
        );
      }
    }

    // 旧版本题库不删除。它是迁移失败时的只读安全回退，不会伪装成可删除的内置库。
    final legacyPath = p.join(await getDatabasesPath(), 'question_data.sqlite');
    if (await File(legacyPath).exists()) {
      final legacy = await userDb.query(
        'QuestionBank',
        where: 'bank_id = ?',
        whereArgs: ['legacy_combined'],
        limit: 1,
      );
      if (legacy.isEmpty) {
        await userDb.insert('QuestionBank', {
          'bank_id': 'legacy_combined',
          'name': '旧版合并题库（兼容回退）',
          'description': '旧版本题库，仅用于老用户兼容和迁移失败回退',
          'version': 'legacy',
          'schema_version': 0,
          'local_path': legacyPath,
          'content_hash': '',
          'size': await File(legacyPath).length(),
          'enabled': 1,
          'built_in': 0,
          'update_enabled': 0,
          'install_state': 'installed',
          'remote_url': null,
          'identity_id': '',
          'updated_at': now,
        });
      }
    }
    await userDb.insert(
      'MigrationState',
      {
        'migration_id': 'question_bank_catalog_v1',
        'from_version': 1,
        'to_version': 3,
        'state': 'completed',
        'started_at': now,
        'finished_at': now,
        'error': '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[bank-scan] 题库目录初始化总耗时 ${swTotal.elapsedMilliseconds}ms');
  }

  Future<void> _backupLegacyFiles() async {
    final databasePath = await getDatabasesPath();
    final backupDirectory = Directory(p.join(databasePath, 'migration_backup'));
    await backupDirectory.create(recursive: true);
    for (final name in const ['user_data.sqlite', 'question_data.sqlite']) {
      final source = File(p.join(databasePath, name));
      final backup = File(p.join(backupDirectory.path, name));
      if (await source.exists() && !await backup.exists()) {
        await source.copy(backup.path);
      }
    }
  }

  Future<List<QuestionBank>> listBanks() async {
    await initialize();
    final rows = await (await UserDBHelper().database).query(
      'QuestionBank',
      orderBy: 'built_in DESC, name COLLATE NOCASE',
    );
    return rows.map(QuestionBank.fromMap).toList();
  }

  Future<QuestionBank?> find(String bankId) async {
    final rows = await (await UserDBHelper().database).query(
      'QuestionBank',
      where: 'bank_id = ?',
      whereArgs: [bankId],
      limit: 1,
    );
    return rows.isEmpty ? null : QuestionBank.fromMap(rows.first);
  }

  Future<String> activeBankId() async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getString('activeBankId') ?? 'dental_final';
    final preferredBank = await find(preferred);
    if (preferredBank != null &&
        preferredBank.enabled &&
        preferredBank.isInstalled) {
      return preferred;
    }
    final installed = (await listBanks()).where((bank) =>
        bank.enabled && bank.isInstalled && bank.bankId != 'legacy_combined');
    final first = installed.isNotEmpty ? installed.first : null;
    if (first != null) {
      await prefs.setString('activeBankId', first.bankId);
      await prefs.setString('identityId', first.identityId);
      return first.bankId;
    }
    // 保留默认值，让下载/导入完成后无需再次设置页面状态。
    return preferred;
  }

  Future<void> selectBank(String bankId) async {
    final bank = await find(bankId);
    if (bank == null || !bank.enabled || !bank.isInstalled) {
      throw StateError('题库尚未安装或已禁用');
    }
    await QuestionBankDatabaseManager().closeBank(bankId);
    await DatabaseHelper().switchBank(bankId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeBankId', bankId);
    if (bank.identityId.isNotEmpty) {
      await prefs.setString('identityId', bank.identityId);
    }
  }

  Future<void> setEnabled(String bankId, bool enabled) async {
    final bank = await find(bankId);
    if (bank == null) throw StateError('题库不存在');
    if (!enabled && bank.bankId == await activeBankId()) {
      final alternatives = (await listBanks()).where((candidate) =>
          candidate.bankId != bankId &&
          candidate.enabled &&
          candidate.isInstalled);
      if (alternatives.isEmpty) {
        throw StateError('至少需要保留一个已启用的题库');
      }
      await selectBank(alternatives.first.bankId);
    }
    await (await UserDBHelper().database).update(
      'QuestionBank',
      {'enabled': enabled ? 1 : 0},
      where: 'bank_id = ?',
      whereArgs: [bankId],
    );
  }

  Future<BankFileValidation> validatePath(
    String filePath, {
    String? expectedBankId,
  }) =>
      _databaseManager.validateFile(
        filePath,
        expectedBankId: expectedBankId,
      );

  Future<Directory> _ensureQuestionBankRoot() async {
    final directory = Directory(await _databaseManager.rootPath);
    await directory.create(recursive: true);
    return directory;
  }

  Future<QuestionBank> importFile(
    String sourcePath, {
    String? expectedBankId,
    String? versionOverride,
    bool? updateEnabled,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const FormatException('选择的文件不存在');
    final extension = p.extension(sourcePath).toLowerCase();
    String databasePath = sourcePath;
    File? temporaryDatabase;
    try {
      if (extension == '.zip') {
        final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
        final candidate = archive.firstWhere(
          (entry) =>
              entry.isFile &&
              p.extension(entry.name).toLowerCase() == '.sqlite',
          orElse: () => throw const FormatException('ZIP 中没有 SQLite 题库文件'),
        );
        final temporaryPath = p.join(
          (await _ensureQuestionBankRoot()).path,
          '.import-${DateTime.now().microsecondsSinceEpoch}.sqlite',
        );
        temporaryDatabase = File(temporaryPath);
        await temporaryDatabase.parent.create(recursive: true);
        await temporaryDatabase.writeAsBytes(candidate.content as List<int>);
        databasePath = temporaryPath;
      }
      final validation = await validatePath(
        databasePath,
        expectedBankId: expectedBankId,
      );
      if (!validation.isValid || validation.metadata == null) {
        throw FormatException(validation.message);
      }
      return await _installValidatedFile(
        databasePath,
        validation.metadata!,
        versionOverride: versionOverride,
        updateEnabled: updateEnabled,
      );
    } finally {
      if (temporaryDatabase != null && await temporaryDatabase.exists()) {
        await temporaryDatabase.delete();
      }
    }
  }

  Future<QuestionBank> _installValidatedFile(
    String sourcePath,
    Map<String, dynamic> metadata, {
    String? versionOverride,
    bool? updateEnabled,
  }) async {
    final bankId = metadata['bank_id'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(bankId)) {
      throw const FormatException('题库 bank_id 含有非法路径字符');
    }
    final spec = QuestionBankDefaults.byId(bankId);
    final directory = p.join(await _databaseManager.rootPath, bankId);
    final targetPath = p.join(directory, '$bankId.sqlite');
    final stagingPath = '$targetPath.staging';
    final backupPath = '$targetPath.bak';
    await Directory(directory).create(recursive: true);
    await _databaseManager.closeBank(bankId);
    await DatabaseHelper().close();

    final sourceFile = File(sourcePath);
    final bytes = await sourceFile.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final configuredRemote = configuredRemoteBanks[bankId];
    final isOfficialContent =
        configuredRemote?['sqlite_sha256']?.toString() == hash;
    final resolvedUpdateEnabled = updateEnabled ?? isOfficialContent;
    // 下载更新使用远程发布版本；导入的官方同内容文件也沿用远程发布版本，
    // 避免 BankMeta 里的内容版本（1.0.0）把发布版本（3.0.0）回退。
    final String resolvedVersion;
    if (versionOverride != null) {
      resolvedVersion = versionOverride;
    } else if (isOfficialContent) {
      resolvedVersion = configuredRemote?['version']?.toString() ?? '1.0.0';
    } else {
      resolvedVersion = metadata['version'] as String? ?? '1.0.0';
    }
    final staging = File(stagingPath);
    await staging.writeAsBytes(bytes, flush: true);
    final stagedValidation =
        await validatePath(stagingPath, expectedBankId: bankId);
    if (!stagedValidation.isValid) {
      if (await staging.exists()) await staging.delete();
      throw FormatException(stagedValidation.message);
    }

    final target = File(targetPath);
    var hadBackup = false;
    try {
      if (await target.exists()) {
        if (await File(backupPath).exists()) await File(backupPath).delete();
        await target.rename(backupPath);
        hadBackup = true;
      }
      await staging.rename(targetPath);

      final userDb = await UserDBHelper().database;
      final existing = await find(bankId);
      final bank = QuestionBank(
        bankId: bankId,
        name: metadata['name'] as String? ??
            existing?.name ??
            spec?.name ??
            bankId,
        description: existing?.description ?? spec?.description ?? '',
        version: resolvedVersion,
        schemaVersion: (metadata['schema_version'] as num?)?.toInt() ?? 1,
        localPath: targetPath,
        contentHash: hash,
        size: bytes.length,
        enabled: existing?.enabled ?? true,
        builtIn: spec != null || (existing?.builtIn ?? false),
        updateEnabled: resolvedUpdateEnabled,
        installState: 'installed',
        remoteUrl: existing?.remoteUrl,
        identityId: spec?.identityId ??
            (metadata['identity_id'] as String?) ??
            existing?.identityId ??
            '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await userDb.insert(
        'QuestionBank',
        bank.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return bank;
    } catch (error) {
      // 目录记录写入失败或进程在替换阶段失败时，尽量恢复旧文件。
      if (await target.exists()) await target.delete();
      final backup = File(backupPath);
      if (hadBackup && await backup.exists()) {
        await backup.rename(targetPath);
      }
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> checkRemoteManifest() async {
    Map<String, dynamic> decoded;
    try {
      final manifestUrl = await GitHubProxyConfig.getManifestUrl();
      http.Response response;
      try {
        response = await http.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 8));
      } catch (proxyError) {
        debugPrint('镜像题库清单拉取失败 ($proxyError)，尝试官方直连兜底...');
        response = await http
            .get(Uri.parse(GitHubProxyConfig.rawBaseUrl))
            .timeout(const Duration(seconds: 8));
      }

      if (response.statusCode != 200) {
        throw HttpException('题库清单请求失败：HTTP ${response.statusCode}');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('远程更新清单格式不正确');
      }
      final nestedBanks = value['question_banks'];
      if (value['banks'] is List) {
        decoded = value;
      } else if (nestedBanks is Map && nestedBanks['banks'] is List) {
        decoded = Map<String, dynamic>.from(nestedBanks);
      } else if (nestedBanks is List) {
        decoded = {
          'manifest_version': value['manifest_version'] ?? 1,
          'schema_version': value['schema_version'] ?? supportedSchemaVersion,
          'banks': nestedBanks,
        };
      } else {
        throw const FormatException('远程更新清单缺少题库列表');
      }
    } catch (error) {
      // 三个 ZIP 已经发布，但独立 manifest 尚未上传时，使用内置清单。
      // 仍然保留远程 manifest 优先，后续发布 manifest 后可直接覆盖这些值。
      debugPrint('远程题库清单不可用，使用内置清单：$error');
      decoded = {
        'manifest_version': 1,
        'schema_version': supportedSchemaVersion,
        'banks': configuredRemoteBanks.values.toList(),
      };
    }

    final remoteEntries = <String, Map<String, dynamic>>{};
    for (final raw in decoded['banks'] as List) {
      if (raw is Map && raw['bank_id'] != null) {
        final entry = Map<String, dynamic>.from(raw);
        remoteEntries[entry['bank_id'].toString()] = entry;
      }
    }
    // 远程 manifest 可以覆盖内置版本；如果远程条目仍是旧的本地 manifest
    // 格式（没有下载 URL 或 SHA-256），则使用已发布 ZIP 的完整信息。
    for (final entry in configuredRemoteBanks.values) {
      final bankId = entry['bank_id'].toString();
      final current = remoteEntries[bankId];
      if (current == null) {
        remoteEntries[bankId] = Map<String, dynamic>.from(entry);
      } else if (current['url']?.toString().isNotEmpty != true ||
          current['sha256']?.toString().isNotEmpty != true) {
        remoteEntries[bankId] = {
          ...entry,
          ...current,
          'version': entry['version'],
          'url': entry['url'],
          'size': entry['size'],
          'sha256': entry['sha256'],
        };
      } else if (current['sqlite_sha256']?.toString().isNotEmpty != true) {
        current['sqlite_sha256'] = entry['sqlite_sha256'];
      }
    }

    final userDb = await UserDBHelper().database;
    for (final raw in remoteEntries.values) {
      final bankId = raw['bank_id']!.toString();
      final existing = await find(bankId);
      final spec = QuestionBankDefaults.byId(bankId);
      await userDb.insert(
        'QuestionBank',
        {
          'bank_id': bankId,
          'name':
              raw['name']?.toString() ?? existing?.name ?? spec?.name ?? bankId,
          'description':
              raw['description']?.toString() ?? existing?.description ?? '',
          'version': existing?.version ?? '0.0.0',
          'schema_version': int.tryParse('${raw['schema_version'] ?? 0}') ?? 0,
          'local_path': existing?.localPath ?? '',
          'content_hash': existing?.contentHash ?? '',
          'size': existing?.size ?? 0,
          'enabled': existing?.enabled == false ? 0 : 1,
          'built_in': spec != null || (existing?.builtIn ?? false) ? 1 : 0,
          'update_enabled': existing?.updateEnabled == false ? 0 : 1,
          'install_state': existing?.installState ?? 'available',
          'remote_url': raw['url']?.toString(),
          'identity_id':
              raw['identity_id']?.toString() ?? spec?.identityId ?? '',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return {
      ...decoded,
      'banks': remoteEntries.values.toList(),
    };
  }

  Future<QuestionBank> downloadBank(
    String bankId, {
    Map<String, dynamic>? remoteEntry,
    DownloadProgressCallback? onProgress,
  }) async {
    final local = await find(bankId);
    final remote = remoteEntry ?? configuredRemoteBanks[bankId];
    final url = remote?['url']?.toString() ?? local?.remoteUrl;
    if (url == null || url.isEmpty) {
      throw StateError('题库尚未配置远程直链');
    }

    final expectedSize = int.tryParse(
      '${remote?['size'] ?? ''}',
    );
    final expectedHash = remote?['sha256']?.toString();
    if (expectedHash == null || expectedHash.isEmpty) {
      throw const FormatException('远程题库清单缺少 SHA-256，拒绝安装');
    }
    final remoteBankId = remote?['bank_id']?.toString();
    if (remoteBankId != null && remoteBankId != bankId) {
      throw FormatException('远程题库标识不匹配：清单为 $remoteBankId，目标为 $bankId');
    }

    final client = http.Client();
    File? temporary;
    try {
      final downloadUrl = await GitHubProxyConfig.resolveDownloadUrl(url);
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('题库下载失败：HTTP ${response.statusCode}');
      }

      final responseLength = response.contentLength;
      final totalBytes = responseLength != null && responseLength > 0
          ? responseLength
          : expectedSize != null && expectedSize > 0
              ? expectedSize
              : null;
      final remoteExtension = p.extension(Uri.parse(url).path).toLowerCase();
      final temporaryPath = p.join(
        (await _ensureQuestionBankRoot()).path,
        '.download-${DateTime.now().microsecondsSinceEpoch}${remoteExtension == '.zip' ? '.zip' : '.sqlite'}',
      );
      final temporaryFile = File(temporaryPath);
      temporary = temporaryFile;
      final sink = temporaryFile.openWrite();
      var receivedBytes = 0;
      onProgress?.call(receivedBytes, totalBytes);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (expectedSize != null &&
          expectedSize > 0 &&
          receivedBytes != expectedSize) {
        throw FormatException('下载文件大小校验失败');
      }
      final bytes = await temporaryFile.readAsBytes();
      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != expectedHash) {
        throw FormatException('下载文件 SHA-256 校验失败');
      }

      return await importFile(
        temporaryPath,
        expectedBankId: bankId,
        versionOverride: remote?['version']?.toString(),
        updateEnabled: true,
      );
    } finally {
      client.close();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  bool hasUpdate(QuestionBank bank, Map<String, dynamic> remote) {
    if (!bank.updateEnabled) return false;
    final remoteHash = remote['sqlite_sha256']?.toString();
    if (remoteHash != null &&
        remoteHash.isNotEmpty &&
        bank.contentHash.isNotEmpty) {
      return remoteHash != bank.contentHash;
    }
    final remoteVersion = remote['version']?.toString();
    return remoteVersion != null &&
        compareVersions(remoteVersion, bank.version) > 0;
  }

  int compareVersions(String left, String right) {
    return VersionUtils.compareVersions(left, right);
  }
}
