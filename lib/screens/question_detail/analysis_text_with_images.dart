import 'package:flutter/material.dart';

import '../../common/adaptive_route.dart';
import '../../models/analysis_image.dart';
import '../../services/ai_search_client.dart';
import '../../services/analysis_image_loader.dart';
import '../../services/cloud_textbook_fallback_service.dart';
import '../../services/local_textbook_service.dart';
import '../../services/textbook_client.dart';
import '../../widgets/image_view.dart';
import '../textbook_reader_page.dart';
import '../textbook_search_page.dart';

typedef AnalysisGalleryOpener =
    Future<void> Function(
      BuildContext context,
      List<String> imageUrls,
      int initialIndex,
      List<FullScreenImagePageFallback> pageFallbacks,
      Future<void> Function(
        BuildContext viewerContext,
        int pageIndex,
        FullScreenImagePageFallback fallback,
      )
      onCloudTextbookFallback,
    );

/// 教材引用先读取真实图片，再打开画廊；图片失效或需要核对原书时支持回退云端教材。
class AnalysisTextWithImages extends StatefulWidget {
  final String text;
  final String? storedImages;
  final String legacyBaseUrl;
  final String? fallbackQuery;
  final Future<String?> Function()? resolveSubjectName;
  final AnalysisImageLoader? imageLoader;
  final Future<LocalTextbookOpenResult> Function(String reference)?
  openLocalReference;
  final TextbookGateway? textbookGateway;
  final AnalysisGalleryOpener? openGallery;

  const AnalysisTextWithImages({
    super.key,
    required this.text,
    this.storedImages,
    required this.legacyBaseUrl,
    this.fallbackQuery,
    this.resolveSubjectName,
    this.imageLoader,
    this.openLocalReference,
    this.textbookGateway,
    this.openGallery,
  });

  @override
  State<AnalysisTextWithImages> createState() => _AnalysisTextWithImagesState();
}

