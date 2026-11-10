import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/chapter.dart';

/// 跨章节边缘滑动状态数据模型
class ChapterCrossOverscrollState {
  final bool isNext;
  final double distance;
  final Chapter? targetChapter;

  const ChapterCrossOverscrollState({
    this.isNext = true,
    this.distance = 0.0,
    this.targetChapter,
  });
}

/// 跨章节滑动纯图标动效指示器（无文字设计）
///
/// 当用户滑动至首题/末题或首章/末章边界时，在边缘以流线型圆弧胶囊展现拉伸与充能动效：
/// 1. 随滑动距离展开流体胶囊与圆形进度环；
/// 2. 章节九宫格（垂直）达到阈值后启动 500ms 蓄力停顿高能光环；题目流（水平）拉满即高能，松手即切；
/// 3. 原生支持水平（题目详情左右滑）与垂直（章节九宫格上下滑）双轴向。
class ChapterCrossIndicator extends StatefulWidget {
  final bool isNext;
  final double overscrollDistance;
  final double threshold;
  final Chapter? targetChapter;
  final Axis axis;
  final Duration? dwellDuration;

  const ChapterCrossIndicator({
    super.key,
    required this.isNext,
    required this.overscrollDistance,
    this.threshold = 85.0,
    required this.targetChapter,
    this.axis = Axis.horizontal,
    this.dwellDuration,
  });

  @override
  State<ChapterCrossIndicator> createState() => _ChapterCrossIndicatorState();
}

class _ChapterCrossIndicatorState extends State<ChapterCrossIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _dwellAnimController;

  Duration get _effectiveDwellDuration =>
      widget.dwellDuration ??
      (widget.axis == Axis.vertical
          ? const Duration(milliseconds: 500)
          : Duration.zero);

  @override
  void initState() {
    super.initState();
    final dur = _effectiveDwellDuration;
    _dwellAnimController = AnimationController(
      vsync: this,
      duration: dur == Duration.zero ? const Duration(milliseconds: 1) : dur,
    );
    final progress = (widget.overscrollDistance / widget.threshold).clamp(0.0, 1.0);
    if (progress >= 1.0 && widget.targetChapter != null) {
      if (dur == Duration.zero) {
        _dwellAnimController.value = 1.0;
      } else {
        _dwellAnimController.forward();
      }
    }
  }

  @override
  void didUpdateWidget(ChapterCrossIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dur = _effectiveDwellDuration;
    if (_dwellAnimController.duration != (dur == Duration.zero ? const Duration(milliseconds: 1) : dur)) {
      _dwellAnimController.duration = dur == Duration.zero ? const Duration(milliseconds: 1) : dur;
    }

    final oldProgress = (oldWidget.overscrollDistance / oldWidget.threshold).clamp(0.0, 1.0);
    final newProgress = (widget.overscrollDistance / widget.threshold).clamp(0.0, 1.0);
    final bool oldReady = oldProgress >= 1.0 && oldWidget.targetChapter != null;
    final bool newReady = newProgress >= 1.0 && widget.targetChapter != null;

    if (newReady && !oldReady) {
      if (dur == Duration.zero) {
        _dwellAnimController.value = 1.0;
      } else {
        _dwellAnimController.forward(from: 0.0);
      }
    } else if (!newReady && oldReady) {
      _dwellAnimController.reset();
    }
  }

  @override
  void dispose() {
    _dwellAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.overscrollDistance <= 2.0) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = (widget.overscrollDistance / widget.threshold).clamp(0.0, 1.0);
    final bool isReady = progress >= 1.0 && widget.targetChapter != null;
    final bool isVertical = widget.axis == Axis.vertical;

    // 动态弹性拉伸尺寸：从 28px 到最大 84px
    final double extent = math.min(84.0, 24.0 + widget.overscrollDistance * 0.7);
    final double opacity = (widget.overscrollDistance / 20.0).clamp(0.0, 1.0);

    final double width = isVertical ? 72.0 : extent;
    final double height = isVertical ? extent : 72.0;

    final BorderRadius borderRadius = isVertical
        ? (widget.isNext
            ? const BorderRadius.vertical(top: Radius.circular(36))
            : const BorderRadius.vertical(bottom: Radius.circular(36)))
        : (widget.isNext
            ? const BorderRadius.horizontal(left: Radius.circular(36))
            : const BorderRadius.horizontal(right: Radius.circular(36)));

    final Offset shadowOffset = isVertical
        ? Offset(0, widget.isNext ? -3 : 3)
        : Offset(widget.isNext ? -3 : 3, 2);

    final IconData directionIcon = isVertical
        ? (widget.isNext
            ? (isReady
                ? Icons.keyboard_double_arrow_down_rounded
                : Icons.arrow_downward_rounded)
            : (isReady
                ? Icons.keyboard_double_arrow_up_rounded
                : Icons.arrow_upward_rounded))
        : (widget.isNext
            ? (isReady
                ? Icons.keyboard_double_arrow_right_rounded
                : Icons.arrow_forward_rounded)
            : (isReady
                ? Icons.keyboard_double_arrow_left_rounded
                : Icons.arrow_back_rounded));

    return Positioned(
      top: isVertical ? (widget.isNext ? null : 0) : 0,
      bottom: isVertical ? (widget.isNext ? 0 : null) : 0,
      left: isVertical ? 0 : (widget.isNext ? null : 0),
      right: isVertical ? 0 : (widget.isNext ? 0 : null),
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: AnimatedBuilder(
            animation: _dwellAnimController,
            builder: (context, child) {
              final double dwellVal = _effectiveDwellDuration == Duration.zero
                  ? 1.0
                  : _dwellAnimController.value;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: isReady
                      ? scheme.primary
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.95),
                  borderRadius: borderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: isReady
                          ? scheme.primary.withValues(alpha: 0.35 + dwellVal * 0.25)
                          : Colors.black.withValues(alpha: 0.12),
                      blurRadius: isReady ? (16 + dwellVal * 8) : 8,
                      offset: shadowOffset,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: Center(
                    child: widget.targetChapter == null
                        // 无相邻章节时的边界阻断图标
                        ? Icon(
                            Icons.do_not_disturb_on_rounded,
                            size: 26,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          )
                        // 动态充能与双箭头切换动效
                        : SizedBox(
                            width: 44,
                            height: 44,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // 环形进度指示环：未就绪显示位移进度，就绪停顿期展示蓄能光环
                                SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: CircularProgressIndicator(
                                    value: isReady
                                        ? (_effectiveDwellDuration == Duration.zero
                                            ? 1.0
                                            : (0.3 + dwellVal * 0.7))
                                        : progress,
                                    strokeWidth: isReady ? (2.8 + dwellVal * 0.8) : 2.8,
                                    backgroundColor: isReady
                                        ? scheme.onPrimary.withValues(alpha: 0.25)
                                        : scheme.outlineVariant.withValues(alpha: 0.4),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isReady ? scheme.onPrimary : scheme.primary,
                                    ),
                                  ),
                                ),

                                // 方向/就绪图标：就绪期轻微脉冲放大
                                Transform.scale(
                                  scale: isReady ? (1.15 + dwellVal * 0.15) : 0.95,
                                  child: Icon(
                                    directionIcon,
                                    size: isReady ? 24 : 20,
                                    color: isReady ? scheme.onPrimary : scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
