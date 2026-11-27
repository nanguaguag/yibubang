import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../common/ykb_encrypt.dart';
import '../db/database_helper.dart';
import '../db/durable_sync_queue.dart';
import '../models/note.dart';
import '../models/question.dart';
import 'auth_service.dart';
import 'ykb_sync_service.dart';

/// 医考帮笔记业务与同步队列服务
class NoteService {
  static final NoteService instance = NoteService._internal();
  NoteService._internal();

  static const String keySyncNotesToYkb = 'sync_notes_to_ykb';

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

  /// 正文、修订号和上传义务在同一用户库事务内保存。
  Future<void> saveNote(QuestionNote note, {Question? question}) async {
    final owner = await DurableSyncQueue.owner();
    final db = await UserDBHelper().database;
    final enabled = await isSyncEnabled();
    final removedLocalPaths = <String>[];
    await db.transaction((tx) async {
      final deleted = await tx.query(
        'NoteTombstones',
        where: 'local_id=?',
        whereArgs: [note.id],
      );
      if (deleted.isNotEmpty) throw StateError('笔记已删除，请新建笔记');
      final old = await tx.query('Notes', where: 'id=?', whereArgs: [note.id]);
      if (old.isNotEmpty) {
        final oldNote = QuestionNote.fromMap(old.single);
        final keptPaths = note.images
            .map((i) => i.localPath)
            .whereType<String>()
            .toSet();
        for (final img in oldNote.images) {
          final path = img.localPath;
          if (path != null && path.isNotEmpty && !keptPaths.contains(path)) {
            removedLocalPaths.add(path);
          }
        }
      }
      final revision = old.isEmpty ? 1 : (old.single['revision'] as int) + 1;
      final saved = note.copyWith(
        syncStatus: enabled ? 1 : 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        remoteId: old.isEmpty
            ? note.remoteId
            : old.single['remote_id'] as String?,
      );
      await tx.insert('Question', {
        'id': note.questionId,
        'chapter_id': question?.chapterId ?? '',
        'chapter_parent_id': question?.chapterParentId ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.delete(
        'CloudDeletedNotes',
        where: 'id=?',
        whereArgs: [saved.id],
      );
      await tx.insert('Notes', {
        ...saved.toMap(),
        'revision': revision,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete(
        'NoteSyncQueue',
        where: "note_id=? AND action='upload' AND queue_state!='sending'",
        whereArgs: [note.id],
      );
      if (enabled) await _queueNote(tx, saved, owner, question: question);
    });
    _cleanupSandboxImages(removedLocalPaths);
    if (enabled) unawaited(processQueue(question: question));
    notifyNoteChanged();
  }

  /// 保留在途上传和删除标记，晚到 ACK 可补远端删除，拉取不会复活原笔记。
  Future<void> deleteNote(QuestionNote note, {Question? question}) async {
    final owner = await DurableSyncQueue.owner();
    final db = await UserDBHelper().database;
    final enabled = await isSyncEnabled();
    final removedLocalPaths = <String>[];
    await db.transaction((tx) async {
      final rows = await tx.query('Notes', where: 'id=?', whereArgs: [note.id]);
      final current = rows.isEmpty ? note : QuestionNote.fromMap(rows.single);
      for (final img in current.images) {
        if (img.localPath != null && img.localPath!.isNotEmpty) {
          removedLocalPaths.add(img.localPath!);
        }
      }
      final remote = current.remoteId?.isNotEmpty == true
          ? current.remoteId
          : (!current.id.startsWith('local_') ? current.id : null);
      final inflight = await tx.query(
        'NoteSyncQueue',
        columns: ['owner_user_id'],
        where: "note_id=? AND action='upload' AND queue_state='sending'",
        whereArgs: [current.id],
      );
      final owners = {
        owner,
        ...inflight.map((r) => r['owner_user_id'] as String),
      };
      for (final account in owners) {
        await tx.insert('NoteTombstones', {
          'local_id': current.id,
          'owner_user_id': account,
          'remote_id': remote,
          'question_id': current.questionId,
          'content': current.content,
          'imgs': jsonEncode(current.images.map((i) => i.toJson()).toList()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.delete('Notes', where: 'id=?', whereArgs: [note.id]);
      await tx.delete(
        'NoteSyncQueue',
        where: "note_id=? AND action='upload' AND queue_state!='sending'",
        whereArgs: [note.id],
      );
      if (enabled && remote != null) {
        await _queueDelete(
          tx,
          current.questionId,
          remote,
          owner,
          question: question,
        );
      }
    });
    _cleanupSandboxImages(removedLocalPaths);
    if (enabled) unawaited(processQueue(question: question));
    notifyNoteChanged();
  }

  /// 清理应用沙盒 note_images 目录下不再被引用的孤儿图片文件
  void _cleanupSandboxImages(List<String> paths) {
    for (final rawPath in paths) {
      try {
        if (p.basename(p.dirname(rawPath)) != 'note_images') continue;
        final file = File(rawPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<void> _queueNote(
    DatabaseExecutor tx,
    QuestionNote note,
    String owner, {
    Question? question,
    Map<String, dynamic>? metadata,
  }) async {
    await DurableSyncQueue.enqueue('NoteSyncQueue', {
      ...NoteSyncQueueItem(
        id: 'upload_${generateSimpleId()}',
        action: 'upload',
        noteId: note.id,
        questionId: note.questionId,
        payload: jsonEncode({
          ...note.toMap(),
          'subject_id':
              question?.chapterParentId ?? metadata?['subject_id'] ?? '',
          'identity_id': question?.identityId ?? metadata?['identity_id'] ?? '',
          'app_id':
              question?.nativeAppId ??
              question?.appId ??
              metadata?['app_id'] ??
              '12',
        }),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ).toMap(),
      'owner_user_id': owner,
    }, executor: tx);
  }

  Future<void> _queueDelete(
    DatabaseExecutor tx,
    String questionId,
    String remote,
    String owner, {
    Question? question,
    Map<String, dynamic>? metadata,
  }) async {
    final existing = await tx.query(
      'NoteSyncQueue',
      where: "action='delete' AND note_id=? AND owner_user_id=?",
      whereArgs: [remote, owner],
    );
    if (existing.isNotEmpty) return;
    await DurableSyncQueue.enqueue('NoteSyncQueue', {
      ...NoteSyncQueueItem(
        id: 'del_${generateSimpleId()}',
        action: 'delete',
        noteId: remote,
        questionId: questionId,
        payload: jsonEncode({
          'subject_id':
              question?.chapterParentId ?? metadata?['subject_id'] ?? '',
          'identity_id': question?.identityId ?? metadata?['identity_id'] ?? '',
          'app_id':
              question?.nativeAppId ??
              question?.appId ??
              metadata?['app_id'] ??
              '12',
        }),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ).toMap(),
      'owner_user_id': owner,
    }, executor: tx);
  }

  /// 上传单张图片到医考帮服务器
  Future<NoteImage?> uploadImage(
    File file, {
    String? subjectId,
    String? identityId,
    String? appId,
    String? expectedOwner,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;
      if (!loggedIn) {
        debugPrint('[NoteService] uploadImage skipped: user not logged in');
        return null;
      }
      if (expectedOwner != null &&
          prefs.getString('user_id') != expectedOwner) {
        throw StateError('笔记同步账号已切换');
      }
      final token = prefs.getString('token') ?? '';
      final secret = prefs.getString('secret') ?? '';
      final userId = prefs.getString('user_id') ?? '';

      final effectiveIdentityId =
          (identityId != null && identityId.isNotEmpty)
              ? identityId
              : (prefs.getString('identityId') ?? '1');
      final effectiveAppId =
          (appId != null && appId.isNotEmpty) ? appId : '12';
      final effectiveSubjectId =
          (subjectId != null && subjectId.isNotEmpty) ? subjectId : '1';

      final timestamp = getTimestamp();
      final fields = <String, String>{
        'subject_id': effectiveSubjectId,
        'is_svip': '0',
        'user_id': userId,
        'identity_id': effectiveIdentityId,
        'is_vip': '0',
        'secret': secret,
        'app_id': effectiveAppId,
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
      final client = http.Client();
      final http.Response response;
      try {
        response = await (() async => http.Response.fromStream(
          await client.send(request),
        ))().timeout(const Duration(seconds: 30));
      } finally {
        client.close();
      }
      final bodyStr = utf8.decode(response.bodyBytes);
      debugPrint(
        '[NoteService] uploadImage response (${response.statusCode}): $bodyStr',
      );

      final data = jsonDecode(bodyStr);
      final code = data['code']?.toString() ?? '';
      if (code == '309') {
        debugPrint('[NoteService] uploadImage session expired (309)');
        await AuthService.instance.handleExpiredSession(loggedIn ? token : null);
        throw const FormatException('309_TOKEN_EXPIRED');
      }
      if (code == '200' && data['data'] != null) {
        final bImg = data['data']['b_img']?.toString() ?? '';
        final sImg = data['data']['s_img']?.toString() ?? bImg;
        return NoteImage(bImg: bImg, sImg: sImg, localPath: file.path);
      } else {
        debugPrint(
          '[NoteService] uploadImage failed with code: ${data['code']}, msg: ${data['message']}',
        );
      }
    } on FormatException {
      rethrow;
    } on StateError {
      rethrow;
    } catch (e, stack) {
      debugPrint('[NoteService] uploadImage exception: $e\n$stack');
    }
    return null;
  }

  /// 当 pushNote 返回 code=200 但 data={} 不含新建笔记 id 时，
  /// 紧跟查询一次 getNote，按正文和首图匹配出服务端刚分配的真实 id。
  Future<String?> _resolveCreatedRemoteId({
    required QuestionNote note,
    required QuestionSyncMeta meta,
    required String owner,
  }) async {
    try {
      final resp = await basicReq(
        '/allQuestion/Note/getNote',
        {
          'question_id': note.questionId,
          'subject_id': meta.subjectId,
          'identity_id': meta.identityId,
          'app_id': meta.appId,
          'module_type': '1',
          'page': '1',
          'size': '20',
          'is_vip': '0',
          'is_svip': '0',
        },
        method: 'GET',
        expectedOwner: owner,
      );
      if (resp['code']?.toString() != '200' || resp['data'] is! List) {
        return null;
      }
      final remoteList = resp['data'] as List;
      final db = await UserDBHelper().database;
      final localRows = await db.query(
        'Notes',
        columns: ['id', 'remote_id'],
        where: 'question_id = ?',
        whereArgs: [note.questionId],
      );
      final boundRemoteIds = localRows
          .where((r) => r['id'] != note.id)
          .map((r) => r['remote_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final expectedImg =
          note.images.isNotEmpty ? note.images.first.bImg : '';

      String? bestId;
      var bestCtime = -1;
      for (final raw in remoteList) {
        if (raw is! Map) continue;
        final rId = raw['id']?.toString() ?? '';
        if (rId.isEmpty || boundRemoteIds.contains(rId)) continue;
        final rContent = raw['content']?.toString() ?? '';
        if (rContent != note.content) continue;
        var rImg = '';
        if (raw['img'] is List && (raw['img'] as List).isNotEmpty) {
          final first = (raw['img'] as List).first;
          if (first is Map) {
            rImg = first['b_img']?.toString() ?? '';
          }
        }
        if (expectedImg.isNotEmpty && rImg.isNotEmpty && expectedImg != rImg) {
          continue;
        }
        final ctime = int.tryParse(raw['ctime']?.toString() ?? '0') ?? 0;
        if (ctime >= bestCtime) {
          bestCtime = ctime;
          bestId = rId;
        }
      }
      return bestId;
    } catch (e) {
      debugPrint('[NoteService] _resolveCreatedRemoteId failed: $e');
      return null;
    }
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

    final pullOwner = prefs.getString('user_id') ?? '';
    // 先跑一下当前题目的上传队列
    await processQueue(question: question);

    // 从医考帮获取笔记
    try {
      final meta = await YkbSyncService.instance.resolveQuestionMeta(
        question.id,
        question: question,
      );

      final resp = await basicReq(
        '/allQuestion/Note/getNote',
        {
          'question_id': question.id,
          'subject_id': meta.subjectId,
          'identity_id': meta.identityId,
          'app_id': meta.appId,
          'module_type': '1',
          'page': '1',
          'size': '20',
          'is_vip': '0',
          'is_svip': '0',
        },
        method: 'GET',
        expectedOwner: pullOwner,
      );
      if (await DurableSyncQueue.owner() != pullOwner) {
        return await getLocalNotes(question.id);
      }

      if (resp['code'].toString() == '200' && resp['data'] is List) {
        final remoteList = resp['data'] as List;
        final localNotes = await getLocalNotes(question.id);
        final db = await UserDBHelper().database;
        final claimedLocalIds = <String>{};

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

          final account = pullOwner;
          final tombs = await db.query(
            'NoteTombstones',
            where: 'owner_user_id=? AND question_id=?',
            whereArgs: [account, question.id],
          );
          final remoteImage = rImages.isEmpty ? '' : rImages.first.bImg;
          final deleted = tombs.any((t) {
            if (t['remote_id'] == rId) return true;
            if (t['remote_id'] != null || t['content'] != rContent) {
              return false;
            }
            final images = jsonDecode(t['imgs'] as String) as List;
            final image = images.isEmpty ? '' : (images.first as Map)['b_img'];
            return image == remoteImage;
          });
          if (deleted) {
            continue;
          }
          // 匹配本地记录：优先按 remote_id 或 id，其次认领尚未关联 remote_id 但内容一致的本地笔记
          var matchedLocal = localNotes
              .where((n) => n.remoteId == rId || n.id == rId)
              .firstOrNull;
          matchedLocal ??= localNotes
              .where(
                (n) =>
                    !claimedLocalIds.contains(n.id) &&
                    (n.remoteId == null || n.remoteId!.isEmpty) &&
                    n.content == rContent,
              )
              .firstOrNull;
          if (matchedLocal != null) {
            claimedLocalIds.add(matchedLocal.id);
          }

          if (matchedLocal == null) {
            // 本地不存在，插入
            // 外键约束已开启：先补 Question 兜底行（查看他人笔记的题可能从未作答）。
            await db.insert('Question', {
              'id': question.id,
              'chapter_id': meta.chapterId,
              'chapter_parent_id': meta.chapterParentId,
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
                where:
                    'id = ? AND updated_at = ? AND content = ? AND imgs = ? AND sync_status = 0',
                whereArgs: [
                  matchedLocal.id,
                  matchedLocal.updatedAt,
                  matchedLocal.content,
                  jsonEncode(
                    matchedLocal.images.map((i) => i.toJson()).toList(),
                  ),
                ],
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
              'subject_id': meta.subjectId,
            }),
            'question_id': int.tryParse(question.id) ?? 0,
            'subject_id': meta.subjectId,
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
  Future<bool> _executeRow(Map<String, dynamic> row, Question? question) async {
    final item = NoteSyncQueueItem.fromMap(row);
    final owner = row['owner_user_id'] as String;
    if (item.action == 'upload') {
      return _processUploadItem(item, question, owner);
    }
    if (item.action == 'delete') {
      return _processDeleteItem(item, question, owner);
    }
    throw StateError('不支持的笔记同步任务: ${item.action}');
  }

  Future<bool> retryItem(String id, {Question? question}) async {
    if (!await DurableSyncQueue.reset('NoteSyncQueue', id: id)) return false;
    return DurableSyncQueue.run(
      'NoteSyncQueue',
      (row) => _executeRow(row, question),
      onlyId: id,
    );
  }

  Future<void> resetItemRetry(String id) async {
    await DurableSyncQueue.reset('NoteSyncQueue', id: id);
  }

  Future<void> resetAllRetries() async {
    await DurableSyncQueue.reset('NoteSyncQueue');
  }

  Future<void> processQueue({Question? question}) async {
    await DurableSyncQueue.run(
      'NoteSyncQueue',
      (row) => _executeRow(row, question),
    );
  }

  Future<bool> _processUploadItem(
    NoteSyncQueueItem item,
    Question? fallbackQuestion,
    String owner,
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
    var revision = noteRows.first['revision'] as int;

    Map<String, dynamic> itemPayload = {};
    if (item.payload != null && item.payload!.isNotEmpty) {
      try {
        itemPayload = jsonDecode(item.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }

    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      item.questionId,
      question: fallbackQuestion,
      subjectId: itemPayload['subject_id']?.toString(),
      identityId: itemPayload['identity_id']?.toString(),
      appId: itemPayload['app_id']?.toString(),
    );

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
            subjectId: meta.subjectId,
            identityId: meta.identityId,
            appId: meta.appId,
            expectedOwner: owner,
          );
          if (uploaded == null) throw StateError('笔记图片尚未上传成功');
          updatedImages[0] = uploaded;
          final changed = await db.update(
            'Notes',
            {'imgs': jsonEncode(updatedImages.map((i) => i.toJson()).toList())},
            where: 'id=? AND revision=?',
            whereArgs: [note.id, revision],
          );
          if (changed == 0) {
            await _queueCurrentNote(db, note.id, owner, itemPayload);
            return true;
          }
          note = note.copyWith(images: updatedImages);
          revision++;
        }
      }
    }

    final current = await db.query(
      'Notes',
      where: 'id=? AND revision=?',
      whereArgs: [note.id, revision],
    );
    if (current.isEmpty) {
      await _queueCurrentNote(db, note.id, owner, itemPayload);
      return true;
    }
    // 调用 pushNote
    final params = <String, dynamic>{
      'question_id': note.questionId,
      'content': note.content,
      'module_type': '1',
      'subject_id': meta.subjectId,
      'identity_id': meta.identityId,
      'app_id': meta.appId,
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
      expectedOwner: owner,
      method: 'POST',
    );
    debugPrint('[NoteService] pushNote result: $resp');
    final code = resp['code']?.toString() ?? 'protocol_error';
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
      final data = resp['data'];
      var remoteId = note.remoteId?.isNotEmpty == true
          ? note.remoteId
          : (data is Map ? (data['id'] ?? data['note_id'])?.toString() : null);
      if (remoteId == null || remoteId.isEmpty) {
        remoteId = await _resolveCreatedRemoteId(
          note: note,
          meta: meta,
          owner: owner,
        );
      }
      if (remoteId == null || remoteId.isEmpty) {
        await db.update(
          'NoteSyncQueue',
          {
            'last_error': '上传已确认但缺少可靠笔记ID，请核对远端后关联；自动重试已暂停',
            'last_response': jsonEncode({
              'code': 'protocol_error',
              'response': resp,
            }),
          },
          where: 'id=?',
          whereArgs: [item.id],
        );
        return false;
      }
      var needsQueue = false;
      await db.transaction((tx) async {
        final tomb = await tx.query(
          'NoteTombstones',
          where: 'local_id=? AND owner_user_id=?',
          whereArgs: [note.id, owner],
        );
        if (tomb.isNotEmpty) {
          await tx.update(
            'NoteTombstones',
            {'remote_id': remoteId},
            where: 'local_id=? AND owner_user_id=?',
            whereArgs: [note.id, owner],
          );
          await _queueDelete(
            tx,
            note.questionId,
            remoteId!,
            owner,
            metadata: itemPayload,
          );
        } else {
          // 关联远端身份独立于正文版本；仅实际发送的版本可标记为已同步。
          await tx.update(
            'Notes',
            {'remote_id': remoteId},
            where: 'id=?',
            whereArgs: [note.id],
          );
          needsQueue =
              await tx.update(
                'Notes',
                {'sync_status': 0},
                where: 'id=? AND revision=?',
                whereArgs: [note.id, revision],
              ) ==
              0;
        }
      });
      if (needsQueue) await _queueCurrentNote(db, note.id, owner, itemPayload);

      // 记录笔记上传流水到 Activities
      try {
        await db.insert('Activities', {
          'id': generateSimpleId(),
          'title': 'NoteUpload',
          'description': jsonEncode(params),
          'question_id': int.tryParse(note.questionId) ?? 0,
          'subject_id': meta.subjectId,
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

  Future<void> _queueCurrentNote(
    Database db,
    String id,
    String owner,
    Map<String, dynamic> metadata,
  ) async {
    await db.transaction((tx) async {
      final rows = await tx.query('Notes', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final pending = await tx.query(
        'NoteSyncQueue',
        where: "note_id=? AND action='upload' AND queue_state='pending'",
        whereArgs: [id],
      );
      if (pending.isEmpty) {
        await _queueNote(
          tx,
          QuestionNote.fromMap(rows.single),
          owner,
          metadata: metadata,
        );
      }
    });
  }

  Future<bool> _processDeleteItem(
    NoteSyncQueueItem item,
    Question? fallbackQuestion,
    String owner,
  ) async {
    if (item.noteId == null || item.noteId!.isEmpty) return true;

    final db = await UserDBHelper().database;

    Map<String, dynamic> itemPayload = {};
    if (item.payload != null && item.payload!.isNotEmpty) {
      try {
        itemPayload = jsonDecode(item.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }

    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      item.questionId,
      question: fallbackQuestion,
      subjectId: itemPayload['subject_id']?.toString(),
      identityId: itemPayload['identity_id']?.toString(),
      appId: itemPayload['app_id']?.toString(),
    );

    final resp = await basicReq(
      '/allQuestion/Note/cleanNote',
      {
        'id': item.noteId,
        'question_id': item.questionId,
        'module_type': '1',
        'subject_id': meta.subjectId,
        'identity_id': meta.identityId,
        'app_id': meta.appId,
        'is_vip': '0',
        'is_svip': '0',
      },
      method: 'POST',
      expectedOwner: owner,
    );

    final code = resp['code']?.toString() ?? 'protocol_error';
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
            'subject_id': meta.subjectId,
          }),
          'question_id': int.tryParse(item.questionId) ?? 0,
          'subject_id': meta.subjectId,
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
