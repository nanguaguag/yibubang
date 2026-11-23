import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../db/database_helper.dart';
import '../db/durable_sync_queue.dart';
import '../db/question_bank_manager.dart';
import '../models/chapter.dart';
import '../models/question.dart';

/// 题目同步上下文元数据（统一解析 subjectId / chapterId / identityId / appId）
class QuestionSyncMeta {
  final String subjectId;
  final String chapterId;
  final String identityId;
  final String appId;
  final String chapterParentId;

  const QuestionSyncMeta({
    required this.subjectId,
    required this.chapterId,
    required this.identityId,
    required this.appId,
    required this.chapterParentId,
  });
}

/// 医考帮同步队列单项
class YkbSyncQueueItem {
  final String id;
  final String type; // 'cut', 'answer', 'redo_chapter'
  final String? itemId;
  final Map<String, dynamic> payload;
  final int retryCount;
  final int createdAt;
  final String? lastError;
  final String? lastResponse;

  YkbSyncQueueItem({
    required this.id,
    required this.type,
    this.itemId,
    required this.payload,
    this.retryCount = 0,
    required this.createdAt,
    this.lastError,
    this.lastResponse,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'item_id': itemId,
    'payload': jsonEncode(payload),
    'retry_count': retryCount,
    'created_at': createdAt,
    'last_error': lastError,
    'last_response': lastResponse,
  };

  factory YkbSyncQueueItem.fromMap(Map<String, dynamic> map) =>
      YkbSyncQueueItem(
        id: map['id'] as String,
        type: map['type'] as String,
        itemId: map['item_id'] as String?,
        payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        lastError: map['last_error'] as String?,
        lastResponse: map['last_response'] as String?,
      );

  YkbSyncQueueItem copyWith({
    String? id,
    String? type,
    String? itemId,
    Map<String, dynamic>? payload,
    int? retryCount,
    int? createdAt,
    String? lastError,
    String? lastResponse,
  }) => YkbSyncQueueItem(
    id: id ?? this.id,
    type: type ?? this.type,
    itemId: itemId ?? this.itemId,
    payload: payload ?? this.payload,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
    lastError: lastError ?? this.lastError,
    lastResponse: lastResponse ?? this.lastResponse,
  );
}

/// 内存中的同步响应记录（不写入数据库，可随时清理）
class SyncResponseRecord {
  final String queueId;
  final String? itemId;
  final String type;
  final String code; // '200', '400', '403', '500', 'ERR' 等
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? response;
  final String rawResponse;
  final int timestamp;

  SyncResponseRecord({
    required this.queueId,
    this.itemId,
    required this.type,
    required this.code,
    this.payload,
    this.response,
    required this.rawResponse,
    required this.timestamp,
  });

  bool get isSuccess => code == '200';
}

/// 同步响应全局内存缓存
class SyncResponseCache {
  static final SyncResponseCache instance = SyncResponseCache._internal();
  SyncResponseCache._internal();

  final Map<String, SyncResponseRecord> _byQueueId = {};
  final Map<String, SyncResponseRecord> _byTypedItem = {};
  final Map<String, SyncResponseRecord> _byItemId = {};
  final List<SyncResponseRecord> _history = [];

  static String _typedKey(String type, String itemId) => '$type:$itemId';

