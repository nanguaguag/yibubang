import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/ykb_encrypt.dart';

import '../common/adaptive_route.dart';
import '../common/request.dart';
import '../db/database_helper.dart';
import '../models/comment.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../services/comment_service.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';
import '../widgets/common/app_network_image.dart';
import '../widgets/flashcard_edit_dialog.dart';
import '../widgets/image_view.dart';
import 'comment_reply_page.dart';
import 'my_page.dart';
import 'question_comments_page.dart';

Future<bool> checkLoginStatus() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getBool('loggedin') ?? false;
}

/// 唤起发表评论底部弹窗（提交到医考帮并自动归纳保存到本地「我的评论」）
Future<bool> showPublishCommentSheet(
  BuildContext context, {
  required Question question,
}) async {
  final loggedIn = await checkLoginStatus();
  if (!context.mounted) return false;
  if (!loggedIn) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先登录医考帮账号后再发表评论')));
    return false;
  }

  final controller = TextEditingController();
  bool submitting = false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '发表题目评论',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  minLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '分享你的解题技巧、记忆口诀或疑问...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      icon: submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(submitting ? '发送中...' : '发布评论'),
                      onPressed: submitting
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('请输入评论内容')),
                                );
                                return;
                              }
                              setSheetState(() => submitting = true);
                              try {
                                final resp = await CommentService.instance
                                    .publishComment(
                                      content: text,
                                      question: question,
                                    );
                                if (!ctx.mounted) return;
                                if (resp['code']?.toString() == '200') {
                                  Navigator.of(ctx).pop(true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('评论发布成功，已归纳至「我的评论」'),
                                    ),
                                  );
                                } else {
                                  setSheetState(() => submitting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        resp['message']?.toString() ?? '评论发布失败',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setSheetState(() => submitting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('发布异常: $e')),
                                  );
                                }
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return result == true;
}

class CommentPage extends StatefulWidget {
  final Question question;
  // 外层滚动的控制器，用于实现「滚动到底自动加载下一页」
  final ScrollController? scrollController;

  const CommentPage({super.key, required this.question, this.scrollController});

  @override
  State<CommentPage> createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage>
    with AutomaticKeepAliveClientMixin {
  int _tab = 1; // 1=最热, 0=最新, 2=我的点赞, 3=我的评论
  bool? _loggedIn; // null=检查登录状态中
  final List<Comment> _latest = [];
  final List<Comment> _hot = [];
  List<SavedComment> _myPraised = [];
  List<SavedComment> _myComments = [];
  Set<String> _praisedIds = {};
  int _page = 0; // 已加载页数
  bool _latestHasMore = true;
  bool _hotHasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    CommentService.instance.commentSyncEventNotifier.addListener(
      _refreshLocalSaved,
    );
    _initData();
  }

