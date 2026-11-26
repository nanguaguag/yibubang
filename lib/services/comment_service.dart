import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../common/ykb_encrypt.dart';
import '../db/database_helper.dart';
import '../db/durable_sync_queue.dart';
import '../models/comment.dart';
import '../models/question.dart';
import 'ykb_sync_service.dart';

/// 医考帮评论四维排序分类（对应 /comment/main/hot 的 type 参数）
enum CommentSortType {
  mostLiked('', '最多点赞'),
  hottest('recommend', '最高热度'),
  mostReplied('replies', '最多回复'),
  latest('newst', '最新发布');

  final String apiType;
  final String label;
  const CommentSortType(this.apiType, this.label);
}

/// 全局批量扫描同步评论/点赞进度状态（跨页面生命周期保持）
class CommentBatchSyncState {
  final SavedCommentCategory? category;
  final int current;
  final int total;
  final bool isRunning;
  final bool isCancelled;

  const CommentBatchSyncState({
    this.category,
    this.current = 0,
    this.total = 0,
    this.isRunning = false,
    this.isCancelled = false,
  });

  CommentBatchSyncState copyWith({
    SavedCommentCategory? category,
    int? current,
    int? total,
    bool? isRunning,
    bool? isCancelled,
  }) {
    return CommentBatchSyncState(
      category: category ?? this.category,
      current: current ?? this.current,
      total: total ?? this.total,
      isRunning: isRunning ?? this.isRunning,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }
}

/// 医考帮评论、我的点赞 (mypraise) 与我的评论 (mycomment) 同步及本地归纳管理服务
class CommentService {
  static final CommentService instance = CommentService._internal();
  CommentService._internal();

  static const String keySyncCommentsFromYkb = 'sync_comments_from_ykb';

  /// 全局点赞/评论变动通知器（触发 UI 实时刷新）
  final ValueNotifier<int> commentSyncEventNotifier = ValueNotifier<int>(0);

  /// 全局批量扫描同步状态（跨页面生命周期保持）
  final ValueNotifier<CommentBatchSyncState> batchSyncNotifier =
      ValueNotifier<CommentBatchSyncState>(const CommentBatchSyncState());

  /// 当前是否有全局批量同步在运行
  bool get isBatchSyncing => batchSyncNotifier.value.isRunning;

  /// 取消当前正在运行的全局批量同步
  void cancelBatchSync() {
    if (batchSyncNotifier.value.isRunning) {
      batchSyncNotifier.value =
          batchSyncNotifier.value.copyWith(isCancelled: true);
    }
  }

  void notifyCommentChanged() {
    commentSyncEventNotifier.value++;
  }

