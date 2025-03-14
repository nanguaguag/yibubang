import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/common/ykb_encrypt.dart';

import '../models/question.dart';
import '../models/comment.dart';
import '../common/request.dart';
import '../db/settings.dart';
import 'my_page.dart';

class CommentPage extends StatefulWidget {
  final Question question;

  const CommentPage({required this.question});

  @override
  _CommentPageState createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage>
    with SingleTickerProviderStateMixin {
  Future<CommentData>? _commentDataFuture;

  // 请求接口数据
  Future<CommentData> fetchComments() async {
    final response = await basicReq('/Comment/Main/list', {
      'obj_id': widget.question.id,
      'module_type': '1',
      'comment_type': '2',
      'break_point': getTimestamp(),
      'page': '1',
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

  Future<bool> checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loggedin') ?? false;
  }

  Widget commentList() {
    return FutureBuilder<CommentData>(
      future: _commentDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 请求等待中，显示加载圆圈
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('加载失败: ${snapshot.error}'));
        } else if (snapshot.hasData) {
          final commentData = snapshot.data!;
          return DefaultTabController(
            length: 2, // 2 个 Tab
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                CommentList(comments: commentData.hot),
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
                CommentList(comments: commentData.timeLine),
              ],
            ),
          );
        } else {
          return Container();
        }
      },
    );
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
          _commentDataFuture = fetchComments();
          return commentList();
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

  CommentList({required this.comments});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true, // 根据内容大小自动扩展高度
      physics: NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        return CommentItem(comment: comment);
      },
    );
  }
}

// 单个评论项
class CommentItem extends StatelessWidget {
  final Comment comment;

  CommentItem({required this.comment});

  Widget commentPraise(Comment comment) {
    if (int.parse(comment.praiseNum) >= int.parse(comment.opposeNum)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (comment.replies != "0")
            TextButton(
              child: Text("${comment.replies}条回复"),
              onPressed: () {},
            ),
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
          if (comment.replies != "0")
            TextButton(
              child: Text("${comment.replies}条回复"),
              onPressed: () {},
            ),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
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
            if (comment.parentId != '0')
              Container(
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
                  color: Colors.grey[200],
                ),
                child: Text(
                  comment.reply.isNotEmpty ? comment.reply[0].content : '原评论内容',
                  style: TextStyle(fontStyle: FontStyle.normal),
                ),
              ),
            // 评论内容
            Text(
              comment.content,
              style: TextStyle(fontSize: 16),
            ),
            // 如果有图像，则显示图像
            if (comment.imgs.isNotEmpty) SizedBox(height: 8.0),
            if (comment.imgs.isNotEmpty) Image.network(comment.imgs),
            if (comment.imgs.isNotEmpty) SizedBox(height: 8.0),
            // 点赞数显示
            commentPraise(comment),
          ],
        ),
      ),
    );
  }
}
