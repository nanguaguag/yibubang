import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/data_transfer.dart';
import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import '../models/bank_content_state.dart';
import '../models/bank_source.dart';
import '../services/question_bank_file_service.dart';

typedef DownloadProgressCallback =
    void Function(int receivedBytes, int? totalBytes);

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
  final Set<String> _installing = {};

  /// 初始化题库目录只允许同时执行一次，避免启动入口和页面重复扫描题库。
  /// 初始化失败时清空 Future，后续进入题库管理页面仍可以重试。
  Future<void> initialize() {
    return _initializationFuture ??= _initializeInternal().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initializationFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
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
        '[bank-scan] 题库 ${spec.bankId} 校验阶段耗时 ${swBank.elapsedMilliseconds}ms',
      );
      if (fileExists &&
          validation != null &&
          !validation.isValid &&
          await File(backupPath).exists()) {
        final backupValidation = await validatePath(
          backupPath,
          expectedBankId: spec.bankId,
        );
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
          {'install_state': 'broken', 'local_path': path},
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
    await userDb.insert('MigrationState', {
      'migration_id': 'question_bank_catalog_v1',
      'from_version': 1,
      'to_version': 3,
      'state': 'completed',
      'started_at': now,
      'finished_at': now,
      'error': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    final installed = (await listBanks()).where(
      (bank) =>
          bank.enabled && bank.isInstalled && bank.bankId != 'legacy_combined',
    );
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
      final alternatives = (await listBanks()).where(
        (candidate) =>
            candidate.bankId != bankId &&
            candidate.enabled &&
            candidate.isInstalled,
      );
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

  /// Removes installed content while retaining global answers, notes, course
  /// choices and history. Subscribed/built-in banks remain available to download.
  Future<void> deleteBank(String bankId, {bool keepAvailable = false}) async {
    if (_installing.isNotEmpty) throw StateError('已有题库正在安装、更新或删除');
    _installing.add(bankId);
    FileSystemEntity? original, removed;
    Future<FileSystemEntity> move(
      FileSystemEntity entity,
      String destination,
    ) => entity is File
        ? entity.rename(destination)
        : (entity as Directory).rename(destination);
    var committed = false;
    try {
      final bank = await find(bankId);
      if (bank == null) return;
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(bankId)) {
        throw const FormatException('题库标识格式不正确');
      }
      final legacy = bankId == 'legacy_combined';
      final expected = legacy
          ? p.join(await getDatabasesPath(), 'question_data.sqlite')
          : await _databaseManager.pathFor(bankId);
      if (bank.localPath.isNotEmpty &&
          p.normalize(p.absolute(bank.localPath)) !=
              p.normalize(p.absolute(expected))) {
        throw StateError('题库路径不属于应用题库目录，无法删除');
      }
      final path = legacy ? expected : p.dirname(expected);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        if (type !=
            (legacy
                ? FileSystemEntityType.file
                : FileSystemEntityType.directory)) {
          throw StateError('题库路径类型异常，无法删除');
        }
        original = legacy ? File(path) : Directory(path);
        final parent = legacy
            ? await Directory(await getDatabasesPath()).resolveSymbolicLinks()
            : await Directory(
                await _databaseManager.rootPath,
              ).resolveSymbolicLinks();
        if (await original.resolveSymbolicLinks() !=
            p.join(parent, legacy ? 'question_data.sqlite' : bankId)) {
          throw StateError('题库路径指向其他位置，无法删除');
        }
        await _databaseManager.closeBank(bankId);
        await DatabaseHelper().close();
        // Move the complete directory, including old installation backups.
        // A metadata failure can restore it without modifying any SQLite file.
        removed = await move(
          original,
          p.join(
            p.dirname(path),
            '.removed-$bankId-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
      }
      final db = await UserDBHelper().database;
      await db.transaction((txn) async {
        if (keepAvailable || bank.builtIn) {
          await txn.update(
            'QuestionBank',
            {
              'local_path': '',
              'content_hash': '',
              'size': 0,
              'install_state': 'available',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'bank_id = ?',
            whereArgs: [bankId],
          );
        } else {
          await txn.delete(
            'QuestionBank',
            where: 'bank_id = ?',
            whereArgs: [bankId],
          );
        }
        for (final table in [
          'BankContentState',
          'YkbBankSyncState',
          'YkbBankChapterState',
        ]) {
          await txn.delete(table, where: 'bank_id = ?', whereArgs: [bankId]);
        }
        await txn.insert('BankHistory', {
          'id': generateSimpleId(),
          'bank_id': bankId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'action': '删除本地题库',
          'version': bank.version,
          'added': 0,
          'question_count': 0,
        });
      });
      committed = true;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('activeBankId') == bankId) {
        await prefs.remove('activeBankId');
        await prefs.remove('identityId');
      }
      await activeBankId();
    } catch (_) {
      if (!committed && removed != null && await removed.exists()) {
        await move(removed, original!.path);
      }
      rethrow;
    } finally {
      if (committed && removed != null && await removed.exists()) {
        try {
          await removed.delete(recursive: true);
        } catch (error) {
          debugPrint('[bank-delete] 已移除题库，暂存文件清理失败：$error');
        }
      }
      _installing.remove(bankId);
    }
  }

  Future<BankFileValidation> validatePath(
    String filePath, {
    String? expectedBankId,
  }) => _databaseManager.validateFile(filePath, expectedBankId: expectedBankId);

  Future<Directory> _ensureQuestionBankRoot() async {
    final directory = Directory(await _databaseManager.rootPath);
    await directory.create(recursive: true);
    return directory;
  }

  Future<QuestionBank> importFile(
    String sourcePath, {
    String? expectedBankId,
    String? expectedIdentityId,
    String? expectedSqliteHash,
    String? versionOverride,
    bool? updateEnabled,
    BankRelease? upstream,
    VoidCallback? onInstallReady,
    Future<BankImportMode?> Function(QuestionBank existing)? onConflict,
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
      final metadata = validation.metadata!;
      if (expectedIdentityId != null &&
          metadata['identity_id'] != expectedIdentityId) {
        throw const FormatException('下载题库的学科与订阅清单不一致');
      }
      if (expectedSqliteHash != null &&
          sha256.convert(await File(databasePath).readAsBytes()).toString() !=
              expectedSqliteHash.toLowerCase()) {
        throw const FormatException('SQLite SHA-256 与订阅清单不一致');
      }
      final bankId = metadata['bank_id'] as String;
      // Reserve before awaiting the user choice; installations share a user DB
      // connection and must not race file replacement or ATTACH aliases.
      if (_installing.isNotEmpty) throw StateError('已有题库正在安装或更新');
      _installing.add(bankId);
      Directory? mergeDirectory;
      try {
        final existing = await find(bankId);
        final mode = existing?.isInstalled == true && onConflict != null
            ? await onConflict(existing!)
            : BankImportMode.replace;
        if (mode == null) throw BankImportCancelled();
        onInstallReady?.call();
        final addedCount = existing?.isInstalled == true
            ? await QuestionBankFileService.countNewQuestions(
                existing!.localPath,
                databasePath,
              )
            : (metadata['question_count'] as num?)?.toInt() ?? 0;
        if (mode == BankImportMode.merge) {
          final localValidation = await validatePath(existing!.localPath);
          if (!localValidation.isValid ||
              localValidation.metadata?['identity_id'] !=
                  metadata['identity_id']) {
            throw const FormatException('题库所属学科不一致，无法增量合并');
          }
          mergeDirectory = await Directory.systemTemp.createTemp('bank-merge-');
          final merged = await QuestionBankFileService.merge(
            localPath: existing.localPath,
            incomingPath: databasePath,
            temporaryDirectory: mergeDirectory,
            version: QuestionBankFileService.nextVersion(existing.version),
          );
          databasePath = merged.path;
          final mergedValidation = await validatePath(
            databasePath,
            expectedBankId: bankId,
          );
          if (!mergedValidation.isValid) {
            throw FormatException(mergedValidation.message);
          }
          final installed = await _installValidatedFile(
            databasePath,
            mergedValidation.metadata!,
            updateEnabled: false,
            historyAction: '增量合并',
            addedCount: addedCount,
            upstream: upstream,
            merged: true,
          );
          return installed;
        }
        final installed = await _installValidatedFile(
          databasePath,
          metadata,
          versionOverride: versionOverride,
          updateEnabled: updateEnabled,
          historyAction: existing?.isInstalled == true ? '更新题库' : '创建/导入',
          addedCount: addedCount,
          upstream: upstream,
        );
        return installed;
      } finally {
        _installing.remove(bankId);
        if (mergeDirectory != null && await mergeDirectory.exists()) {
          await mergeDirectory.delete(recursive: true);
        }
      }
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
    required String historyAction,
    required int addedCount,
    BankRelease? upstream,
    bool merged = false,
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
    upstream ??= isOfficialContent && !merged
        ? BankRelease.fromEntry(BankSourceCatalog.officialId, configuredRemote!)
        : null;
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
    final stagedValidation = await validatePath(
      stagingPath,
      expectedBankId: bankId,
    );
    if (!stagedValidation.isValid) {
      if (await staging.exists()) await staging.delete();
      throw FormatException(stagedValidation.message);
    }

    final target = File(targetPath);
    var hadBackup = false;
    Database? attachedDb;
    try {
      if (await target.exists()) {
        if (await File(backupPath).exists()) await File(backupPath).delete();
        await target.rename(backupPath);
        hadBackup = true;
      }
      await staging.rename(targetPath);

      final userDb = await UserDBHelper().database;
      await userDb.execute('ATTACH DATABASE ? AS install_bank', [targetPath]);
      attachedDb = userDb;
      final existing = await find(bankId);
      final bank = QuestionBank(
        bankId: bankId,
        name:
            metadata['name'] as String? ??
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
        identityId:
            (metadata['identity_id'] as String?) ??
            spec?.identityId ??
            existing?.identityId ??
            '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await userDb.transaction((txn) async {
        await txn.insert(
          'QuestionBank',
          bank.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final previous = await txn.query(
          'BankContentState',
          where: 'bank_id = ?',
          whereArgs: [bankId],
        );
        final state = previous.isEmpty
            ? BankContentState(
                bankId: bankId,
                installedHash: existing?.contentHash ?? '',
              )
            : BankContentState.fromMap(previous.single);
        await txn.insert(
          'BankContentState',
          state.installed(hash, release: upstream, merged: merged).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert('BankHistory', {
          'id': generateSimpleId(),
          'bank_id': bank.bankId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'action': historyAction,
          'version': bank.version,
          'added': addedCount,
          'question_count': (metadata['question_count'] as num?)?.toInt() ?? 0,
        });
        // A full rebuild may move courses from the former root to their actual
        // leaf identities. Preserve choices when the old ownership disappeared.
        await txn.rawInsert(
          '''
          INSERT OR IGNORE INTO IdentitySubject
            (bank_id, identity_id, subject_id, correct, incorrect, selected)
          SELECT ?, x.identity_id, x.subject_id, 0, 0,
            COALESCE((SELECT MAX(old.selected) FROM IdentitySubject old
              WHERE old.bank_id = ? AND old.subject_id = x.subject_id
                AND NOT EXISTS (SELECT 1 FROM install_bank.IdentitySubject kept
                  WHERE kept.identity_id = old.identity_id
                    AND kept.subject_id = old.subject_id)), 0)
          FROM install_bank.IdentitySubject x WHERE 1
        ''',
          [bankId, bankId],
        );
        await rebuildAttachedQuestionCount(txn, bankId, alias: 'install_bank');
      });
      return bank;
    } catch (error) {
      if (attachedDb != null) {
        await attachedDb.execute('DETACH DATABASE install_bank');
        attachedDb = null;
      }
      // 目录记录写入失败或进程在替换阶段失败时，尽量恢复旧文件。
      if (await target.exists()) await target.delete();
      final backup = File(backupPath);
      if (hadBackup && await backup.exists()) {
        await backup.rename(targetPath);
      }
      if (await staging.exists()) await staging.delete();
      rethrow;
    } finally {
      if (attachedDb != null) {
        await attachedDb.execute('DETACH DATABASE install_bank');
      }
    }
  }

  Future<void> registerRemoteEntries(List<Map<String, dynamic>> entries) async {
    final userDb = await UserDBHelper().database;
    for (final entry in entries) {
      final bankId = entry['bank_id'] as String;
      final existing = await find(bankId);
      if (existing == null) {
        await userDb.insert('QuestionBank', {
          'bank_id': bankId,
          'name': entry['name']?.toString() ?? bankId,
          'description': entry['description']?.toString() ?? '',
          'identity_id': entry['identity_id']?.toString() ?? '',
          'remote_url': entry['url']?.toString(),
        });
      } else {
        // An installed file owns its root and content version. A subscription
        // supplies download information, not replacement identity metadata.
        await userDb.update(
          'QuestionBank',
          {
            'remote_url': entry['url']?.toString(),
            if (!existing.isInstalled)
              'identity_id':
                  entry['identity_id']?.toString() ?? existing.identityId,
          },
          where: 'bank_id = ?',
          whereArgs: [bankId],
        );
      }
    }
  }

  Future<void> removeRemoteEntries(List<Map<String, dynamic>> entries) async {
    final db = await UserDBHelper().database;
    for (final entry in entries) {
      final id = entry['bank_id'] as String;
      final bank = await find(id);
      if (bank == null || bank.remoteUrl != entry['url']) continue;
      if (!bank.isInstalled && !bank.builtIn) {
        await db.delete('QuestionBank', where: 'bank_id = ?', whereArgs: [id]);
      } else {
        await db.update(
          'QuestionBank',
          {'remote_url': configuredRemoteBanks[id]?['url']},
          where: 'bank_id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> history(String bankId) async =>
      (await UserDBHelper().database).query(
        'BankHistory',
        where: 'bank_id = ?',
        whereArgs: [bankId],
        orderBy: 'timestamp DESC',
      );

  Future<BankContentState> contentState(String bankId) async {
    final rows = await (await UserDBHelper().database).query(
      'BankContentState',
      where: 'bank_id = ?',
      whereArgs: [bankId],
    );
    return rows.isEmpty
        ? BankContentState(bankId: bankId)
        : BankContentState.fromMap(rows.single);
  }

  /// Old installations can prove a baseline by matching a known SQLite digest.
  Future<void> establishBaseline(QuestionBank bank, BankRelease release) async {
    if (release.sqliteHash != bank.contentHash) return;
    final db = await UserDBHelper().database;
    await db.transaction((txn) async {
      final current = await txn.query(
        'QuestionBank',
        where: 'bank_id = ?',
        whereArgs: [bank.bankId],
      );
      if (current.isEmpty ||
          current.single['content_hash'] != bank.contentHash) {
        return;
      }
      await txn.insert(
        'BankContentState',
        BankContentState(
          bankId: bank.bankId,
        ).installed(bank.contentHash, release: release).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
