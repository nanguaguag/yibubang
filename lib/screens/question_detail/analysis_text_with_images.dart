import 'package:flutter/material.dart';

import '../../models/analysis_image.dart';
import '../../services/analysis_image_loader.dart';
import '../../services/local_textbook_service.dart';
import 'question_header_view.dart';

/// 教材引用先读取真实图片，再打开画廊；旧题库仍兼容约定的图片地址。
class AnalysisTextWithImages extends StatefulWidget {
  final String text;
  final String? storedImages;
  final String legacyBaseUrl;
  final AnalysisImageLoader? imageLoader;
  final Future<LocalTextbookOpenResult> Function(String reference)?
  openLocalReference;

  const AnalysisTextWithImages({
    super.key,
    required this.text,
    this.storedImages,
    required this.legacyBaseUrl,
    this.imageLoader,
    this.openLocalReference,
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
    var localFallbackAttempted = false;
    if (selected.status != AnalysisImageLoadStatus.ready) {
      final pageReference = images[index].reference;
      final reference = pageReference == null
          ? null
          : _localTextbookReference(pageReference, index);
      if (reference != null) {
        localFallbackAttempted = true;
        final result =
            await (widget.openLocalReference ??
                LocalTextbookService().openReference)(reference);
        if (!mounted || generation != _generation) return;
        if (result.status == LocalTextbookOpenStatus.opened) {
          setState(() => _loadingIndex = null);
          return;
        }
      }
      setState(() => _loadingIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !localFallbackAttempted
                ? '图片加载失败，请检查网络连接'
                : (selected.status == AnalysisImageLoadStatus.missing
                      ? '在线图片不存在；无法打开本地教材 PDF'
                      : '图片暂时无法加载；无法打开本地教材 PDF'),
          ),
        ),
      );
      return;
    }

    final otherResults = await Future.wait([
      for (var i = 0; i < images.length; i++)
        if (i != index) _loader.load(images[i]),
    ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    if (!mounted || generation != _generation) return;
    final urls = <String>{selected.url!};
    for (final result in otherResults) {
      if (result.status == AnalysisImageLoadStatus.ready) urls.add(result.url!);
    }
    final galleryUrls = urls.toList();
    setState(() => _loadingIndex = null);
    showFullScreenImage(
      context,
      galleryUrls,
      galleryUrls.indexOf(selected.url!),
    );
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
      if (images[index].urls.isEmpty &&
          _localTextbookReference(images[index].reference ?? '', index) ==
              null) {
        spans.add(_textWithBold(reference));
      } else {
        spans.add(WidgetSpan(child: _imageButton(images, index, reference)));
      }
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
