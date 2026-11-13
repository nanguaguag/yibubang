import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/ai_search.dart';
import '../services/textbook_client.dart';

/// Fetch a small page asset only when the result card is built in the viewport.
class TextbookThumbnail extends StatefulWidget {
  static final cache = CacheManager(
    Config(
      'textbook-thumbnails-v1',
      stalePeriod: const Duration(days: 180),
      maxNrOfCacheObjects: 300,
    ),
  );
  final AiCitation citation;
  final TextbookGateway gateway;
  final double width;
  const TextbookThumbnail({
    super.key,
    required this.citation,
    required this.gateway,
    this.width = 84,
  });
  @override
  State<TextbookThumbnail> createState() => _TextbookThumbnailState();
}

class _TextbookThumbnailState extends State<TextbookThumbnail> {
  CacheManager get cache => TextbookThumbnail.cache;
  late Future<File?> image;
  @override
  void initState() {
    super.initState();
    image = _load();
  }

  @override
  void didUpdateWidget(covariant TextbookThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation.bookId != widget.citation.bookId ||
        oldWidget.citation.sourceVersion != widget.citation.sourceVersion ||
        oldWidget.citation.pdfPage != widget.citation.pdfPage) {
      image = _load();
    }
  }

  Future<File?> _load() async {
    final c = widget.citation;
    final key =
        'textbooks/${c.bookId}/${c.sourceVersion}/thumbnails/${c.pdfPage.toString().padLeft(4, '0')}.webp';
    final cached = await cache.getFileFromCache(key);
    if (cached != null && await cached.file.exists()) return cached.file;
    final signed = await widget.gateway.thumbnail(c);
    if (signed['url'] is! String) return null;
    return cache.getSingleFile(signed['url'], key: key);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${widget.citation.bookTitle}第${widget.citation.pdfPage}页缩略图',
    image: true,
    child: Container(
      width: widget.width,
      height: widget.width * 1.4,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: FutureBuilder<File?>(
        future: image,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.file(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.menu_book_outlined),
            );
          }
          if (snapshot.hasError) {
            return InkWell(
              onTap: () => setState(() => image = _load()),
              child: const Icon(Icons.refresh_rounded),
            );
          }
          return const Center(child: Icon(Icons.menu_book_outlined));
        },
      ),
    ),
  );
}
