import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../common/ykb_encrypt.dart';
import '../db/database_helper.dart';
import '../models/note.dart';
import '../models/question.dart';
import 'ykb_sync_service.dart';

/// 医考帮笔记业务与同步队列服务
class NoteService {
  static final NoteService instance = NoteService._internal();
  NoteService._internal();

  static const String keySyncNotesToYkb = 'sync_notes_to_ykb';

  bool _isProcessingQueue = false;

  /// 全局笔记变动与同步状态更新通知器（触发 UI 实时刷新）
  final ValueNotifier<int> noteSyncEventNotifier = ValueNotifier<int>(0);

  void notifyNoteChanged() {
    noteSyncEventNotifier.value++;
  }

  /// 判断用户是否开启了「同步笔记到医考帮」
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySyncNotesToYkb) ?? true;
  }

  /// 获取指定题目的所有本地笔记
  Future<List<QuestionNote>> getLocalNotes(String questionId) async {
    final db = await UserDBHelper().database;
    final rows = await db.query(
      'Notes',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'timestamp DESC',
    );
    return rows.map((e) => QuestionNote.fromMap(e)).toList();
  }

  /// 获取所有本地笔记（按时间倒序）
  Future<List<QuestionNote>> getAllNotes() async {
    final db = await UserDBHelper().database;
    final rows = await db.query('Notes', orderBy: 'timestamp DESC');
    return rows.map((e) => QuestionNote.fromMap(e)).toList();
  }

  /// 保存或更新笔记（先落本地 SQLite，若开启同步则入队并触发同步）
  Future<void> saveNote(QuestionNote note, {Question? question}) async {
    final db = await UserDBHelper().database;
    final syncEnabled = await isSyncEnabled();

    final noteToSave = note.copyWith(
      syncStatus: syncEnabled ? 1 : 0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 外键约束已开启：先补 Question 兜底行，防止为「未作答的题」写笔记时
    // Notes.question_id 引用失败导致插入被拒绝。
    await db.insert('Question', {
      'id': note.questionId,
      'chapter_id': question?.chapterId ?? '',
      'chapter_parent_id': question?.chapterParentId ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
      'Notes',
      noteToSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
      '[NoteService] saveNote locally: ${note.id}, syncEnabled: $syncEnabled',
    );

    if (syncEnabled) {
      final queuePayload = {
        ...noteToSave.toMap(),
        'subject_id': question?.chapterParentId ?? '',
        'identity_id': question?.identityId ?? '',
        'app_id': question?.nativeAppId ?? question?.appId ?? '12',
      };
      await _enqueue(
        NoteSyncQueueItem(
          id: 'upload_${note.id}_${DateTime.now().millisecondsSinceEpoch}',
          action: 'upload',
          noteId: note.id,
          questionId: note.questionId,
          payload: jsonEncode(queuePayload),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      // 触发后台处理
      processQueue(question: question);
    }
    notifyNoteChanged();
  }

  /// 删除笔记（先从本地 SQLite 移除，取消未决上传，若开启同步且有 remoteId 则入删除队列）
  Future<void> deleteNote(QuestionNote note, {Question? question}) async {
    final db = await UserDBHelper().database;
    final syncEnabled = await isSyncEnabled();

    // 1. 查找是否存在已关联的 remoteId（防止内存中对象未带 remoteId 但本地库中已有）
    String? effectiveRemoteId = note.remoteId;
    if (effectiveRemoteId == null || effectiveRemoteId.isEmpty) {
      final existing = await db.query(
        'Notes',
        columns: ['remote_id'],
        where: 'id = ?',
        whereArgs: [note.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        effectiveRemoteId = existing.first['remote_id'] as String?;
      }
    }
    // 若 id 本身不是 local_ 开头，说明其本身就是服务端笔记 ID
    if ((effectiveRemoteId == null || effectiveRemoteId.isEmpty) &&
        !note.id.startsWith('local_')) {
      effectiveRemoteId = note.id;
    }

    // 2. 从本地 SQLite 删除该笔记
    await db.delete('Notes', where: 'id = ?', whereArgs: [note.id]);
    debugPrint(
      '[NoteService] deleteNote locally: ${note.id}, remoteId: $effectiveRemoteId',
    );

    // 3. 取消并清除队列中该笔记所有待上传任务（避免后续冗余发包）
    await db.delete(
      'NoteSyncQueue',
      where: 'note_id = ? AND action = ?',
      whereArgs: [note.id, 'upload'],
    );

    // 4. 若开启同步且存在有效远端 ID，入队 delete 任务同步至云端
    if (syncEnabled &&
        effectiveRemoteId != null &&
        effectiveRemoteId.isNotEmpty) {
      final queuePayload = {
        'subject_id': question?.chapterParentId ?? '',
        'identity_id': question?.identityId ?? '',
        'app_id': question?.nativeAppId ?? question?.appId ?? '12',
      };
      await _enqueue(
        NoteSyncQueueItem(
          id: 'del_${effectiveRemoteId}_${DateTime.now().millisecondsSinceEpoch}',
          action: 'delete',
          noteId: effectiveRemoteId,
          questionId: note.questionId,
          payload: jsonEncode(queuePayload),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      processQueue(question: question);
    }
    notifyNoteChanged();
  }

  /// 上传单张图片到医考帮服务器
  Future<NoteImage?> uploadImage(
    File file, {
    required String subjectId,
    required String identityId,
    required String appId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;
      if (!loggedIn) {
        debugPrint('[NoteService] uploadImage skipped: user not logged in');
        return null;
      }
      final token = prefs.getString('token') ?? '';
      final secret = prefs.getString('secret') ?? '';
      final userId = prefs.getString('user_id') ?? '';

      final timestamp = getTimestamp();
      final fields = <String, String>{
        'subject_id': subjectId,
        'is_svip': '0',
        'user_id': userId,
        'identity_id': identityId,
        'is_vip': '0',
        'secret': secret,
        'app_id': appId,
        'token': token,
      };

      final uri = Uri.parse('$rootUrl/allQuestion/Note/uploads');
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll({
        'User-Agent': 'Redmi_23078RKD5C',
        'Connection': 'Keep-Alive',
        'timestamp': timestamp,
        'signature': getSignature(timestamp, fields, loggedIn),
        'client-type': 'android',
        'app-version': appVersionDefault,
        'uuid': imei,
        'channel': channelDefault,
        'app-type': 'ykb',
      });

      request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      debugPrint('[NoteService] uploadImage start for ${file.path}');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final bodyStr = utf8.decode(response.bodyBytes);
      debugPrint(
        '[NoteService] uploadImage response (${response.statusCode}): $bodyStr',
      );

      final data = jsonDecode(bodyStr);
      if ((data['code'] == '200' || data['code'] == 200) &&
          data['data'] != null) {
        final bImg = data['data']['b_img']?.toString() ?? '';
        final sImg = data['data']['s_img']?.toString() ?? bImg;
        return NoteImage(bImg: bImg, sImg: sImg, localPath: file.path);
      } else {
        debugPrint(
          '[NoteService] uploadImage failed with code: ${data['code']}, msg: ${data['message']}',
        );
      }
    } catch (e, stack) {
      debugPrint('[NoteService] uploadImage exception: $e\n$stack');
    }
    return null;
  }

  /// 为特定题目双向增量同步笔记：
  /// 1. 执行待处理队列
  /// 2. 从医考帮拉取最新笔记，与本地内容比对，不同则覆盖更新
  Future<List<QuestionNote>> syncNotesForQuestion(Question question) async {
    final syncEnabled = await isSyncEnabled();
    if (!syncEnabled) {
      return getLocalNotes(question.id);
    }

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) {
      return getLocalNotes(question.id);
    }

    // 先跑一下当前题目的上传队列
    await processQueue(question: question);

    // 从医考帮获取笔记
    try {
      final identityId = question.identityId?.isNotEmpty == true
          ? question.identityId!
          : (prefs.getString('identityId') ?? '');
      final subjectId = question.chapterParentId ?? '';
      final appId = question.nativeAppId?.isNotEmpty == true
          ? question.nativeAppId!
          : (question.appId?.isNotEmpty == true ? question.appId! : '12');

      final resp = await basicReq('/allQuestion/Note/getNote', {
        'question_id': question.id,
        'subject_id': subjectId,
        'identity_id': identityId,
        'app_id': appId,
        'module_type': '1',
        'page': '1',
        'size': '20',
        'is_vip': '0',
        'is_svip': '0',
      }, method: 'GET');

      if (resp['code'] == '200' && resp['data'] is List) {
        final remoteList = resp['data'] as List;
        final localNotes = await getLocalNotes(question.id);
        final db = await UserDBHelper().database;

        for (final item in remoteList) {
          final rId = item['id']?.toString() ?? '';
          final rContent = item['content']?.toString() ?? '';
          final rCtime = int.tryParse(item['ctime']?.toString() ?? '0') ?? 0;
          final rTimestamp = rCtime > 0
              ? rCtime * 1000
              : DateTime.now().millisecondsSinceEpoch;

          List<NoteImage> rImages = [];
          if (item['img'] is List) {
            rImages = (item['img'] as List).map((i) {
              return NoteImage(
                bImg: i['b_img']?.toString() ?? '',
                sImg: i['s_img']?.toString() ?? i['b_img']?.toString() ?? '',
                bWidth: int.tryParse(i['b_width']?.toString() ?? '0') ?? 0,
                bHeight: int.tryParse(i['b_height']?.toString() ?? '0') ?? 0,
              );
            }).toList();
          }

          // 匹配本地记录：按 remote_id 或 id
          final matchedLocal = localNotes
              .where((n) => n.remoteId == rId || n.id == rId)
              .firstOrNull;

          if (matchedLocal == null) {
            // 本地不存在，插入
            // 外键约束已开启：先补 Question 兜底行（查看他人笔记的题可能从未作答）。
            await db.insert('Question', {
              'id': question.id,
              'chapter_id': question.chapterId ?? '',
              'chapter_parent_id': question.chapterParentId ?? '',
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            final newNote = QuestionNote(
              id: rId,
              remoteId: rId,
              questionId: question.id,
              content: rContent,
              images: rImages,
              timestamp: rTimestamp,
              updatedAt: rTimestamp,
              syncStatus: 0,
            );
            await db.insert(
              'Notes',
              newNote.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } else {
            // 本地已存在：确保关联上 remoteId，并遵循 LWW (以最新时间戳为准) 避免旧版本回退覆盖
            final bool needLinkRemoteId =
                matchedLocal.remoteId == null || matchedLocal.remoteId!.isEmpty;
            final bool isRemoteNewer = rTimestamp > matchedLocal.updatedAt;
            final bool contentDiff = matchedLocal.content != rContent;

            if (matchedLocal.syncStatus == 0 && isRemoteNewer && contentDiff) {
              // 云端只有第1张图片，保留本地后续图片
              final List<NoteImage> mergedImages = [
                if (rImages.isNotEmpty)
                  rImages.first
                else if (matchedLocal.images.isNotEmpty)
                  matchedLocal.images.first,
                if (matchedLocal.images.length > 1)
                  ...matchedLocal.images.sublist(1),
              ];
              final updated = matchedLocal.copyWith(
                remoteId: rId,
                content: rContent,
                images: mergedImages,
                updatedAt: rTimestamp,
                syncStatus: 0,
              );
              await db.update(
                'Notes',
                updated.toMap(),
                where: 'id = ?',
                whereArgs: [matchedLocal.id],
              );
            } else if (needLinkRemoteId) {
              await db.update(
                'Notes',
                {'remote_id': rId},
                where: 'id = ?',
                whereArgs: [matchedLocal.id],
              );
            }
          }
        }

        // 记录从医考帮拉取笔记流水到 Activities
        try {
          await db.insert('Activities', {
            'id': generateSimpleId(),
            'title': 'NotePull',
            'description': jsonEncode({
              'question_id': question.id,
              'pulled_count': remoteList.length,
              'subject_id': subjectId,
            }),
            'question_id': int.tryParse(question.id) ?? 0,
            'subject_id': subjectId,
            'is_right': 'pull',
            'duration': 0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[NoteService] pull remote notes error: $e');
    }

    return getLocalNotes(question.id);
  }

  /// 队列入队
  Future<void> _enqueue(NoteSyncQueueItem item) async {
    final db = await UserDBHelper().database;
    await db.insert(
      'NoteSyncQueue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 单项手动重试笔记任务（重置重试计数为 0 并立即尝试发包）
  Future<bool> retryItem(String id, {Question? question}) async {
    final db = await UserDBHelper().database;
    final rows = await db.query(
      'NoteSyncQueue',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return false;

    await resetItemRetry(id);
    final item = NoteSyncQueueItem.fromMap(rows.first);

    bool success = false;
    try {
      if (item.action == 'upload') {
        success = await _processUploadItem(item, question);
      } else if (item.action == 'delete') {
        success = await _processDeleteItem(item, question);
      } else {
        success = true;
      }
    } catch (e) {
      await db.update(
        'NoteSyncQueue',
        {'retry_count': 1, 'last_error': e.toString()},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      return false;
    }

    if (success) {
      await db.delete('NoteSyncQueue', where: 'id = ?', whereArgs: [item.id]);
      return true;
    } else {
      await db.update(
        'NoteSyncQueue',
        {'retry_count': 1},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      return false;
    }
  }

  /// 单项重置重试计数
  Future<void> resetItemRetry(String id) async {
    final db = await UserDBHelper().database;
    await db.update(
      'NoteSyncQueue',
      {'retry_count': 0, 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 一键重置笔记队列所有任务的重试计数
  Future<void> resetAllRetries() async {
    final db = await UserDBHelper().database;
    await db.update('NoteSyncQueue', {'retry_count': 0, 'last_error': null});
  }

  /// 执行同步队列（断网重试）
  Future<void> processQueue({Question? question}) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;
      if (!loggedIn) {
        debugPrint('[NoteService] processQueue skipped: not logged in');
        _isProcessingQueue = false;
        return;
      }

      final db = await UserDBHelper().database;
      final queueRows = await db.query(
        'NoteSyncQueue',
        orderBy: 'created_at ASC',
        limit: 15,
      );

      if (queueRows.isEmpty) {
        _isProcessingQueue = false;
        return;
      }
      debugPrint(
        '[NoteService] processQueue started, pending items: ${queueRows.length}',
      );

      for (final row in queueRows) {
        final item = NoteSyncQueueItem.fromMap(row);
        bool success = false;

        try {
          if (item.action == 'upload') {
            success = await _processUploadItem(item, question);
          } else if (item.action == 'delete') {
            success = await _processDeleteItem(item, question);
          } else {
            success = true;
          }
        } catch (e, stack) {
          debugPrint('[NoteService] process queue item error: $e\n$stack');
          final errJson = const JsonEncoder.withIndent(
            '  ',
          ).convert({'error': e.toString()});
          await db.update(
            'NoteSyncQueue',
            {
              'retry_count': item.retryCount + 1,
              'last_error': e.toString(),
              'last_response': errJson,
            },
            where: 'id = ?',
            whereArgs: [item.id],
          );
          if (item.retryCount + 1 >= 5) {
            debugPrint('[NoteService] 任务 ${item.id} 异常重试达到上限(5次)，移出队列');
            await db.delete(
              'NoteSyncQueue',
              where: 'id = ?',
              whereArgs: [item.id],
            );
          }
          // 网络异常时暂停后续重试，等待下一次触发
          break;
        }

        if (success) {
          debugPrint('[NoteService] queue item succeeded: ${item.id}');
          await db.delete(
            'NoteSyncQueue',
            where: 'id = ?',
            whereArgs: [item.id],
          );
        } else {
          debugPrint('[NoteService] queue item failed: ${item.id}');
          if (item.retryCount + 1 >= 5) {
            debugPrint(
              '[NoteService] 任务 ${item.id} 达到最大重试次数上限(5次)，移出活跃队列以防队头阻塞',
            );
            await db.delete(
              'NoteSyncQueue',
              where: 'id = ?',
              whereArgs: [item.id],
            );
          } else {
            await db.update(
              'NoteSyncQueue',
              {'retry_count': item.retryCount + 1},
              where: 'id = ?',
              whereArgs: [item.id],
            );
          }
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<bool> _processUploadItem(
    NoteSyncQueueItem item,
    Question? fallbackQuestion,
  ) async {
    final db = await UserDBHelper().database;
    final noteRows = await db.query(
      'Notes',
      where: 'id = ?',
      whereArgs: [item.noteId],
    );

    if (noteRows.isEmpty) {
      // 本地已不存在该笔记，直接视为完成出队
      return true;
    }

    QuestionNote note = QuestionNote.fromMap(noteRows.first);
    final prefs = await SharedPreferences.getInstance();

    // 优先从 payload 中提取已序列化的参数，避免后台队列无 fallbackQuestion 导致 subject_id 为空
    Map<String, dynamic> itemPayload = {};
    if (item.payload != null && item.payload!.isNotEmpty) {
      try {
        itemPayload = jsonDecode(item.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }

    String subjectId = itemPayload['subject_id']?.toString() ?? '';
    String identityId = itemPayload['identity_id']?.toString() ?? '';
    String appId = itemPayload['app_id']?.toString() ?? '';

    if (subjectId.isEmpty && fallbackQuestion != null) {
      subjectId = fallbackQuestion.chapterParentId ?? '';
    }
    if (identityId.isEmpty && fallbackQuestion != null) {
      identityId = fallbackQuestion.identityId ?? '';
    }
    if (appId.isEmpty && fallbackQuestion != null) {
      appId = fallbackQuestion.nativeAppId ?? fallbackQuestion.appId ?? '';
    }

    // 若依然缺失，从本地数据库反查题目的 chapter_parent_id
    if (subjectId.isEmpty) {
      try {
        final qRows = await db.query(
          'Question',
          columns: ['chapter_parent_id'],
          where: 'id = ?',
          whereArgs: [item.questionId],
          limit: 1,
        );
        if (qRows.isNotEmpty) {
          final parentId = qRows.first['chapter_parent_id']?.toString();
          if (parentId != null && parentId.isNotEmpty) {
            subjectId = parentId;
          }
        }
      } catch (_) {}
    }

    if (identityId.isEmpty) {
      identityId = prefs.getString('identityId') ?? '';
    }
    if (appId.isEmpty) {
      appId = '12';
    }

    // 云端优先保存第一张图片：检查第一张图片是否需要上传
    final List<NoteImage> updatedImages = List.from(note.images);
    if (updatedImages.isNotEmpty) {
      final firstImg = updatedImages.first;
      if (firstImg.bImg.isEmpty &&
          firstImg.localPath != null &&
          firstImg.localPath!.isNotEmpty) {
        final file = File(firstImg.localPath!);
        if (await file.exists()) {
          debugPrint(
            '[NoteService] uploading first image to cloud: ${file.path}',
          );
          final uploaded = await uploadImage(
            file,
            subjectId: subjectId,
            identityId: identityId,
            appId: appId,
          );
          if (uploaded != null) {
            updatedImages[0] = uploaded;
            note = note.copyWith(images: updatedImages);
            await db.update(
              'Notes',
              note.toMap(),
              where: 'id = ?',
              whereArgs: [note.id],
            );
          }
        }
      }
    }

    // 调用 pushNote
    final params = <String, dynamic>{
      'question_id': note.questionId,
      'content': note.content,
      'module_type': '1',
      'subject_id': subjectId,
      'identity_id': identityId,
      'app_id': appId,
      'is_vip': '0',
      'is_svip': '0',
    };
    if (note.remoteId != null && note.remoteId!.isNotEmpty) {
      params['id'] = note.remoteId;
    }
    if (note.images.isNotEmpty) {
      final firstImg = note.images.first;
      if (firstImg.bImg.isNotEmpty) {
        params['b_img'] = firstImg.bImg;
        params['s_img'] = firstImg.sImg.isNotEmpty
            ? firstImg.sImg
            : firstImg.bImg;
        params['img'] = jsonEncode([firstImg.toJson()]);
      }
    }

    debugPrint('[NoteService] calling pushNote with params: $params');
    final resp = await basicReq(
      '/allQuestion/Note/pushNote',
      params,
      method: 'POST',
    );
    debugPrint('[NoteService] pushNote result: $resp');
    final code = resp['code']?.toString() ?? '200';
    final rawResp = const JsonEncoder.withIndent('  ').convert(resp);
    SyncResponseCache.instance.record(
      queueId: item.id,
      itemId: note.questionId,
      type: 'note_upload',
      code: code,
      payload: params,
      response: resp,
      rawResponse: rawResp,
    );

    if (resp['code'] == '200' || resp['code'] == 200) {
      String? remoteId = note.remoteId;
      if (remoteId == null || remoteId.isEmpty) {
        // 新上传的笔记尝试查询 getNote 获取服务端生成的 remoteId
        try {
          final listResp = await basicReq('/allQuestion/Note/getNote', {
            'question_id': note.questionId,
            'subject_id': subjectId,
            'identity_id': identityId,
            'app_id': appId,
            'module_type': '1',
            'page': '1',
            'size': '5',
            'is_vip': '0',
            'is_svip': '0',
          }, method: 'GET');
          if (listResp['code'] == '200' && listResp['data'] is List) {
            final list = listResp['data'] as List;
            if (list.isNotEmpty) {
              remoteId = list.first['id']?.toString();
            }
          }
        } catch (_) {}
      }

      await db.update(
        'Notes',
        {'remote_id': remoteId, 'sync_status': 0},
        where: 'id = ?',
        whereArgs: [note.id],
      );

      // 记录笔记上传流水到 Activities
      try {
        await db.insert('Activities', {
          'id': generateSimpleId(),
          'title': 'NoteUpload',
          'description': jsonEncode(params),
          'question_id': int.tryParse(note.questionId) ?? 0,
          'subject_id': subjectId,
          'is_right': 'upload',
          'duration': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}

      notifyNoteChanged();
      return true;
    }

    await db.update(
      'NoteSyncQueue',
      {
        'last_error': resp['message']?.toString() ?? 'Code ${resp['code']}',
        'last_response': rawResp,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );

    return false;
  }

  Future<bool> _processDeleteItem(
    NoteSyncQueueItem item,
    Question? fallbackQuestion,
  ) async {
    if (item.noteId == null || item.noteId!.isEmpty) return true;

    final db = await UserDBHelper().database;
    final prefs = await SharedPreferences.getInstance();

    Map<String, dynamic> itemPayload = {};
    if (item.payload != null && item.payload!.isNotEmpty) {
      try {
        itemPayload = jsonDecode(item.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }

    String subjectId = itemPayload['subject_id']?.toString() ?? '';
    String identityId = itemPayload['identity_id']?.toString() ?? '';
    String appId = itemPayload['app_id']?.toString() ?? '';

    if (subjectId.isEmpty && fallbackQuestion != null) {
      subjectId = fallbackQuestion.chapterParentId ?? '';
    }
    if (identityId.isEmpty && fallbackQuestion != null) {
      identityId = fallbackQuestion.identityId ?? '';
    }
    if (appId.isEmpty && fallbackQuestion != null) {
      appId = fallbackQuestion.nativeAppId ?? fallbackQuestion.appId ?? '';
    }

    if (subjectId.isEmpty) {
      try {
        final qRows = await db.query(
          'Question',
          columns: ['chapter_parent_id'],
          where: 'id = ?',
          whereArgs: [item.questionId],
          limit: 1,
        );
        if (qRows.isNotEmpty) {
          final parentId = qRows.first['chapter_parent_id']?.toString();
          if (parentId != null && parentId.isNotEmpty) {
            subjectId = parentId;
          }
        }
      } catch (_) {}
    }

    if (identityId.isEmpty) {
      identityId = prefs.getString('identityId') ?? '';
    }
    if (appId.isEmpty) {
      appId = '12';
    }

    final resp = await basicReq('/allQuestion/Note/cleanNote', {
      'id': item.noteId,
      'question_id': item.questionId,
      'module_type': '1',
      'subject_id': subjectId,
      'identity_id': identityId,
      'app_id': appId,
      'is_vip': '0',
      'is_svip': '0',
    }, method: 'POST');

    final code = resp['code']?.toString() ?? '200';
    final rawResp = const JsonEncoder.withIndent('  ').convert(resp);
    SyncResponseCache.instance.record(
      queueId: item.id,
      itemId: item.questionId,
      type: 'note_delete',
      code: code,
      payload: {'id': item.noteId, 'question_id': item.questionId},
      response: resp,
      rawResponse: rawResp,
    );

    if (resp['code'] == '200' || resp['code'] == 200) {
      // 记录笔记删除流水到 Activities
      try {
        await db.insert('Activities', {
          'id': generateSimpleId(),
          'title': 'NoteDelete',
          'description': jsonEncode({
            'note_id': item.noteId,
            'question_id': item.questionId,
            'subject_id': subjectId,
          }),
          'question_id': int.tryParse(item.questionId) ?? 0,
          'subject_id': subjectId,
          'is_right': 'delete',
          'duration': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}

      return true;
    }

    await db.update(
      'NoteSyncQueue',
      {
        'last_error': resp['message']?.toString() ?? 'Code ${resp['code']}',
        'last_response': rawResp,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );

    return false;
  }
}
