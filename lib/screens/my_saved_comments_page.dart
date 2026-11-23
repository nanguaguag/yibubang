import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/adaptive_route.dart';
import '../common/platform_adaptive.dart';
import '../common/question_navigation.dart';
import '../db/database_helper.dart';
import '../models/comment.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../repositories/question_search_repository.dart';
import '../services/comment_service.dart';
import '../services/note_service.dart';
import '../widgets/common/app_network_image.dart';
import '../widgets/flashcard_edit_dialog.dart';
import '../widgets/image_view.dart';

/// 「我的点赞」与「我的评论」本地归纳管理页面（与 MyNotesPage 具备一致的搜索、时间轴、课程筛选、转笔记/制闪卡与原题跳转）
class MySavedCommentsPage extends StatefulWidget {
  final SavedCommentCategory category;

  const MySavedCommentsPage({
    super.key,
    required this.category,
  });

  @override
  State<MySavedCommentsPage> createState() => _MySavedCommentsPageState();
}

class _MySavedCommentsPageState extends State<MySavedCommentsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final QuestionSearchRepository _questionRepo = QuestionSearchRepository();

  List<SavedComment> _allItems = [];
  Map<String, QuestionSearchResult> _questionMetaMap = {};
  bool _loading = true;
  bool _isSearching = false;
  bool _syncing = false;
  String _syncProgressText = '';
  String _keyword = '';
  String? _filterSubject;

  // 右侧时间轴拖动与当前滚动进度 (0.0 ~ 1.0)
  double _scrollProgress = 0.0;
  bool _isDraggingTimeline = false;
  String _draggedDateText = '';

  @override
  void initState() {
    super.initState();
    // 跨页面恢复当前分类正在执行的后台同步状态
    final syncState = CommentService.instance.batchSyncNotifier.value;
    final matchesCategory = syncState.category == null ||
        syncState.category == widget.category;
    if (syncState.isRunning && matchesCategory) {
      _syncing = true;
      _syncProgressText = '${syncState.current}/${syncState.total}';
    }
    _loadData();
    _scrollController.addListener(_onScroll);
    CommentService.instance.commentSyncEventNotifier.addListener(_onSyncEvent);
    CommentService.instance.batchSyncNotifier.addListener(
      _onBatchSyncStateChanged,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    CommentService.instance.commentSyncEventNotifier.removeListener(_onSyncEvent);
    CommentService.instance.batchSyncNotifier.removeListener(
      _onBatchSyncStateChanged,
    );
    super.dispose();
  }

  void _onBatchSyncStateChanged() {
    if (!mounted) return;
    final state = CommentService.instance.batchSyncNotifier.value;
    final matchesCategory = state.category == null ||
        state.category == widget.category;
    if (state.isRunning && matchesCategory) {
      if (!_syncing || _syncProgressText != '${state.current}/${state.total}') {
        setState(() {
          _syncing = true;
          _syncProgressText = '${state.current}/${state.total}';
        });
      }
    } else if (!state.isRunning && _syncing) {
      setState(() {
        _syncing = false;
        _syncProgressText = '';
      });
      _loadData();
    }
  }

  void _onScroll() {
    if (!_isDraggingTimeline && _scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        final progress =
            (_scrollController.offset / maxScroll).clamp(0.0, 1.0);
        if ((progress - _scrollProgress).abs() > 0.005) {
          setState(() {
            _scrollProgress = progress;
          });
        }
      }
    }
  }

  void _onSyncEvent() {
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final items = await CommentService.instance.getAllSavedComments(
        category: widget.category,
      );
      final qIds = items
          .map((e) => e.questionId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final metaMap = <String, QuestionSearchResult>{};
      if (qIds.isNotEmpty) {
        try {
          final results = await _questionRepo.loadQuestionsByIds(qIds);
          for (final r in results) {
            metaMap[r.questionId] = r;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _questionMetaMap = metaMap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<String> get _subjectOptions => _allItems
      .map((item) => _questionMetaMap[item.questionId]?.subjectName)
      .where((s) => s != null && s.isNotEmpty)
      .map((s) => s!)
      .toSet()
      .toList()
    ..sort();

  List<SavedComment> get _filteredItems {
    final term = _keyword.trim().toLowerCase();
    return _allItems.where((item) {
      final meta = _questionMetaMap[item.questionId];
      if (_filterSubject != null &&
          (meta?.subjectName ?? '') != _filterSubject) {
        return false;
      }
      if (term.isNotEmpty) {
        final inContent = item.content.toLowerCase().contains(term);
        final inNick = item.nickname.toLowerCase().contains(term);
        final inSchool = item.school.toLowerCase().contains(term);
        final inStem = (meta?.stem ?? '').toLowerCase().contains(term);
        if (!inContent && !inNick && !inSchool && !inStem) return false;
      }
      return true;
    }).toList();
  }

  String _formatDate(int timestamp, String fallbackCtime) {
    if (timestamp <= 0) return fallbackCtime;
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Future<T?> _showNoAnimationDialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    );
  }

  String _estimateSyncTime(int questionCount) {
    final seconds = (questionCount * 0.2).ceil();
    if (seconds <= 5) return '约 5 秒内';
    if (seconds < 60) return '约 $seconds 秒';
    final mins = seconds ~/ 60;
    final remainSec = seconds % 60;
    if (remainSec == 0) return '约 $mins 分钟';
    return '约 $mins 分 $remainSec 秒';
  }

  void _showActiveSyncProgressDialog() {
    final label = widget.category.label;
    _showNoAnimationDialog(
      context: context,
      builder: (dlgCtx) {
        final theme = Theme.of(dlgCtx);
        final scheme = theme.colorScheme;
        return ValueListenableBuilder<CommentBatchSyncState>(
          valueListenable: CommentService.instance.batchSyncNotifier,
          builder: (context, state, child) {
            final curr = state.current;
            final total = state.total;
            final percent = total > 0 ? (curr / total).clamp(0.0, 1.0) : 0.0;
            final remain = math.max(0, total - curr);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 10),
                  Text('正在扫描同步$label'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在后台逐题拉取医考帮最新$label并归纳入库...',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '进度：$curr / $total 题',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      Text(
                        '${(percent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '预计剩余耗时：${_estimateSyncTime(remain)}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dlgCtx).pop(),
                  child: const Text('后台运行'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: scheme.error,
                    backgroundColor: scheme.errorContainer.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('终止同步'),
                  onPressed: () {
                    CommentService.instance.cancelBatchSync();
                    Navigator.of(dlgCtx).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('正在终止同步，将在完成当前题目后停止...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleBatchSync() async {
    final currentSync = CommentService.instance.batchSyncNotifier.value;
    if (currentSync.isRunning) {
      final matchesCategory = currentSync.category == null ||
          currentSync.category == widget.category;
      if (matchesCategory) {
        _showActiveSyncProgressDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '后台正在同步医考帮${currentSync.category?.label ?? "其他数据"}，请稍候...',
            ),
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;
    if (!loggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录医考帮账号后再执行同步')),
      );
      return;
    }

    final touchedIds = await CommentService.instance.getTouchedQuestionIds();
    if (!mounted) return;
    if (touchedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地暂无可扫描的已做题或收藏记录')),
      );
      return;
    }

    final label = widget.category.label;
    final confirmed = await _showNoAnimationDialog<bool>(
      context: context,
      builder: (dlgCtx) {
        final theme = Theme.of(dlgCtx);
        final scheme = theme.colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.sync_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Text('扫描同步$label'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将扫描本地已做、收藏及记过笔记的题目，从医考帮官方接口获取最新的$label并归纳入库。',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '待扫描题目总数',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${touchedIds.length} 题',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '预计耗时',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _estimateSyncTime(touchedIds.length),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '提示：同步在后台轻量运行，请尽量保持网络畅通。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: const Text('开始同步'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _syncing = true;
      _syncProgressText = '0/${touchedIds.length}';
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await CommentService.instance.syncFromTouchedQuestions(
        category: widget.category,
        targetQuestionIds: touchedIds,
        onProgress: (curr, total) {
          if (mounted) {
            setState(() {
              _syncProgressText = '$curr/$total';
            });
          }
        },
      );
      await _loadData();
      if (mounted) {
        final wasCancelled =
            CommentService.instance.batchSyncNotifier.value.isCancelled;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              wasCancelled
                  ? '已终止同步，本次新增归纳 $added 条${widget.category.label}'
                  : added > 0
                      ? '同步完成，新增归纳 $added 条${widget.category.label}'
                      : '同步完成，当前${widget.category.label}已是最新',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('同步失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncProgressText = '';
        });
      }
    }
  }

  Future<void> _handleCopy(SavedComment item) async {
    await Clipboard.setData(ClipboardData(text: item.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制评论内容到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleConvertToNote(SavedComment item) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<NoteImage> images = [];
    if (item.imgWatermark.isNotEmpty) {
      images.add(
        NoteImage(
          bImg: item.imgWatermark,
          sImg: item.imgWatermark,
        ),
      );
    }
    final meta = _questionMetaMap[item.questionId];
    final q = Question(
      id: item.questionId,
      chapterParentId: meta?.subjectId,
      userAnswer: '',
      sourceBankId: meta?.bankId,
    );
    final newNote = QuestionNote(
      id: 'local_${now}_${item.questionId}',
      questionId: item.questionId,
      content: item.content,
      images: images,
      timestamp: now,
      updatedAt: now,
    );
    await NoteService.instance.saveNote(newNote, question: q);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存至「我的笔记」'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleConvertToFlashcard(SavedComment item) async {
    final meta = _questionMetaMap[item.questionId];
    Map<String, String> resolved = const {};
    try {
      resolved = await DatabaseHelper.resolveSubjectAndChapter(
        subjectId: meta?.subjectId,
      );
    } catch (_) {}
    final subject = meta?.subjectName ?? resolved['subject'] ?? '';
    final defaultTags = [
      if (subject.isNotEmpty) subject,
      widget.category == SavedCommentCategory.praise ? '高赞评论' : '我的评论',
    ];
    if (!mounted) return;
    await FlashcardEditDialog.showAsBottomSheet(
      context,
      initialFront: meta?.stem ?? '',
      initialBack: item.content,
      questionId: item.questionId,
      initialTags: defaultTags,
      restoreText: meta?.restore,
      explainText: meta?.explain,
      dialogTitle: '💬 转为自制闪卡',
    );
  }

  Future<void> _handleDelete(SavedComment item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移除${widget.category.label}'),
        content: Text('确定要从本地${widget.category.label}归纳库中移除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await CommentService.instance.deleteSavedComment(item.id);
      _loadData();
    }
  }

  Future<void> _jumpToQuestion(String questionId) async {
    try {
      final result = _questionMetaMap[questionId] ??
          await _questionRepo.findQuestion(questionId);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未在题库中找到对应的题目 (ID: $questionId)')),
        );
        return;
      }
      await openQuestionDetailPage(context, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开题目失败：$e')),
        );
      }
    }
  }

  void _openFullScreen(String url) {
    Navigator.push(
      context,
      adaptivePageRoute(
        builder: (context) => FullScreenImageView(
          imageUrls: [url],
          initialIndex: 0,
        ),
      ),
    );
  }

  void _showFilterSheet() {
    final subjects = _subjectOptions;
    showAdaptiveModalSheet(
      context: context,
      title: '按课程筛选',
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final all = <String>['全部', ...subjects];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '所在课程',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _filterSubject = null);
                            setModalState(() {});
                          },
                          child: const Text('重置'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (subjects.isEmpty)
                      const Text(
                        '当前记录暂无关联课程信息',
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final opt in all)
                            ChoiceChip(
                              label: Text(opt),
                              selected:
                                  (opt == '全部' && _filterSubject == null) ||
                                      opt == _filterSubject,
                              onSelected: (_) {
                                setState(() {
                                  _filterSubject = opt == '全部' ? null : opt;
                                });
                                setModalState(() {});
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<InlineSpan> _highlightSpans(
    String text,
    String term,
    TextStyle base,
    TextStyle highlight,
  ) {
    if (term.isEmpty) return [TextSpan(text: text, style: base)];
    final spans = <InlineSpan>[];
    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();
    var start = 0;
    var index = lowerText.indexOf(lowerTerm);
    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: base));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + term.length),
          style: highlight,
        ),
      );
      start = index + term.length;
      index = lowerText.indexOf(lowerTerm, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
    return spans;
  }

  Widget _buildItemCard(SavedComment item) {
    final theme = Theme.of(context);
    final term = _keyword.trim();
    final meta = _questionMetaMap[item.questionId];
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
        ) ??
        const TextStyle(fontSize: 14, height: 1.5);
    final highlightStyle = TextStyle(
      fontWeight: FontWeight.bold,
      backgroundColor: Colors.yellow.withValues(alpha: 0.55),
      color: Colors.black87,
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            adaptivePageRoute(
              builder: (_) => SavedCommentDetailPage(
                item: item,
                questionMeta: meta,
              ),
            ),
          );
          _loadData();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：作者头像、昵称、学校、时间与点赞数徽章
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: item.avatar.trim().isNotEmpty
                        ? AppNetworkImage.provider(item.avatar)
                        : null,
                    child: item.avatar.trim().isEmpty
                        ? const Icon(Icons.person, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.nickname.isNotEmpty
                                    ? item.nickname
                                    : '医考帮用户',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.school.isNotEmpty &&
                                item.school != '0') ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  item.school,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _formatDate(item.timestamp, item.ctime),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (meta?.subjectName != null &&
                      meta!.subjectName!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        meta.subjectName!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.thumb_up_alt_rounded,
                          size: 12,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${item.praiseNum}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 引用的父级评论（若有）
              if (item.replyList.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: const Border(
                      left: BorderSide(color: Colors.grey, width: 3),
                    ),
                    color: Colors.grey.withValues(alpha: 0.14),
                  ),
                  child: Text(
                    '${item.replyList.first.nickname}: ${item.replyList.first.content}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // 评论正文
              if (item.content.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: _highlightSpans(
                      item.content,
                      term,
                      baseStyle,
                      highlightStyle,
                    ),
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              // 附图预览
              if (item.imgWatermark.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _openFullScreen(item.imgWatermark),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AppNetworkImage(
                      imageUrl: item.imgWatermark,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
              // 关联题目摘要预览
              if (meta != null && meta.stem.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '原题：${meta.stem}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              const Divider(height: 12),
              // 底部操作栏：转笔记、制闪卡、复制、移除 + 查看原题
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 15),
                    label: const Text('转笔记', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleConvertToNote(item),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    icon: const Icon(Icons.style_outlined, size: 15),
                    label: const Text('制闪卡', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleConvertToFlashcard(item),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 15),
                    label: const Text('复制', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleCopy(item),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('移除', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleDelete(item),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 15),
                    label: const Text('查看原题', style: TextStyle(fontSize: 12)),
                    onPressed: () => _jumpToQuestion(item.questionId),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onDragUpdate(double localY, double trackHeight, double trackTop) {
    final filtered = _filteredItems;
    if (trackHeight <= 0 || filtered.isEmpty) return;

    final dy = (localY - trackTop).clamp(0.0, trackHeight);
    final progress = dy / trackHeight;
    final idx = ((progress * (filtered.length - 1)).round())
        .clamp(0, filtered.length - 1);
    final item = filtered[idx];
    final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    final dateText = item.timestamp > 0
        ? '${dt.year}年${dt.month.toString().padLeft(2, '0')}月${dt.day.toString().padLeft(2, '0')}日'
        : item.ctime;

    setState(() {
      _isDraggingTimeline = true;
      _scrollProgress = progress;
      _draggedDateText = dateText;
    });

    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _scrollController.jumpTo(progress * maxScroll);
      }
    }
  }

  void _onDragEnd() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _isDraggingTimeline) {
        setState(() {
          _isDraggingTimeline = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    final theme = Theme.of(context);
    final label = widget.category.label;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索$label内容、作者或原题...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _keyword = v),
              )
            : Text('$label (${_allItems.length})'),
        actions: [
          if (_syncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text(
                  _syncProgressText.isEmpty ? '同步中' : _syncProgressText,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                tooltip: '正在扫描同步，点击查看进度或终止',
                onPressed: _showActiveSyncProgressDialog,
              ),
            )
          else
            IconButton(
              tooltip: '从医考帮扫描同步已做/收藏题目的$label',
              icon: const Icon(Icons.sync_rounded),
              onPressed: _handleBatchSync,
            ),
          IconButton(
            tooltip: _isSearching ? '取消搜索' : '搜索',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _keyword = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: '按课程筛选',
            icon: Badge(
              isLabelVisible: _filterSubject != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.category == SavedCommentCategory.praise
                              ? Icons.thumb_up_off_alt_rounded
                              : Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.category == SavedCommentCategory.praise
                              ? '暂无点赞评论记录\n在题目评论区点赞或打开做过的题即可自动归纳同步'
                              : '暂无个人评论记录\n在题目评论区发表评论或打开评论过的题即可自动归纳同步',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: Text('扫描已做题库同步$label'),
                          onPressed: _syncing ? null : _handleBatchSync,
                        ),
                      ],
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        '没有符合筛选条件的$label',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final maxHeight = constraints.maxHeight;
                        const trackTop = 24.0;
                        const trackBottom = 24.0;
                        final trackHeight = maxHeight - trackTop - trackBottom;

                        return Stack(
                          children: [
                            ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 8, 28, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                return _buildItemCard(filtered[index]);
                              },
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              width: 26,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: (details) => _onDragUpdate(
                                  details.localPosition.dy,
                                  trackHeight,
                                  trackTop,
                                ),
                                onVerticalDragUpdate: (details) =>
                                    _onDragUpdate(
                                  details.localPosition.dy,
                                  trackHeight,
                                  trackTop,
                                ),
                                onVerticalDragEnd: (_) => _onDragEnd(),
                                onVerticalDragCancel: () => _onDragEnd(),
                                onTapDown: (details) {
                                  _onDragUpdate(
                                    details.localPosition.dy,
                                    trackHeight,
                                    trackTop,
                                  );
                                  _onDragEnd();
                                },
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: trackTop,
                                      bottom: trackBottom,
                                      left: 12,
                                      child: Container(
                                        width: 2,
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.outlineVariant
                                              .withValues(alpha: 0.6),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: (trackTop +
                                              _scrollProgress * trackHeight -
                                              7.0)
                                          .clamp(
                                        trackTop - 7.0,
                                        maxHeight - trackBottom - 7.0,
                                      ),
                                      left: 6,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: theme.colorScheme.surface,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_isDraggingTimeline &&
                                _draggedDateText.isNotEmpty)
                              Positioned(
                                top: (trackTop +
                                        _scrollProgress * trackHeight -
                                        16.0)
                                    .clamp(8.0, maxHeight - 40.0),
                                right: 28,
                                child: Material(
                                  elevation: 4,
                                  shadowColor: Colors.black26,
                                  borderRadius: BorderRadius.circular(16),
                                  color: theme.colorScheme.primaryContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.event_note_rounded,
                                          size: 14,
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          _draggedDateText,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: theme
                                                .colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
    );
  }
}

/// 评论/点赞归纳详情页（与 NoteDetailPage 对应）
class SavedCommentDetailPage extends StatefulWidget {
  final SavedComment item;
  final QuestionSearchResult? questionMeta;

  const SavedCommentDetailPage({
    super.key,
    required this.item,
    this.questionMeta,
  });

  @override
  State<SavedCommentDetailPage> createState() => _SavedCommentDetailPageState();
}

class _SavedCommentDetailPageState extends State<SavedCommentDetailPage> {
  bool _openingQuestion = false;

  String _formatDate(int timestamp, String fallback) {
    if (timestamp <= 0) return fallback;
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.item.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制评论文本到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleConvertToNote() async {
    final item = widget.item;
    final now = DateTime.now().millisecondsSinceEpoch;
    final images = <NoteImage>[
      if (item.imgWatermark.isNotEmpty)
        NoteImage(bImg: item.imgWatermark, sImg: item.imgWatermark),
    ];
    final q = Question(
      id: item.questionId,
      chapterParentId: widget.questionMeta?.subjectId,
      userAnswer: '',
      sourceBankId: widget.questionMeta?.bankId,
    );
    final newNote = QuestionNote(
      id: 'local_${now}_${item.questionId}',
      questionId: item.questionId,
      content: item.content,
      images: images,
      timestamp: now,
      updatedAt: now,
    );
    await NoteService.instance.saveNote(newNote, question: q);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存至「我的笔记」')),
      );
    }
  }

  Future<void> _handleDelete() async {
    final label = SavedCommentCategory.fromValue(widget.item.category).label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移除$label'),
        content: Text('确定要从本地$label归纳库中移除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await CommentService.instance.deleteSavedComment(widget.item.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _jumpToQuestion() async {
    if (_openingQuestion) return;
    setState(() => _openingQuestion = true);
    try {
      final repo = QuestionSearchRepository();
      final result = widget.questionMeta ??
          await repo.findQuestion(widget.item.questionId);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('未在题库中找到对应的题目 (ID: ${widget.item.questionId})'),
          ),
        );
        return;
      }
      await openQuestionDetailPage(context, result);
    } finally {
      if (mounted) {
        setState(() => _openingQuestion = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final label = SavedCommentCategory.fromValue(item.category).label;

    return Scaffold(
      appBar: AppBar(
        title: Text('$label详情'),
        actions: [
          IconButton(
            tooltip: '复制文本',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _handleCopy,
          ),
          IconButton(
            tooltip: '转存为笔记',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _handleConvertToNote,
          ),
          IconButton(
            tooltip: '移除记录',
            icon: const Icon(Icons.delete_outline),
            onPressed: _handleDelete,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: item.avatar.trim().isNotEmpty
                              ? AppNetworkImage.provider(item.avatar)
                              : null,
                          child: item.avatar.trim().isEmpty
                              ? const Icon(Icons.person, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nickname.isNotEmpty
                                    ? item.nickname
                                    : '医考帮用户',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                [
                                  if (item.school.isNotEmpty &&
                                      item.school != '0')
                                    item.school,
                                  _formatDate(item.timestamp, item.ctime),
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.thumb_up_alt_rounded,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item.praiseNum}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (item.replyList.isNotEmpty) ...[
                      for (final r in item.replyList)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            border: const Border(
                              left: BorderSide(color: Colors.grey, width: 3),
                            ),
                            color: Colors.grey.withValues(alpha: 0.14),
                          ),
                          child: Text(
                            '${r.nickname}: ${r.content}',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                    SelectableText(
                      item.content.isNotEmpty ? item.content : '(无文字内容)',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    if (item.imgWatermark.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.push(
                            context,
                            adaptivePageRoute(
                              builder: (_) => FullScreenImageView(
                                imageUrls: [item.imgWatermark],
                                initialIndex: 0,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AppNetworkImage(
                            imageUrl: item.imgWatermark,
                            height: 220,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _openingQuestion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.menu_book_outlined),
                  label: const Text(
                    '查看原题',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _openingQuestion ? null : _jumpToQuestion,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
