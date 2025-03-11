// 数据模型
class CommentData {
  final List<Comment> hot;
  final List<Comment> timeLine;

  CommentData({required this.hot, required this.timeLine});

  factory CommentData.fromJson(Map<String, dynamic> json) {
    var hotList = json['hot'] as List? ?? [];
    var timeLineList = json['time_line'] as List? ?? [];
    return CommentData(
      hot: hotList.map((e) => Comment.fromJson(e)).toList(),
      timeLine: timeLineList.map((e) => Comment.fromJson(e)).toList(),
    );
  }
}

class Comment {
  final String id;
  final String content;
  final String praiseNum;
  final String floorNum;
  final String school;
  final String ctime;
  final String avatar;
  final String nickname;
  final String imgs;
  final String parentId;
  final List<Comment> reply;

  Comment({
    required this.id,
    required this.content,
    required this.praiseNum,
    required this.floorNum,
    required this.school,
    required this.ctime,
    required this.avatar,
    required this.nickname,
    required this.imgs,
    required this.parentId,
    required this.reply,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    var replyList = <Comment>[];
    if (json['reply'] != null && json['reply'] is List) {
      replyList = (json['reply'] as List)
          .map(
            (e) => Comment.fromJson(e),
          )
          .toList();
    }
    return Comment(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      praiseNum: json['praise_num'] ?? '0',
      floorNum: json['floor_num'] ?? '0',
      school: json['school'] ?? '0',
      ctime: json['ctime'] ?? '0',
      avatar: json['avatar'] ?? '',
      nickname: json['nickname'] ?? '',
      imgs: json['imgs'] ?? '',
      parentId: json['parent_id'] ?? '0',
      reply: replyList,
    );
  }
}
