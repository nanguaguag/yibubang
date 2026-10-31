import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import 'ykb_bank_sync_service.dart';

/// 一次「智能增量同步」的结果。
class YkbBankSmartSyncResult {
  final bool installed;
  final int manifestChapters;
  final int queuedChapters;
  final int processedChapters;
  final int fetchedChapters;
  final int restrictedChapters;
  final int addedQuestions;
  final int updatedQuestions;
  final int extraLocalQuestions;
  final int remainingChapters;
  final int requestsUsed;
  final int elapsedMs;
  final String? error;

  const YkbBankSmartSyncResult({
    this.installed = false,
    this.manifestChapters = 0,
    this.queuedChapters = 0,
    this.processedChapters = 0,
    this.fetchedChapters = 0,
    this.restrictedChapters = 0,
    this.addedQuestions = 0,
    this.updatedQuestions = 0,
    this.extraLocalQuestions = 0,
    this.remainingChapters = 0,
    this.requestsUsed = 0,
    this.elapsedMs = 0,
    this.error,
  });

  bool get isSuccess => error == null;

  String get summary {
    if (error != null) return '智能同步暂停：$error';
    final restrictedText = restrictedChapters > 0
        ? '，跳过 $restrictedChapters 章无权限'
        : '';
    if (!installed) {
      return '检查 $manifestChapters 章，暂无需更新的题库内容$restrictedText'
          '（剩余 $remainingChapters 章，${elapsedMs}ms）';
    }
    return '题库已更新：新增 $addedQuestions 题、更新 $updatedQuestions 题，'
        '保留本地额外 $extraLocalQuestions 题$restrictedText；'
        '本次 $processedChapters 章，剩余 $remainingChapters 章后台继续';
  }
}

/// 医考帮题库「智能增量同步」。
///
/// 设计要点：
/// 1. 先拉身份树 + 章节目录（少量请求），用远端章节的 count/updated_at 与本地状态比对，
///    只把变化的章节排队，不再每次全量拉 1000+ 章。
/// 2. 本地题库是旧版章节结构，远端章节 ID 会漂移（例如本地 45011=心血管，远端 45011=肾）。
///    因此绝不按章节 ID 直接覆盖：先按「同 ID + 标题」「归一化标题」「同科目模糊标题」
///    「题目 ID 重合度」做语义映射，映射不到的题会落到新章节，避免把不同章节混在一起。
/// 3. 只增不删：本地已有题目/作答进度不会被远端覆盖或删除；远端新题补入，
///    远端内容变化的同 ID 题更新内容字段。章节可能有「官方 N 题 + 本地额外 M 题」。
/// 4. 每批最多 N 章，复制当前题库到 staging 文件，事务内应用增量，做
///    integrity_check / foreign_key_check / 计数校验，最后交给既有
///    `QuestionBankRepository.importFile` 做 SHA-256 校验、备份和原子替换。
/// 5. 状态（manifest 哈希、章节哈希、映射、待处理队列、失败退避）持久化在用户库，
///    应用退出后可续传；请求带随机抖动和每轮预算，失败指数退避。
class YkbBankSmartSyncService {
  static final YkbBankSmartSyncService instance =
      YkbBankSmartSyncService._internal();
  YkbBankSmartSyncService._internal();

  static const String keyEnabled = 'sync_bank_smart_enabled';
  static const int _pendingTtlMs = 24 * 60 * 60 * 1000;
  static const int _defaultMaxChapters = 12;
  static const int _maxRequestsPerRun = 28;
  static const int _minRequestGapMs = 1200;
  static const int _maxRequestGapMs = 3200;

  bool _running = false;
  int _requestsUsed = 0;

  @visibleForTesting
  String contentHashForTesting(Map<String, dynamic> row) => _rowHash(row);

  @visibleForTesting
  List<Map<String, dynamic>> pendingForTesting(String raw) => _decodePending(
    _encodePending(_decodePending(raw)),
  ).map((chapter) => chapter.toJson()).toList();