  void record({
    required String queueId,
    String? itemId,
    required String type,
    required String code,
    Map<String, dynamic>? payload,
    Map<String, dynamic>? response,
    required String rawResponse,
  }) {
    final item = SyncResponseRecord(
      queueId: queueId,
      itemId: itemId,
      type: type,
      code: code,
      payload: payload,
      response: response,
      rawResponse: rawResponse,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _byQueueId[queueId] = item;
    if (itemId != null && itemId.isNotEmpty) {
      _byItemId[itemId] = item;
      _byTypedItem[_typedKey(type, itemId)] = item;
    }
    _history.insert(0, item);
    if (_history.length > 200) {
      final removed = _history.removeLast();
      if (_byQueueId[removed.queueId] == removed) {
        _byQueueId.remove(removed.queueId);
      }
      if (removed.itemId != null) {
        if (_byItemId[removed.itemId] == removed) {
          _byItemId.remove(removed.itemId);
        }
        final tKey = _typedKey(removed.type, removed.itemId!);
        if (_byTypedItem[tKey] == removed) {
          _byTypedItem.remove(tKey);
        }
      }
    }
  }

  SyncResponseRecord? getByQueueId(String? queueId) {
    if (queueId == null) return null;
    return _byQueueId[queueId];
  }

  SyncResponseRecord? getByItemId(String? itemId, {String? type}) {
    if (itemId == null || itemId.isEmpty) return null;
    if (type != null && type.isNotEmpty) {
      return _byTypedItem[_typedKey(type, itemId)];
    }
    return _byItemId[itemId];
  }

  List<SyncResponseRecord> get history => List.unmodifiable(_history);

  void clear() {
    _byQueueId.clear();
    _byTypedItem.clear();
    _byItemId.clear();
    _history.clear();
  }
}

/// 医考帮云端数据（斩题、做题、章节重做）同步及离线队列服务
class YkbSyncService {
  static final YkbSyncService instance = YkbSyncService._internal();
  YkbSyncService._internal();

  static const String keySyncCutToYkb = 'sync_cut_to_ykb';
  static const String keySyncAnswersToYkb = 'sync_answers_to_ykb';
  static const String keySyncRedoToYkb = 'sync_redo_to_ykb';
  static const String keySyncReviewAnswersToYkb = 'sync_review_answers_to_ykb';
  static const String keySyncReviewCutToYkb = 'sync_review_cut_to_ykb';

