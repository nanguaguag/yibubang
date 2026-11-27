import 'dart:io' show Platform, File;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'common/app_network_image.dart';

/// 每一页全屏图片关联的教材回退上下文。
class FullScreenImagePageFallback {
  final String? reference;
  final String? searchQuery;
  final String? bookHint;
  final bool initiallyFailed;
  final String? failureMessage;

  const FullScreenImagePageFallback({
    this.reference,
    this.searchQuery,
    this.bookHint,
    this.initiallyFailed = false,
    this.failureMessage,
  });
}

class FullScreenImageView extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final List<FullScreenImagePageFallback>? pageFallbacks;
  final Future<void> Function(
    BuildContext context,
    int pageIndex,
    FullScreenImagePageFallback fallback,
  )?
  onCloudTextbookFallback;

  const FullScreenImageView({
    super.key,
    required this.imageUrls,
    required this.initialIndex,
    this.pageFallbacks,
    this.onCloudTextbookFallback,
  });

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  late PageController _pageController;
  late int _currentIndex;
  final Set<int> _failedPages = <int>{};
  final Map<int, int> _retryTokens = <int, int>{};
  bool _searchingTextbook = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.imageUrls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    final fallbacks = widget.pageFallbacks;
    if (fallbacks != null) {
      for (var i = 0; i < fallbacks.length; i++) {
        if (fallbacks[i].initiallyFailed) {
          _failedPages.add(i);
        }
      }
    }
  }

  FullScreenImagePageFallback? _fallbackFor(int index) {
    final fallbacks = widget.pageFallbacks;
    if (fallbacks == null || index < 0 || index >= fallbacks.length) {
      return null;
    }
    return fallbacks[index];
  }

  bool get _hasCloudFallback =>
      widget.onCloudTextbookFallback != null &&
      _fallbackFor(_currentIndex) != null;

  bool get _isCurrentPageFailed => _failedPages.contains(_currentIndex);

  void _markPageFailed(int index) {
    if (_failedPages.contains(index)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failedPages.contains(index)) {
        setState(() => _failedPages.add(index));
      }
    });
  }

  Future<void> _retryPage(int index) async {
    if (index < 0 || index >= widget.imageUrls.length) return;
    final url = widget.imageUrls[index].trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      try {
        await CachedNetworkImage.evictFromCache(url);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _failedPages.remove(index);
      _retryTokens[index] = (_retryTokens[index] ?? 0) + 1;
    });
  }

  Future<void> _triggerCloudTextbook(int index) async {
    final callback = widget.onCloudTextbookFallback;
    final fallback = _fallbackFor(index);
    if (callback == null || fallback == null || _searchingTextbook) return;
    setState(() => _searchingTextbook = true);
    try {
      await callback(context, index, fallback);
    } finally {
      if (mounted) {
        setState(() => _searchingTextbook = false);
      }
    }
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return AppNetworkImage.provider(url);
    }
    final file = File(url);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return AppNetworkImage.provider(url);
  }

  Future<void> _saveImage(String url) async {
    // 读取或下载图片
    final List<int> bytes;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败')),
        );
        return;
      }
      bytes = response.bodyBytes;
    } else {
      final file = File(url);
      if (!file.existsSync()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
        return;
      }
      bytes = await file.readAsBytes();
    }

    // 如果是移动端请求权限
    if (Platform.isAndroid || Platform.isIOS) {
      if (!await Permission.photos.request().isGranted) return;
      // 保存到相册
      try {
        await FlutterImageGallerySaver.saveImage(Uint8List.fromList(bytes));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('成功保存到相册')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } else {
      // 获取 macOS/Windows/Linux 下用户文档目录（或 Pictures 目录）
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/photo_$_currentIndex.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 $filePath')),
      );
    }
  }

  Future<void> _copyImageUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('成功复制图像URL')),
    );
  }

  void _onLongPress() {
    if (_isCurrentPageFailed) return;
    final url = widget.imageUrls[_currentIndex];
    if (url.trim().isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('保存图像'),
              onTap: () {
                Navigator.pop(context);
                _saveImage(url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制图像链接'),
              onTap: () {
                Navigator.pop(context);
                _copyImageUrl(url);
              },
            ),
            if (_hasCloudFallback)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('在医不帮云端教材中查看'),
                onTap: () {
                  Navigator.pop(context);
                  _triggerCloudTextbook(_currentIndex);
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureView(BuildContext context, int index) {
    final fallback = _fallbackFor(index);
    final hasUrl =
        index >= 0 &&
        index < widget.imageUrls.length &&
        widget.imageUrls[index].trim().isNotEmpty;
    final message =
        fallback?.failureMessage ??
        (hasUrl ? '图片加载失败，请检查网络连接' : '原教材图片不存在');
    final canSearchCloud =
        widget.onCloudTextbookFallback != null && fallback != null;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => Navigator.pop(context),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  size: 54,
                  color: Colors.white70,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                if (canSearchCloud) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _searchingTextbook
                        ? null
                        : () => _triggerCloudTextbook(index),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('在医不帮云端教材中查看'),
                  ),
                ],
                if (hasUrl) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    onPressed: _searchingTextbook
                        ? null
                        : () => _retryPage(index),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新加载'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopRightMenu(BuildContext context) {
    final url = widget.imageUrls[_currentIndex].trim();
    return Positioned(
      top: 8,
      right: 12,
      child: SafeArea(
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: PopupMenuButton<String>(
            tooltip: '更多选项',
            icon: _searchingTextbook
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.more_horiz_rounded, color: Colors.white),
            enabled: !_searchingTextbook,
            onSelected: (value) {
              switch (value) {
                case 'cloud_textbook':
                  _triggerCloudTextbook(_currentIndex);
                  break;
                case 'save_image':
                  _saveImage(url);
                  break;
                case 'copy_url':
                  _copyImageUrl(url);
                  break;
              }
            },
            itemBuilder: (context) => [
              if (_hasCloudFallback)
                const PopupMenuItem<String>(
                  value: 'cloud_textbook',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('在医不帮云端教材中查看'),
                    ],
                  ),
                ),
              if (url.isNotEmpty) ...[
                const PopupMenuItem<String>(
                  value: 'save_image',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save_alt, size: 20),
                      SizedBox(width: 10),
                      Text('保存图像'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'copy_url',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 20),
                      SizedBox(width: 10),
                      Text('复制图像链接'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _isCurrentPageFailed ? null : () => Navigator.pop(context),
            onLongPress: _onLongPress,
            child: PhotoViewGallery.builder(
              itemCount: widget.imageUrls.length,
              pageController: _pageController,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              builder: (context, index) {
                final url = widget.imageUrls[index].trim();
                if (_failedPages.contains(index) || url.isEmpty) {
                  return PhotoViewGalleryPageOptions.customChild(
                    disableGestures: true,
                    child: _buildFailureView(context, index),
                  );
                }
                final retryToken = _retryTokens[index] ?? 0;
                return PhotoViewGalleryPageOptions(
                  key: ValueKey('gallery_${index}_$retryToken'),
                  imageProvider: _getImageProvider(url),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  errorBuilder: (context, error, stackTrace) {
                    _markPageFailed(index);
                    return _buildFailureView(context, index);
                  },
                );
              },
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
          ),
          if (!_isCurrentPageFailed && _hasCloudFallback)
            _buildTopRightMenu(context),
          if (_searchingTextbook)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 14),
                        Text(
                          '正在云端教材中检索...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
