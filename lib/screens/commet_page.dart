import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/common/ykb_encrypt.dart';
import 'package:flutter/services.dart';

import '../widgets/image_view.dart';
import '../models/question.dart';
import '../models/comment.dart';
import '../common/request.dart';
import '../db/settings.dart';

import 'my_page.dart';
import 'comment_reply_page.dart';

Future<bool> checkLoginStatus() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getBool('loggedin') ?? false;
}

Widget generateComment(CommentData commentData, Question question) {
  Widget hotComments = Column(
    children: [
      SizedBox(height: 20),
      Row(
        children: [
          Container(
            width: 4, // 控制竖条的宽度
            height: 20, // 控制竖条的高度
            color: Colors.deepOrange, // 竖条颜色
          ),
          SizedBox(width: 8.0),
          Text(
            '最热评论 (${commentData.hot.length})',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      Divider(),
      CommentList(
        comments: commentData.hot,
        question: question,
      ),
    ],
  );

  Widget timelineComments = Column(
    children: [
      SizedBox(height: 20),
      Row(
        children: [
          Container(
            width: 4, // 控制竖条的宽度
            height: 20, // 控制竖条的高度
            color: Colors.deepOrange, // 竖条颜色
          ),
          SizedBox(width: 8.0),
          Text(
            '最新评论 (${commentData.timeLine.length})',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      Divider(),
      CommentList(
        comments: commentData.timeLine,
        question: question,
      ),
    ],
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (commentData.hot.isNotEmpty) hotComments,
      if (commentData.timeLine.isNotEmpty) timelineComments,
    ],
  );
}

Widget commentList(Future<CommentData>? commentDataFuture, Question question) {
  return FutureBuilder<CommentData>(
    future: commentDataFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        // 请求等待中，显示加载圆圈
        return Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        return Center(child: Text('加载失败: ${snapshot.error}'));
      } else if (snapshot.hasData) {
        final commentData = snapshot.data!;
        return generateComment(commentData, question);
      } else {
        return Container();
      }
    },
  );
}

class CommentPage extends StatefulWidget {
  final Question question;

  const CommentPage({required this.question});

  @override
  _CommentPageState createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage>
    with SingleTickerProviderStateMixin {
  // 请求接口数据
  Future<CommentData> _fetchComments({int page = 1}) async {
    final response = await basicReq('/Comment/Main/list', {
      'obj_id': widget.question.id,
      'module_type': '1',
      'comment_type': '2',
      'break_point': getTimestamp(),
      'page': page.toString(),
      'app_id': widget.question.appId,
    });
    if (response['code'] == 309) {
      // 登录过期，重新登录
      clearUserInfo();
      return CommentData.fromJson({
        'hot': [],
        'time_line': [],
      });
    }
    return CommentData.fromJson(response['data']);
  }

  @override
  void initState() {
    super.initState();
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: checkLoginStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return _buildErrorMessage(snapshot.error);
        } else if (snapshot.data!) {
          return commentList(_fetchComments(), widget.question);
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 5),
              Text("您还没登录，无法查看评论哦～"),
              SizedBox(height: 5),
              TextButton(
                child: Text("点击登录"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuthCheckPage(),
                    ),
                  );
                },
              ),
              SizedBox(height: 5),
            ],
          );
        }
      },
    );
  }
}

// 评论列表组件
class CommentList extends StatelessWidget {
  final List<Comment> comments;
  final Question question;

  CommentList({
    required this.comments,
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true, // 根据内容大小自动扩展高度
      physics: NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        return CommentItem(
          comment: comment,
          question: question,
        );
      },
    );
  }
}

// 单个评论项
class CommentItem extends StatelessWidget {
  final Comment comment;
  final Question question;

  CommentItem({
    required this.comment,
    required this.question,
  });

  Widget _gotoReplyBtn(
    Comment comment,
    Question question,
    BuildContext context,
  ) {
    if (comment.replies != "0") {
      return TextButton(
        child: Text("${comment.replies}条回复"),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CommentReplyPage(
                comment: comment,
                question: question,
              ),
            ),
          );
        },
      );
    }
    return Container();
  }

  Widget _commentPraise(
    Comment comment,
    Question question,
    BuildContext context,
  ) {
    if (int.parse(comment.praiseNum) == int.parse(comment.opposeNum)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _gotoReplyBtn(comment, question, context),
          Icon(Icons.thumb_up_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4.0),
          Text(
            comment.praiseNum,
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(width: 8.0),
          Icon(Icons.thumb_down_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4.0),
          Text(
            comment.opposeNum,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    } else if (int.parse(comment.praiseNum) > int.parse(comment.opposeNum)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _gotoReplyBtn(comment, question, context),
          Icon(Icons.thumb_up, size: 16, color: Colors.green),
          SizedBox(width: 4.0),
          Text(
            comment.praiseNum,
            style: TextStyle(color: Colors.green),
          ),
          SizedBox(width: 8.0),
          Icon(Icons.thumb_down_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4.0),
          Text(
            comment.opposeNum,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _gotoReplyBtn(comment, question, context),
          Icon(Icons.thumb_up_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4.0),
          Text(
            comment.praiseNum,
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(width: 8.0),
          Icon(Icons.thumb_down, size: 16, color: Colors.red),
          SizedBox(width: 4.0),
          Text(
            comment.opposeNum,
            style: TextStyle(color: Colors.redAccent),
          ),
        ],
      );
    }
  }

  void _showFullScreenImage(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageView(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _getReplyComment(
    Comment comment,
    BuildContext context, {
    int depth = 0,
  }) {
    int replyLength = comment.reply.length;
    if (replyLength == 0 || comment.parentId == '0') {
      return Container();
    } else if (depth == replyLength - 1) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(8.0),
        margin: EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Colors.grey,
              width: 4.0,
            ),
          ),
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        child: _commentContent(comment.reply[0], context),
      );
    } else if (depth < replyLength - 1) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(8.0),
        margin: EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Colors.grey,
              width: 4.0,
            ),
          ),
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        child: Column(
          children: [
            _getReplyComment(
              comment,
              context,
              depth: depth + 1,
            ),
            _commentContent(comment.reply[replyLength - 1 - depth], context),
          ],
        ),
      );
    } else {
      return Container();
    }
  }

  Widget _commentContent(Comment comment, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户头像和用户名
        Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(comment.avatar),
              maxRadius: 10,
            ),
            SizedBox(width: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.nickname,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "${comment.school} ${comment.ctime}",
                  style: TextStyle(
                    fontWeight: FontWeight.w300,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 8.0),
        // 如果是回复，则先显示引用的原评论内容
        _getReplyComment(comment, context),
        // 评论内容
        Text(
          comment.content,
          style: TextStyle(fontSize: 16),
        ),
        // 如果有图像，则显示图像
        if (comment.imgWatermark.isNotEmpty)
          InkWell(
            onTap: () {
              _showFullScreenImage(
                context,
                [comment.imgWatermark],
                0,
              );
            },
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Image.network(
                comment.imgWatermark,
                height: 200,
              ),
            ),
          ),
        // 点赞数显示
        _commentPraise(comment, question, context),
      ],
    );
  }

  void _showOptions(BuildContext context, Comment comment) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制评论'),
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: comment.content),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('复制成功！')),
                );
                Navigator.pop(ctx);
              },
            ),
            SizedBox(height: 20),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: EdgeInsets.all(8.0),
      child: InkWell(
        onTap: () => _showOptions(context, comment),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: _commentContent(comment, context),
        ),
      ),
    );
  }
}
