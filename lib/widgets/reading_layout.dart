import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ContentPosition { left, center, right }

class ReadingLayoutController extends ChangeNotifier {
  ReadingLayoutController._();
  static final instance = ReadingLayoutController._();
  static const prefsKey = 'reading_layout_v1';

  double maxWidth = 960;
  double horizontalInset = 0;
  ContentPosition position = ContentPosition.center;
  TextAlign textAlign = TextAlign.left;
  double lineHeight = 1.5;
  double letterSpacing = 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(prefs.getString(prefsKey) ?? '{}');
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 无效配置恢复默认排版，避免影响打开题目。
    }
    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      if (value is! num || !value.isFinite) return fallback;
      return value.toDouble().clamp(min, max);
    }

    final width = number('maxWidth', 960, 0, 1440);
    maxWidth = width == 0 ? 0 : width.clamp(480, 1440);
    horizontalInset = number('horizontalInset', 0, 0, 80);
    position =
        ContentPosition.values
            .where((p) => p.name == data['position'])
            .firstOrNull ??
        ContentPosition.center;
    textAlign =
        [
          TextAlign.left,
          TextAlign.center,
          TextAlign.right,
          TextAlign.justify,
        ].where((p) => p.name == data['textAlign']).firstOrNull ??
        TextAlign.left;
    lineHeight = number('lineHeight', 1.5, 1, 2.2);
    letterSpacing = number('letterSpacing', 0, 0, 3);
    notifyListeners();
  }

  Future<void> update({
    double? maxWidth,
    double? horizontalInset,
    ContentPosition? position,
    TextAlign? textAlign,
    double? lineHeight,
    double? letterSpacing,
  }) async {
    if (maxWidth != null && maxWidth.isFinite) {
      this.maxWidth = maxWidth == 0 ? 0 : maxWidth.clamp(480, 1440);
    }
    if (horizontalInset != null && horizontalInset.isFinite) {
      this.horizontalInset = horizontalInset.clamp(0, 80);
    }
    if (position != null) this.position = position;
    if (textAlign != null) this.textAlign = textAlign;
    if (lineHeight != null && lineHeight.isFinite) {
      this.lineHeight = lineHeight.clamp(1, 2.2);
    }
    if (letterSpacing != null && letterSpacing.isFinite) {
      this.letterSpacing = letterSpacing.clamp(0, 3);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode({
        'maxWidth': this.maxWidth,
        'horizontalInset': this.horizontalInset,
        'position': this.position.name,
        'textAlign': this.textAlign.name,
        'lineHeight': this.lineHeight,
        'letterSpacing': this.letterSpacing,
      }),
    );
  }

  Future<void> reset() => update(
    maxWidth: 960,
    horizontalInset: 0,
    position: ContentPosition.center,
    textAlign: TextAlign.left,
    lineHeight: 1.5,
    letterSpacing: 0,
  );
}

/// 仅包裹题目正文；不限制外层滚动视口、笔记或评论的宽度。
class ReadingContent extends StatelessWidget {
  const ReadingContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ReadingLayoutController.instance,
    builder: (context, _) {
      final layout = ReadingLayoutController.instance;
      return LayoutBuilder(
        builder: (context, constraints) {
          final inset = math.min(
            layout.horizontalInset,
            constraints.maxWidth * .2,
          );
          final available = constraints.maxWidth - inset * 2;
          final width = layout.maxWidth == 0
              ? available
              : math.min(layout.maxWidth, available);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Align(
              heightFactor: 1,
              alignment: switch (layout.position) {
                ContentPosition.left => Alignment.topLeft,
                ContentPosition.center => Alignment.topCenter,
                ContentPosition.right => Alignment.topRight,
              },
              child: SizedBox(
                width: width,
                child: DefaultTextStyle.merge(
                  textAlign: layout.textAlign,
                  style: TextStyle(
                    height: layout.lineHeight,
                    letterSpacing: layout.letterSpacing,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
