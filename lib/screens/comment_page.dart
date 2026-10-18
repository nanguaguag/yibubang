import '../common/adaptive_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/common/ykb_encrypt.dart';
import 'package:flutter/services.dart';

import '../widgets/image_view.dart';
import '../widgets/common/app_network_image.dart';
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
              adaptivePageRoute(
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
class CommentItem extends StatefulWidget {
  final Comment comment;
  final Question question;

  const CommentItem({
    super.key,
    required this.comment,
    required this.question,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  late int _praiseCount;
  late int _opposeCount;
  bool _isPraised = false;
  bool _isPraising = false;

  @override
  void initState() {
    super.initState();
    _praiseCount = int.tryParse(widget.comment.praiseNum) ?? 0;
    _opposeCount = int.tryParse(widget.comment.opposeNum) ?? 0;
  }

  @override
  void didUpdateWidget(covariant CommentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id ||
        oldWidget.comment.praiseNum != widget.comment.praiseNum) {
      _praiseCount = int.tryParse(widget.comment.praiseNum) ?? 0;
      _opposeCount = int.tryParse(widget.comment.opposeNum) ?? 0;
      _isPraised = false;
    }
  }

  Future<void> _handlePraise() async {
    if (_isPraising) return;

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再点赞')),
      );
      return;
    }

    if (_isPraised) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('您已经点赞过该评论了')),
      );
      return;
    }

    setState(() => _isPraising = true);
    try {
      final identityId = widget.question.identityId?.isNotEmpty == true
          ? widget.question.identityId!
          : (prefs.getString('identityId') ?? '');
      final subjectId = widget.question.chapterParentId ?? '';
      final appId = widget.question.appId?.isNotEmpty == true
          ? widget.question.appId!
          : '1';

      final resp = await basicReq(
        '/Comment/Main/praise',
        {
          'id': widget.comment.id,
          'obj_id': widget.question.id,
          'type': '1',
          'comment_type': '2',
          'module_type': '1',
          'subject_id': subjectId,
          'identity_id': identityId,
          'app_id': appId,
          'is_vip': '0',
          'is_svip': '0',
        },
      );

      if (!mounted) return;
      if (resp['code'] == '200' || resp['code'] == 200) {
        setState(() {
          _isPraised = true;
          _praiseCount += 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message']?.toString() ?? '点赞成功！')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message']?.toString() ?? '点赞失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('点赞出错: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPraising = false);
      }
    }
  }

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
            adaptivePageRoute(
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
    final bool hasPraised = _isPraised || _praiseCount > _opposeCount;
    final Color praiseColor = hasPraised ? Colors.green : Colors.grey;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _gotoReplyBtn(comment, question, context),
        InkWell(
          onTap: _isPraising ? null : _handlePraise,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasPraised ? Icons.thumb_up : Icons.thumb_up_outlined,
                  size: 16,
                  color: praiseColor,
                ),
                const SizedBox(width: 4.0),
                Text(
                  '$_praiseCount',
                  style: TextStyle(
                    color: praiseColor,
                    fontWeight: hasPraised ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _opposeCount > _praiseCount
                    ? Icons.thumb_down
                    : Icons.thumb_down_outlined,
                size: 16,
                color: _opposeCount > _praiseCount ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 4.0),
              Text(
                '$_opposeCount',
                style: TextStyle(
                  color: _opposeCount > _praiseCount
                      ? Colors.redAccent
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      adaptivePageRoute(
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
              maxRadius: 10,
              backgroundImage: comment.avatar.trim().isNotEmpty
                  ? AppNetworkImage.provider(comment.avatar)
                  : null,
              child: comment.avatar.trim().isEmpty
                  ? const Icon(Icons.person, size: 12)
                  : null,
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
              child: AppNetworkImage(
                imageUrl: comment.imgWatermark,
                height: 200,
              ),
            ),
          ),
        // 点赞数显示
        _commentPraise(comment, widget.question, context),
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
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
      margin: const EdgeInsets.all(8.0),
      child: InkWell(
        onTap: () => _showOptions(context, widget.comment),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _commentContent(widget.comment, context),
        ),
      ),
    );
  }
}
