import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../common/app_strings.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';
import '../screens/statistics_page.dart';
import '../db/data_transfer.dart';
import '../repositories/question_bank_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 默认主页为“我的课程”
  Map<String, dynamic> updateData = {}; // 更新信息

  // 当前应用版本号
  late String currentVersion;

  @override
  void initState() {
    super.initState();
    // 先给个默认值，避免 late 未初始化被读到
    currentVersion = "0.0.0";
    // 异步初始化放到单独方法里
    _initAsync();
  }

  Future<void> _initAsync() async {
    final swInit = Stopwatch()..start();
    // 获取应用信息
    final info = await PackageInfo.fromPlatform();

    // 如果这个 async 结束时页面已经销毁，直接 return
    if (!mounted) return;

    setState(() {
      currentVersion = info.version;
    });

    // 题库目录初始化可能正在 main() 的后台任务中执行，这里复用同一个 Future，
    // 不会再次扫描和校验所有题库。
    try {
      await QuestionBankRepository().initialize();
    } catch (error) {
      debugPrint('题库目录初始化失败：$error');
    }
    debugPrint('[startup] HomePage 题库目录初始化(${swInit.elapsedMilliseconds}ms)');
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('needToRebuildQuestionCount') ?? false) {
      try {
        await rebuildQuestionCount(
          bankId: prefs.getString('activeBankId') ?? 'dental_final',
        );
        await prefs.setBool('needToRebuildQuestionCount', false);
      } catch (error) {
        debugPrint('题库统计重建暂未完成：$error');
      }
    }

    try {
      await _loadAppUpdateData();
      if (mounted) await _checkForAppUpdate();
    } catch (error) {
      debugPrint('应用更新清单获取失败：$error');
    }
  }

  Future<void> _loadAppUpdateData() async {
    final response = await http.get(
      Uri.parse('https://files.melonhu.cn/yibubang/yibubang_update.json'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept-Charset': 'utf-8',
      },
    ).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw HttpException('应用更新清单请求失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('应用更新清单格式不正确');
    }
    updateData = decoded;
  }

  // 三个页面对应底部导航栏
  final List<Widget> _screens = [
    ChoosedSubjectsPage(),
    StatisticsPage(),
    AuthCheckPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
  Future<void> _checkForAppUpdate() async {
    if (updateData.isEmpty) return;
    String latestVersion = updateData["latest_app"] ?? currentVersion;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 用户关闭「接受应用更新」时跳过更新弹窗
    if (!(prefs.getBool('accept_update') ?? true)) return;
    if (!mounted) return;

    if (prefs.getBool('needToRebuildQuestionCount') ?? false) {
      if (await rebuildQuestionCount()) {
        // 重算成功
        prefs.setBool('needToRebuildQuestionCount', false);
      }
      if (!mounted) return;
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
            icon: Icon(Icons.insights),
            label: AppStrings.statisticsTitle,
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
