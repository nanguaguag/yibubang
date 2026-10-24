import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';

enum ThemeColorMode { system, custom }

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);

  static final ThemeController instance = ThemeController._();

  Color _themeColor = Colors.blue;
  ThemeColorMode _themeColorMode = ThemeColorMode.system;
  Duration _animationDuration = const Duration(milliseconds: 300);
  Color? _systemAccentColor;

  ThemeMode get themeMode => value;
  Color get themeColor => _themeColor;
  ThemeColorMode get themeColorMode => _themeColorMode;
  Duration get animationDuration => _animationDuration;

  Color get effectiveSeedColor {
    if (_themeColorMode == ThemeColorMode.system && _systemAccentColor != null) {
      return _systemAccentColor!;
    }
    return _themeColor;
  }

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

  // 直接设置主题模式（设置页三选一使用）
  Future<void> setTheme(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    debugPrint('Theme changed to: $value');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeModeToString(value));
  }

  Future<void> initSystemTheme() async {
    try {
      await SystemTheme.accentColor.load();
      _systemAccentColor = SystemTheme.accentColor.accent;
    } catch (e) {
      debugPrint('加载系统主题色失败: $e');
    }
  }

  Future<void> recoverTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedTheme = prefs.getString('themeMode');
    debugPrint('Recovered theme from prefs: $savedTheme');

    if (savedTheme != null) {
      value = _themeModeFromString(savedTheme);
    }

    int? savedDuration = prefs.getInt('animationDuration');
    if (savedDuration != null) {
      _animationDuration = Duration(milliseconds: savedDuration);
    }

    int? savedColorMode = prefs.getInt('themeColorMode');
    if (savedColorMode != null && savedColorMode < ThemeColorMode.values.length) {
      _themeColorMode = ThemeColorMode.values[savedColorMode];
    }

    int? savedColor = prefs.getInt('themeColor');
    if (savedColor != null) {
      _themeColor = Color(savedColor);
    }

    await initSystemTheme();
    notifyListeners();
  }

  Future<void> setAnimationDuration(Duration duration) async {
    _animationDuration = duration;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('animationDuration', duration.inMilliseconds);
  }

  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', color.toARGB32());
  }

  Future<void> setThemeColorMode(ThemeColorMode mode) async {
    _themeColorMode = mode;
    if (mode == ThemeColorMode.system) {
      await initSystemTheme();
    }
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColorMode', mode.index);
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