class _AnalysisTextWithImagesState extends State<AnalysisTextWithImages> {
  late AnalysisImageLoader _loader;
  int? _loadingIndex;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loader = widget.imageLoader ?? AnalysisImageLoader();
  }

  @override
  void didUpdateWidget(covariant AnalysisTextWithImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text ||
        widget.storedImages != oldWidget.storedImages ||
        widget.legacyBaseUrl != oldWidget.legacyBaseUrl ||
        widget.imageLoader != oldWidget.imageLoader) {
      _generation++;
      _loadingIndex = null;
      _loader = widget.imageLoader ?? AnalysisImageLoader();
    }
  }

  Future<void> _openImages(List<AnalysisImage> images, int index) async {
    if (_loadingIndex != null) return;
    final generation = _generation;
    setState(() => _loadingIndex = index);
    final selected = await _loader.load(images[index]);
    if (!mounted || generation != _generation) return;

    if (selected.status != AnalysisImageLoadStatus.ready) {
      final pageReference = images[index].reference;
      final reference = pageReference == null
          ? null
          : _localTextbookReference(pageReference, index);
      if (reference != null) {
        final result =
            await (widget.openLocalReference ??
                LocalTextbookService().openReference)(reference);
        if (!mounted || generation != _generation) return;
        if (result.status == LocalTextbookOpenStatus.opened) {
          setState(() => _loadingIndex = null);
          return;
        }
      }
    }

    final galleryUrls = <String>[];
    final pageFallbacks = <FullScreenImagePageFallback>[];
    for (var i = 0; i < images.length; i++) {
      final result = i == index ? selected : null;
      final resolvedUrl = result?.status == AnalysisImageLoadStatus.ready
          ? result!.url!
          : (images[i].urls.isNotEmpty ? images[i].urls.first : '');
      final failed = result != null &&
          result.status != AnalysisImageLoadStatus.ready;
      final failureMessage = switch (result?.status) {
        AnalysisImageLoadStatus.missing => '原教材图片已失效或已被移除',
        AnalysisImageLoadStatus.unavailable => '图片加载失败，请检查网络连接',
        _ => null,
      };
      galleryUrls.add(resolvedUrl);
      pageFallbacks.add(
        FullScreenImagePageFallback(
          reference: images[i].reference,
          searchQuery: CloudTextbookFallbackService.extractSearchQuery(
            widget.text,
            i,
            fallbackText: widget.fallbackQuery,
          ),
          bookHint: CloudTextbookFallbackService.extractBookHint(
            images[i].reference,
          ),
          initiallyFailed: failed,
          failureMessage: failureMessage,
        ),
      );
    }

    setState(() => _loadingIndex = null);
    final opener = widget.openGallery ?? _defaultOpenGallery;
    await opener(
      context,
      galleryUrls,
      index,
      pageFallbacks,
      _openCloudTextbook,
    );
  }

  Future<void> _defaultOpenGallery(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
    List<FullScreenImagePageFallback> pageFallbacks,
    Future<void> Function(
      BuildContext viewerContext,
      int pageIndex,
      FullScreenImagePageFallback fallback,
    )
    onCloudTextbookFallback,
  ) {
    return Navigator.push<void>(
      context,
      adaptivePageRoute(
        builder: (_) => FullScreenImageView(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          pageFallbacks: pageFallbacks,
          onCloudTextbookFallback: onCloudTextbookFallback,
        ),
      ),
    );
  }

  Future<void> _openCloudTextbook(
    BuildContext viewerContext,
    int pageIndex,
    FullScreenImagePageFallback fallback,
  ) async {
    final subjectName = await widget.resolveSubjectName?.call();
    if (!viewerContext.mounted) return;
    final query = (fallback.searchQuery ?? '').trim().isNotEmpty
        ? fallback.searchQuery!.trim()
        : CloudTextbookFallbackService.cleanFallbackText(
            widget.fallbackQuery ?? '',
          );

    if (query.isEmpty) {
      await Navigator.of(viewerContext).push(
        adaptivePageRoute(
          builder: (_) => TextbookSearchPage(gateway: widget.textbookGateway),
        ),
      );
      return;
    }

    try {
      final outcome = await CloudTextbookFallbackService().search(
        query: query,
        subjectName: subjectName,
        bookHint: fallback.bookHint,
        gateway: widget.textbookGateway,
      );
      if (!viewerContext.mounted) return;

      final first = outcome.firstCitation;
      if (first != null) {
        await Navigator.of(viewerContext).push(
          adaptivePageRoute(
            builder: (_) => TextbookReaderPage(
              citation: first,
              gateway: widget.textbookGateway,
              searchHits: outcome.hits,
              searchQuery: outcome.query,
            ),
          ),
        );
        return;
      }

      final matchedBookIds = outcome.matchedBooks
          .map((b) => b['book_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      ScaffoldMessenger.of(viewerContext).showSnackBar(
        SnackBar(
          content: const Text('未在云端教材中检索到匹配内容'),
          action: SnackBarAction(
            label: '手动搜索',
            onPressed: () {
              if (!viewerContext.mounted) return;
              Navigator.of(viewerContext).push(
                adaptivePageRoute(
                  builder: (_) => TextbookSearchPage(
                    gateway: widget.textbookGateway,
                    initialQuery: outcome.query,
                    initialBookIds: matchedBookIds,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!viewerContext.mounted) return;
      final message = error is AiSearchException
          ? error.message
          : '云端教材检索失败：$error';
      ScaffoldMessenger.of(viewerContext).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String? _localTextbookReference(String pageReference, int index) {
    final page = RegExp(
      r'P\d+',
      caseSensitive: false,
    ).firstMatch(pageReference);
    if (page == null) return null;
    final title = RegExp(
      r'(?:第?[0-9一二三四五六七八九十]+版)?系统解剖学\s*'
      '${RegExp.escape(page.group(0)!)}'
      r'(?!\d)',
      caseSensitive: false,
    );
    final matches = analysisImageReferencePattern
        .allMatches(widget.text)
        .toList();
    if (index >= matches.length) return null;
    final citation = matches[index];
    final from = citation.start > 50 ? citation.start - 50 : 0;
    final to = citation.end + 16 < widget.text.length
        ? citation.end + 16
        : widget.text.length;
    final nearbyText = widget.text.substring(from, to);
    final match = title.firstMatch(nearbyText);
    return match?.group(0)?.replaceAll(RegExp(r'\s+'), ' ');
  }

  Widget _imageButton(List<AnalysisImage> images, int index, String label) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: Colors.deepOrange,
      ),
      onPressed: _loadingIndex == null
          ? () => _openImages(images, index)
          : null,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          if (_loadingIndex == index)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.photo, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = analysisImages(
      text: widget.text,
      storedImages: widget.storedImages,
      legacyBaseUrl: widget.legacyBaseUrl,
    );
    final spans = <InlineSpan>[];
    var end = 0;
    var index = 0;
    for (final match in analysisImageReferencePattern.allMatches(widget.text)) {
      spans.add(_textWithBold(widget.text.substring(end, match.start)));
      final reference = match.group(0)!;
      spans.add(WidgetSpan(child: _imageButton(images, index, reference)));
      end = match.end;
      index++;
    }
    spans.add(_textWithBold(widget.text.substring(end)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: spans)),
        for (var i = index; i < images.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _imageButton(images, i, '查看配图'),
          ),
      ],
    );
  }

  TextSpan _textWithBold(String text) {
    final pattern = RegExp(r'（[A-Z](对|错)(，为本题正确答案)?）');
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return TextSpan(
      style: const TextStyle(fontSize: 16, height: 1.8),
      children: spans,
    );
  }
}
