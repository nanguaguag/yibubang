import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../db/database_helper.dart';
import '../models/chapter.dart';
import '../models/question.dart';

/// 医考帮同步队列单项
class YkbSyncQueueItem {
  final String id;
  final String type; // 'cut', 'answer', 'redo_chapter'
  final String? itemId;
  final Map<String, dynamic> payload;
  final int retryCount;
  final int createdAt;
  final String? lastError;

  YkbSyncQueueItem({
    required this.id,
    required this.type,
    this.itemId,
    required this.payload,
    this.retryCount = 0,
    required this.createdAt,
    this.lastError,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'item_id': itemId,
        'payload': jsonEncode(payload),
        'retry_count': retryCount,
        'created_at': createdAt,
        'last_error': lastError,
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
      );
}

/// 医考帮云端数据（斩题、做题、章节重做）同步及离线队列服务
class YkbSyncService {
  static final YkbSyncService instance = YkbSyncService._internal();
  YkbSyncService._internal();

  static const String keySyncCutToYkb = 'sync_cut_to_ykb';
  static const String keySyncAnswersToYkb = 'sync_answers_to_ykb';
  static const String keySyncRedoToYkb = 'sync_redo_to_ykb';

  bool _isProcessingQueue = false;

  /// 是否开启斩题同步到医考帮
  Future<bool> isSyncCutEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySyncCutToYkb) ?? true;
  }

  /// 是否开启做题同步到医考帮
  Future<bool> isSyncAnswersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // 兼容历史 key: questionUpload / sync_question_bank
    if (prefs.containsKey(keySyncAnswersToYkb)) {
      return prefs.getBool(keySyncAnswersToYkb) ?? true;
    }
    if (prefs.containsKey('questionUpload')) {
      return prefs.getBool('questionUpload') ?? true;
    }
    return true;
  }

  /// 是否开启章节重做同步到医考帮
  Future<bool> isSyncRedoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySyncRedoToYkb) ?? true;
  }

  /// 同步斩题状态到医考帮
  Future<void> syncCutQuestion({
    required Question question,
    required bool isCut,
    Chapter? chapter,
  }) async {
    final enabled = await isSyncCutEnabled();
    if (!enabled) {
      debugPrint('[YkbSyncService] syncCutToYkb is disabled, skip cut sync');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // 优先从 chapter 获取真实科目 subjectId，否则回退
    final subjectId = (chapter?.subjectId.isNotEmpty == true)
        ? chapter!.subjectId
        : (question.chapterParentId?.isNotEmpty == true
            ? question.chapterParentId!
            : '');
    final chapterId = (chapter?.id.isNotEmpty == true)
        ? chapter!.id
        : (question.chapterId?.isNotEmpty == true ? question.chapterId! : '');
    final identityId = (chapter?.identityId?.isNotEmpty == true)
        ? chapter!.identityId!
        : (question.identityId?.isNotEmpty == true
            ? question.identityId!
            : (prefs.getString('identityId') ?? ''));
    final appId = question.nativeAppId?.isNotEmpty == true
        ? question.nativeAppId!
        : (question.appId?.isNotEmpty == true ? question.appId! : '12');

    final payload = <String, dynamic>{
      'subject_id': subjectId,
      'identity_id': identityId,
      'module_type': '1',
      'is_vip': '0',
      'is_svip': '0',
      'question_id': question.id,
      'operate': isCut ? 'add' : 'del',
      'chapter_id': chapterId,
      'unit_id': '',
      'app_id': appId,
    };

    final queueId =
        'cut_${question.id}_${isCut ? "add" : "del"}_${DateTime.now().millisecondsSinceEpoch}';
    await _enqueue(YkbSyncQueueItem(
      id: queueId,
      type: 'cut',
      itemId: question.id,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    debugPrint(
        '[YkbSyncService] 已入队斩题同步: questionId=${question.id}, operate=${payload['operate']}, subjectId=$subjectId, chapterId=$chapterId');
    unawaited(processQueue());
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
  }) async {
    final enabled = await isSyncAnswersEnabled();
    if (!enabled) {
      debugPrint('[YkbSyncService] syncAnswersToYkb is disabled, skip answer sync');
      return;
    }

    // 只有已判题（正确 status==1 或 错误 status==2）才同步到医考帮
    if (userQuestion.status != 1 && userQuestion.status != 2) return;

    final prefs = await SharedPreferences.getInstance();
    final resolvedSubjectId = (subjectId != null && subjectId.isNotEmpty)
        ? subjectId
        : (question.chapterParentId?.isNotEmpty == true
            ? question.chapterParentId!
            : '');
    final resolvedChapterId = (chapterId != null && chapterId.isNotEmpty)
        ? chapterId
        : (question.chapterId?.isNotEmpty == true ? question.chapterId! : '');
    final resolvedIdentityId = (identityId != null && identityId.isNotEmpty)
        ? identityId
        : (question.identityId?.isNotEmpty == true
            ? question.identityId!
            : (prefs.getString('identityId') ?? ''));
    final appId = question.nativeAppId?.isNotEmpty == true
        ? question.nativeAppId!
        : (question.appId?.isNotEmpty == true ? question.appId! : '12');

    final isRight = userQuestion.status == 1 ? '1' : '0';
    final durationSec = (durationMs / 1000).round().clamp(1, 3600).toString();
    final answerStr = getLastAnswer(userQuestion.userAnswer);

    // 外层 identity_id 在抓包中通常对应科目 subject_id 或用户所选身份
    final outerIdentityId = (resolvedSubjectId.isNotEmpty)
        ? resolvedSubjectId
        : (prefs.getString('identityId') ?? resolvedIdentityId);

    final answerItem = {
      'paper_id': '0',
      'identity_id': resolvedIdentityId,
      'chapter_id': resolvedChapterId,
      'collection_id': '',
      'category_id': '',
      'chapter_parent_id': chapterParentId ?? question.chapterParentId ?? '',
      'answer': answerStr,
      'question_id': int.tryParse(question.id) ?? question.id,
      'is_right': isRight,
      'app_id': appId,
      'duration': durationSec,
      'subject_id': resolvedSubjectId,
    };

    final payload = <String, dynamic>{
      'subject_id': resolvedSubjectId,
      'is_svip': '0',
      'module_type': '1',
      'identity_id': outerIdentityId,
      'is_vip': '0',
      'question_category_id': '2',
      'app_id': appId,
      'answer': jsonEncode([answerItem]),
    };

    final queueId =
        'ans_${question.id}_${DateTime.now().millisecondsSinceEpoch}';
    await _enqueue(YkbSyncQueueItem(
      id: queueId,
      type: 'answer',
      itemId: question.id,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    debugPrint(
        '[YkbSyncService] 已入队作答同步: questionId=${question.id}, answer=$answerStr, isRight=$isRight, subjectId=$resolvedSubjectId, chapterId=$resolvedChapterId');
    unawaited(processQueue());
  }

  /// 同步重做章节到医考帮
  Future<void> syncRedoChapter({
    required Chapter chapter,
    String? appId,
  }) async {
    final enabled = await isSyncRedoEnabled();
    if (!enabled) {
      debugPrint('[YkbSyncService] syncRedoToYkb is disabled, skip redo sync');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final identityId = chapter.identityId?.isNotEmpty == true
        ? chapter.identityId!
        : (prefs.getString('identityId') ?? '');
    final resolvedAppId = appId ?? '12';

    final payload = <String, dynamic>{
      'subject_id': chapter.subjectId,
      'obj_id': chapter.id,
      'is_svip': '0',
      'identity_id': identityId,
      'module_type': '1',
      'is_vip': '0',
      'type': 'chapter',
      'category': 'chapter',
      'app_id': resolvedAppId,
      'is_wrong': '0',
    };

    final queueId =
        'redo_${chapter.id}_${DateTime.now().millisecondsSinceEpoch}';
    await _enqueue(YkbSyncQueueItem(
      id: queueId,
      type: 'redo_chapter',
      itemId: chapter.id,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    debugPrint(
        '[YkbSyncService] 已入队章节重做同步: chapterId=${chapter.id}, subjectId=${chapter.subjectId}');
    unawaited(processQueue());
  }

  /// 后台处理同步队列
  Future<void> processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;
      if (!loggedIn) {
        debugPrint('[YkbSyncService] 用户未登录医考帮，同步任务保留在队列中等待登录后同步');
        return;
      }

      final items = await _getPendingItems();
      if (items.isEmpty) return;
      debugPrint('[YkbSyncService] 开始处理医考帮同步队列，待处理项数: ${items.length}');

      for (final item in items) {
        try {
          debugPrint(
              '[YkbSyncService] 执行队列任务: id=${item.id}, type=${item.type}, retry=${item.retryCount}');
          bool success = false;
          if (item.type == 'cut') {
            final resp = await basicReq(
              '/allQuestion/cutQuestion/cut',
              Map<String, dynamic>.from(item.payload),
            );
            debugPrint('[YkbSyncService] 斩题同步响应: $resp');
            if (resp['code'] == '200') {
              success = true;
            } else {
              await _markError(
                  item, resp['message']?.toString() ?? 'Code ${resp['code']}');
            }
          } else if (item.type == 'answer') {
            final resp = await basicReq(
              '/Question/Answer/postBatchForAll',
              Map<String, dynamic>.from(item.payload),
            );
            debugPrint('[YkbSyncService] 作答同步响应: $resp');
            if (resp['code'] == '200') {
              success = true;
            } else {
              await _markError(
                  item, resp['message']?.toString() ?? 'Code ${resp['code']}');
            }
          } else if (item.type == 'redo_chapter') {
            final resp = await basicReq(
              '/allquestion/main/redoAnswerWithWrong',
              Map<String, dynamic>.from(item.payload),
            );
            debugPrint('[YkbSyncService] 重做章节同步响应: $resp');
            if (resp['code'] == '200') {
              success = true;
            } else {
              await _markError(
                  item, resp['message']?.toString() ?? 'Code ${resp['code']}');
            }
          }

          if (success) {
            await _dequeue(item.id);
            debugPrint('[YkbSyncService] 同步任务成功并已移出队列: ${item.id}');
          } else {
            debugPrint('[YkbSyncService] 服务端业务错误，暂停队列后续执行，等待下一次触发');
            break;
          }
        } catch (e, stack) {
          debugPrint('[YkbSyncService] 网络或异常中断 ${item.type}: $e');
          debugPrint('$stack');
          await _markError(item, e.toString());
          break; // 网络断开，保留在队列中等待下次重试
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // --- SQLite 队列读写辅助方法 ---

  Future<void> _enqueue(YkbSyncQueueItem item) async {
    final db = await UserDBHelper().database;
    await db.insert(
      'YkbSyncQueue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _dequeue(String id) async {
    final db = await UserDBHelper().database;
    await db.delete(
      'YkbSyncQueue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<YkbSyncQueueItem>> _getPendingItems() async {
    final db = await UserDBHelper().database;
    final rows = await db.query(
      'YkbSyncQueue',
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => YkbSyncQueueItem.fromMap(r)).toList();
  }

  Future<void> _markError(YkbSyncQueueItem item, String error) async {
    final db = await UserDBHelper().database;
    await db.update(
      'YkbSyncQueue',
      {
        'retry_count': item.retryCount + 1,
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }
}
