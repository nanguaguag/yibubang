import 'package:flutter/material.dart';
import 'package:yibubang/common/ykb_encrypt.dart';
import '../models/question.dart';
import '../models/comment.dart';
import '../common/request.dart';
import '../db/settings.dart';

import 'commet_page.dart';

class CommentReplyPage extends StatefulWidget {
  final Comment comment;
  final Question question;

  const CommentReplyPage({
    required this.comment,
    required this.question,
  });

  @override
  _CommentPageState createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentReplyPage>
    with SingleTickerProviderStateMixin {
  // 请求接口数据
  Future<CommentData> _fetchComments({int page = 1}) async {
    final response = await basicReq('/Comment/Main/getCommentReply', {
      'obj_id': widget.question.id,
      'module_type': '1',
      'comment_type': '2',
      'break_point': getTimestamp(),
      'page': page.toString(),
      'id': widget.comment.id,
      'app_id': widget.question.appId,
    });
    if (response['code'] == 309) {
      // 登录过期，重新登录
      clearUserInfo();
      return CommentData.fromJson({
        'time_line': [],
      });
    }
    return CommentData.fromJson(response['data']);
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '评论回复',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<bool>(
        future: checkLoginStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return _buildErrorMessage(snapshot.error);
          } else if (snapshot.data!) {
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: 8),
              children: [
                CommentItem(
                  comment: widget.comment,
                  question: widget.question,
                ),
                commentList(_fetchComments(), widget.question),
              ],
            );
          } else {
            return Container();
          }
        },
      ),
    );
  }
}
