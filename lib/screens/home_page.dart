import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/app_strings.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 默认主页为题库页
  bool isDownloading = false;
  double downloadProgress = 0.00; // 下载进度
  String statusText = '点击按钮下载题库';
  Map<String, dynamic> updateData = {}; // 更新信息

  // 缓存判断是否需要下载的 Future
  late Future<bool> _needToDownloadFuture;
  // 当前应用版本号（请根据实际情况修改）
  final String currentVersion = AppStrings.appVersion;

  @override
  void initState() {
    super.initState();
    _needToDownloadFuture = needToDownload();
    // 如果需要下载，则自动触发下载任务
    _needToDownloadFuture.then((needDownload) {
      if (needDownload) {
        downloadAndExtractZip();
      }
      // 检查应用更新（注意此处依赖于 updateData 已经加载）
      if (updateData.isNotEmpty) {
        checkForAppUpdate();
      }
    });
  }

  // 两个页面对应底部导航栏
  final List<Widget> _screens = [
    ChoosedSubjectsPage(),
    AuthCheckPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// 计算文件的 MD5 值
  Future<String> calculateMd5(File file) async {
    List<int> fileBytes = await file.readAsBytes();
    return md5.convert(fileBytes).toString();
  }

  /// 判断是否需要下载题库，同时加载更新信息
  Future<bool> needToDownload() async {
    if (updateData.isEmpty) {
      final Uri updateUrl = Uri.parse(
        'https://files.melonhu.cn/yibubang/yibubang_update.json',
      );
      final updateResponse = await http.get(
        updateUrl,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept-Charset': 'utf-8',
        },
      );
      if (updateResponse.statusCode != 200) {
        print('请求失败，状态码: ${updateResponse.statusCode}');
        return true;
      }
      // 初始化更新信息
      updateData = jsonDecode(utf8.decode(
        updateResponse.bodyBytes,
      ));
    }

    String appDocDir = await getDatabasesPath();
    String filePath = '$appDocDir/question_data.sqlite.zip';
    File file = File(filePath);

    if (await file.exists()) {
      String fileMd5 = await calculateMd5(file);
      if (fileMd5 == updateData['latest_data_md5']) {
        return false;
      }
      return true;
    }
    return true;
  }

  /// 下载并解压 ZIP 文件
  Future<void> downloadAndExtractZip() async {
    // 再次判断是否需要下载
    if (!await needToDownload()) return;

    setState(() {
      isDownloading = true;
      statusText = '正在下载题库...请将APP保持在前台';
      downloadProgress = 0.00;
    });

    try {
      // Step 1: 获取存储目录并创建下载文件
      String appDocDir = await getDatabasesPath();
      String filePath = '$appDocDir/question_data.sqlite.zip';
      File file = File(filePath);

      // Step 2: 下载 ZIP 文件
      final latestDataUrl = updateData['latest_data_url'];
      var request = http.Request('GET', Uri.parse(latestDataUrl));
      var response = await request.send();

      int totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      var sink = file.openWrite();

      // 使用 forEach 遍历 stream 中的每个 chunk
      await response.stream.forEach((List<int> chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes != 0) {
          setState(() {
            downloadProgress = receivedBytes / totalBytes;
          });
        }
      });

      await sink.flush();
      await sink.close();

      // Step 3: 解压 ZIP 文件
      List<int> bytes = await file.readAsBytes();
      Archive archive = ZipDecoder().decodeBytes(bytes);
      for (var fileInArchive in archive) {
        // 排除无效目录（如 __MACOSX）
        if (fileInArchive.isFile &&
            !fileInArchive.name.startsWith('__MACOSX')) {
          String fileName = fileInArchive.name;
          File extractedFile = File('$appDocDir/$fileName');
          await extractedFile.writeAsBytes(fileInArchive.content as List<int>);
        }
      }

      //// Step 4: 解压后删除 ZIP 文件以节省空间
      //if (await file.exists()) {
      //  await file.delete();
      //}

      setState(() {
        isDownloading = false;
        statusText = '题库下载并解压完成';
        // 下载完成后更新 Future 状态，进入主页
        _needToDownloadFuture = Future.value(false);
      });
    } catch (error) {
      setState(() {
        isDownloading = false;
        statusText = '题库下载失败：$error';
      });
    }
  }

  /// 构建进度指示控件或重新下载按钮
  Widget buildProgress() {
    if (isDownloading) {
      return Column(
        children: [
          CircularProgressIndicator(value: downloadProgress),
          SizedBox(height: 20),
          Text(
            '${(downloadProgress * 100).toStringAsFixed(2)}%',
          ),
        ],
      );
    } else {
      return ElevatedButton(
        onPressed: downloadAndExtractZip,
        child: Text('重新下载'),
      );
    }
  }

  /// 比较版本号函数，返回 1 表示 v1 大于 v2，0 表示相等，-1 表示 v1 小于 v2
  int compareVersions(String v1, String v2) {
    List<int> v1Parts = v1.split('.').map(int.parse).toList();
    List<int> v2Parts = v2.split('.').map(int.parse).toList();
    int length =
        v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
    for (int i = 0; i < length; i++) {
      int part1 = i < v1Parts.length ? v1Parts[i] : 0;
      int part2 = i < v2Parts.length ? v2Parts[i] : 0;
      if (part1 > part2) return 1;
      if (part1 < part2) return -1;
    }
    return 0;
  }

  /// 检查应用更新，如果有新版本则弹窗提示
  void checkForAppUpdate() {
    String latestVersion = updateData["latest_app"] ?? currentVersion;
    if (compareVersions(latestVersion, currentVersion) > 0) {
      // 弹窗提示更新
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('应用更新'),
          content: Text(updateData["update_info"] ?? "检测到新版本，请及时更新"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // 打开默认浏览器，跳转到更新页面
                String url = updateData["latest_app_url"] ??
                    "https://github.com/nanguaguag/yibubang/releases/";
                final Uri uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  print("无法打开更新页面：$url");
                }
              },
              child: Text('前往GitHub下载'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _needToDownloadFuture,
      builder: (context, snapshot) {
        // // 加载中时显示加载指示器
        //if (snapshot.connectionState == ConnectionState.waiting) {
        //  return Scaffold(
        //    body: Center(child: CircularProgressIndicator()),
        //  );
        //}

        // 如果需要下载，则显示下载页面
        if (snapshot.hasData && snapshot.data == true) {
          return Scaffold(
            appBar: AppBar(
              title: Text('需要下载题库'),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(statusText),
                  SizedBox(height: 20),
                  buildProgress(),
                ],
              ),
            ),
          );
        } else {
          // 下载成功或不需要下载，则进入主页
          return Scaffold(
            body: _screens[_selectedIndex],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.book),
                  label: AppStrings.selectedSubjectsTitle,
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: AppStrings.myPageTitle,
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
