import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

class ThemeController extends GetxController {
  // 定义三种主题模式：Light, Dark, System
  var themeMode = ThemeMode.system.obs;

  // 切换主题模式
  void toggleTheme() async {
    if (themeMode.value == ThemeMode.light) {
      themeMode.value = ThemeMode.dark;
    } else if (themeMode.value == ThemeMode.dark) {
      themeMode.value = ThemeMode.system;
    } else {
      themeMode.value = ThemeMode.light;
    }

    // 使用 GetX 改变应用的主题模式
    Get.changeThemeMode(themeMode.value);
    debugPrint('Theme changed to: ${themeMode.value}');

    // 保存当前主题模式到 SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String themeString;
    switch (themeMode.value) {
      case ThemeMode.light:
        themeString = 'light';
        break;
      case ThemeMode.dark:
        themeString = 'dark';
        break;
      case ThemeMode.system:
        themeString = 'system';
        break;
    }
    await prefs.setString('themeMode', themeString);
  }

  void recoverTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedTheme = prefs.getString('themeMode');
    debugPrint('Recovered theme from prefs: $savedTheme');

    if (savedTheme != null) {
      switch (savedTheme) {
        case 'light':
          themeMode.value = ThemeMode.light;
          break;
        case 'dark':
          themeMode.value = ThemeMode.dark;
          break;
        case 'system':
          themeMode.value = ThemeMode.system;
          break;
      }
      Get.changeThemeMode(themeMode.value);
    }
  }

  IconData getIcon() {
    // 根据当前主题模式返回不同的图标
    if (themeMode.value == ThemeMode.light) {
      return Icons.wb_sunny; // 浅色模式图标
    } else if (themeMode.value == ThemeMode.dark) {
      return Icons.nights_stay; // 暗黑模式图标
    } else {
      return Icons.brightness_auto; // 自动模式图标
    }
  }
}