  Future<bool> isSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keySyncCommentsFromYkb) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 确保 SavedComments 与墓碑表在当前连接上已就绪（兼容测试内存库与历史库）
  Future<void> ensureTables([DatabaseExecutor? executor]) async {
    final db = executor ?? await UserDBHelper().database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SavedComments (
        id TEXT PRIMARY KEY,
        comment_id TEXT NOT NULL,
        question_id TEXT NOT NULL,
        category TEXT NOT NULL,
        user_id TEXT NOT NULL DEFAULT '',
        nickname TEXT NOT NULL DEFAULT '',
        avatar TEXT NOT NULL DEFAULT '',
        school TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        praise_num INTEGER NOT NULL DEFAULT 0,
        oppose_num INTEGER NOT NULL DEFAULT 0,
        replies INTEGER NOT NULL DEFAULT 0,
        floor_num TEXT NOT NULL DEFAULT '1',
        ctime TEXT NOT NULL DEFAULT '',
        img_watermark TEXT NOT NULL DEFAULT '',
        reply_json TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_saved_comments_question_cat
        ON SavedComments(question_id, category)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_saved_comments_cat_time
        ON SavedComments(category, timestamp DESC)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CloudDeletedSavedComments (
        id TEXT PRIMARY KEY
      )
    ''');
  }

  /// 获取指定题目的本地归纳点赞或个人评论
  Future<List<SavedComment>> getLocalComments(
    String questionId, {
    SavedCommentCategory? category,
  }) async {
    final db = await UserDBHelper().database;
    await ensureTables(db);
    final where = category != null
        ? 'question_id = ? AND category = ?'
        : 'question_id = ?';
    final whereArgs = category != null
        ? [questionId, category.value]
        : [questionId];
    final rows = await db.query(
      'SavedComments',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => SavedComment.fromMap(r)).toList();
  }

  /// 获取某题目下已保存在本地的点赞评论 ID 集合
  Future<Set<String>> getLocalPraisedCommentIds(String questionId) async {
    final list = await getLocalComments(
      questionId,
      category: SavedCommentCategory.praise,
    );
    return list.map((e) => e.commentId).toSet();
  }

  /// 获取所有本地归纳保存的点赞或评论（按时间倒序）
  Future<List<SavedComment>> getAllSavedComments({
    SavedCommentCategory? category,
  }) async {
    final db = await UserDBHelper().database;
    await ensureTables(db);
    final rows = await db.query(
      'SavedComments',
      where: category != null ? 'category = ?' : null,
      whereArgs: category != null ? [category.value] : null,
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => SavedComment.fromMap(r)).toList();
  }

  /// 保存或更新单条归纳评论/点赞
  Future<void> saveComment(
    SavedComment item, {
    Question? question,
    bool clearTombstone = true,
  }) async {
    final db = await UserDBHelper().database;
    await ensureTables(db);
    await db.transaction((tx) async {
      await tx.insert('Question', {
        'id': item.questionId,
        'chapter_id': question?.chapterId ?? '',
        'chapter_parent_id': question?.chapterParentId ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (clearTombstone) {
        await tx.delete(
          'CloudDeletedSavedComments',
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
      await tx.insert(
        'SavedComments',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    notifyCommentChanged();
  }

  /// 删除本地保存的某条点赞或评论记录
  Future<void> deleteSavedComment(String id) async {
    final db = await UserDBHelper().database;
    await ensureTables(db);
    await db.transaction((tx) async {
      await tx.insert(
        'CloudDeletedSavedComments',
        {'id': id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await tx.delete('SavedComments', where: 'id = ?', whereArgs: [id]);
    });
    notifyCommentChanged();
  }

  /// 从普通评论列表中自动提取当前用户已点赞 (is_praise=='1') 或自己发表 (is_author=='1') 的评论落库
  Future<void> harvestFromCommentList(
    List<Comment> comments, {
    required String questionId,
    Question? question,
    String? currentUserId,
  }) async {
    if (comments.isEmpty) return;
    final toSave = <SavedComment>[];
    for (final c in comments) {
      if (c.id.isEmpty) continue;
      if (c.isPraise == '1') {
        toSave.add(
          SavedComment.fromApiComment(
            c,
            questionId: questionId,
            category: SavedCommentCategory.praise.value,
          ),
        );
      }
      if (c.isAuthor == '1' ||
          (currentUserId != null &&
              currentUserId.isNotEmpty &&
              c.userId == currentUserId)) {
        toSave.add(
          SavedComment.fromApiComment(
            c,
            questionId: questionId,
            category: SavedCommentCategory.myComment.value,
          ),
        );
      }
    }
    if (toSave.isEmpty) return;
    await _upsertRemoteBatch(
      toSave,
      questionId: questionId,
      question: question,
    );
  }

  Future<int> _upsertRemoteBatch(
    List<SavedComment> items, {
    required String questionId,
    Question? question,
    String? chapterId,
    String? chapterParentId,
  }) async {
    if (items.isEmpty) return 0;
    final db = await UserDBHelper().database;
    await ensureTables(db);
    var insertedOrUpdated = 0;
    await db.transaction((tx) async {
      final tombRows = await tx.query('CloudDeletedSavedComments');
      final tombIds = tombRows.map((r) => r['id']?.toString() ?? '').toSet();

      await tx.insert('Question', {
        'id': questionId,
        'chapter_id': chapterId ?? question?.chapterId ?? '',
        'chapter_parent_id': chapterParentId ?? question?.chapterParentId ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      for (final item in items) {
        if (tombIds.contains(item.id)) continue;
        final existing = await tx.query(
          'SavedComments',
          columns: ['id', 'updated_at', 'timestamp'],
          where: 'id = ?',
          whereArgs: [item.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await tx.insert(
            'SavedComments',
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          insertedOrUpdated++;
        } else {
          final oldTs = (existing.first['timestamp'] as num?)?.toInt() ?? 0;
          final keptTs = item.timestamp > 0 ? item.timestamp : oldTs;
          final updated = SavedComment(
            id: item.id,
            commentId: item.commentId,
            questionId: item.questionId,
            category: item.category,
            userId: item.userId,
            nickname: item.nickname,
            avatar: item.avatar,
            school: item.school,
            content: item.content,
            praiseNum: item.praiseNum,
            opposeNum: item.opposeNum,
            replies: item.replies,
            floorNum: item.floorNum,
            ctime: item.ctime,
            imgWatermark: item.imgWatermark,
            replyList: item.replyList,
            timestamp: keptTs,
            updatedAt: item.updatedAt > oldTs ? item.updatedAt : oldTs,
            syncStatus: 0,
          );
          await tx.update(
            'SavedComments',
            updated.toMap(),
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      }
    });
    if (insertedOrUpdated > 0) {
      notifyCommentChanged();
    }
    return insertedOrUpdated;
  }

  /// 与 NoteService.syncNotesForQuestion 相同的流程：
  /// 拉取指定题目的「我的点赞」(func=mypraise) 与「我的评论」(func=mycomment) 并合并落入本地用户库
  Future<void> syncCommentsForQuestion(
    Question question, {
    bool syncPraise = true,
    bool syncMyComment = true,
  }) async {
    if (!await isSyncEnabled()) return;
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) return;

    final pullOwner = prefs.getString('user_id') ?? '';
    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      question.id,
      question: question,
    );
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);

    if (syncPraise) {
      await _pullCategoryForQuestion(
        question: question,
        meta: meta,
        outerIdentityId: outerIdentityId,
        pullOwner: pullOwner,
        func: 'mypraise',
        category: SavedCommentCategory.praise,
      );
    }
    if (syncMyComment) {
      await _pullCategoryForQuestion(
        question: question,
        meta: meta,
        outerIdentityId: outerIdentityId,
        pullOwner: pullOwner,
        func: 'mycomment',
        category: SavedCommentCategory.myComment,
      );
    }
  }

  Future<List<SavedComment>> _pullCategoryForQuestion({
    required Question question,
    required QuestionSyncMeta meta,
    required String outerIdentityId,
    required String pullOwner,
    required String func,
    required SavedCommentCategory category,
  }) async {
    try {
      final ts = getTimestamp();
      final resp = await basicReq(
        '/Comment/Main/list',
        {
          'subject_id': meta.subjectId,
          'obj_id': question.id,
          'is_svip': '0',
          'module_type': '1',
          'identity_id': outerIdentityId,
          'is_vip': '0',
          'func': func,
          'comment_type': '2',
          'break_point': ts,
          'page': '1',
          'app_id': meta.appId,
        },
        method: 'POST',
        expectedOwner: pullOwner,
      );

      final code = resp['code']?.toString() ?? '';
      if (code == '309') {
        return await getLocalComments(question.id, category: category);
      }

      if (await DurableSyncQueue.owner() != pullOwner) {
        return await getLocalComments(question.id, category: category);
      }

      if (code == '200' && resp['data'] is Map) {
        final data = CommentData.fromJson(
          Map<String, dynamic>.from(resp['data'] as Map),
        );
        final allRemote = <Comment>[...data.hot, ...data.timeLine];
        if (allRemote.isNotEmpty) {
          final seenIds = <String>{};
          final savedList = <SavedComment>[];
          for (final c in allRemote) {
            if (c.id.isEmpty || !seenIds.add(c.id)) continue;
            savedList.add(
              SavedComment.fromApiComment(
                c,
                questionId: question.id,
                category: category.value,
              ),
            );
          }
          await _upsertRemoteBatch(
            savedList,
            questionId: question.id,
            question: question,
            chapterId: meta.chapterId,
            chapterParentId: meta.chapterParentId,
          );
        }
      }
    } catch (e) {
      debugPrint('[CommentService] pull $func for ${question.id} error: $e');
    }
    return getLocalComments(question.id, category: category);
  }

  /// 获取医考帮题目评论四维排序（最多点赞 / 最高热度 / 最多回复 / 最新发布）
  /// 接口：POST /comment/main/hot
  Future<CommentData> fetchSortedComments({
    required Question question,
    required CommentSortType sortType,
    required int page,
    String? breakPoint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? '';
    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      question.id,
      question: question,
    );
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);

    final response = await basicReq('/comment/main/hot', {
      'subject_id': meta.subjectId,
      'obj_id': question.id,
      'is_svip': '0',
      'module_type': '1',
      'identity_id': outerIdentityId,
      'is_vip': '0',
      'type': sortType.apiType,
      'comment_type': '2',
      'break_point': breakPoint ?? getTimestamp(),
      'page': page.toString(),
      'app_id': meta.appId,
    });

    final dynamic code = response['code'];
    if (code == 309 || code == '309') {
      return CommentData(hot: const [], timeLine: const []);
    }

    final dynamic rawData = response['data'];
    CommentData result;
    if (rawData is Map<String, dynamic>) {
      result = CommentData.fromJson(rawData);
    } else if (rawData is Map) {
      result = CommentData.fromJson(Map<String, dynamic>.from(rawData));
    } else {
      result = CommentData(hot: const [], timeLine: const []);
    }

    // 顺带自动归档返回列表中已标记为本人点赞或本人发表的评论
    unawaited(
      harvestFromCommentList(
        [...result.hot, ...result.timeLine],
        questionId: question.id,
        question: question,
        currentUserId: currentUserId,
      ),
    );

    return result;
  }

  /// 点赞评论并自动归纳保存至本地「我的点赞」及云同步
  Future<Map<String, dynamic>> praiseComment({
    required Comment comment,
    required Question question,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      question.id,
      question: question,
    );
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);

    final resp = await basicReq('/Comment/Main/praise', {
      'id': comment.id,
      'obj_id': question.id,
      'type': '1',
      'comment_type': '2',
      'module_type': '1',
      'subject_id': meta.subjectId,
      'identity_id': outerIdentityId,
      'app_id': meta.appId,
      'is_vip': '0',
      'is_svip': '0',
    });

    final code = resp['code']?.toString() ?? '';
    if (code == '200') {
      final currentPraise = int.tryParse(comment.praiseNum) ?? 0;
      final praisedComment = Comment(
        id: comment.id,
        objId: question.id,
        userId: comment.userId,
        content: comment.content,
        praiseNum: '${currentPraise + 1}',
        opposeNum: comment.opposeNum,
        floorNum: comment.floorNum,
        replies: comment.replies,
        school: comment.school,
        ctime: comment.ctime,
        ctimeTimestamp: comment.ctimeTimestamp,
        avatar: comment.avatar,
        nickname: comment.nickname,
        imgs: comment.imgs,
        cimgs: comment.cimgs,
        imgWatermark: comment.imgWatermark,
        parentId: comment.parentId,
        isPraise: '1',
        isAuthor: comment.isAuthor,
        reply: comment.reply,
      );
      final saved = SavedComment.fromApiComment(
        praisedComment,
        questionId: question.id,
        category: SavedCommentCategory.praise.value,
        fallbackTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await saveComment(saved, question: question);
    }
    return resp;
  }

  /// 发表评论并自动归纳保存至本地「我的评论」及云同步
  /// 接口：POST /Comment/Main/publish
  Future<Map<String, dynamic>> publishComment({
    required String content,
    required Question question,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      question.id,
      question: question,
    );
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);

    final resp = await basicReq('/Comment/Main/publish', {
      'subject_id': meta.subjectId,
      'obj_id': question.id,
      'is_svip': '0',
      'module_type': '1',
      'identity_id': outerIdentityId,
      'is_vip': '0',
      'content': content,
      'comment_type': '2',
      'app_id': meta.appId,
    });

    final code = resp['code']?.toString() ?? '';
    if (code == '200') {
      Comment created;
      if (resp['data'] is Map) {
        created = Comment.fromJson(
          Map<String, dynamic>.from(resp['data'] as Map),
        );
      } else {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        created = Comment(
          id: 'local_$nowSec',
          objId: question.id,
          userId: prefs.getString('user_id') ?? '',
          content: content,
          praiseNum: '0',
          opposeNum: '0',
          floorNum: '1',
          replies: '0',
          school: prefs.getString('now_name') ?? '',
          ctime: '刚刚',
          ctimeTimestamp: nowSec,
          avatar: prefs.getString('avatar') ?? '',
          nickname: prefs.getString('nickname') ?? '我',
          imgs: '',
          cimgs: '',
          imgWatermark: '',
          parentId: '0',
          isPraise: '0',
          isAuthor: '1',
          reply: const [],
        );
      }
      final saved = SavedComment.fromApiComment(
        created,
        questionId: question.id,
        category: SavedCommentCategory.myComment.value,
        fallbackTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await saveComment(saved, question: question);
    }
    return resp;
  }

  /// 批量扫描用户已作答/收藏/记笔记的题目，从医考帮拉取历史点赞或个人评论
  /// 获取待扫描同步评论/点赞的题目列表（已做题、收藏、笔记或已有评论的题目去重集合）
  Future<List<String>> getTouchedQuestionIds() async {
    final db = await UserDBHelper().database;
    await ensureTables(db);
    final qRows = await db.rawQuery('''
      SELECT id FROM Question WHERE status != 0 OR collection = 1
      UNION
      SELECT DISTINCT question_id AS id FROM Notes
      UNION
      SELECT DISTINCT question_id AS id FROM SavedComments
    ''');
    return qRows
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<int> syncFromTouchedQuestions({
    SavedCommentCategory? category,
    List<String>? targetQuestionIds,
    bool Function()? isCancelled,
    void Function(int current, int total)? onProgress,
  }) async {
    // 互斥保护：严禁两个批量同步任务并发运行
    if (batchSyncNotifier.value.isRunning) {
      throw StateError('已有批量同步任务在后台运行中，请勿重复发起');
    }

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) {
      throw StateError('请先登录医考帮账号后再执行同步');
    }

    final qIds = targetQuestionIds ?? await getTouchedQuestionIds();
    if (qIds.isEmpty) return 0;

    // 标记全局状态为运行中
    batchSyncNotifier.value = CommentBatchSyncState(
      category: category,
      current: 0,
      total: qIds.length,
      isRunning: true,
      isCancelled: false,
    );

    final beforeCount = (await getAllSavedComments(category: category)).length;
    try {
      for (var i = 0; i < qIds.length; i++) {
        if (batchSyncNotifier.value.isCancelled ||
            isCancelled?.call() == true) {
          break;
        }
        final currentStep = i + 1;
        batchSyncNotifier.value = batchSyncNotifier.value.copyWith(
          current: currentStep,
          total: qIds.length,
        );
        onProgress?.call(currentStep, qIds.length);

        final q = Question(id: qIds[i], userAnswer: '');
        await syncCommentsForQuestion(
          q,
          syncPraise:
              category == null || category == SavedCommentCategory.praise,
          syncMyComment:
              category == null || category == SavedCommentCategory.myComment,
        );
      }
    } finally {
      final wasCancelled = batchSyncNotifier.value.isCancelled;
      batchSyncNotifier.value = batchSyncNotifier.value.copyWith(
        isRunning: false,
        isCancelled: wasCancelled,
      );
      notifyCommentChanged();
    }

    final afterCount = (await getAllSavedComments(category: category)).length;
    return (afterCount - beforeCount).clamp(0, 999999);
  }
}
