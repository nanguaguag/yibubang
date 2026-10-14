import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 平台自适应路由切入：
/// - 安卓：MaterialPageRoute（走 pageTransitionsTheme 的 Material 3 转场）
/// - 其他平台（iOS/macOS 等）：CupertinoPageRoute（保留原生 iOS 风格转场）
Route<T> adaptivePageRoute<T>({required WidgetBuilder builder}) {
  if (Platform.isAndroid) {
    return MaterialPageRoute<T>(builder: builder);
  }
  return CupertinoPageRoute<T>(builder: builder);
}