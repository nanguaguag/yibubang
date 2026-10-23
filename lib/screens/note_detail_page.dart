import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/adaptive_route.dart';
import '../common/question_navigation.dart';
import '../models/note.dart';
import '../repositories/question_search_repository.dart';
import '../services/note_service.dart';
import '../widgets/image_view.dart';
import '../widgets/note_editor_sheet.dart';

class NoteDetailPage extends StatefulWidget {
  final QuestionNote note;

  const NoteDetailPage({
    super.key,
    required this.note,
  });

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late QuestionNote _note;
  bool _openingQuestion = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    NoteService.instance.noteSyncEventNotifier.addListener(_onSyncEvent);
  }

  @override
  void dispose() {
    NoteService.instance.noteSyncEventNotifier.removeListener(_onSyncEvent);
    super.dispose();
  }

  void _onSyncEvent() async {
    final all = await NoteService.instance.getAllNotes();
    final updated = all.where((n) => n.id == _note.id).firstOrNull;
    if (updated != null && mounted) {
      setState(() => _note = updated);
    }
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

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: _note.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制笔记文本到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleEdit() async {
    await showNoteEditorSheet(
      context,
      existingNote: _note,
      onSaved: () async {
        final all = await NoteService.instance.getAllNotes();
        final updated = all.where((n) => n.id == _note.id).firstOrNull;
        if (updated != null && mounted) {
          setState(() => _note = updated);
        }
      },
    );
  }

  Future<void> _handleDelete() async {
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
      await NoteService.instance.deleteNote(_note);
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
      final result = await repo.findQuestion(_note.questionId);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('未在题库中找到对应的题目 (ID: ${_note.questionId})'),
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

  Widget _buildSyncBadge(ThemeData theme) {
    final isSynced = _note.remoteId != null &&
        _note.remoteId!.isNotEmpty &&
        _note.syncStatus == 0;
    final isPending = _note.syncStatus == 1;

    Color color = Colors.grey;
    IconData icon = Icons.cloud_off_outlined;
    String label = '本地笔记';

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记详情'),
        actions: [
          IconButton(
            tooltip: '复制文本',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _handleCopy,
          ),
          IconButton(
            tooltip: '修改笔记',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _handleEdit,
          ),
          IconButton(
            tooltip: '删除笔记',
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
                    // 时间与同步状态
                    Row(
                      children: [
                        Text(
                          _formatDate(_note.timestamp),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildSyncBadge(theme),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // 笔记内容（支持选择复制与后续 Markdown 渲染）
                    SelectableText(
                      _note.content.isNotEmpty ? _note.content : '(无文字内容)',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    // 图片展示
                    if (_note.images.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '附图 (${_note.images.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _note.images.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final img = entry.value;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _openFullScreen(_note.images, idx),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: buildNoteThumbnail(img, 90, 90),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 底部查看原题按钮
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
