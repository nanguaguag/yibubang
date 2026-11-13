import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/app_strings.dart';

/// 底栏 / 侧栏导航项配置
class BottomNavItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
  bool enabled;

  BottomNavItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };
}

/// 底栏导航项管理与持久化服务
class BottomNavConfig {
  static const String keyBottomNavConfig = 'bottom_nav_items_config';

  static final ValueNotifier<List<BottomNavItem>> configNotifier =
      ValueNotifier<List<BottomNavItem>>(getDefaultItems());

  static List<BottomNavItem> getDefaultItems() => [
        BottomNavItem(
          id: 'subjects',
          title: AppStrings.selectedSubjectsTitle,
          subtitle: '题库、科目与章节做题目录',
          icon: Icons.book_outlined,
          selectedIcon: Icons.book,
          enabled: true,
        ),
        BottomNavItem(
          id: 'daily_plan',
          title: '每日计划',
          subtitle: 'Anki 记忆曲线与每日抽题打卡',
          icon: Icons.psychology_outlined,
          selectedIcon: Icons.psychology,
          enabled: true,
        ),
        BottomNavItem(
          id: 'ai_search',
          title: 'AI 搜索',
          subtitle: '医学知识检索、解释与追问',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
        ),
        BottomNavItem(
          id: 'statistics',
          title: AppStrings.statisticsTitle,
          subtitle: '做题数据、正确率与历史流水统计',
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights,
          enabled: true,
        ),
        BottomNavItem(
          id: 'profile',
          title: AppStrings.myPageTitle,
          subtitle: '个人中心、账号与偏好设置',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          enabled: true,
        ),
      ];

  /// 从 SharedPreferences 加载配置
  static Future<List<BottomNavItem>> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyBottomNavConfig);
    final defaults = getDefaultItems();
    if (raw == null || raw.isEmpty) {
      configNotifier.value = defaults;
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw) as List;
      final Map<String, bool> enabledMap = {};
      final List<String> order = [];

      for (final item in decoded) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final enabled = item['enabled'] == true;
          if (id.isNotEmpty) {
            order.add(id);
            enabledMap[id] = enabled;
          }
        }
      }

      final List<BottomNavItem> result = [];
      // 按照用户保存的顺序添加
      for (final id in order) {
        final found = defaults.where((d) => d.id == id).firstOrNull;
        if (found != null) {
          found.enabled = enabledMap[id] ?? true;
          result.add(found);
        }
      }
      // 补充可能新增的默认项
      for (final d in defaults) {
        if (!result.any((r) => r.id == d.id)) {
          // Place newly introduced tabs beside their default neighbour while
          // retaining the saved order and enabled state of existing tabs.
          final before = defaults.skip(defaults.indexOf(d) + 1)
              .map((item) => result.indexWhere((r) => r.id == item.id))
              .where((index) => index >= 0).firstOrNull;
          result.insert(before ?? result.length, d);
        }
      }

      // 保证至少有两个启用的项（Material 3 NavigationBar 强制 destinations.length >= 2）
      while (result.where((item) => item.enabled).length < 2) {
        for (final item in result) {
          if (!item.enabled) {
            item.enabled = true;
            break;
          }
        }
      }

      configNotifier.value = result;
      return result;
    } catch (_) {
      configNotifier.value = defaults;
      return defaults;
    }
  }

  /// 保存配置
  static Future<void> saveConfig(List<BottomNavItem> items) async {
    // 确保至少保留两个启用的 Tab（符合 Material 3 NavigationBar 原生契约）
    while (items.where((item) => item.enabled).length < 2) {
      for (final item in items) {
        if (!item.enabled) {
          item.enabled = true;
          break;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((s) => s.toJson()).toList();
    await prefs.setString(keyBottomNavConfig, jsonEncode(jsonList));
    configNotifier.value = List.from(items);
  }

  /// 恢复默认设置
  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyBottomNavConfig);
    configNotifier.value = getDefaultItems();
  }
}
