import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart'; // for Clipboard

class FullScreenImageView extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const FullScreenImageView({
    Key? key,
    required this.imageUrls,
    required this.initialIndex,
  }) : super(key: key);

  @override
  _FullScreenImageViewState createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  Future<void> _saveImage(String url) async {
    // 下载图片
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载失败')),
      );
      return;
    }

    // 如果是移动端请求权限
    if (Platform.isAndroid || Platform.isIOS) {
      if (!await Permission.photos.request().isGranted) return;
      // 保存到相册
      try {
        await FlutterImageGallerySaver.saveImage(response.bodyBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功保存到相册')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } else {
      // 获取 macOS/Windows/Linux 下用户文档目录（或 Pictures 目录）
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/photo_$_currentIndex.jpg';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 $filePath')),
      );
    }
  }

  Future<void> _copyImageUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('成功复制图像URL')),
    );
  }

  void _onLongPress() {
    final url = widget.imageUrls[_currentIndex];
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('保存图像'),
              onTap: () {
                Navigator.pop(context);
                _saveImage(url);
              },
            ),
            //ListTile(
            //  leading: const Icon(Icons.copy),
            //  title: const Text('复制图像到剪切板'),
            //  onTap: () {
            //    Navigator.pop(context);
            //    _saveImageToClipboard(url);
            //  },
            //),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制图像链接'),
              onTap: () {
                Navigator.pop(context);
                _copyImageUrl(url);
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        onLongPress: _onLongPress,
        child: PhotoViewGallery.builder(
          itemCount: widget.imageUrls.length,
          pageController: _pageController,
          onPageChanged: (idx) => setState(() => _currentIndex = idx),
          builder: (context, index) {
            return PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(widget.imageUrls[index]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
            );
          },
          scrollPhysics: const BouncingScrollPhysics(),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
