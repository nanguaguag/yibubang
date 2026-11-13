import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:photo_view/photo_view.dart';
import '../models/ai_search.dart';
import '../services/textbook_client.dart';
import '../services/ai_search_client.dart';

class TextbookReaderPage extends StatefulWidget {
  final AiCitation citation;
  final TextbookGateway? gateway;
  final BaseCacheManager? cacheManager;
  const TextbookReaderPage({
    super.key,
    required this.citation,
    this.gateway,
    this.cacheManager,
  });
  @override
  State<TextbookReaderPage> createState() => _TextbookReaderPageState();
}

class _TextbookReaderPageState extends State<TextbookReaderPage> {
  static final cache = CacheManager(
    Config(
      'textbook-pages-v1',
      stalePeriod: const Duration(days: 180),
      maxNrOfCacheObjects: 160,
    ),
  );
  late final TextbookGateway gateway;
  late final PageController pager;
  late int current;
  final readerFocus = FocusNode(debugLabel: 'textbook reader');
  final Map<int, Future<File>> pages = {};
  AiCitation get citation => widget.citation;
  BaseCacheManager get pageCache => widget.cacheManager ?? cache;
  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? TextbookClient();
    current = citation.pdfPage.clamp(
      1,
      citation.pageCount > 0 ? citation.pageCount : 1,
    );
    pager = PageController(initialPage: current - 1);
  }

  Future<File> _load(int page) => pages.putIfAbsent(page, () async {
    final key =
        'textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${page.toString().padLeft(4, '0')}.webp';
    final existing = await pageCache.getFileFromCache(key);
    if (existing != null && await existing.file.exists()) return existing.file;
    final signed = await gateway.page(citation, page);
    return pageCache.getSingleFile(signed['url'] as String, key: key);
  });
  void _move(int delta) {
    if (current + delta < 1 || current + delta > citation.pageCount) return;
    pager.animateToPage(
      current - 1 + delta,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _readerKey(FocusNode node, KeyEvent event) {
    if (!const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform) ||
        ModalRoute.of(context)?.isCurrent != true ||
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() !=
            null ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _move(delta);
    return KeyEventResult.handled;
  }

  Future<void> _jump() async {
    final input = TextEditingController(text: '$current');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到 PDF 页'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(helperText: '1–${citation.pageCount} 页'),
          onSubmitted: (value) {
            final n = int.tryParse(value);
            if (n != null && n >= 1 && n <= citation.pageCount) {
              Navigator.of(context).pop(n);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(input.text);
              if (n != null && n >= 1 && n <= citation.pageCount) {
                Navigator.of(context).pop(n);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    // The dialog's reverse transition may still use its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (mounted && page != null) pager.jumpToPage(page - 1);
  }

  @override
  void dispose() {
    pager.dispose();
    readerFocus.dispose();
    if (widget.gateway == null) gateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: readerFocus,
    autofocus: true,
    onKeyEvent: _readerKey,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          citation.bookTitle.isEmpty ? citation.title : citation.bookTitle,
        ),
        actions: [
          IconButton(
            tooltip: '跳转页码',
            onPressed: _jump,
            icon: const Icon(Icons.find_in_page_outlined),
          ),
        ],
      ),
      body:
          // PhotoView's axis-aware recognizer claims two-finger scaling before
          // PageView's horizontal drag can steal it; panning still hands off at edges.
          PhotoViewGestureDetectorScope(
            axis: Axis.horizontal,
            child: PageView.builder(
              controller: pager,
              itemCount: citation.pageCount > 0 ? citation.pageCount : 1,
              onPageChanged: (i) => setState(() {
                current = i + 1;
              }),
              itemBuilder: (context, index) {
                final page = index + 1;
                return FutureBuilder<File>(
                  future: _load(page),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                snapshot.error is AiSearchException
                                    ? (snapshot.error as AiSearchException)
                                          .message
                                    : '页图加载失败，请检查网络后重试',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.tonal(
                                onPressed: () => setState(() {
                                  pages.remove(page);
                                }),
                                child: const Text('重新加载'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return PhotoView(
                      key: ValueKey('textbook_page_$page'),
                      imageProvider: FileImage(snapshot.data!),
                      gestureDetectorBehavior: HitTestBehavior.opaque,
                      backgroundDecoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                      ),
                      minScale: PhotoViewComputedScale.contained,
                      initialScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.contained * 5,
                      loadingBuilder: (context, event) =>
                          const Center(child: CircularProgressIndicator()),
                      errorBuilder: (context, error, stack) => Center(
                        child: FilledButton.tonal(
                          onPressed: () async {
                            final key =
                                'textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${page.toString().padLeft(4, '0')}.webp';
                            await pageCache.removeFile(key);
                            if (mounted) {
                              setState(() {
                                pages.remove(page);
                              });
                            }
                          },
                          child: const Text('页图读取失败，重新下载'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: current > 1 ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('PDF 第 $current / ${citation.pageCount} 页'),
                    if (current == citation.pdfPage &&
                        citation.printedPage.isNotEmpty)
                      Text(
                        '书页 ${citation.printedPage}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (current == citation.pdfPage && citation.needsReview)
                      Text(
                        '符号、公式请核对原页',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: current < citation.pageCount ? () => _move(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