  /// 是否开启斩题同步到医考帮
  Future<bool> isSyncCutEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySyncCutToYkb) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 是否开启做题同步到医考帮
  Future<bool> isSyncAnswersEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 兼容历史 key: questionUpload (不应与题库清单 sync_question_bank 混淆)
      if (prefs.containsKey(keySyncAnswersToYkb)) {
        return prefs.getBool(keySyncAnswersToYkb) ?? true;
      }
      if (prefs.containsKey('questionUpload')) {
        return prefs.getBool('questionUpload') ?? true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 是否开启章节重做同步到医考帮
  Future<bool> isSyncRedoEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySyncRedoToYkb) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 是否开启每日复习做题同步到医考帮
  Future<bool> isSyncReviewAnswersEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySyncReviewAnswersToYkb) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 是否开启每日复习熟练斩题同步到医考帮
  Future<bool> isSyncReviewCutEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySyncReviewCutToYkb) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 统一解析题目的同步上下文元数据（subjectId, chapterId, identityId, appId）。
  /// 优先使用显式参数与 Question/Chapter，缺失时自动回退查询用户库投影与题库。
  Future<QuestionSyncMeta> resolveQuestionMeta(
    String questionId, {
    Question? question,
    Chapter? chapter,
    String? subjectId,
    String? chapterId,
    String? identityId,
    String? appId,
    String? chapterParentId,
    String? bankId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var resSubject =
        _nonEmpty(subjectId) ??
        _nonEmpty(chapter?.subjectId) ??
        _nonEmpty(question?.chapterParentId) ??
        '';
    var resChapter =
        _nonEmpty(chapterId) ??
        _nonEmpty(chapter?.id) ??
        _nonEmpty(question?.chapterId) ??
        '';
    var resIdentity =
        _nonEmpty(identityId) ??
        _nonEmpty(chapter?.identityId) ??
        _nonEmpty(question?.nativeIdentityId) ??
        _nonEmpty(question?.identityId) ??
        '';
    var resAppId =
        _nonEmpty(appId) ??
        _nonEmpty(question?.nativeAppId) ??
        _nonEmpty(question?.appId) ??
        '';
    var resParent =
        _nonEmpty(chapterParentId) ?? _nonEmpty(question?.chapterParentId) ?? '';

    if (resSubject.isEmpty ||
        resChapter.isEmpty ||
        resIdentity.isEmpty ||
        resParent.isEmpty) {
      try {
        final userDb = await UserDBHelper().database;
        final relRows = await userDb.query(
          'QuestionRelations',
          columns: ['identity_id', 'subject_id', 'chapter_id'],
          where: 'question_id = ?',
          whereArgs: [questionId],
          limit: 1,
        );
        if (relRows.isNotEmpty) {
          final r = relRows.first;
          if (resSubject.isEmpty) {
            resSubject = _nonEmpty(r['subject_id']?.toString()) ?? '';
          }
          if (resChapter.isEmpty) {
            resChapter = _nonEmpty(r['chapter_id']?.toString()) ?? '';
          }
          if (resIdentity.isEmpty) {
            resIdentity = _nonEmpty(r['identity_id']?.toString()) ?? '';
          }
        }
        if (resParent.isEmpty || resChapter.isEmpty) {
          final qRows = await userDb.query(
            'Question',
            columns: ['chapter_id', 'chapter_parent_id'],
            where: 'id = ?',
            whereArgs: [questionId],
            limit: 1,
          );
          if (qRows.isNotEmpty) {
            final r = qRows.first;
            if (resParent.isEmpty) {
              resParent = _nonEmpty(r['chapter_parent_id']?.toString()) ?? '';
            }
            if (resChapter.isEmpty) {
              resChapter = _nonEmpty(r['chapter_id']?.toString()) ?? '';
            }
          }
        }
      } catch (_) {}
    }

    if (resSubject.isEmpty ||
        resChapter.isEmpty ||
        resIdentity.isEmpty ||
        resAppId.isEmpty ||
        resParent.isEmpty) {
      final targetBankId =
          _nonEmpty(bankId) ??
          _nonEmpty(question?.sourceBankId) ??
          _nonEmpty(prefs.getString('activeBankId'));
      if (targetBankId != null) {
        try {
          final bankDb = await QuestionBankDatabaseManager().openBank(
            targetBankId,
          );
          final qRows = await bankDb.query(
            'Question',
            columns: [
              'chapter_id',
              'chapter_parent_id',
              'identity_id',
              'native_identity_id',
              'app_id',
              'native_app_id',
            ],
            where: 'id = ?',
            whereArgs: [questionId],
            limit: 1,
          );
          if (qRows.isNotEmpty) {
            final r = qRows.first;
            if (resParent.isEmpty) {
              resParent = _nonEmpty(r['chapter_parent_id']?.toString()) ?? '';
            }
            if (resChapter.isEmpty) {
              resChapter = _nonEmpty(r['chapter_id']?.toString()) ?? '';
            }
            if (resIdentity.isEmpty) {
              resIdentity =
                  _nonEmpty(r['native_identity_id']?.toString()) ??
                  _nonEmpty(r['identity_id']?.toString()) ??
                  '';
            }
            if (resAppId.isEmpty) {
              resAppId =
                  _nonEmpty(r['native_app_id']?.toString()) ??
                  _nonEmpty(r['app_id']?.toString()) ??
                  '';
            }
          }
          if (resSubject.isEmpty || resChapter.isEmpty || resIdentity.isEmpty) {
            final iqRows = await bankDb.query(
              'IdentityQuestion',
              columns: ['identity_id', 'subject_id', 'chapter_id'],
              where: 'question_id = ?',
              whereArgs: [questionId],
              limit: 1,
            );
            if (iqRows.isNotEmpty) {
              final r = iqRows.first;
              if (resSubject.isEmpty) {
                resSubject = _nonEmpty(r['subject_id']?.toString()) ?? '';
              }
              if (resChapter.isEmpty) {
                resChapter = _nonEmpty(r['chapter_id']?.toString()) ?? '';
              }
              if (resIdentity.isEmpty) {
                resIdentity = _nonEmpty(r['identity_id']?.toString()) ?? '';
              }
            }
          }
        } catch (_) {}
      }
    }

    if (resIdentity.isEmpty) {
      resIdentity = _nonEmpty(prefs.getString('identityId')) ?? '';
    }
    if (resSubject.isEmpty) {
      resSubject = _nonEmpty(prefs.getString('subjectId')) ??
          _nonEmpty(prefs.getString('activeSubjectId')) ??
          (resParent.isNotEmpty ? resParent : resIdentity);
    }
    if (resIdentity.isEmpty) {
      resIdentity = resSubject;
    }
    if (resAppId.isEmpty) {
      resAppId = '12';
    }
    if (resParent.isEmpty) {
      resParent = resSubject;
    }

    return QuestionSyncMeta(
      subjectId: resSubject,
      chapterId: resChapter,
      identityId: resIdentity,
      appId: resAppId,
      chapterParentId: resParent,
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  /// 同步斩题状态到医考帮
  Future<void> syncCutQuestion({
    required Question question,
    required bool isCut,
    Chapter? chapter,
    String? bankId,
  }) async {
    final queueOwner = await DurableSyncQueue.owner();
    final enabled = await isSyncCutEnabled();
    if (!enabled) {
      debugPrint('[YkbSyncService] syncCutToYkb is disabled, skip cut sync');
      return;
    }

    final meta = await resolveQuestionMeta(
      question.id,
      question: question,
      chapter: chapter,
      bankId: bankId,
    );

    final payload = <String, dynamic>{
      'subject_id': meta.subjectId,
      'identity_id': meta.identityId,
      'module_type': '1',
      'is_vip': '0',
      'is_svip': '0',
      'question_id': question.id,
      'operate': isCut ? 'add' : 'del',
      'chapter_id': meta.chapterId,
      'unit_id': '',
      'app_id': meta.appId,
    };

    final queueId =
        'cut_${question.id}_${isCut ? "add" : "del"}_${DateTime.now().millisecondsSinceEpoch}';
    final db = await UserDBHelper().database;
    await db.transaction((tx) async {
      await tx.delete(
        'YkbSyncQueue',
        where:
            "owner_user_id = ? AND type = 'cut' AND item_id = ? AND queue_state = 'pending'",
        whereArgs: [queueOwner, question.id],
      );
      await _enqueue(
        YkbSyncQueueItem(
          id: queueId,
          type: 'cut',
          itemId: question.id,
          payload: payload,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
        owner: queueOwner,
        executor: tx,
      );
      await tx.insert('Activities', {
        'id': generateSimpleId(),
        'title': 'CutQuestion',
        'description': jsonEncode(payload),
        'question_id': int.tryParse(question.id) ?? 0,
        'subject_id': meta.subjectId,
        'chapter_id': meta.chapterId,
        'is_right': isCut ? 'cut' : 'uncut',
        'duration': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    debugPrint(
      '[YkbSyncService] 已入队斩题同步: questionId=${question.id}, operate=${payload['operate']}, subjectId=${meta.subjectId}, chapterId=${meta.chapterId}',
    );
    unawaited(processQueue());
  }

  /// 仅凭 questionId 同步斩题状态（供「我的-已斩题目」列表与「每日复习」熟练斩题调用）
  Future<void> syncCutByQuestionId({
    required String questionId,
    required bool isCut,
    String? bankId,
  }) async {
    await syncCutQuestion(
      question: Question(id: questionId, userAnswer: '', sourceBankId: bankId),
      isCut: isCut,
      bankId: bankId,
    );
  }

  /// 同步单题作答记录到医考帮
  Future<void> syncAnswer({
    required Question question,
    required UserQuestion userQuestion,
    int durationMs = 0,
    String? subjectId,
    String? chapterId,
    String? identityId,
    String? chapterParentId,
    String? bankId,
  }) async {
    final queueOwner = await DurableSyncQueue.owner();
    final enabled = await isSyncAnswersEnabled();
    if (!enabled) {
      debugPrint(
        '[YkbSyncService] syncAnswersToYkb is disabled, skip answer sync',
      );
      return;
    }

    // 只有已判题（正确 status==1 或 错误 status==2）才同步到医考帮
    if (userQuestion.status != 1 && userQuestion.status != 2) return;

    final rawAnswer = getLastAnswer(userQuestion.userAnswer).trim();
    // 主观题自评（如“已掌握”/“未掌握”）不属于医考帮选择题答案格式，跳过选择题批量接口
    if (question.isSubjective ||
        rawAnswer.isEmpty ||
        !RegExp(r'^[A-Za-z]+$').hasMatch(rawAnswer)) {
      debugPrint(
        '[YkbSyncService] 跳过非选择题/主观题自评同步: questionId=${question.id}, answer=$rawAnswer',
      );
      return;
    }

    final answerStr = sortString(rawAnswer.toUpperCase());
    final meta = await resolveQuestionMeta(
      question.id,
      question: question,
      subjectId: subjectId,
      chapterId: chapterId,
      identityId: identityId,
      chapterParentId: chapterParentId,
      bankId: bankId,
    );

    final prefs = await SharedPreferences.getInstance();
    final isRight = userQuestion.status == 1 ? '1' : '0';
    final durationSec = (durationMs / 1000).round().clamp(1, 3600).toString();

    // 外层 identity_id 在抓包中通常对应科目 subject_id 或用户所选身份
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);

    final answerItem = {
      'paper_id': '0',
      'identity_id': meta.identityId,
      'chapter_id': meta.chapterId,
      'collection_id': '',
      'category_id': '',
      'chapter_parent_id': meta.chapterParentId,
      'answer': answerStr,
      'question_id': int.tryParse(question.id) ?? question.id,
      'is_right': isRight,
      'app_id': meta.appId,
      'duration': durationSec,
      'subject_id': meta.subjectId,
    };

    final payload = <String, dynamic>{
      'subject_id': meta.subjectId,
      'is_svip': '0',
      'module_type': '1',
      'identity_id': outerIdentityId,
      'is_vip': '0',
      'question_category_id': '2',
      'app_id': meta.appId,
      'answer': jsonEncode([answerItem]),
    };

    final queueId =
        'ans_${question.id}_${DateTime.now().millisecondsSinceEpoch}';
    final db = await UserDBHelper().database;
    await db.transaction((tx) async {
      await tx.delete(
        'YkbSyncQueue',
        where:
            "owner_user_id = ? AND type = 'answer' AND item_id = ? AND queue_state = 'pending'",
        whereArgs: [queueOwner, question.id],
      );
      await _enqueue(
        YkbSyncQueueItem(
          id: queueId,
          type: 'answer',
          itemId: question.id,
          payload: payload,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
        owner: queueOwner,
        executor: tx,
      );
    });

    debugPrint(
      '[YkbSyncService] 已入队作答同步: questionId=${question.id}, answer=$answerStr, isRight=$isRight, subjectId=${meta.subjectId}, chapterId=${meta.chapterId}',
    );
    unawaited(processQueue());
  }

  /// 同步重做章节到医考帮
  /// 构建本地重做义务；调用方可在重置答案事务内持久化，事务外再发包。
  Future<Map<String, dynamic>?> prepareRedoChapter({
    required Chapter chapter,
    String? appId,
  }) async {
    final owner = await DurableSyncQueue.owner();
    if (!await isSyncRedoEnabled()) return null;
    final prefs = await SharedPreferences.getInstance();
    final identityId = chapter.identityId?.isNotEmpty == true
        ? chapter.identityId!
        : (prefs.getString('identityId') ?? '');
    final payload = <String, dynamic>{
      'subject_id': chapter.subjectId,
      'obj_id': chapter.id,
      'is_svip': '0',
      'identity_id': identityId,
      'module_type': '1',
      'is_vip': '0',
      'type': 'chapter',
      'category': 'chapter',
      'app_id': appId ?? '12',
      'is_wrong': '0',
    };
    return {
      ...YkbSyncQueueItem(
        id: generateSimpleId(),
        type: 'redo_chapter',
        itemId: chapter.id,
        payload: payload,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ).toMap(),
      'owner_user_id': owner,
    };
  }

  /// 执行单个队列项目的网络请求，返回 true 表示成功 (200)，false 表示返回非 200，抛出异常表示网络中断
  Future<bool> _executeItemRequest(YkbSyncQueueItem item, String owner) async {
    String? responseCode;
    bool success = false;
    Map<String, dynamic> resp = {};

    if (item.type == 'cut') {
      resp = await basicReq(
        '/allQuestion/cutQuestion/cut',
        Map<String, dynamic>.from(item.payload),
        expectedOwner: owner,
      );
    } else if (item.type == 'answer') {
      resp = await basicReq(
        '/Question/Answer/postBatchForAll',
        Map<String, dynamic>.from(item.payload),
        expectedOwner: owner,
      );
    } else if (item.type == 'redo_chapter') {
      resp = await basicReq(
        '/allquestion/main/redoAnswerWithWrong',
        Map<String, dynamic>.from(item.payload),
        expectedOwner: owner,
      );
    } else {
      throw StateError('不支持的同步任务类型: ${item.type}');
    }

    debugPrint('[YkbSyncService] ${item.type} 同步响应: $resp');
    responseCode = resp['code']?.toString() ?? 'protocol_error';
    final rawResp = const JsonEncoder.withIndent('  ').convert(resp);
    SyncResponseCache.instance.record(
      queueId: item.id,
      itemId: item.itemId,
      type: item.type,
      code: responseCode,
      payload: item.payload,
      response: resp,
      rawResponse: rawResp,
    );

    if (responseCode == '200') {
      success = true;
    } else {
      await _recordFailureResponse(
        item,
        resp['message']?.toString() ?? 'Code ${resp['code']}',
        lastResponse: rawResp,
      );
      if (responseCode == '309') {
        throw const FormatException('309_TOKEN_EXPIRED');
      }
    }
    return success;
  }

  /// 手动重试与后台队列共享互斥，未知账号旧任务只在用户点击时认领。
  Future<bool> retryItem(String id) async {
    if (!await DurableSyncQueue.reset('YkbSyncQueue', id: id)) return false;
    return DurableSyncQueue.run('YkbSyncQueue', _executeRow, onlyId: id);
  }

  Future<void> resetItemRetry(String id) async {
    await DurableSyncQueue.reset('YkbSyncQueue', id: id);
  }

  Future<void> resetAllRetries() async {
    await DurableSyncQueue.reset('YkbSyncQueue');
  }

  Future<bool> _executeRow(Map<String, dynamic> row) => _executeItemRequest(
    YkbSyncQueueItem.fromMap(row),
    row['owner_user_id'] as String,
  );
  Future<void> processQueue() async {
    await DurableSyncQueue.run('YkbSyncQueue', _executeRow);
  }

  Future<void> _enqueue(
    YkbSyncQueueItem item, {
    required String owner,
    DatabaseExecutor? executor,
  }) => DurableSyncQueue.enqueue('YkbSyncQueue', {
    ...item.toMap(),
    'owner_user_id': owner,
  }, executor: executor);

  Future<void> _recordFailureResponse(
    YkbSyncQueueItem item,
    String error, {
    String? lastResponse,
  }) async {
    final db = await UserDBHelper().database;
    final values = <String, dynamic>{'last_error': error};
    if (lastResponse != null) {
      values['last_response'] = lastResponse;
    }
    await db.update(
      'YkbSyncQueue',
      values,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }
}
