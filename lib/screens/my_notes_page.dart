import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/adaptive_route.dart';
import '../common/question_navigation.dart';
import '../models/note.dart';
import '../repositories/question_search_repository.dart';
import '../services/note_service.dart';
import '../widgets/image_view.dart';
import '../widgets/note_editor_sheet.dart';
import 'note_detail_page.dart';

class MyNotesPage extends StatefulWidget {
  const MyNotesPage({super.key});

  @override
  State<MyNotesPage> createState() => _MyNotesPageState();
}

class _MyNotesPageState extends State<MyNotesPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final QuestionSearchRepository _questionRepo = QuestionSearchRepository();

  List<QuestionNote> _allNotes = [];
  bool _loading = true;
  bool _isSearching = false;
  String _keyword = '';

  // 右侧时间轴拖动与当前滚动进度 (0.0 ~ 1.0)
  double _scrollProgress = 0.0;
  bool _isDraggingTimeline = false;
  String _draggedDateText = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _scrollController.addListener(_onScroll);
    NoteService.instance.noteSyncEventNotifier.addListener(_onSyncEvent);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    NoteService.instance.noteSyncEventNotifier.removeListener(_onSyncEvent);
    super.dispose();
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
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await NoteService.instance.getAllNotes();
      if (!mounted) return;
      setState(() {
        _allNotes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<QuestionNote> get _filteredNotes {
    final term = _keyword.trim().toLowerCase();
    if (term.isEmpty) return _allNotes;
    return _allNotes.where((note) {
      return note.content.toLowerCase().contains(term);
    }).toList();
  }

  String _formatDate(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Future<void> _handleCopy(QuestionNote note) async {
    await Clipboard.setData(ClipboardData(text: note.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制笔记文本到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleEdit(QuestionNote note) async {
    await showNoteEditorSheet(
      context,
      existingNote: note,
      onSaved: _loadNotes,
    );
  }

  Future<void> _handleDelete(QuestionNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这条笔记吗？若开启了云端同步，云端笔记也将一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await NoteService.instance.deleteNote(note);
      _loadNotes();
    }
  }

  Future<void> _jumpToQuestion(String questionId) async {
    try {
      final result = await _questionRepo.findQuestion(questionId);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('未在题库中找到对应的题目 (ID: $questionId)'),
          ),
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

  void _openFullScreen(List<NoteImage> images, int initialIndex) {
    final urls = images.map((img) {
      if (img.bImg.isNotEmpty) return img.bImg;
      if (img.sImg.isNotEmpty) return img.sImg;
      return img.localPath ?? '';
    }).toList();

    Navigator.push(
      context,
      adaptivePageRoute(
        builder: (context) => FullScreenImageView(
          imageUrls: urls,
          initialIndex: initialIndex,
        ),
      ),
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

  Widget _buildSyncBadge(QuestionNote note) {
    final isSynced = note.remoteId != null &&
        note.remoteId!.isNotEmpty &&
        note.syncStatus == 0;
    final isPending = note.syncStatus == 1;

    Color color = Colors.grey;
    IconData icon = Icons.cloud_off_outlined;
    String label = '本地';

    if (isSynced) {
      color = Colors.green;
      icon = Icons.cloud_done_outlined;
      label = '已同步';
    } else if (isPending) {
      color = Colors.orange;
      icon = Icons.cloud_upload_outlined;
      label = '待同步';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(QuestionNote note) {
    final theme = Theme.of(context);
    final term = _keyword.trim();
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
              builder: (context) => NoteDetailPage(note: note),
            ),
          );
          _loadNotes();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：日期与上传状态
              Row(
                children: [
                  Text(
                    _formatDate(note.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSyncBadge(note),
                ],
              ),
              const SizedBox(height: 8),
              // 笔记文本预览（模糊搜索高亮）
              if (note.content.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: _highlightSpans(
                      note.content,
                      term,
                      baseStyle,
                      highlightStyle,
                    ),
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              // 图片缩略图
              if (note.images.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: note.images.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final img = entry.value;
                    return GestureDetector(
                      onTap: () => _openFullScreen(note.images, idx),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: buildNoteThumbnail(img, 56, 56),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 6),
              const Divider(height: 12),
              // 操作项：修改、复制、删除（左侧）与 查看原题（靠右同行）
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('修改', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleEdit(note),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 15),
                    label: const Text('复制', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleCopy(note),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('删除', style: TextStyle(fontSize: 12)),
                    onPressed: () => _handleDelete(note),
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
                    onPressed: () => _jumpToQuestion(note.questionId),
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
    final filtered = _filteredNotes;
    if (trackHeight <= 0 || filtered.isEmpty) return;

    final dy = (localY - trackTop).clamp(0.0, trackHeight);
    final progress = dy / trackHeight;
    final noteIndex =
        ((progress * (filtered.length - 1)).round()).clamp(0, filtered.length - 1);
    final note = filtered[noteIndex];
    final dt = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final dateText = '$y年$m月$d日';

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
    final filtered = _filteredNotes;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索笔记内容...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _keyword = v),
              )
            : Text('我的笔记 (${_allNotes.length})'),
        actions: [
          IconButton(
            tooltip: _isSearching ? '取消搜索' : '搜索笔记',
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allNotes.isEmpty
              ? Center(
                  child: Text(
                    '暂无笔记，在刷题时记录重点吧~',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        '未找到包含“$_keyword”的笔记',
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
                            // 笔记列表（右侧预留 28 像素防遮挡时间轴）
                            ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 8, 28, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                return _buildNoteCard(filtered[index]);
                              },
                            ),
                            // 右侧长轴与小圆点
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
                                onVerticalDragUpdate: (details) => _onDragUpdate(
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
                                    // 垂直长轴
                                    Positioned(
                                      top: trackTop,
                                      bottom: trackBottom,
                                      left: 12,
                                      child: Container(
                                        width: 2,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.6),
                                          borderRadius:
                                              BorderRadius.circular(1),
                                        ),
                                      ),
                                    ),
                                    // 轴上的小圆点
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
                            // 拖动时浮现的日期气泡
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