  @override
  void didUpdateWidget(covariant CommentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
    if (oldWidget.question.id != widget.question.id) {
      _latest.clear();
      _hot.clear();
      _myPraised = [];
      _myComments = [];
      _praisedIds = {};
      _page = 0;
      _latestHasMore = true;
      _hotHasMore = true;
      _loading = false;
      _initData();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    CommentService.instance.commentSyncEventNotifier.removeListener(
      _refreshLocalSaved,
    );
    super.dispose();
  }

  // 保持评论区状态，避免滚出屏幕被 ListView 回收后评论重新加载
  @override
  bool get wantKeepAlive => true;

  Future<void> _refreshLocalSaved() async {
    try {
      final praised = await CommentService.instance.getLocalComments(
        widget.question.id,
        category: SavedCommentCategory.praise,
      );
      final mine = await CommentService.instance.getLocalComments(
        widget.question.id,
        category: SavedCommentCategory.myComment,
      );
      if (mounted) {
        setState(() {
          _myPraised = praised;
          _myComments = mine;
          _praisedIds = praised.map((e) => e.commentId).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _initData() async {
    await _refreshLocalSaved();
    final loggedIn = await checkLoginStatus();
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
    if (loggedIn) {
      // 与笔记相同：打开题目时后台自动从医考帮拉取本题「我的点赞」与「我的评论」并落库
      unawaited(
        CommentService.instance.syncCommentsForQuestion(widget.question),
      );
      await _loadMore();
    }
  }

  // 请求接口数据，page 为分页页码
  Future<CommentData> _fetchComments({required int page}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? '';
    final meta = await YkbSyncService.instance.resolveQuestionMeta(
      widget.question.id,
      question: widget.question,
    );
    final outerIdentityId = meta.subjectId.isNotEmpty
        ? meta.subjectId
        : (prefs.getString('identityId') ?? meta.identityId);
    final response = await basicReq('/Comment/Main/list', {
      'subject_id': meta.subjectId,
      'identity_id': outerIdentityId,
      'obj_id': widget.question.id,
      'module_type': '1',
      'comment_type': '2',
      'break_point': getTimestamp(),
      'page': page.toString(),
      'app_id': meta.appId,
      'is_vip': '0',
      'is_svip': '0',
    });
    final dynamic code = response['code'];
    final bool isTokenExpired = code == 309 || code == '309';
    if (isTokenExpired) {
      return CommentData.fromJson({'hot': [], 'time_line': []});
    }
    final dynamic rawData = response['data'];
    CommentData data;
    if (rawData is Map<String, dynamic>) {
      data = CommentData.fromJson(rawData);
    } else if (rawData is Map) {
      data = CommentData.fromJson(Map<String, dynamic>.from(rawData));
    } else {
      data = CommentData.fromJson({'hot': [], 'time_line': []});
    }
    unawaited(
      CommentService.instance.harvestFromCommentList(
        [...data.hot, ...data.timeLine],
        questionId: widget.question.id,
        question: widget.question,
        currentUserId: currentUserId,
      ),
    );
    return data;
  }

  List<Comment> _currentList() {
    switch (_tab) {
      case 0:
        return _latest;
      case 2:
        return _myPraised.map((e) => e.toComment()).toList();
      case 3:
        return _myComments.map((e) => e.toComment()).toList();
      case 1:
      default:
        return _hot;
    }
  }

  bool _currentHasMore() {
    if (_tab == 2 || _tab == 3) return false;
    return _tab == 0 ? _latestHasMore : _hotHasMore;
  }

  void _onScroll() {
    if (_tab == 2 || _tab == 3) return;
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
    if ((tab == 0 || tab == 1) && _currentList().isEmpty && _currentHasMore()) {
      _loadMore();
    }
  }

  Widget _buildHeader(BuildContext context) {
    const Color orangeAccent = Color(0xFFB39D6B);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.comment_outlined, color: orangeAccent, size: 22),
            const SizedBox(width: 6),
            const Text(
              '讨论评论',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: orangeAccent,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('写评论'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () async {
                final ok = await showPublishCommentSheet(
                  context,
                  question: widget.question,
                );
                if (ok && mounted) {
                  await _refreshLocalSaved();
                }
              },
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.sort_rounded, size: 17),
              label: const Text('四维排序'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () =>
                  QuestionCommentsPage.open(context, question: widget.question),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabBtn('最热', 1),
              const SizedBox(width: 8),
              _buildTabBtn('最新', 0),
              const SizedBox(width: 8),
              _buildTabBtn(
                _myPraised.isEmpty ? '我的点赞' : '我的点赞 (${_myPraised.length})',
                2,
              ),
              const SizedBox(width: 8),
              _buildTabBtn(
                _myComments.isEmpty ? '我的评论' : '我的评论 (${_myComments.length})',
                3,
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Colors.grey.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Colors.grey[700],
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
        const Text("您还没登录，无法在线加载医考帮评论哦～"),
        const SizedBox(height: 5),
        TextButton(
          child: const Text("点击登录"),
          onPressed: () {
            Navigator.push(
              context,
              adaptivePageRoute(builder: (context) => const AuthCheckPage()),
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
    final List<Comment> comments = _currentList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        if (_loggedIn == false && (_tab == 0 || _tab == 1))
          _buildGuest()
        else ...[
          if (comments.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _tab == 2
                      ? '本题暂无您点赞的评论'
                      : (_tab == 3 ? '本题暂无您发表的评论' : '暂无评论'),
                ),
              ),
            ),
          ...comments.map(
            (c) => CommentItem(
              comment: c,
              question: widget.question,
              initiallyPraised: c.isPraise == '1' || _praisedIds.contains(c.id),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_currentHasMore() && comments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('进入评论区看板'),
                  onPressed: () => QuestionCommentsPage.open(
                    context,
                    question: widget.question,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// 单个评论项
class CommentItem extends StatefulWidget {
  final Comment comment;
  final Question question;
  final bool initiallyPraised;

  const CommentItem({
    super.key,
    required this.comment,
    required this.question,
    this.initiallyPraised = false,
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
    _isPraised = widget.initiallyPraised || widget.comment.isPraise == '1';
  }

  @override
  void didUpdateWidget(covariant CommentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id ||
        oldWidget.comment.praiseNum != widget.comment.praiseNum ||
        oldWidget.initiallyPraised != widget.initiallyPraised) {
      _praiseCount = int.tryParse(widget.comment.praiseNum) ?? 0;
      _opposeCount = int.tryParse(widget.comment.opposeNum) ?? 0;
      _isPraised = widget.initiallyPraised || widget.comment.isPraise == '1';
    }
  }

  Future<void> _handlePraise() async {
    if (_isPraising) return;

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再点赞')));
      return;
    }

    if (_isPraised) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('您已经点赞过该评论了')));
      return;
    }

    setState(() => _isPraising = true);
    try {
      final resp = await CommentService.instance.praiseComment(
        comment: widget.comment,
        question: widget.question,
      );

      if (!mounted) return;
      if (resp['code'] == '200' || resp['code'] == 200) {
        setState(() {
          _isPraised = true;
          _praiseCount += 1;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message']?.toString() ?? '点赞失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('点赞出错: $e')));
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
              builder: (context) =>
                  CommentReplyPage(comment: comment, question: question),
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
    final bool hasPraised = _isPraised;
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
                    fontWeight: hasPraised
                        ? FontWeight.bold
                        : FontWeight.normal,
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
        padding: const EdgeInsets.all(8.0),
        margin: const EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          border: const Border(
            left: BorderSide(color: Colors.grey, width: 4.0),
          ),
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        child: _commentContent(comment.reply[0], context),
      );
    } else if (depth < replyLength - 1) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8.0),
        margin: const EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          border: const Border(
            left: BorderSide(color: Colors.grey, width: 4.0),
          ),
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        child: Column(
          children: [
            _getReplyComment(comment, context, depth: depth + 1),
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
            const SizedBox(width: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.nickname,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "${comment.school} ${comment.ctime}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w300,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        // 如果是回复，则先显示引用的原评论内容
        _getReplyComment(comment, context),
        // 评论内容
        Text(comment.content, style: const TextStyle(fontSize: 16)),
        // 如果有图像，则显示图像
        if (comment.imgWatermark.isNotEmpty)
          InkWell(
            onTap: () {
              _showFullScreenImage(context, [comment.imgWatermark], 0);
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
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
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制评论'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: comment.content));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('复制成功！')));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_alt_outlined),
              title: const Text('归纳保存到「我的点赞」'),
              onTap: () async {
                Navigator.pop(ctx);
                final saved = SavedComment.fromApiComment(
                  comment,
                  questionId: widget.question.id,
                  category: SavedCommentCategory.praise.value,
                );
                await CommentService.instance.saveComment(
                  saved,
                  question: widget.question,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已归纳保存到「我的点赞」！')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('保存为笔记'),
              onTap: () async {
                Navigator.pop(ctx);
                final now = DateTime.now().millisecondsSinceEpoch;
                final List<NoteImage> images = [];
                if (comment.imgWatermark.isNotEmpty) {
                  images.add(
                    NoteImage(
                      bImg: comment.imgWatermark,
                      sImg: comment.imgWatermark,
                    ),
                  );
                }
                final newNote = QuestionNote(
                  id: 'local_${now}_${widget.question.id}',
                  questionId: widget.question.id,
                  content: comment.content,
                  images: images,
                  timestamp: now,
                  updatedAt: now,
                );
                await NoteService.instance.saveNote(
                  newNote,
                  question: widget.question,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已成功将评论保存为笔记！')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('制作成闪卡'),
              onTap: () async {
                Navigator.pop(ctx);
                Map<String, String> resolved = const {};
                try {
                  resolved = await DatabaseHelper.resolveSubjectAndChapter(
                    subjectId: widget.question.chapterParentId,
                    chapterId: widget.question.chapterId,
                  );
                } catch (_) {}
                final subject = resolved['subject'] ?? '';
                final chapter = resolved['chapter'] ?? '';
                final defaultTags = [
                  if (subject.isNotEmpty) subject,
                  if (chapter.isNotEmpty) chapter,
                  '评论精选',
                ];

                if (!context.mounted) return;

                FlashcardEditDialog.showAsBottomSheet(
                  context,
                  initialFront: widget.question.title ?? '',
                  initialBack: comment.content,
                  questionId: widget.question.id,
                  initialTags: defaultTags,
                  restoreText: widget.question.restore,
                  explainText: widget.question.explain,
                  dialogTitle: '💬 评论制作闪卡',
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
