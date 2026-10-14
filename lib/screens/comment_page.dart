import 'package:flutter/cupertino.dart';
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

class CommentPage extends StatefulWidget {
  final Question question;
  // 外层滚动的控制器，用于实现「滚动到底自动加载下一页」
  final ScrollController? scrollController;

  const CommentPage({
    super.key,
    required this.question,
    this.scrollController,
  });

  @override
  _CommentPageState createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage>
    with AutomaticKeepAliveClientMixin {
  int _tab = 1; // 0=最新, 1=最热
  bool? _loggedIn; // null=检查登录状态中
  final List<Comment> _latest = [];
  final List<Comment> _hot = [];
  int _page = 0; // 已加载页数
  bool _latestHasMore = true;
  bool _hotHasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    _checkLogin();
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  // 保持评论区状态，避免滚出屏幕被 ListView 回收后评论重新加载
  @override
  bool get wantKeepAlive => true;

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

  List<Comment> _currentList() => _tab == 0 ? _latest : _hot;
  bool _currentHasMore() => _tab == 0 ? _latestHasMore : _hotHasMore;

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    if (controller.position.pixels >=
        controller.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_currentHasMore()) return;
    setState(() => _loading = true);
    try {
      final int nextPage = _page + 1;
      final CommentData data = await _fetchComments(page: nextPage);
      if (!mounted) return;
      setState(() {
        _latest.addAll(data.timeLine);
        _hot.addAll(data.hot);
        _page = nextPage;
        if (data.timeLine.isEmpty) _latestHasMore = false;
        if (data.hot.isEmpty) _hotHasMore = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _switchTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (_currentList().isEmpty && _currentHasMore()) {
      _loadMore();
    }
  }

  Widget _buildTabBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildTabBtn('最新', 0),
        const SizedBox(width: 8),
        _buildTabBtn('最热', 1),
      ],
    );
  }

  Widget _buildTabBtn(String label, int tab) {
    final bool selected = _tab == tab;
    final Color primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => _switchTab(tab),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Colors.grey,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Theme.of(context).colorScheme.onPrimary : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildGuest() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 5),
        const Text("您还没登录，无法查看评论哦～"),
        const SizedBox(height: 5),
        TextButton(
          child: const Text("点击登录"),
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (context) => AuthCheckPage(),
              ),
            );
          },
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求调用
    if (_loggedIn == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loggedIn == false) {
      return _buildGuest();
    }
    final List<Comment> comments = _currentList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabBar(),
        if (comments.isEmpty && !_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('暂无评论')),
          ),
        ...comments.map(
          (c) => CommentItem(comment: c, question: widget.question),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_currentHasMore() && comments.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('没有更多评论了')),
          ),
      ],
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
            CupertinoPageRoute(
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
      CupertinoPageRoute(
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
