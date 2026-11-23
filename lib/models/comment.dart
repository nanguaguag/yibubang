import 'dart:convert';

// 数据模型
class CommentData {
  final List<Comment> hot;
  final List<Comment> timeLine;

  CommentData({required this.hot, required this.timeLine});

  factory CommentData.fromJson(Map<String, dynamic> json) {
    final hotList = json['hot'] is List ? json['hot'] as List : const [];
    final timeLineList =
        json['time_line'] is List ? json['time_line'] as List : const [];
    return CommentData(
      hot: hotList
          .whereType<Map>()
          .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      timeLine: timeLineList
          .whereType<Map>()
          .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class Comment {
  final String id;
  final String objId;
  final String userId;
  final String content;
  final String praiseNum;
  final String opposeNum;
  final String floorNum;
  final String replies;
  final String school;
  final String ctime;
  final int ctimeTimestamp;
  final String avatar;
  final String nickname;
  final String imgs;
  final String cimgs;
  final String imgWatermark;
  final String parentId;
  final String isPraise;
  final String isAuthor;
  final List<Comment> reply;

  Comment({
    required this.id,
    this.objId = '',
    this.userId = '',
    required this.content,
    required this.praiseNum,
    required this.opposeNum,
    required this.floorNum,
    required this.replies,
    required this.school,
    required this.ctime,
    this.ctimeTimestamp = 0,
    required this.avatar,
    required this.nickname,
    required this.imgs,
    required this.cimgs,
    required this.imgWatermark,
    required this.parentId,
    this.isPraise = '0',
    this.isAuthor = '0',
    required this.reply,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    var replyList = <Comment>[];
    if (json['reply'] is List) {
      replyList = (json['reply'] as List)
          .whereType<Map>()
          .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawCimgs = json['cimgs'] ?? json['c_imgs'];
    final String cimgsStr = rawCimgs == null
        ? ''
        : (rawCimgs is String ? rawCimgs : jsonEncode(rawCimgs));
    final rawReplies = json['replies'] ?? json['reply_num'] ?? '0';
    return Comment(
      id: json['id']?.toString() ?? '',
      objId: json['obj_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      praiseNum: json['praise_num']?.toString() ?? '0',
      opposeNum: json['oppose_num']?.toString() ?? '0',
      floorNum: json['floor_num']?.toString() ?? '1',
      replies: rawReplies.toString(),
      school: json['school']?.toString() ?? '',
      ctime: json['ctime']?.toString() ?? '',
      ctimeTimestamp:
          int.tryParse(json['ctime_timestamp']?.toString() ?? '0') ?? 0,
      avatar: json['avatar']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      imgs: json['imgs']?.toString() ?? '',
      cimgs: cimgsStr,
      imgWatermark: json['img_watermark']?.toString() ?? '',
      parentId: json['parent_id']?.toString() ?? '0',
      isPraise: json['is_praise']?.toString() ?? '0',
      isAuthor: json['is_author']?.toString() ?? '0',
      reply: replyList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'obj_id': objId,
        'user_id': userId,
        'content': content,
        'praise_num': praiseNum,
        'oppose_num': opposeNum,
        'floor_num': floorNum,
        'replies': replies,
        'school': school,
        'ctime': ctime,
        'ctime_timestamp': ctimeTimestamp.toString(),
        'avatar': avatar,
        'nickname': nickname,
        'imgs': imgs,
        'cimgs': cimgs,
        'img_watermark': imgWatermark,
        'parent_id': parentId,
        'is_praise': isPraise,
        'is_author': isAuthor,
        'reply': reply.map((e) => e.toJson()).toList(),
      };
}

/// 归纳保存在本地并支持云同步的评论分类
enum SavedCommentCategory {
  /// 我点赞的评论 (func=mypraise)
  praise('praise', '我的点赞'),

  /// 我发表的评论 (func=mycomment)
  myComment('my_comment', '我的评论');

  final String value;
  final String label;
  const SavedCommentCategory(this.value, this.label);

  static SavedCommentCategory fromValue(String? val) {
    if (val == 'my_comment') return SavedCommentCategory.myComment;
    return SavedCommentCategory.praise;
  }
}

/// 本地持久化与云同步的评论记录（我的点赞 / 我的评论）
class SavedComment {
  final String id; // '${category}_${commentId}'
  final String commentId;
  final String questionId;
  final String category; // 'praise' | 'my_comment'
  final String userId;
  final String nickname;
  final String avatar;
  final String school;
  final String content;
  final int praiseNum;
  final int opposeNum;
  final int replies;
  final String floorNum;
  final String ctime;
  final String imgWatermark;
  final List<Comment> replyList;
  final int timestamp;
  final int updatedAt;
  final int syncStatus; // 0: 已同步, 1: 待同步

  const SavedComment({
    required this.id,
    required this.commentId,
    required this.questionId,
    required this.category,
    this.userId = '',
    this.nickname = '',
    this.avatar = '',
    this.school = '',
    required this.content,
    this.praiseNum = 0,
    this.opposeNum = 0,
    this.replies = 0,
    this.floorNum = '1',
    this.ctime = '',
    this.imgWatermark = '',
    this.replyList = const [],
    required this.timestamp,
    required this.updatedAt,
    this.syncStatus = 0,
  });

  static String buildId(String category, String commentId) =>
      '${category}_$commentId';

  factory SavedComment.fromApiComment(
    Comment comment, {
    required String questionId,
    required String category,
    int? fallbackTimestamp,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ts = comment.ctimeTimestamp > 0
        ? comment.ctimeTimestamp * 1000
        : (fallbackTimestamp ?? now);
    final effectiveQid =
        questionId.isNotEmpty ? questionId : comment.objId;
    return SavedComment(
      id: buildId(category, comment.id),
      commentId: comment.id,
      questionId: effectiveQid,
      category: category,
      userId: comment.userId,
      nickname: comment.nickname,
      avatar: comment.avatar,
      school: comment.school,
      content: comment.content,
      praiseNum: int.tryParse(comment.praiseNum) ?? 0,
      opposeNum: int.tryParse(comment.opposeNum) ?? 0,
      replies: int.tryParse(comment.replies) ?? 0,
      floorNum: comment.floorNum,
      ctime: comment.ctime,
      imgWatermark: comment.imgWatermark,
      replyList: comment.reply,
      timestamp: ts,
      updatedAt: ts,
      syncStatus: 0,
    );
  }

  Comment toComment() {
    return Comment(
      id: commentId,
      objId: questionId,
      userId: userId,
      content: content,
      praiseNum: praiseNum.toString(),
      opposeNum: opposeNum.toString(),
      floorNum: floorNum,
      replies: replies.toString(),
      school: school,
      ctime: ctime,
      ctimeTimestamp: timestamp ~/ 1000,
      avatar: avatar,
      nickname: nickname,
      imgs: '',
      cimgs: '',
      imgWatermark: imgWatermark,
      parentId: replyList.isNotEmpty ? replyList.first.id : '0',
      isPraise: category == SavedCommentCategory.praise.value ? '1' : '0',
      isAuthor: category == SavedCommentCategory.myComment.value ? '1' : '0',
      reply: replyList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'comment_id': commentId,
      'question_id': questionId,
      'category': category,
      'user_id': userId,
      'nickname': nickname,
      'avatar': avatar,
      'school': school,
      'content': content,
      'praise_num': praiseNum,
      'oppose_num': opposeNum,
      'replies': replies,
      'floor_num': floorNum,
      'ctime': ctime,
      'img_watermark': imgWatermark,
      'reply_json': jsonEncode(replyList.map((e) => e.toJson()).toList()),
      'timestamp': timestamp,
      'updated_at': updatedAt,
      'sync_status': syncStatus,
    };
  }

  factory SavedComment.fromMap(Map<String, dynamic> map) {
    List<Comment> parsedReplies = [];
    final rawReply = map['reply_json']?.toString() ?? '';
    if (rawReply.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawReply);
        if (decoded is List) {
          parsedReplies = decoded
              .whereType<Map>()
              .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }
    final ts = (map['timestamp'] as num?)?.toInt() ?? 0;
    final up = (map['updated_at'] as num?)?.toInt() ?? ts;
    final cat = map['category']?.toString() ?? SavedCommentCategory.praise.value;
    final cid = map['comment_id']?.toString() ?? '';
    return SavedComment(
      id: map['id']?.toString() ?? buildId(cat, cid),
      commentId: cid,
      questionId: map['question_id']?.toString() ?? '',
      category: cat,
      userId: map['user_id']?.toString() ?? '',
      nickname: map['nickname']?.toString() ?? '',
      avatar: map['avatar']?.toString() ?? '',
      school: map['school']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      praiseNum: (map['praise_num'] as num?)?.toInt() ??
          (int.tryParse(map['praise_num']?.toString() ?? '0') ?? 0),
      opposeNum: (map['oppose_num'] as num?)?.toInt() ??
          (int.tryParse(map['oppose_num']?.toString() ?? '0') ?? 0),
      replies: (map['replies'] as num?)?.toInt() ??
          (int.tryParse(map['replies']?.toString() ?? '0') ?? 0),
      floorNum: map['floor_num']?.toString() ?? '1',
      ctime: map['ctime']?.toString() ?? '',
      imgWatermark: map['img_watermark']?.toString() ?? '',
      replyList: parsedReplies,
      timestamp: ts,
      updatedAt: up,
      syncStatus: (map['sync_status'] as num?)?.toInt() ?? 0,
    );
  }
}
