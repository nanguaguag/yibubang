import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ThemeController extends GetxController {
  // 定义三种主题模式：Light, Dark, System
  var themeMode = ThemeMode.system.obs;

  // 切换主题模式
  void toggleTheme() {
    if (themeMode.value == ThemeMode.light) {
      themeMode.value = ThemeMode.dark;
    } else if (themeMode.value == ThemeMode.dark) {
      themeMode.value = ThemeMode.system;
    } else {
      themeMode.value = ThemeMode.light;
    }

    // 使用 GetX 改变应用的主题模式
    Get.changeThemeMode(themeMode.value);
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
