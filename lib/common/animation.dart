import 'package:flutter/material.dart';
import '../widgets/theme_controller.dart';

/// 全局动画配置工具类
class AppAnimation {
  /// 全局配置的动画时长
  static Duration get duration => ThemeController.instance.animationDuration;

  /// 全局配置的动画毫秒数
  static int get durationMs => ThemeController.instance.animationDuration.inMilliseconds;

  /// 常用缓动曲线
  static const Curve curve = Curves.easeInOutCubic;
  static const Curve fastOutSlowIn = Curves.fastOutSlowIn;
}
