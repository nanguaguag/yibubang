import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);

  static final ThemeController instance = ThemeController._();

  // 切换主题模式
  void toggleTheme() async {
    if (value == ThemeMode.light) {
      value = ThemeMode.dark;
    } else if (value == ThemeMode.dark) {
      value = ThemeMode.system;
    } else {
      value = ThemeMode.light;
    }

    debugPrint('Theme changed to: $value');

    // 保存当前主题模式到 SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeModeToString(value));
  }

  void recoverTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedTheme = prefs.getString('themeMode');
    debugPrint('Recovered theme from prefs: $savedTheme');

    if (savedTheme != null) {
      value = _themeModeFromString(savedTheme);
    }
  }

  IconData getIcon() {
    // 根据当前主题模式返回不同的图标
    if (value == ThemeMode.light) {
      return Icons.wb_sunny; // 浅色模式图标
    } else if (value == ThemeMode.dark) {
      return Icons.nights_stay; // 暗黑模式图标
    } else {
      return Icons.brightness_auto; // 自动模式图标
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _themeModeFromString(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}