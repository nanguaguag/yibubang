import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../common/platform_adaptive.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../services/note_service.dart';
import 'common/app_network_image.dart';

Widget buildNoteThumbnail(NoteImage img, double width, double height) {
  if (img.localPath != null && img.localPath!.isNotEmpty) {
    final file = File(img.localPath!);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.withValues(alpha: 0.2),
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
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

/// 弹出笔记创建 / 编辑 BottomSheet
Future<void> showNoteEditorSheet(
  BuildContext context, {
  QuestionNote? existingNote,
  String? defaultQuestionId,
  Question? question,
  VoidCallback? onSaved,
}) async {
  final textController = TextEditingController(
    text: existingNote?.content ?? '',
  );
  final List<NoteImage> images = List.from(existingNote?.images ?? []);

  await showAdaptiveModalSheet<void>(
    context: context,
    title: existingNote == null ? '写笔记' : '编辑笔记',
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existingNote == null ? '写笔记' : '编辑笔记',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                              child: buildNoteThumbnail(img, 64, 64),
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
                            final appDir =
                                await getApplicationSupportDirectory();
                            final noteImagesDir =
                                Directory(p.join(appDir.path, 'note_images'));
                            if (!noteImagesDir.existsSync()) {
                              noteImagesDir.createSync(recursive: true);
                            }
                            final List<NoteImage> newImgs = [];
                            for (final f in result.files) {
                              if (f.path != null) {
                                try {
                                  final srcFile = File(f.path!);
                                  final ext = p.extension(f.path!);
                                  final destFileName =
                                      'note_${DateTime.now().millisecondsSinceEpoch}_${newImgs.length}$ext';
                                  final destFile = File(
                                      p.join(noteImagesDir.path, destFileName));
                                  await srcFile.copy(destFile.path);
                                  newImgs.add(NoteImage(
                                    bImg: '',
                                    sImg: '',
                                    localPath: destFile.path,
                                  ));
                                } catch (e) {
                                  debugPrint('[Note] 复制所选本地图片到应用沙盒失败: $e');
                                  newImgs.add(NoteImage(
                                    bImg: '',
                                    sImg: '',
                                    localPath: f.path,
                                  ));
                                }
                              }
                            }
                            setSheetState(() {
                              images.addAll(newImgs);
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

                          final qId = existingNote?.questionId ??
                              question?.id ??
                              defaultQuestionId ??
                              '';
                          final now = DateTime.now().millisecondsSinceEpoch;
                          final QuestionNote noteToSave = existingNote != null
                              ? existingNote.copyWith(
                                  content: content,
                                  images: images,
                                  updatedAt: now,
                                )
                              : QuestionNote(
                                  id: 'local_${now}_$qId',
                                  questionId: qId,
                                  content: content,
                                  images: images,
                                  timestamp: now,
                                  updatedAt: now,
                                );

                          Navigator.of(ctx).pop();
                          await NoteService.instance.saveNote(
                            noteToSave,
                            question: question,
                          );
                          onSaved?.call();
                        },
                        child: const Text('保存'),
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
