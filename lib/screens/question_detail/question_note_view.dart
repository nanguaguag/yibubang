import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../common/adaptive_route.dart';
import '../../models/note.dart';
import '../../models/question.dart';
import '../../services/note_service.dart';
import '../../widgets/common/app_network_image.dart';
import '../../widgets/image_view.dart';

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

  Future<void> _showNoteEditor(
    BuildContext context, {
    String? initialContent,
    QuestionNote? existingNote,
  }) async {
    final textController = TextEditingController(
      text: existingNote?.content ?? initialContent ?? '',
    );
    final List<NoteImage> images = List.from(existingNote?.images ?? []);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        existingNote == null
                            ? Icons.note_add_outlined
                            : Icons.edit_note_outlined,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        existingNote == null ? '写笔记' : '编辑笔记',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: textController,
                    maxLines: 5,
                    minLines: 3,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '写下本题的解题思路、重点总结...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 图片列表预览
                  if (images.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: images.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final img = entry.value;
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildThumbnailImage(img, 64, 64),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    images.removeAt(idx);
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 18),
                        label: const Text('添加图片'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                            allowMultiple: true,
                          );
                          if (result != null && result.files.isNotEmpty) {
                            setSheetState(() {
                              for (final f in result.files) {
                                if (f.path != null) {
                                  images.add(NoteImage(
                                    bImg: '',
                                    sImg: '',
                                    localPath: f.path,
                                  ));
                                }
                              }
                            });
                          }
                        },
                      ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final content = textController.text.trim();
                          if (content.isEmpty && images.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入笔记内容或添加图片')),
                            );
                            return;
                          }

                          final now = DateTime.now().millisecondsSinceEpoch;
                          final QuestionNote noteToSave = existingNote != null
                              ? existingNote.copyWith(
                                  content: content,
                                  images: images,
                                  updatedAt: now,
                                )
                              : QuestionNote(
                                  id: 'local_${now}_${widget.question.id}',
                                  questionId: widget.question.id,
                                  content: content,
                                  images: images,
                                  timestamp: now,
                                  updatedAt: now,
                                );

                          Navigator.of(ctx).pop();
                          await NoteService.instance.saveNote(
                            noteToSave,
                            question: widget.question,
                          );
                          await _loadNotes();
                        },
                        child: const Text('保存'),
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
  }

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

  Widget _buildThumbnailImage(NoteImage img, double width, double height) {
    if (img.localPath != null && img.localPath!.isNotEmpty) {
      final file = File(img.localPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.cover,
        );
      }
    }
    final url = img.sImg.isNotEmpty ? img.sImg : img.bImg;
    if (url.isNotEmpty) {
      return AppNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: width,
      height: height,
      color: Colors.grey.withValues(alpha: 0.2),
      child: const Icon(Icons.image, color: Colors.grey),
    );
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
                              child: _buildThumbnailImage(img, 72, 72),
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
