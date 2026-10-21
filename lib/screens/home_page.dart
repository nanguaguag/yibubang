import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/app_strings.dart';
import '../db/data_transfer.dart';
import '../repositories/question_bank_repository.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';
import '../screens/statistics_page.dart';
import '../services/app_update_service.dart';

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
      if (mounted) await _checkForAppUpdate();
    } catch (error) {
      debugPrint('应用更新检查失败：$error');
    }
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
                Navigator.of(context).pop();
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
    final prefs = await SharedPreferences.getInstance();
    // 用户关闭「接受应用更新」时跳过更新弹窗
    if (!(prefs.getBool('accept_update') ?? true)) return;
    if (!mounted) return;

    if (prefs.getBool('needToRebuildQuestionCount') ?? false) {
      if (await rebuildQuestionCount()) {
        prefs.setBool('needToRebuildQuestionCount', false);
      }
      if (!mounted) return;
      showRestartDialog(context);
    }

    final newUpdate = await AppUpdateService().checkUpdate();
    if (newUpdate != null && mounted) {
      await AppUpdateService().showUpdateDialog(context, newUpdate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _screens[_selectedIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: AppStrings.selectedSubjectsTitle,
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: AppStrings.statisticsTitle,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: AppStrings.myPageTitle,
          ),
        ],
      ),
    );
  }
}
