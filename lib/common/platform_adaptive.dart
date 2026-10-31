import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_shapes.dart';
import 'adaptive_route.dart';

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

/// 自适应模态弹出内部 Scope
class _AdaptiveModalScope extends InheritedWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final BuildContext dialogContext;

  const _AdaptiveModalScope({
    required this.navigatorKey,
    required this.dialogContext,
    required super.child,
  });

  static _AdaptiveModalScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AdaptiveModalScope>();
  }

  @override
  bool updateShouldNotify(_AdaptiveModalScope oldWidget) => false;
}

/// 哨兵路由：占位在模态弹窗内置 Navigator 的栈底，
/// 使得首个页面拥有 canPop=true 和 fullscreenDialog 特征（呈现优雅的关闭按钮），
/// 并在首个页面被关闭（pop）时通知外层模态弹窗退出。
class _ModalSentinelRoute extends PageRoute<void> {
  _ModalSentinelRoute()
      : super(settings: const RouteSettings(name: '__adaptive_modal_sentinel__'));

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => false;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const SizedBox.shrink();
  }
}

/// 监听模态内置 Navigator 路由变化的 Observer
class _AdaptiveModalNavigatorObserver extends NavigatorObserver {
  final void Function(dynamic result) onDismissModal;
  _AdaptiveModalNavigatorObserver({required this.onDismissModal});

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is _ModalSentinelRoute || previousRoute == null) {
      onDismissModal(route.currentResult);
    }
  }
}

/// 承载内置 Navigator 的模态弹窗容器
class _AdaptiveModalContainer extends StatefulWidget {
  final BuildContext dialogContext;
  final GlobalKey<NavigatorState> nestedNavKey;
  final WidgetBuilder initialBuilder;

  const _AdaptiveModalContainer({
    required this.dialogContext,
    required this.nestedNavKey,
    required this.initialBuilder,
  });

  @override
  State<_AdaptiveModalContainer> createState() => _AdaptiveModalContainerState();
}

class _AdaptiveModalContainerState extends State<_AdaptiveModalContainer> {
  late final _AdaptiveModalNavigatorObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = _AdaptiveModalNavigatorObserver(
      onDismissModal: (result) {
        if (mounted && Navigator.of(widget.dialogContext).canPop()) {
          Navigator.of(widget.dialogContext).pop(result);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AdaptiveModalScope(
      navigatorKey: widget.nestedNavKey,
      dialogContext: widget.dialogContext,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final nav = widget.nestedNavKey.currentState;
          if (nav == null) {
            if (Navigator.of(widget.dialogContext).canPop()) {
              Navigator.of(widget.dialogContext).pop(result);
            }
            return;
          }
          final popped = await nav.maybePop(result);
          if (!popped && widget.dialogContext.mounted) {
            if (Navigator.of(widget.dialogContext).canPop()) {
              Navigator.of(widget.dialogContext).pop(result);
            }
          }
        },
        child: HeroControllerScope(
          controller: MaterialApp.createMaterialHeroController(),
          child: Navigator(
            key: widget.nestedNavKey,
            observers: [_observer],
            onGenerateInitialRoutes: (navigator, initialRouteName) {
              return [
                _ModalSentinelRoute(),
                MaterialPageRoute(
                  builder: (nestedContext) =>
                      widget.initialBuilder(nestedContext),
                  fullscreenDialog: true,
                ),
              ];
            },
            onGenerateRoute: (settings) => null,
          ),
        ),
      ),
    );
  }
}

/// 自适应模态页面跳转（Adaptive Modal Page）
///
/// 针对原本为独立完整页面的功能（如登录、选择课程、题库管理、刷题流水记录、设置页、笔记列表等）：
/// - **移动端 (窄屏/手机)**：使用原生全屏路由跳转 [adaptivePageRoute]，保留原生手势与转场；
/// - **桌面端 (宽屏/横屏)**：使用居中模态卡片浮窗 [showDialog]，带有精致边框、圆角、阴影与合理的宽高约束，
///   避免在宽屏桌面显示器上被横向过度拉伸。
/// - **内部路由支持**：如果在模态弹窗内继续通过 [Navigator.push] 或 [pushAdaptiveModalPage] 跳转到其他子页面
///   （例如：设置 -> 主题颜色、我的笔记 -> 查看原题、我的错题 -> 题目详情），将在该模态窗口内部流畅转场替代当前视图，
///   子页面拥有返回按钮回到上级，完好保持层级关系，绝不堆叠多个弹窗，且始终处于自适应模态弹出状态。
Future<T?> pushAdaptiveModalPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BoxConstraints? desktopConstraints,
  bool barrierDismissible = true,
}) {
  if (isDesktopLayout(context)) {
    // 若当前环境已处于自适应模态弹出弹窗内，则直接在该弹窗内置 Navigator 中进行页面平滑替换/推入，
    // 不叠加多层遮罩，子页面具有返回按钮可逐层返回上一页
    final currentScope = _AdaptiveModalScope.maybeOf(context);
    if (currentScope != null) {
      return Navigator.of(context).push<T>(
        adaptivePageRoute(builder: builder),
      );
    }

    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final defaultConstraints = BoxConstraints(
      maxWidth: 760,
      maxHeight: (size.height * 0.88).clamp(520.0, 860.0),
    );

    final GlobalKey<NavigatorState> nestedNavKey = GlobalKey<NavigatorState>();

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          elevation: 8,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: desktopConstraints ?? defaultConstraints,
            child: _AdaptiveModalContainer(
              dialogContext: dialogCtx,
              nestedNavKey: nestedNavKey,
              initialBuilder: builder,
            ),
          ),
        );
      },
    );
  }

  // 移动端保持原样全屏路由推入
  return Navigator.of(context).push<T>(
    adaptivePageRoute(builder: builder),
  );
}
