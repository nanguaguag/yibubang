import 'package:flutter/material.dart';

import '../common/platform_adaptive.dart';
import '../common/ykb_encrypt.dart';
import '../models/comment.dart';
import '../models/question.dart';
import '../services/comment_service.dart';
import 'comment_page.dart';

/// 独立的题目评论四维排序页面（最多点赞 / 最高热度 / 最多回复 / 最新发布）
/// 可从题目详情页评论区进入，通过 TabBar 分为 4 个板块。
class QuestionCommentsPage extends StatefulWidget {
  final Question question;
  final CommentSortType initialSort;

  const QuestionCommentsPage({
    super.key,
    required this.question,
    this.initialSort = CommentSortType.mostLiked,
  });

  static Future<void> open(
    BuildContext context, {
    required Question question,
    CommentSortType initialSort = CommentSortType.mostLiked,
  }) {
    return pushAdaptiveModalPage<void>(
      context,
      desktopConstraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
      builder: (_) => QuestionCommentsPage(
        question: question,
        initialSort: initialSort,
      ),
    );
  }

  @override
  State<QuestionCommentsPage> createState() => _QuestionCommentsPageState();
}

class _QuestionCommentsPageState extends State<QuestionCommentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<CommentSortType, GlobalKey<_CommentSortTabViewState>> _tabKeys = {
    for (final t in CommentSortType.values)
      t: GlobalKey<_CommentSortTabViewState>(),
  };

  @override
  void initState() {
    super.initState();
    final initialIndex = CommentSortType.values.indexOf(widget.initialSort);
    _tabController = TabController(
      length: CommentSortType.values.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handlePublish() async {
    final published = await showPublishCommentSheet(
      context,
      question: widget.question,
    );
    if (published && mounted) {
      // 刷新「最新发布」Tab
      _tabKeys[CommentSortType.latest]?.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('题目评论区'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('写评论'),
            onPressed: _handlePublish,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: [
            for (final sort in CommentSortType.values) Tab(text: sort.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final sort in CommentSortType.values)
            _CommentSortTabView(
              key: _tabKeys[sort],
              question: widget.question,
              sortType: sort,
            ),
        ],
      ),
    );
  }
}

class _CommentSortTabView extends StatefulWidget {
  final Question question;
  final CommentSortType sortType;

  const _CommentSortTabView({
    super.key,
    required this.question,
    required this.sortType,
  });

  @override
  State<_CommentSortTabView> createState() => _CommentSortTabViewState();
}

class _CommentSortTabViewState extends State<_CommentSortTabView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final List<Comment> _comments = [];
  Set<String> _praisedIds = {};
  int _page = 0;
  String _breakPoint = '';
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _breakPoint = getTimestamp();
    _scrollController.addListener(_onScroll);
    CommentService.instance.commentSyncEventNotifier
        .addListener(_refreshLocalPraiseState);
    _initLoad();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    CommentService.instance.commentSyncEventNotifier
        .removeListener(_refreshLocalPraiseState);
    super.dispose();
  }

  Future<void> _refreshLocalPraiseState() async {
    final ids = await CommentService.instance.getLocalPraisedCommentIds(
      widget.question.id,
    );
    if (mounted) {
      setState(() => _praisedIds = ids);
    }
  }

  Future<void> _initLoad() async {
    await _refreshLocalPraiseState();
    await _loadMore();
  }

  Future<void> refresh() async {
    setState(() {
      _comments.clear();
      _page = 0;
      _breakPoint = getTimestamp();
      _hasMore = true;
      _error = null;
    });
    await _refreshLocalPraiseState();
    await _loadMore();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nextPage = _page + 1;
      final data = await CommentService.instance.fetchSortedComments(
        question: widget.question,
        sortType: widget.sortType,
        page: nextPage,
        breakPoint: _breakPoint,
      );
      if (!mounted) return;
      final incoming = <Comment>[...data.hot, ...data.timeLine];
      final existingIds = _comments.map((c) => c.id).toSet();
      final deduped =
          incoming.where((c) => c.id.isEmpty || existingIds.add(c.id)).toList();
      setState(() {
        _comments.addAll(deduped);
        _page = nextPage;
        if (incoming.isEmpty) {
          _hasMore = false;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_comments.isEmpty) {
          _error = '加载评论失败：$e';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: refresh,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('暂无评论')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _comments.length + 1,
        itemBuilder: (context, index) {
          if (index == _comments.length) {
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!_hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '没有更多评论了',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              );
            }
            return const SizedBox(height: 16);
          }
          final c = _comments[index];
          return CommentItem(
            comment: c,
            question: widget.question,
            initiallyPraised: c.isPraise == '1' || _praisedIds.contains(c.id),
          );
        },
      ),
    );
  }
}
