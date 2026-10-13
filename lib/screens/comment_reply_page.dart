import 'package:flutter/material.dart';
import 'package:yibubang/common/ykb_encrypt.dart';
import '../models/question.dart';
import '../models/comment.dart';
import '../common/request.dart';
import '../db/settings.dart';

import 'comment_page.dart';

class CommentReplyPage extends StatefulWidget {
  final Comment comment;
  final Question question;

  const CommentReplyPage({
    required this.comment,
    required this.question,
  });

  @override
  _CommentReplyPageState createState() => _CommentReplyPageState();
}

class _CommentReplyPageState extends State<CommentReplyPage> {
  final ScrollController _controller = ScrollController();
  bool? _loggedIn;
  final List<Comment> _replies = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _checkLogin();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkLogin() async {
    final loggedIn = await checkLoginStatus();
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
    if (loggedIn) {
      await _loadMore();
    }
  }

  // 请求接口数据，page 为分页页码
  Future<CommentData> _fetchComments({required int page}) async {
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

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.pixels >=
        _controller.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final int nextPage = _page + 1;
      final CommentData data = await _fetchComments(page: nextPage);
      if (!mounted) return;
      setState(() {
        _replies.addAll(data.timeLine);
        _page = nextPage;
        if (data.timeLine.isEmpty) _hasMore = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '评论回复',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loggedIn == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loggedIn == false) {
      return const Center(child: Text('请先登录'));
    }
    return ListView(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        CommentItem(
          comment: widget.comment,
          question: widget.question,
        ),
        if (_replies.isEmpty && !_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('暂无回复')),
          ),
        ..._replies.map(
          (c) => CommentItem(comment: c, question: widget.question),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_hasMore && _replies.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('没有更多回复了')),
          ),
      ],
    );
  }
}