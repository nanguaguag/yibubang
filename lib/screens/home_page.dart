import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/database_helper.dart';
import '../common/app_strings.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';
import '../db/data_transfer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<bool> checkTransferScuess() async {
  UserDBHelper userdb = UserDBHelper();
  return !((await userdb.isTableEmpty('Question')) ||
      (await userdb.isTableEmpty('Chapter')) ||
      (await userdb.isTableEmpty('Subject')));
}

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

  // 当前应用版本号
  late String currentVersion;
  // 缓存判断是否需要下载的 Future
  late bool needToDownload;
  //late Future<bool> _needToDownloadFuture;

  @override
  void initState() {
    super.initState();
    // 先给个默认值，避免 late 未初始化被读到
    currentVersion = "0.0.0";
    needToDownload = false;
    // 异步初始化放到单独方法里
    _initAsync();
  }

  Future<void> _initAsync() async {
    final info = await PackageInfo.fromPlatform();

    debugPrint("App 名称: ${info.appName}");
    debugPrint("包名: ${info.packageName}");
    debugPrint("版本号: ${info.version}");
    debugPrint("构建号: ${info.buildNumber}");

    // 如果这个 async 结束时页面已经销毁，直接 return
    if (!mounted) return;

    setState(() {
      currentVersion = info.version;
    });

    final needDownload = await _needToDownload();

    if (!mounted) return;

    // 如果需要下载，则自动触发下载任务
    if (needDownload) {
      debugPrint("需要下载，downloading...");
      _downloadAndExtractZip();
    }
    // 检查应用更新（注意此处依赖于 updateData 已经加载）
    // 如果 updateData 是异步加载来的，你需要确保它在这里之前已经加载完
    if (updateData.isNotEmpty) {
      _checkForAppUpdate();
    }
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
  Future<String> _calculateMd5(File file) async {
    List<int> fileBytes = await file.readAsBytes();
    return md5.convert(fileBytes).toString();
  }

  /// 判断是否需要下载题库，同时加载更新信息
  Future<bool> _needToDownload() async {
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
        debugPrint('请求失败，状态码: ${updateResponse.statusCode}');
        return true;
      }
      // 初始化更新信息
      updateData = jsonDecode(utf8.decode(
        updateResponse.bodyBytes,
      ));
    }

    // Step 1: 获取存储目录并创建下载文件
    String appDocDir = await getDatabasesPath();
    String filePath = '$appDocDir/question_data.sqlite.zip';
    File file = File(filePath);

    final dataForVersion = updateData['data_for_version'];

    // 如果远程JSON文件包含当前版本的数据库信息，则进行MD5校验
    if (dataForVersion is Map && dataForVersion.containsKey(currentVersion)) {
      final dataMd5 = dataForVersion[currentVersion]["md5"];
      debugPrint("目标数据库md5: $dataMd5");
      if (await file.exists()) {
        String fileMd5 = await _calculateMd5(file);
        debugPrint("本地数据库md5: $fileMd5");
        if (fileMd5 == dataMd5) {
          return false;
        }
        return true;
      }
      return true;
    } else {
      // 否则跳过下载
      debugPrint("当前版本无对应题库，跳过下载");
      return false;
    }
  }

  /// 下载并解压 ZIP 文件
  Future<void> _downloadAndExtractZip() async {
    // 再次判断是否需要下载
    if (!await _needToDownload()) return;

    setState(() {
      needToDownload = true;
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
      final dataUrl = updateData['data_for_version'][currentVersion]["url"] ??
          updateData['latest_data_url'];

      var request = http.Request('GET', Uri.parse(dataUrl));
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
        needToDownload = false;
      });
    } catch (error) {
      setState(() {
        isDownloading = false;
        statusText = '题库下载失败：$error';
      });
    }
  }

  /// 构建进度指示控件或重新下载按钮
  Widget _buildProgress() {
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
        onPressed: _downloadAndExtractZip,
        child: Text('重新下载'),
      );
    }
  }

  /// 比较版本号函数，返回 1 表示 v1 大于 v2，0 表示相等，-1 表示 v1 小于 v2
  int _compareVersions(String v1, String v2) {
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

  /// 显示加载框（禁止用户交互）
  void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击背景关闭
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text("正在迁移数据，请稍候...")),
            ],
          ),
        );
      },
    );
  }

  /// 显示“请重启”提示框
  void showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点空白关闭
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("完成"),
          content: const Text("题目对错数量统计完成，建议重启应用以完成更新"),
          actions: [
            TextButton(
              onPressed: () {
                // 用户确认后退出 app 或关闭对话框
                // SystemNavigator.pop(); // 用这个退出 app
                Navigator.of(context).pop(); // 或者只是关闭对话框
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  /// 检查应用更新，如果有新版本则弹窗提示
  void _checkForAppUpdate() async {
    String latestVersion = updateData["latest_app"] ?? currentVersion;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('needToRebuildQuestionCount') ?? false) {
      if (await rebuildQuestionCount()) {
        // 重算成功
        prefs.setBool('needToRebuildQuestionCount', false);
      }
      //Navigator.of(context, rootNavigator: true).pop();
      showRestartDialog(context);
    }
    if (_compareVersions(latestVersion, currentVersion) > 0) {
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
                  debugPrint("无法打开更新页面：$url");
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
    // 如果需要下载，则显示下载页面
    if (needToDownload) {
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
              _buildProgress(),
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
  }
}
