import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/animation.dart';
import '../common/platform_adaptive.dart';
import '../db/data_transfer.dart';
import '../models/bottom_nav_config.dart';
import '../repositories/question_bank_repository.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/daily_plan_page.dart';
import '../screens/my_page.dart';
import '../screens/statistics_page.dart';
import '../services/app_update_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 默认主页为“我的课程”
  late PageController _pageController;
  Map<String, dynamic> updateData = {}; // 更新信息
  // IndexedStack 会包装每个子页；全局键让导航重排/布局切换保留当前页面实例。
  final Map<String, GlobalKey> _tabKeys = {};

  // 当前应用版本号
  late String currentVersion;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    // 先给个默认值，避免 late 未初始化被读到
    currentVersion = "0.0.0";
    // 异步初始化放到单独方法里
    _initAsync();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

    try {
      await BottomNavConfig.loadConfig();
    } catch (_) {}
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

  void _ensurePageController(int targetIndex) {
    if (!_pageController.hasClients) {
      if (_pageController.initialPage != targetIndex) {
        _pageController.dispose();
        _pageController = PageController(initialPage: targetIndex);
      }
    } else {
      if (_pageController.page?.round() != targetIndex) {
        _pageController.jumpToPage(targetIndex);
      }
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });

    if (isDesktopLayout(context)) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
      return;
    }

    if (_pageController.hasClients) {
      final duration = AppAnimation.duration;
      if (duration == Duration.zero) {
        _pageController.jumpToPage(index);
      } else {
        _pageController.animateToPage(
          index,
          duration: duration,
          curve: AppAnimation.curve,
        );
      }
    }
  }

  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  /// 检查应用更新，如果有新版本则弹窗提示
  Future<void> _checkForAppUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    // 用户关闭「接受应用更新」时跳过更新弹窗
    if (!(prefs.getBool('accept_update') ?? true)) return;
    if (!mounted) return;

    final newUpdate = await AppUpdateService().checkUpdate();
    if (newUpdate != null && mounted) {
      await AppUpdateService().showUpdateDialog(context, newUpdate);
    }
  }

  Widget _buildTabWidget(String id, {required bool active}) {
    final key = _tabKeys.putIfAbsent(
      id,
      () => GlobalKey(debugLabel: 'tab_$id'),
    );
    switch (id) {
      case 'subjects':
        return _KeepAliveTab(
          key: key,
          active: active,
          child: const ChoosedSubjectsPage(),
        );
      case 'daily_plan':
        return _KeepAliveTab(
          key: key,
          active: active,
          child: const DailyPlanPage(),
        );
      case 'statistics':
        return _KeepAliveTab(
          key: key,
          active: active,
          child: const StatisticsPage(),
        );
      case 'profile':
      default:
        return _KeepAliveTab(key: key, active: active, child: const MyPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = isDesktopLayout(context);

    return ValueListenableBuilder<List<BottomNavItem>>(
      valueListenable: BottomNavConfig.configNotifier,
      builder: (context, allItems, _) {
        final activeItems = allItems.where((i) => i.enabled).toList();
        final validItems = activeItems.length < 2
            ? BottomNavConfig.getDefaultItems()
            : activeItems;
        final clampedIndex = _selectedIndex.clamp(0, validItems.length - 1);
        _ensurePageController(clampedIndex);
        if (clampedIndex != _selectedIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedIndex = clampedIndex);
              if (_pageController.hasClients) {
                _pageController.jumpToPage(clampedIndex);
              }
            }
          });
        }

        final destinations = validItems.map((item) {
          return NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.title,
          );
        }).toList();

        final railDestinations = validItems.map((item) {
          return NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.title),
          );
        }).toList();

        // 宽屏 IndexedStack 会挂载全部子节点，只在首次访问时挂载业务页面。
        // 窄屏 PageView 保持原有预加载/滑动行为，已访问页继续 KeepAlive。
        final tabPages = [
          for (var i = 0; i < validItems.length; i++)
            _buildTabWidget(
              validItems[i].id,
              active: !isDesktop || i == clampedIndex,
            ),
        ];

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: clampedIndex,
                  onDestinationSelected: _onItemTapped,
                  groupAlignment: -1.0,
                  labelType: NavigationRailLabelType.all,
                  destinations: railDestinations,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: IndexedStack(index: clampedIndex, children: tabPages),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: tabPages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: clampedIndex,
            onDestinationSelected: _onItemTapped,
            destinations: destinations,
          ),
        );
      },
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  final bool active;
  const _KeepAliveTab({super.key, required this.child, required this.active});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  late bool _initialized;

  @override
  void initState() {
    super.initState();
    _initialized = widget.active;
  }

  @override
  void didUpdateWidget(covariant _KeepAliveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 一旦访问过就保留页面，不因切到别的 Tab 重新查询/丢失状态。
    _initialized = _initialized || widget.active;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _initialized ? widget.child : const SizedBox.shrink();
  }
}