  @visibleForTesting
  Future<Map<String, String>> mappingForTesting({
    required Database db,
    required Map<String, dynamic> remote,
    required List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> questions = const [],
    Map<String, dynamic>? state,
  }) async {
    final chapters = <String, _LocalChapter>{};
    for (final row in local) {
      final id = row['id'].toString();
      final name = row['name'].toString();
      chapters[id] = _LocalChapter(
        id: id,
        name: name,
        subjectId: row['subjectId']?.toString() ?? '',
        total: (row['total'] as num?)?.toInt() ?? 0,
        norm: _normTitle(name),
      );
    }
    final mapping = await _resolveMapping(
      _RemoteChapter.fromJson(remote),
      questions,
      state,
      chapters,
      {},
      db,
      'bank',
    );
    return {'id': mapping.localChapterId, 'method': mapping.method};
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(keyEnabled)) {
      return prefs.getBool(keyEnabled) ?? true;
    }
    // 兼容旧开关：sync_question_bank 原本就是题库同步总开关。
    return prefs.getBool('sync_question_bank') ?? true;
  }

  /// 执行一批智能增量同步。
  ///
  /// [manual]：手动触发时忽略开关/自动退避，并允许多处理一些章节。
  /// [forceManifest]：忽略目录缓存，立即重新拉取远端章节目录。
  /// [maxChapters]：本次最多处理多少章（默认自动 8，手动 12）。
  Future<YkbBankSmartSyncResult> run({
    QuestionBank? bank,
    bool manual = false,
    bool forceManifest = false,
    int? maxChapters,
  }) async {
    if (_running) {
      return const YkbBankSmartSyncResult(error: '正在同步中');
    }
    _running = true;
    _requestsUsed = 0;
    final sw = Stopwatch()..start();
    Directory? stagingDir;
    var stagingPath = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('loggedin') ?? false)) {
        return const YkbBankSmartSyncResult(error: '未登录医考帮');
      }
      if (!manual && !await isEnabled()) {
        return const YkbBankSmartSyncResult(error: '智能同步已关闭');
      }

      final resolvedBank = bank ?? await _activeBank();
      if (resolvedBank == null || !resolvedBank.isInstalled) {
        return const YkbBankSmartSyncResult(error: '当前题库未安装');
      }

      final userDb = await UserDBHelper().database;
      await _ensureBankState(userDb, resolvedBank.bankId);
      final bankState = await _loadBankState(userDb, resolvedBank.bankId);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (!manual) {
        final nextRetry = (bankState['next_retry_at'] as num?)?.toInt() ?? 0;
        if (nextRetry > nowMs) {
          return YkbBankSmartSyncResult(
            error: '退避中，${((nextRetry - nowMs) / 60000).ceil()} 分钟后重试',
            elapsedMs: sw.elapsedMilliseconds,
          );
        }
      }

      final chapterStates = await _loadChapterStates(
        userDb,
        resolvedBank.bankId,
      );
      final bankDb = await QuestionBankDatabaseManager().openBank(
        resolvedBank.bankId,
      );
      final localChapters = await _loadLocalChapters(
        bankDb,
        resolvedBank.identityId,
      );
      final localSubjects = await _loadLocalSubjects(bankDb);
      var bankGeneratedAt = 0;
      try {
        bankGeneratedAt =
            Sqflite.firstIntValue(
              await bankDb.rawQuery(
                'SELECT generated_at FROM BankMeta LIMIT 1',
              ),
            ) ??
            0;
      } catch (_) {}

      // 1) 目录：有未完成队列且缓存不旧时直接续传，避免每批都拉 5 次目录。
      final pendingRaw = bankState['pending_json'] as String?;
      final pendingAt =
          (bankState['manifest_fetched_at'] as num?)?.toInt() ?? 0;
      final pending = <_RemoteChapter>[];
      if (!forceManifest &&
          pendingRaw != null &&
          pendingRaw.isNotEmpty &&
          nowMs - pendingAt < _pendingTtlMs) {
        pending.addAll(_decodePending(pendingRaw));
      }

      _Manifest? manifest;
      if (pending.isEmpty) {
        manifest = await _fetchManifest(
          resolvedBank,
          prefs,
          localChapters,
          chapterStates,
          bankGeneratedAt: bankGeneratedAt,
        );
        debugPrint(
          '[ykb-smart-sync] ${resolvedBank.bankId} '
          'manifest=${manifest.leaves.length} chapters, '
          'queue=${manifest.pending.length}, bootstrap=${manifest.bootstraps.length}',
        );
        pending.addAll(manifest.pending);
      }

      final limit = maxChapters ?? (manual ? 12 : _defaultMaxChapters);
      final batch = pending.take(limit).toList();
      final remaining = pending.skip(limit).toList();
      final chapterStateUpdates = <Map<String, dynamic>>[];
      chapterStateUpdates.addAll(manifest?.bootstraps ?? const []);

      if (batch.isEmpty) {
        await _saveBankState(userDb, resolvedBank.bankId, {
          'manifest_hash': manifest?.hash ?? bankState['manifest_hash'],
          'manifest_fetched_at': manifest != null ? nowMs : pendingAt,
          'pending_json': remaining.isEmpty ? null : _encodePending(remaining),
          'last_sync_at': nowMs,
          'last_success_at': nowMs,
          'next_retry_at': 0,
          'failure_count': 0,
          'last_error': null,
        });
        await _upsertChapterStates(userDb, chapterStateUpdates);
        return YkbBankSmartSyncResult(
          manifestChapters: manifest?.leaves.length ?? 0,
          queuedChapters: pending.length,
          remainingChapters: remaining.length,
          requestsUsed: _requestsUsed,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      // 2) 逐章拉取 + 映射 + 哈希比对。
      final fetched = <_FetchedChapter>[];
      final stateOnly = <Map<String, dynamic>>[];
      final restrictedStates = <Map<String, dynamic>>[];
      final failed = <_RemoteChapter>[];
      var restricted = 0;

      for (final rc in batch) {
        if (_requestsUsed >= _maxRequestsPerRun) {
          remaining.insert(0, rc);
          continue;
        }
        await _jitter();
        final fetchResult =
            await YkbBankSyncService.fetchChapterQuestionsResult(
              identityId: rc.identityId,
              appId: rc.appId,
              moduleType: rc.moduleType,
              chapterId: rc.id,
            );
        _requestsUsed++;
        if (fetchResult.isRestricted) {
          // 203：当前账号无该章节查看权限。按周重试，避免每轮都撞 203。
          restricted++;
          restrictedStates.add(
            _chapterStateRow(
              resolvedBank.bankId,
              rc,
              'restricted',
              '',
              '',
              rc.title,
              'restricted',
              0,
              nowMs,
            ),
          );
          continue;
        }
        if (!fetchResult.isOk || fetchResult.questions == null) {
          debugPrint(
            '[ykb-smart-sync] 章节 ${rc.id} 拉取失败: '
            '${fetchResult.code} ${fetchResult.message}',
          );
          failed.add(rc);
          continue;
        }
        final questions = fetchResult.questions!;
        if (questions.length != rc.count) {
          // count 与列表不一致：宁可留到下一轮，不把半章数据写进题库。
          debugPrint(
            '[ykb-smart-sync] 章节 ${rc.id} 数量不一致: '
            'list=${questions.length}, manifest=${rc.count}',
          );
          failed.add(rc);
          continue;
        }
        final remoteHash = _chapterHash(questions, rc, resolvedBank.identityId);
        final oldState = chapterStates[rc.id];
        if (oldState != null &&
            (oldState['remote_hash']?.toString() ?? '') == remoteHash) {
          stateOnly.add(
            _chapterStateRow(
              resolvedBank.bankId,
              rc,
              remoteHash,
              oldState['local_chapter_id']?.toString() ?? '',
              oldState['local_subject_id']?.toString() ?? '',
              oldState['local_title']?.toString() ?? '',
              oldState['match_method']?.toString() ?? 'hash',
              (oldState['extra_count'] as num?)?.toInt() ?? 0,
              nowMs,
            ),
          );
          continue;
        }

        final mapping = await _resolveMapping(
          rc,
          questions,
          oldState,
          localChapters,
          localSubjects,
          bankDb,
          resolvedBank.identityId,
        );
        fetched.add(
          _FetchedChapter(
            rc: rc,
            questions: questions,
            remoteHash: remoteHash,
            mapping: mapping,
          ),
        );
      }

      if (fetched.isEmpty) {
        await _upsertChapterStates(userDb, [
          ...chapterStateUpdates,
          ...stateOnly,
          ...restrictedStates,
        ]);
        await _saveBankState(userDb, resolvedBank.bankId, {
          'manifest_hash': manifest?.hash ?? bankState['manifest_hash'],
          'manifest_fetched_at': manifest != null ? nowMs : pendingAt,
          'pending_json': _encodePending([...failed, ...remaining]),
          'last_sync_at': nowMs,
          'last_success_at': nowMs,
          'next_retry_at': failed.isEmpty ? 0 : nowMs + _backoffMs(1),
          'failure_count': failed.isEmpty ? 0 : 1,
          'last_error': failed.isEmpty ? null : '${failed.length} 个章节待重试',
        });
        return YkbBankSmartSyncResult(
          manifestChapters: manifest?.leaves.length ?? 0,
          queuedChapters: pending.length,
          processedChapters: stateOnly.length + restricted,
          fetchedChapters: 0,
          restrictedChapters: restricted,
          remainingChapters: failed.length + remaining.length,
          requestsUsed: _requestsUsed,
          elapsedMs: sw.elapsedMilliseconds,
          error: failed.isEmpty ? null : '${failed.length} 个章节待重试',
        );
      }

      // 3) 复制当前题库 -> staging，事务内应用增量。
      final baseVersion =
          RegExp(
            r'^\d+\.\d+\.\d+',
          ).firstMatch(resolvedBank.version)?.group(0) ??
          '3.0.0';
      final deltaVersion = '$baseVersion+delta.${nowMs ~/ 1000}';
      final livePath = await _bankPath(resolvedBank);
      stagingDir = Directory(p.dirname(livePath));
      stagingPath = p.join(
        stagingDir.path,
        '${resolvedBank.bankId}.delta-$nowMs.sqlite',
      );
      await File(livePath).copy(stagingPath);
      final apply = await _applyToStaging(
        stagingPath: stagingPath,
        bankId: resolvedBank.bankId,
        bankIdentityId: resolvedBank.identityId,
        items: fetched,
        nowMs: nowMs,
        version: deltaVersion,
      );

      // 4) 校验 + 原子替换。importFile 内部会做 SHA-256、备份和 rename。
      // 同步后的题库不再跟随旧的远端 3.0.0 包更新，避免覆盖官方 API 增量。
      final installed = await QuestionBankRepository().importFile(
        stagingPath,
        expectedBankId: resolvedBank.bankId,
        versionOverride: deltaVersion,
        updateEnabled: false,
      );
      try {
        if (await File(stagingPath).exists()) await File(stagingPath).delete();
      } catch (_) {}

      // 5) 成功后才写章节状态，避免失败时把未落库的章节标记为已同步。
      for (final item in fetched) {
        chapterStateUpdates.add(
          _chapterStateRow(
            resolvedBank.bankId,
            item.rc,
            item.remoteHash,
            item.mapping.localChapterId,
            item.mapping.localSubjectId,
            item.mapping.localTitle,
            item.mapping.method,
            item.extraCount,
            nowMs,
          ),
        );
      }
      chapterStateUpdates.addAll(stateOnly);
      chapterStateUpdates.addAll(restrictedStates);
      await _upsertChapterStates(userDb, chapterStateUpdates);
      await _saveBankState(userDb, resolvedBank.bankId, {
        'manifest_hash': manifest?.hash ?? bankState['manifest_hash'],
        'manifest_fetched_at': manifest != null ? nowMs : pendingAt,
        'pending_json': _encodePending([...failed, ...remaining]),
        'last_sync_at': nowMs,
        'last_success_at': nowMs,
        'next_retry_at': failed.isEmpty ? 0 : nowMs + _backoffMs(1),
        'failure_count': failed.isEmpty ? 0 : 1,
        'last_error': failed.isEmpty ? null : '${failed.length} 个章节待重试',
        'last_bank_hash': installed.contentHash,
        'installed_at': nowMs,
      });

      debugPrint(
        '[ykb-smart-sync] 安装完成 ${installed.bankId} '
        'v=${installed.version} hash=${installed.contentHash.substring(0, 12)} '
        '新增=${apply.added} 更新=${apply.updated} '
        '额外=${apply.extra} 无权限=$restricted '
        '剩余=${failed.length + remaining.length} '
        '请求=$_requestsUsed',
      );
      return YkbBankSmartSyncResult(
        installed: true,
        manifestChapters: manifest?.leaves.length ?? 0,
        queuedChapters: pending.length,
        processedChapters: fetched.length + stateOnly.length + restricted,
        fetchedChapters: fetched.length,
        restrictedChapters: restricted,
        addedQuestions: apply.added,
        updatedQuestions: apply.updated,
        extraLocalQuestions: apply.extra,
        remainingChapters: failed.length + remaining.length,
        requestsUsed: _requestsUsed,
        elapsedMs: sw.elapsedMilliseconds,
        error: failed.isEmpty ? null : '${failed.length} 个章节待重试',
      );
    } catch (e, stack) {
      debugPrint('[ykb-smart-sync] 失败: $e');
      debugPrint('$stack');
      try {
        if (stagingPath.isNotEmpty && await File(stagingPath).exists()) {
          await File(stagingPath).delete();
        }
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('loggedin') ?? false) {
          final bankId =
              bank?.bankId ??
              (await SharedPreferences.getInstance()).getString('activeBankId');
          if (bankId != null && bankId.isNotEmpty) {
            final userDb = await UserDBHelper().database;
            await _ensureBankState(userDb, bankId);
            final state = await _loadBankState(userDb, bankId);
            final failures =
                ((state['failure_count'] as num?)?.toInt() ?? 0) + 1;
            await _saveBankState(userDb, bankId, {
              'failure_count': failures,
              'next_retry_at':
                  DateTime.now().millisecondsSinceEpoch + _backoffMs(failures),
              'last_error': e.toString(),
              'last_sync_at': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      } catch (_) {}
      return YkbBankSmartSyncResult(
        error: e.toString(),
        requestsUsed: _requestsUsed,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 目录 / 选择
  // ---------------------------------------------------------------------------

  Future<QuestionBank?> _activeBank() async {
    final repository = QuestionBankRepository();
    return repository.find(await repository.activeBankId());
  }

  Future<_Manifest> _fetchManifest(
    QuestionBank bank,
    SharedPreferences prefs,
    Map<String, _LocalChapter> localChapters,
    Map<String, Map<String, dynamic>> chapterStates, {
    required int bankGeneratedAt,
  }) async {
    await _jitter();
    final identityResp = await basicReq('/allQuestion/question/subjectV2', {
      'user_id': prefs.getString('user_id') ?? '',
    }, method: 'GET');
    _requestsUsed++;
    if (identityResp['code']?.toString() != '200') {
      throw StateError('身份目录拉取失败：${identityResp['code']}');
    }
    final tree = _asList(identityResp['data']);
    final identityNode = _findNode(tree, bank.identityId);
    if (identityNode == null) {
      throw StateError('身份树中找不到 ${bank.identityId}');
    }
    final entries = _asList(
      identityNode['children'],
    ).where((e) => (e['identity_id']?.toString() ?? '0') != '0').toList();

    final leaves = <_RemoteChapter>[];
    for (final entry in entries) {
      if (_requestsUsed >= _maxRequestsPerRun) {
        throw StateError('目录请求超出本轮预算');
      }
      await _jitter();
      final chapterResp = await basicReq('/allquestion/question/chapter', {
        'identity_id': entry['identity_id'].toString(),
        'category': 'chapter',
        'type': 'all',
        'module_type': (entry['module_type'] ?? '1').toString(),
        'am_pm': '',
        'search_where': '[]',
        'app_id': (entry['app_id'] ?? '40').toString(),
      });
      _requestsUsed++;
      if (chapterResp['code']?.toString() != '200') {
        throw StateError('章节目录拉取失败：${chapterResp['code']}');
      }
      final identityId = entry['identity_id'].toString();
      final appId = (entry['app_id'] ?? '40').toString();
      final moduleType = (entry['module_type'] ?? '1').toString();
      for (final subject in _asList(chapterResp['data'])) {
        final subjectId = (subject['chapter_id'] ?? '').toString();
        final subjectTitle = subject['title']?.toString() ?? '';
        _collectLeaves(
          subject,
          identityId,
          appId,
          moduleType,
          subjectId,
          subjectTitle,
          leaves,
        );
      }
    }

    // 同一章节可能被多个入口返回，按远端章节 ID 去重。
    final byId = <String, _RemoteChapter>{};
    for (final leaf in leaves) {
      byId.putIfAbsent(leaf.id, () => leaf);
    }
    final unique = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    final hash = _sha256(
      unique
          .map((e) => '${e.id}|${e.identityId}|${e.count}|${e.updatedAt}')
          .join('\n'),
    );

    final bootstraps = <Map<String, dynamic>>[];
    final pending = <_RemoteChapter>[];
    final lastChapterId = prefs.getString('lastChapterId') ?? '';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const restrictedRetryMs = 7 * 24 * 60 * 60 * 1000;
    for (final leaf in unique) {
      final state = chapterStates[leaf.id];
      if (state != null &&
          (state['remote_count'] as num?)?.toInt() == leaf.count &&
          (state['remote_updated_at']?.toString() ?? '') == leaf.updatedAt) {
        final method = state['match_method']?.toString() ?? '';
        final lastSynced = (state['last_synced_at'] as num?)?.toInt() ?? 0;
        // 无权限章节按周重试；期间不占用请求预算。
        if (method != 'restricted' || nowMs - lastSynced < restrictedRetryMs) {
          continue;
        }
        pending.add(leaf);
        continue;
      }
      if (state == null) {
        final sameId = localChapters[leaf.id];
        if (sameId != null && sameId.norm == leaf.norm) {
          if (sameId.total == leaf.count &&
              !_updatedAfterBank(leaf.updatedAt, bankGeneratedAt)) {
            bootstraps.add(
              _chapterStateRow(
                bank.bankId,
                leaf,
                '',
                sameId.id,
                sameId.subjectId,
                sameId.name,
                'id-title-count',
                0,
                nowMs,
              ),
            );
          } else {
            // 题量变化或远端章节在题库生成后更新过：必须拉取校验，
            // 不能按标题/题量猜测，避免映射到别的章节。
            pending.add(leaf);
          }
          continue;
        }
      }
      pending.add(leaf);
    }

    pending.sort((a, b) {
      final ap = _priority(a, lastChapterId, localChapters);
      final bp = _priority(b, lastChapterId, localChapters);
      if (ap != bp) return ap.compareTo(bp);
      final at = a.updatedAt.compareTo(b.updatedAt);
      if (at != 0) return -at;
      return a.id.compareTo(b.id);
    });

    return _Manifest(
      leaves: unique,
      pending: pending,
      bootstraps: bootstraps,
      hash: hash,
    );
  }

  int _priority(
    _RemoteChapter rc,
    String lastChapterId,
    Map<String, _LocalChapter> localChapters,
  ) {
    if (rc.id == lastChapterId) return 0;
    final local = localChapters[rc.id];
    if (local != null && local.norm == rc.norm) return 1;
    if (localChapters.values.any((c) => c.norm == rc.norm)) return 2;
    return 3;
  }

  void _collectLeaves(
    Map<String, dynamic> node,
    String identityId,
    String appId,
    String moduleType,
    String subjectId,
    String subjectTitle,
    List<_RemoteChapter> out,
  ) {
    final children = _asList(node['children']);
    final id = (node['chapter_id'] ?? node['id'] ?? '').toString();
    final title = node['title']?.toString() ?? '';
    if (children.isEmpty) {
      if (id.isEmpty) return;
      out.add(
        _RemoteChapter(
          id: id,
          identityId: identityId,
          subjectId: subjectId,
          subjectTitle: subjectTitle,
          title: title,
          count: int.tryParse(node['count']?.toString() ?? '') ?? 0,
          updatedAt: node['updated_at']?.toString() ?? '',
          appId: appId,
          moduleType: moduleType,
        ),
      );
      return;
    }
    for (final child in children) {
      _collectLeaves(
        child,
        identityId,
        appId,
        moduleType,
        subjectId,
        subjectTitle,
        out,
      );
    }
  }

  Map<String, dynamic>? _findNode(
    List<Map<String, dynamic>> nodes,
    String identityId,
  ) {
    for (final node in nodes) {
      if (node['identity_id']?.toString() == identityId) return node;
      final found = _findNode(_asList(node['children']), identityId);
      if (found != null) return found;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 章节映射
  // ---------------------------------------------------------------------------

  Future<_ChapterMapping> _resolveMapping(
    _RemoteChapter rc,
    List<Map<String, dynamic>> questions,
    Map<String, dynamic>? oldState,
    Map<String, _LocalChapter> localChapters,
    Map<String, _LocalSubject> localSubjects,
    Database bankDb,
    String bankIdentityId,
  ) async {
    final oldLocalId = oldState?['local_chapter_id']?.toString() ?? '';
    if (oldLocalId.isNotEmpty && localChapters.containsKey(oldLocalId)) {
      final local = localChapters[oldLocalId]!;
      return _ChapterMapping(
        localChapterId: local.id,
        localSubjectId: local.subjectId,
        localTitle: local.name,
        method: 'state',
        confidence: 1,
        isNewChapter: false,
        isNewSubject: false,
        subjectName: '',
      );
    }

    final same = localChapters[rc.id];
    if (same != null && same.norm == rc.norm) {
      return _ChapterMapping(
        localChapterId: same.id,
        localSubjectId: same.subjectId,
        localTitle: same.name,
        method: 'id-title',
        confidence: 1,
        isNewChapter: false,
        isNewSubject: false,
        subjectName: '',
      );
    }

    final exact = localChapters.values.where((c) => c.norm == rc.norm).toList();
    if (exact.length == 1) {
      final c = exact.first;
      return _ChapterMapping(
        localChapterId: c.id,
        localSubjectId: c.subjectId,
        localTitle: c.name,
        method: 'title',
        confidence: 0.95,
        isNewChapter: false,
        isNewSubject: false,
        subjectName: '',
      );
    }
    if (exact.length > 1) {
      final sameSubject = exact
          .where((c) => c.subjectId == rc.subjectId)
          .toList();
      if (sameSubject.length == 1) {
        final c = sameSubject.first;
        return _ChapterMapping(
          localChapterId: c.id,
          localSubjectId: c.subjectId,
          localTitle: c.name,
          method: 'title-subject',
          confidence: 0.94,
          isNewChapter: false,
          isNewSubject: false,
          subjectName: '',
        );
      }
    }

    _LocalChapter? best;
    var bestScore = 0.0;
    for (final c in localChapters.values) {
      if (c.norm.isEmpty) continue;
      final score =
          _similarity(rc.norm, c.norm) +
          (c.subjectId == rc.subjectId ? 0.03 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best != null && bestScore >= 0.86) {
      return _ChapterMapping(
        localChapterId: best.id,
        localSubjectId: best.subjectId,
        localTitle: best.name,
        method: 'fuzzy',
        confidence: bestScore,
        isNewChapter: false,
        isNewSubject: false,
        subjectName: '',
      );
    }

    final overlap = await _matchByOverlap(
      rc,
      questions,
      localChapters,
      bankDb,
      bankIdentityId,
    );
    if (overlap != null) return overlap;

    return _newChapterMapping(rc, localChapters, localSubjects);
  }

  Future<_ChapterMapping?> _matchByOverlap(
    _RemoteChapter rc,
    List<Map<String, dynamic>> questions,
    Map<String, _LocalChapter> localChapters,
    Database bankDb,
    String bankIdentityId,
  ) async {
    final ids = questions
        .map((q) => q['id']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return null;

    final existing = <String>[];
    for (var i = 0; i < ids.length; i += 400) {
      final slice = ids.sublist(i, min(i + 400, ids.length));
      final ph = List.filled(slice.length, '?').join(',');
      final rows = await bankDb.rawQuery(
        'SELECT id FROM Question WHERE id IN ($ph)',
        slice,
      );
      existing.addAll(rows.map((r) => r['id']?.toString() ?? ''));
    }
    if (existing.isEmpty) return null;

    final counts = <String, int>{};
    for (var i = 0; i < existing.length; i += 400) {
      final slice = existing.sublist(i, min(i + 400, existing.length));
      final ph = List.filled(slice.length, '?').join(',');
      final rows = await bankDb.rawQuery(
        'SELECT chapter_id, COUNT(*) c FROM IdentityQuestion '
        'WHERE identity_id = ? AND question_id IN ($ph) '
        'GROUP BY chapter_id',
        [bankIdentityId, ...slice],
      );
      for (final row in rows) {
        final cid = row['chapter_id']?.toString() ?? '';
        if (cid.isEmpty) continue;
        counts[cid] = (counts[cid] ?? 0) + ((row['c'] as num?)?.toInt() ?? 0);
      }
    }
    if (counts.isEmpty) return null;

    String? bestId;
    var bestOverlap = 0;
    var bestRatio = 0.0;
    for (final entry in counts.entries) {
      final local = localChapters[entry.key];
      if (local == null) continue;
      final denom = min(local.total, rc.count);
      final ratio = denom > 0 ? entry.value / denom : 0.0;
      if (entry.value > bestOverlap ||
          (entry.value == bestOverlap && ratio > bestRatio)) {
        bestId = entry.key;
        bestOverlap = entry.value;
        bestRatio = ratio;
      }
    }
    if (bestId == null || bestOverlap < 5 || bestRatio < 0.30) return null;
    final local = localChapters[bestId]!;
    return _ChapterMapping(
      localChapterId: local.id,
      localSubjectId: local.subjectId,
      localTitle: local.name,
      method: 'overlap',
      confidence: bestRatio,
      isNewChapter: false,
      isNewSubject: false,
      subjectName: '',
    );
  }

  _ChapterMapping _newChapterMapping(
    _RemoteChapter rc,
    Map<String, _LocalChapter> localChapters,
    Map<String, _LocalSubject> localSubjects,
  ) {
    final localChapterId = localChapters.containsKey(rc.id)
        ? 'ykb_${rc.id}_${_hash8(rc.title)}'
        : rc.id;
    var subjectId = rc.subjectId;
    var subjectName = rc.subjectTitle;
    var isNewSubject = true;
    final byId = localSubjects[rc.subjectId];
    if (byId != null &&
        (_normTitle(byId.name) == _normTitle(rc.subjectTitle) ||
            byId.name == rc.subjectTitle)) {
      subjectId = byId.id;
      subjectName = byId.name;
      isNewSubject = false;
    } else if (byId != null) {
      subjectId = 'ykb_sub_${rc.subjectId}_${_hash8(rc.title)}';
    } else {
      final byName = localSubjects.values
          .where((s) => _normTitle(s.name) == _normTitle(rc.subjectTitle))
          .toList();
      if (byName.length == 1) {
        subjectId = byName.first.id;
        subjectName = byName.first.name;
        isNewSubject = false;
      } else if (localSubjects.containsKey(subjectId)) {
        subjectId = 'ykb_sub_${rc.subjectId}_${_hash8(rc.title)}';
      }
    }
    return _ChapterMapping(
      localChapterId: localChapterId,
      localSubjectId: subjectId,
      localTitle: rc.title,
      method: 'new',
      confidence: 0,
      isNewChapter: true,
      isNewSubject: isNewSubject,
      subjectName: subjectName,
    );
  }

  // ---------------------------------------------------------------------------
  // staging 应用 + 原子安装
  // ---------------------------------------------------------------------------

  Future<_ApplyResult> _applyToStaging({
    required String stagingPath,
    required String bankId,
    required String bankIdentityId,
    required List<_FetchedChapter> items,
    required int nowMs,
    required String version,
  }) async {
    final db = await openDatabase(stagingPath);
    var added = 0;
    var updated = 0;
    var extra = 0;
    try {
      try {
        await db.rawQuery('PRAGMA busy_timeout = 5000');
      } catch (_) {}
      await db.transaction((txn) async {
        for (final item in items) {
          final m = item.mapping;
          if (m.isNewSubject) {
            await txn.insert('Subject', {
              'id': m.localSubjectId,
              'name': m.subjectName,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          if (m.isNewChapter) {
            await txn.insert('Chapter', {
              'id': m.localChapterId,
              'name': m.localTitle,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            await txn.insert('IdentityChapter', {
              'identity_id': bankIdentityId,
              'subject_id': m.localSubjectId,
              'chapter_id': m.localChapterId,
              'total': 0,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await txn.insert('IdentitySubject', {
            'identity_id': bankIdentityId,
            'subject_id': m.localSubjectId,
            'total': 0,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          final remoteIds = item.questions
              .map((q) => q['id']?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
          final existingRows = <String, Map<String, dynamic>>{};
          for (var i = 0; i < remoteIds.length; i += 400) {
            final slice = remoteIds.sublist(i, min(i + 400, remoteIds.length));
            final ph = List.filled(slice.length, '?').join(',');
            final rows = await txn.rawQuery(
              'SELECT * FROM Question WHERE id IN ($ph)',
              slice,
            );
            for (final row in rows) {
              existingRows[row['id'] as String] = Map<String, dynamic>.from(
                row,
              );
            }
          }

          for (final q in item.questions) {
            final row = YkbBankSyncService.questionRow(q, bankIdentityId, {
              'id': m.localChapterId,
              'parentId': m.localSubjectId,
            });
            // 题库是共享内容库，不把账号的作答状态写进题库文件。
            row['cut_question'] = '0';
            row['user_answer'] = '';
            final qid = row['id'] as String;
            final old = existingRows[qid];
            if (old == null) {
              await txn.insert(
                'Question',
                row,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              added++;
            } else if (_rowHash(old) != _rowHash(row)) {
              await txn.update(
                'Question',
                row,
                where: 'id = ?',
                whereArgs: [qid],
              );
              updated++;
            }
            await txn.insert('IdentityQuestion', {
              'identity_id': bankIdentityId,
              'subject_id': m.localSubjectId,
              'chapter_id': m.localChapterId,
              'question_id': qid,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }

          final linkCount =
              Sqflite.firstIntValue(
                await txn.rawQuery(
                  'SELECT COUNT(*) FROM IdentityQuestion '
                  'WHERE identity_id = ? AND chapter_id = ?',
                  [bankIdentityId, m.localChapterId],
                ),
              ) ??
              0;
          final extraCount = linkCount - item.questions.length;
          if (extraCount > 0) extra += extraCount;
          item.extraCount = extraCount > 0 ? extraCount : 0;

          // 兼容旧题库中「Chapter 存在但 IdentityChapter 缺失」的章节。
          await txn.insert('IdentityChapter', {
            'identity_id': bankIdentityId,
            'subject_id': m.localSubjectId,
            'chapter_id': m.localChapterId,
            'total': 0,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.update(
            'IdentityChapter',
            {'total': linkCount},
            where: 'identity_id = ? AND subject_id = ? AND chapter_id = ?',
            whereArgs: [bankIdentityId, m.localSubjectId, m.localChapterId],
          );
          final subjectTotal =
              Sqflite.firstIntValue(
                await txn.rawQuery(
                  'SELECT COUNT(*) FROM IdentityQuestion '
                  'WHERE identity_id = ? AND subject_id = ?',
                  [bankIdentityId, m.localSubjectId],
                ),
              ) ??
              0;
          await txn.update(
            'IdentitySubject',
            {'total': subjectTotal},
            where: 'identity_id = ? AND subject_id = ?',
            whereArgs: [bankIdentityId, m.localSubjectId],
          );
        }

        await txn.rawUpdate(
          'UPDATE BankMeta SET '
          'version = ?, generated_at = ?, '
          'question_count = (SELECT COUNT(*) FROM Question), '
          'relation_count = (SELECT COUNT(*) FROM IdentityQuestion), '
          'chapter_count = (SELECT COUNT(*) FROM Chapter), '
          'subject_count = (SELECT COUNT(*) FROM Subject)',
          [version, nowMs ~/ 1000],
        );
      });

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final integrityResult = integrity.isNotEmpty
          ? integrity.first.values.first?.toString()
          : 'unknown';
      if (integrityResult != 'ok') {
        throw StateError('staging 完整性校验失败: $integrityResult');
      }
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) {
        throw StateError('staging 外键校验失败: ${fk.length} 条');
      }
      final counts = await db.rawQuery(
        'SELECT '
        '(SELECT COUNT(*) FROM Question) q, '
        '(SELECT COUNT(*) FROM IdentityQuestion) iq, '
        '(SELECT COUNT(*) FROM Chapter) c, '
        '(SELECT COUNT(*) FROM Subject) s, '
        '(SELECT question_count FROM BankMeta LIMIT 1) bq, '
        '(SELECT relation_count FROM BankMeta LIMIT 1) br',
      );
      final row = counts.first;
      final q = (row['q'] as num?)?.toInt() ?? 0;
      final iq = (row['iq'] as num?)?.toInt() ?? 0;
      if (q != (row['bq'] as num?)?.toInt() ||
          iq != (row['br'] as num?)?.toInt()) {
        throw StateError('staging 计数校验失败');
      }
    } finally {
      await db.close();
    }
    return _ApplyResult(added: added, updated: updated, extra: extra);
  }

  Future<String> _bankPath(QuestionBank bank) async {
    if (bank.localPath.isNotEmpty && await File(bank.localPath).exists()) {
      return bank.localPath;
    }
    return QuestionBankDatabaseManager().pathFor(bank.bankId);
  }

  // ---------------------------------------------------------------------------
  // 本地索引 / 状态
  // ---------------------------------------------------------------------------

  Future<Map<String, _LocalChapter>> _loadLocalChapters(
    Database bankDb,
    String bankIdentityId,
  ) async {
    final rows = await bankDb.rawQuery(
      'SELECT c.id AS id, c.name AS name, '
      'ic.subject_id AS subject_id, ic.total AS total '
      'FROM Chapter c LEFT JOIN IdentityChapter ic '
      'ON ic.chapter_id = c.id AND ic.identity_id = ?',
      [bankIdentityId],
    );
    final map = <String, _LocalChapter>{};
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || map.containsKey(id)) continue;
      final name = row['name']?.toString() ?? '';
      map[id] = _LocalChapter(
        id: id,
        name: name,
        subjectId: row['subject_id']?.toString() ?? '',
        total: (row['total'] as num?)?.toInt() ?? 0,
        norm: _normTitle(name),
      );
    }
    return map;
  }

  Future<Map<String, _LocalSubject>> _loadLocalSubjects(Database bankDb) async {
    final rows = await bankDb.query('Subject', columns: ['id', 'name']);
    return {
      for (final row in rows)
        row['id'].toString(): _LocalSubject(
          id: row['id'].toString(),
          name: row['name']?.toString() ?? '',
        ),
    };
  }

  Future<Map<String, dynamic>> _loadBankState(
    Database db,
    String bankId,
  ) async {
    final rows = await db.query(
      'YkbBankSyncState',
      where: 'bank_id = ?',
      whereArgs: [bankId],
      limit: 1,
    );
    return rows.isEmpty
        ? <String, dynamic>{'bank_id': bankId}
        : Map<String, dynamic>.from(rows.first);
  }

  Future<void> _ensureBankState(Database db, String bankId) async {
    await db.insert('YkbBankSyncState', {
      'bank_id': bankId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _saveBankState(
    Database db,
    String bankId,
    Map<String, dynamic> values,
  ) async {
    await db.update(
      'YkbBankSyncState',
      values,
      where: 'bank_id = ?',
      whereArgs: [bankId],
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadChapterStates(
    Database db,
    String bankId,
  ) async {
    final rows = await db.query(
      'YkbBankChapterState',
      where: 'bank_id = ?',
      whereArgs: [bankId],
    );
    return {
      for (final row in rows)
        row['remote_chapter_id'].toString(): Map<String, dynamic>.from(row),
    };
  }

  Future<void> _upsertChapterStates(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'YkbBankChapterState',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Map<String, dynamic> _chapterStateRow(
    String bankId,
    _RemoteChapter rc,
    String remoteHash,
    String localChapterId,
    String localSubjectId,
    String localTitle,
    String method,
    int extraCount,
    int nowMs,
  ) {
    return {
      'bank_id': bankId,
      'remote_chapter_id': rc.id,
      'remote_identity_id': rc.identityId,
      'remote_subject_id': rc.subjectId,
      'remote_title': rc.title,
      'remote_count': rc.count,
      'remote_updated_at': rc.updatedAt,
      'remote_hash': remoteHash,
      'local_chapter_id': localChapterId,
      'local_subject_id': localSubjectId,
      'local_title': localTitle,
      'match_method': method,
      'extra_count': extraCount,
      'last_synced_at': nowMs,
    };
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  Future<void> _jitter() async {
    final ms =
        _minRequestGapMs +
        Random().nextInt(_maxRequestGapMs - _minRequestGapMs + 1);
    await Future.delayed(Duration(milliseconds: ms));
  }

  static int _backoffMs(int failures) {
    final minutes = min(24 * 60, 15 * (1 << min(failures, 7)));
    return minutes * 60 * 1000;
  }

  String _chapterHash(
    List<Map<String, dynamic>> questions,
    _RemoteChapter rc,
    String bankIdentityId,
  ) {
    final lines = <String>[];
    for (final q in questions) {
      final row = YkbBankSyncService.questionRow(q, bankIdentityId, {
        'id': rc.id,
        'parentId': rc.subjectId,
      });
      lines.add('${q['id']}|${_rowHash(row)}');
    }
    lines.sort();
    return _sha256('${rc.id}\n${lines.join('\n')}');
  }

  String _rowHash(Map<String, dynamic> row) {
    // 只比较题目内容；章节归属、身份归属和账号状态由同步映射/用户库单独维护。
    const excluded = {
      'cut_question',
      'user_answer',
      'chapter_id',
      'chapter_parent_id',
      'identity_id',
    };
    final keys = row.keys.where((k) => !excluded.contains(k)).toList()..sort();
    return _sha256(keys.map((k) => '$k=${row[k] ?? ''}').join('\n'));
  }

  String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

  String _hash8(String value) => _sha256(value).substring(0, 8);

  bool _updatedAfterBank(String updatedAt, int bankGeneratedAtSeconds) {
    if (updatedAt.isEmpty || bankGeneratedAtSeconds <= 0) return false;
    final dt = DateTime.tryParse(updatedAt);
    if (dt == null) return false;
    return dt.millisecondsSinceEpoch > bankGeneratedAtSeconds * 1000;
  }

  String _normTitle(String title) {
    var t = title;
    t = t.replaceAll(RegExp(r'第[一二三四五六七八九十百千万零〇0-9０-９]+[章节部分篇讲]'), '');
    t = t.replaceAll(RegExp(r'[\s\-—_、，,。.：:；;（）()【】\[\]《》<>]'), '');
    return t;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final lcs = _lcsRatio(a, b);
    return lcs;
  }

  double _lcsRatio(String a, String b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return 0;
    var prev = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      final cur = List<int>.filled(m + 1, 0);
      for (var j = 1; j <= m; j++) {
        cur[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? prev[j - 1] + 1
            : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
      }
      prev = cur;
    }
    return 2 * prev[m] / (n + m);
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  List<_RemoteChapter> _decodePending(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => _RemoteChapter.fromJson(Map<String, dynamic>.from(e)))
          .where((chapter) => chapter.id.isNotEmpty && chapter.count >= 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _encodePending(List<_RemoteChapter> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}

// -----------------------------------------------------------------------------
// 内部数据模型
// -----------------------------------------------------------------------------

class _Manifest {
  final List<_RemoteChapter> leaves;
  final List<_RemoteChapter> pending;
  final List<Map<String, dynamic>> bootstraps;
  final String hash;

  const _Manifest({
    required this.leaves,
    required this.pending,
    required this.bootstraps,
    required this.hash,
  });
}

class _RemoteChapter {
  final String id;
  final String identityId;
  final String subjectId;
  final String subjectTitle;
  final String title;
  final int count;
  final String updatedAt;
  final String appId;
  final String moduleType;

  const _RemoteChapter({
    required this.id,
    required this.identityId,
    required this.subjectId,
    required this.subjectTitle,
    required this.title,
    required this.count,
    required this.updatedAt,
    required this.appId,
    required this.moduleType,
  });

  String get norm => _normStatic(title);

  Map<String, dynamic> toJson() => {
    'id': id,
    'identityId': identityId,
    'subjectId': subjectId,
    'subjectTitle': subjectTitle,
    'title': title,
    'count': count,
    'updatedAt': updatedAt,
    'appId': appId,
    'moduleType': moduleType,
  };

  factory _RemoteChapter.fromJson(Map<String, dynamic> json) => _RemoteChapter(
    id: json['id']?.toString() ?? '',
    identityId: json['identityId']?.toString() ?? '',
    subjectId: json['subjectId']?.toString() ?? '',
    subjectTitle: json['subjectTitle']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
    updatedAt: json['updatedAt']?.toString() ?? '',
    appId: json['appId']?.toString() ?? '40',
    moduleType: json['moduleType']?.toString() ?? '1',
  );
}

class _LocalChapter {
  final String id;
  final String name;
  final String subjectId;
  final int total;
  final String norm;

  const _LocalChapter({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.total,
    required this.norm,
  });
}

class _LocalSubject {
  final String id;
  final String name;

  const _LocalSubject({required this.id, required this.name});
}

class _ChapterMapping {
  final String localChapterId;
  final String localSubjectId;
  final String localTitle;
  final String method;
  final double confidence;
  final bool isNewChapter;
  final bool isNewSubject;
  final String subjectName;

  const _ChapterMapping({
    required this.localChapterId,
    required this.localSubjectId,
    required this.localTitle,
    required this.method,
    required this.confidence,
    required this.isNewChapter,
    required this.isNewSubject,
    required this.subjectName,
  });
}

class _FetchedChapter {
  final _RemoteChapter rc;
  final List<Map<String, dynamic>> questions;
  final String remoteHash;
  final _ChapterMapping mapping;
  int extraCount = 0;

  _FetchedChapter({
    required this.rc,
    required this.questions,
    required this.remoteHash,
    required this.mapping,
  });
}

class _ApplyResult {
  final int added;
  final int updated;
  final int extra;

  const _ApplyResult({
    required this.added,
    required this.updated,
    required this.extra,
  });
}

String _normStatic(String title) {
  var t = title;
  t = t.replaceAll(RegExp(r'第[一二三四五六七八九十百千万零〇0-9０-９]+[章节部分篇讲]'), '');
  t = t.replaceAll(RegExp(r'[\s\-—_、，,。.：:；;（）()【】\[\]《》<>]'), '');
  return t;
}
