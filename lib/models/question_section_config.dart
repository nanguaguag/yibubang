import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 题目详情页板块配置项
class QuestionSectionItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  bool enabled;

  QuestionSectionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };
}

/// 题目详情页板块管理及持久化服务
class QuestionSectionConfig {
  static const String keySectionsConfig = 'question_sections_config';

  static final ValueNotifier<List<QuestionSectionItem>> configNotifier =
      ValueNotifier<List<QuestionSectionItem>>(getDefaultSections());

  static List<QuestionSectionItem> getDefaultSections() => [
        QuestionSectionItem(
          id: 'answer_stat',
          title: '答案与统计',
          subtitle: '正确与用户答案、难度答题统计、题目来源',
          icon: Icons.bar_chart,
          enabled: true,
        ),
        QuestionSectionItem(
          id: 'restore',
          title: '考点还原',
          subtitle: '考点出处教材定位与原题还原',
          icon: Icons.location_on_outlined,
          enabled: true,
        ),
        QuestionSectionItem(
          id: 'explain',
          title: '答案解析',
          subtitle: '题目官方详细文字解析',
          icon: Icons.lightbulb_outlined,
          enabled: true,
        ),
        QuestionSectionItem(
          id: 'label',
          title: '题目标签',
          subtitle: '医考帮官方考点与题目质量投票标签',
          icon: Icons.local_offer_outlined,
          enabled: true,
        ),
        QuestionSectionItem(
          id: 'note',
          title: '我的笔记',
          subtitle: '题目个人文本与图片笔记',
          icon: Icons.edit_note,
          enabled: true,
        ),
        QuestionSectionItem(
          id: 'comment',
          title: '讨论评论',
          subtitle: '考友讨论区、热门精彩评论与回复',
          icon: Icons.comment_outlined,
          enabled: true,
        ),
      ];

  /// 从 SharedPreferences 加载配置
  static Future<List<QuestionSectionItem>> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keySectionsConfig);
    final defaults = getDefaultSections();
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

      final List<QuestionSectionItem> result = [];
      // 按照用户保存的顺序添加
      for (final id in order) {
        final found = defaults.where((d) => d.id == id).firstOrNull;
        if (found != null) {
          found.enabled = enabledMap[id] ?? true;
          result.add(found);
        }
      }
      // 补充可能新增的默认板块
      for (final d in defaults) {
        if (!result.any((r) => r.id == d.id)) {
          result.add(d);
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
  static Future<void> saveConfig(List<QuestionSectionItem> sections) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = sections.map((s) => s.toJson()).toList();
    await prefs.setString(keySectionsConfig, jsonEncode(jsonList));
    configNotifier.value = List.from(sections);
  }

  /// 恢复默认设置
  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySectionsConfig);
    configNotifier.value = getDefaultSections();
  }
}
