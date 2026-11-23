import 'package:flutter/material.dart';

import '../../common/adaptive_route.dart';
import '../../db/database_helper.dart';
import '../../models/note.dart';
import '../../models/question.dart';
import '../../services/note_service.dart';
import '../../widgets/flashcard_edit_dialog.dart';
import '../../widgets/image_view.dart';
import '../../widgets/note_editor_sheet.dart';

/// 题目笔记展示与管理组件
class QuestionNoteView extends StatefulWidget {
  final Question question;

  const QuestionNoteView({
    super.key,
    required this.question,
  });

  @override
  State<QuestionNoteView> createState() => QuestionNoteViewState();
}

class QuestionNoteViewState extends State<QuestionNoteView> {
  List<QuestionNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
    NoteService.instance.noteSyncEventNotifier.addListener(_onSyncEvent);
  }

  @override
  void dispose() {
    NoteService.instance.noteSyncEventNotifier.removeListener(_onSyncEvent);
    super.dispose();
  }

  void _onSyncEvent() {
    if (mounted) {
      _refreshLocalNotes();
    }
  }

  Future<void> _refreshLocalNotes() async {
    final local = await NoteService.instance.getLocalNotes(widget.question.id);
    if (mounted) {
      setState(() {
        _notes = local;
      });
    }
  }

  @override
  void didUpdateWidget(covariant QuestionNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _loadNotes();
    }
  }

  Future<void> _loadNotes() async {
    // 先读本地缓存
    final local = await NoteService.instance.getLocalNotes(widget.question.id);
    if (mounted) {
      setState(() {
        _notes = local;
      });
    }

    // 若开启同步，在后台拉取最新笔记
    if (await NoteService.instance.isSyncEnabled()) {
      final updated =
          await NoteService.instance.syncNotesForQuestion(widget.question);
      if (mounted) {
        setState(() {
          _notes = updated;
        });
      }
    }
  }

  /// 公开方法：供外部（例如评论转笔记）快捷打开编辑器
  void openNoteEditor({String? initialContent, QuestionNote? existingNote}) {
    _showNoteEditor(
      context,
      initialContent: initialContent,
      existingNote: existingNote,
    );
  }

  /// 一键将笔记转为闪卡（题干为 Front，笔记为 Back）
  Future<void> _convertNoteToFlashcard(BuildContext context, QuestionNote note) async {
    final frontText = widget.question.title ?? '';
    final backText = note.content;

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
      '笔记转化',
    ];

    if (!context.mounted) return;

    FlashcardEditDialog.showAsBottomSheet(
      context,
      initialFront: frontText,
      initialBack: backText,
      questionId: widget.question.id,
      initialTags: defaultTags,
      restoreText: widget.question.restore,
      explainText: widget.question.explain,
      dialogTitle: '✨ 一键转为双面闪卡',
    );
  }

  /// 为本题制作自制闪卡
  Future<void> _createFlashcardFromQuestion(BuildContext context) async {
    final frontText = widget.question.title ?? '';

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
    ];

    if (!context.mounted) return;

    FlashcardEditDialog.showAsBottomSheet(
      context,
      initialFront: frontText,
      questionId: widget.question.id,
      initialTags: defaultTags,
      restoreText: widget.question.restore,
      explainText: widget.question.explain,
      dialogTitle: '制作自制闪卡',
    );
  }

  Future<void> _showNoteEditor(
    BuildContext context, {
    String? initialContent,
    QuestionNote? existingNote,
  }) => showNoteEditorSheet(
    context,
    initialContent: initialContent,
    existingNote: existingNote,
    question: widget.question,
    onSaved: _loadNotes,
  );

  Future<void> _confirmDelete(QuestionNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这条笔记吗？若开启了同步，云端笔记也将一并删除。'),
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

    if (confirmed == true) {
      await NoteService.instance.deleteNote(note, question: widget.question);
      await _loadNotes();
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

  @override
  Widget build(BuildContext context) {
    const Color orangeAccent = Color(0xFFB39D6B);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.edit_note, color: orangeAccent, size: 24),
            const SizedBox(width: 6),
            Text(
              '我的笔记',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: orangeAccent,
              ),
            ),
            if (_notes.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: orangeAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_notes.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: orangeAccent,
                  ),
                ),
              ),
            ],
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.style_outlined, size: 17),
              label: const Text('制作闪卡'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _createFlashcardFromQuestion(context),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('写笔记'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _showNoteEditor(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_notes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.note_alt_outlined,
                  size: 36,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  '暂无笔记，记录一下解题关键点吧~',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          ..._notes.map((note) {
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              color: theme.colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        // 同步状态图标
                        if (note.remoteId != null &&
                            note.remoteId!.isNotEmpty &&
                            note.syncStatus == 0)
                          const Tooltip(
                            message: '已同步到医考帮',
                            child: Icon(Icons.cloud_done_outlined,
                                size: 14, color: Colors.green),
                          )
                        else if (note.syncStatus == 1)
                          const Tooltip(
                            message: '等待同步到医考帮',
                            child: Icon(Icons.cloud_upload_outlined,
                                size: 14, color: Colors.orange),
                          )
                        else
                          const Tooltip(
                            message: '未同步到医考帮 (仅本地)',
                            child: Icon(Icons.cloud_off_outlined,
                                size: 14, color: Colors.grey),
                          ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _convertNoteToFlashcard(context, note),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome_rounded, size: 13, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '一键转闪卡',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '编辑',
                          onPressed: () =>
                              _showNoteEditor(context, existingNote: note),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '删除',
                          onPressed: () => _confirmDelete(note),
                        ),
                      ],
                    ),
                    if (note.content.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        note.content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (note.images.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: note.images.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final img = entry.value;
                          return InkWell(
                            onTap: () => _openFullScreen(note.images, idx),
                            borderRadius: BorderRadius.circular(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: buildNoteThumbnail(img, 72, 72),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 10),
        const Divider(color: Color(0x22888888)),
      ],
    );
  }
}
