import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_shapes.dart';

/// 判断当前运行环境是否应采用桌面端/宽屏横屏布局
///
/// 判定逻辑：
/// 1. 处于 macOS / Windows / Linux 平台且窗口宽度 >= 640px；
/// 2. 或处于平板宽屏 (宽度 >= 840px)。
/// 移动端普通手机竖屏（或宽度 < 640px）保持原生移动端布局。
bool isDesktopLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final isDesktopPlatform = !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  if (isDesktopPlatform) {
    return size.width >= 640;
  }
  return size.width >= 840;
}

/// 自适应模态弹出界面（Modal Sheet）
///
/// - **移动端 (窄屏/竖屏)**：保持标准的底部抽屉 [showModalBottomSheet]，带有顶把手与圆角，完全不影响移动端交互。
/// - **桌面端 (宽屏/横屏)**：改为居中卡片式浮窗 [showDialog]，带有精致边框、圆角、阴影与限制宽度（最大 620px），
///   避免在 1080p/2K/4K 显示器上横跨全屏底部导致操作体验恶劣。
Future<T?> showAdaptiveModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  BoxConstraints? constraints,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  Color? backgroundColor,
}) {
  if (isDesktopLayout(context)) {
    final theme = Theme.of(context);
    final effectiveConstraints = constraints ??
        const BoxConstraints(
          maxWidth: 620,
          maxHeight: 720,
        );

    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: backgroundColor ?? theme.colorScheme.surface,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: effectiveConstraints,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 桌面端顶栏：标题与右上角关闭按钮
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    children: [
                      if (title != null && title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: builder(dialogCtx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 移动端保持原样 BottomSheet
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor,
    constraints: constraints ?? const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppShapes.extraLarge),
      ),
    ),
    builder: builder,
  );
}
