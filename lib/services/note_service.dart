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

/// 医考帮笔记业务与同步队列服务
class NoteService {
  static final NoteService instance = NoteService._internal();
  NoteService._internal();

  static const String keySyncNotesToYkb = 'sync_notes_to_ykb';

  bool _isProcessingQueue = false;

  /// 判断用户是否开启了「同步笔记到医考帮」
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySyncNotesToYkb) ?? false;
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

  /// 保存或更新笔记（先落本地 SQLite，若开启同步则入队并触发同步）
  Future<void> saveNote(QuestionNote note, {Question? question}) async {
    final db = await UserDBHelper().database;
    final syncEnabled = await isSyncEnabled();

    final noteToSave = note.copyWith(
      syncStatus: syncEnabled ? 1 : 0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await db.insert(
      'Notes',
      noteToSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (syncEnabled) {
      await _enqueue(NoteSyncQueueItem(
        id: 'upload_${note.id}_${DateTime.now().millisecondsSinceEpoch}',
        action: 'upload',
        noteId: note.id,
        questionId: note.questionId,
        payload: jsonEncode(noteToSave.toMap()),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // 触发后台处理
      processQueue(question: question);
    }
  }

  /// 删除笔记（先从本地 SQLite 移除，若开启同步且有 remoteId 则入删除队列）
  Future<void> deleteNote(QuestionNote note, {Question? question}) async {
    final db = await UserDBHelper().database;
    final syncEnabled = await isSyncEnabled();

    await db.delete(
      'Notes',
      where: 'id = ?',
      whereArgs: [note.id],
    );

    if (syncEnabled && note.remoteId != null && note.remoteId!.isNotEmpty) {
      await _enqueue(NoteSyncQueueItem(
        id: 'del_${note.remoteId}_${DateTime.now().millisecondsSinceEpoch}',
        action: 'delete',
        noteId: note.remoteId,
        questionId: note.questionId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      processQueue(question: question);
    }
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
        'app-version': '2630',
        'uuid': imei,
        'channel': channelDefault,
        'app-type': 'ykb',
      });

      request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['code'] == '200' && data['data'] != null) {
        final bImg = data['data']['b_img']?.toString() ?? '';
        final sImg = data['data']['s_img']?.toString() ?? bImg;
        return NoteImage(
          bImg: bImg,
          sImg: sImg,
          localPath: file.path,
        );
      }
    } catch (e) {
      debugPrint('[NoteService] uploadImage error: $e');
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
      final appId = question.appId?.isNotEmpty == true ? question.appId! : '1';

      final resp = await basicReq(
        '/allQuestion/Note/getNote',
        {
          'question_id': question.id,
          'subject_id': subjectId,
          'identity_id': identityId,
          'app_id': appId,
          'module_type': '1',
          'page': '1',
          'size': '20',
          'is_vip': '0',
          'is_svip': '0',
        },
        method: 'GET',
      );

      if (resp['code'] == '200' && resp['data'] is List) {
        final remoteList = resp['data'] as List;
        final localNotes = await getLocalNotes(question.id);
        final db = await UserDBHelper().database;

        for (final item in remoteList) {
          final rId = item['id']?.toString() ?? '';
          final rContent = item['content']?.toString() ?? '';
          final rCtime = int.tryParse(item['ctime']?.toString() ?? '0') ?? 0;
          final rTimestamp = rCtime > 0 ? rCtime * 1000 : DateTime.now().millisecondsSinceEpoch;

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
          final matchedLocal = localNotes.where(
            (n) => n.remoteId == rId || n.id == rId,
          ).firstOrNull;

          if (matchedLocal == null) {
            // 本地不存在，插入
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
            // 本地已存在，如果内容有差异且本地没有未上传改动，覆盖为云端内容
            if (matchedLocal.syncStatus == 0) {
              final contentDiff = matchedLocal.content != rContent;
              final imageDiff = matchedLocal.images.length != rImages.length;
              if (contentDiff || imageDiff || matchedLocal.remoteId == null) {
                final updated = matchedLocal.copyWith(
                  remoteId: rId,
                  content: rContent,
                  images: rImages,
                  updatedAt: rTimestamp,
                  syncStatus: 0,
                );
                await db.update(
                  'Notes',
                  updated.toMap(),
                  where: 'id = ?',
                  whereArgs: [matchedLocal.id],
                );
              }
            }
          }
        }
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

  /// 执行同步队列（断网重试）
  Future<void> processQueue({Question? question}) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;
      if (!loggedIn) {
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
        } catch (e) {
          debugPrint('[NoteService] process queue item error: $e');
          await db.update(
            'NoteSyncQueue',
            {
              'retry_count': item.retryCount + 1,
              'last_error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [item.id],
          );
          // 网络异常时暂停后续重试，等待下一次触发
          break;
        }

        if (success) {
          await db.delete(
            'NoteSyncQueue',
            where: 'id = ?',
            whereArgs: [item.id],
          );
        } else {
          await db.update(
            'NoteSyncQueue',
            {
              'retry_count': item.retryCount + 1,
            },
            where: 'id = ?',
            whereArgs: [item.id],
          );
          break;
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
    final identityId = fallbackQuestion?.identityId?.isNotEmpty == true
        ? fallbackQuestion!.identityId!
        : (prefs.getString('identityId') ?? '');
    final subjectId = fallbackQuestion?.chapterParentId ?? '';
    final appId = fallbackQuestion?.appId?.isNotEmpty == true
        ? fallbackQuestion!.appId!
        : '1';

    // 检查并上传尚未上传的本地图片
    final List<NoteImage> updatedImages = [];
    bool imagesChanged = false;
    for (final img in note.images) {
      if (img.bImg.isEmpty && img.localPath != null && img.localPath!.isNotEmpty) {
        final file = File(img.localPath!);
        if (await file.exists()) {
          final uploaded = await uploadImage(
            file,
            subjectId: subjectId,
            identityId: identityId,
            appId: appId,
          );
          if (uploaded != null) {
            updatedImages.add(uploaded);
            imagesChanged = true;
            continue;
          }
        }
      }
      updatedImages.add(img);
    }

    if (imagesChanged) {
      note = note.copyWith(images: updatedImages);
      await db.update(
        'Notes',
        note.toMap(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
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

    final resp = await basicReq(
      '/allQuestion/Note/pushNote',
      params,
      method: 'POST',
    );

    if (resp['code'] == '200' || resp['code'] == 200) {
      String? remoteId = note.remoteId;
      if (remoteId == null || remoteId.isEmpty) {
        // 新上传的笔记尝试查询 getNote 获取服务端生成的 remoteId
        try {
          final listResp = await basicReq(
            '/allQuestion/Note/getNote',
            {
              'question_id': note.questionId,
              'subject_id': subjectId,
              'identity_id': identityId,
              'app_id': appId,
              'module_type': '1',
              'page': '1',
              'size': '5',
              'is_vip': '0',
              'is_svip': '0',
            },
            method: 'GET',
          );
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
        {
          'remote_id': remoteId,
          'sync_status': 0,
        },
        where: 'id = ?',
        whereArgs: [note.id],
      );
      return true;
    }

    return false;
  }

  Future<bool> _processDeleteItem(
    NoteSyncQueueItem item,
    Question? fallbackQuestion,
  ) async {
    if (item.noteId == null || item.noteId!.isEmpty) return true;

    final prefs = await SharedPreferences.getInstance();
    final identityId = fallbackQuestion?.identityId?.isNotEmpty == true
        ? fallbackQuestion!.identityId!
        : (prefs.getString('identityId') ?? '');
    final subjectId = fallbackQuestion?.chapterParentId ?? '';
    final appId = fallbackQuestion?.appId?.isNotEmpty == true
        ? fallbackQuestion!.appId!
        : '1';

    final resp = await basicReq(
      '/allQuestion/Note/cleanNote',
      {
        'id': item.noteId,
        'question_id': item.questionId,
        'module_type': '1',
        'subject_id': subjectId,
        'identity_id': identityId,
        'app_id': appId,
        'is_vip': '0',
        'is_svip': '0',
      },
      method: 'POST',
    );

    if (resp['code'] == '200' || resp['code'] == 200) {
      return true;
    }
    return false;
  }
}
