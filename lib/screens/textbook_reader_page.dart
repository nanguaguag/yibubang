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
  final List<TextbookHit>? searchHits;
  final String? searchQuery;
  const TextbookReaderPage({
    super.key,
    required this.citation,
    this.gateway,
    this.cacheManager,
    this.searchHits,
    this.searchQuery,
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
  late PageController pager;
  late AiCitation _citation;
  late int current;
  final readerFocus = FocusNode(debugLabel: 'textbook reader');
  final Map<int, Future<File>> pages = {};
  AiCitation get citation => _citation;
  BaseCacheManager get pageCache => widget.cacheManager ?? cache;
  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? TextbookClient();
    _citation = widget.citation;
    current = citation.pdfPage.clamp(
      1,
      citation.pageCount > 0 ? citation.pageCount : 1,
    );
    pager = PageController(initialPage: current - 1);
  }

  void _switchCitation(AiCitation nextCitation) {
    final nextPage = nextCitation.pdfPage.clamp(
      1,
      nextCitation.pageCount > 0 ? nextCitation.pageCount : 1,
    );
    if (nextCitation.bookId == _citation.bookId &&
        nextCitation.sourceVersion == _citation.sourceVersion) {
      setState(() {
        _citation = nextCitation;
        current = nextPage;
      });
      pager.jumpToPage(nextPage - 1);
      return;
    }
    final oldPager = pager;
    setState(() {
      pages.clear();
      _citation = nextCitation;
      current = nextPage;
      pager = PageController(initialPage: nextPage - 1);
    });
    oldPager.dispose();
  }

  Future<void> _showSearchHitsSheet() async {
    final hits = widget.searchHits;
    if (hits == null || hits.length <= 1) return;
    final selected = await showModalBottomSheet<AiCitation>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '匹配到 ${hits.length} 条云端教材结果',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: hits.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final hit = hits[index];
                  final c = hit.citation;
                  final isCurrent =
                      c.bookId == citation.bookId && c.pdfPage == current;
                  return ListTile(
                    selected: isCurrent,
                    title: Text(
                      '《${c.bookTitle.isEmpty ? c.title : c.bookTitle}》 · PDF 第 ${c.pdfPage} 页',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: hit.snippet.isNotEmpty
                        ? Text(
                            hit.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isCurrent ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.of(sheetContext).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      _switchCitation(selected);
    }
  }

  Future<File> _load(int page) => pages.putIfAbsent(page, () async {
    final key =
        'textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${page.toString().padLeft(4, '0')}.webp';
    final existing = await pageCache.getFileFromCache(key);
    if (existing != null && await existing.file.exists()) return existing.file;
    final signed = await gateway.page(citation, page);
    try {
      return await pageCache.getSingleFile(signed['url'] as String, key: key);
    } catch (_) {
      gateway.invalidateSession();
      final refreshed = await gateway.page(citation, page);
      return pageCache.getSingleFile(refreshed['url'] as String, key: key);
    }
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
          if (widget.searchHits != null && widget.searchHits!.length > 1)
            IconButton(
              tooltip: '切换检索结果',
              onPressed: _showSearchHitsSheet,
              icon: const Icon(Icons.format_list_bulleted_rounded),
            ),
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
