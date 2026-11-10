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
/// 2. 达到切换阈值时图标跃升为双箭头，环形指示条闭合，背景产生高亮光晕与触感震动；
/// 3. 松手即刻由上层 Listener 触发平滑切章转场；
/// 4. 原生支持水平（题目详情左右滑）与垂直（章节九宫格上下滑）双轴向。
class ChapterCrossIndicator extends StatelessWidget {
  final bool isNext;
  final double overscrollDistance;
  final double threshold;
  final Chapter? targetChapter;
  final Axis axis;

  const ChapterCrossIndicator({
    super.key,
    required this.isNext,
    required this.overscrollDistance,
    this.threshold = 60.0,
    required this.targetChapter,
    this.axis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    if (overscrollDistance <= 2.0) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = (overscrollDistance / threshold).clamp(0.0, 1.0);
    final bool isReady = progress >= 1.0 && targetChapter != null;
    final bool isVertical = axis == Axis.vertical;

    // 动态弹性拉伸尺寸：从 28px 到最大 76px
    final double extent = math.min(76.0, 24.0 + overscrollDistance * 0.7);
    final double opacity = (overscrollDistance / 20.0).clamp(0.0, 1.0);

    final double width = isVertical ? 72.0 : extent;
    final double height = isVertical ? extent : 72.0;

    final BorderRadius borderRadius = isVertical
        ? (isNext
            ? const BorderRadius.vertical(top: Radius.circular(36))
            : const BorderRadius.vertical(bottom: Radius.circular(36)))
        : (isNext
            ? const BorderRadius.horizontal(left: Radius.circular(36))
            : const BorderRadius.horizontal(right: Radius.circular(36)));

    final Offset shadowOffset = isVertical
        ? Offset(0, isNext ? -3 : 3)
        : Offset(isNext ? -3 : 3, 2);

    final IconData directionIcon = isVertical
        ? (isNext
            ? (isReady
                ? Icons.keyboard_double_arrow_down_rounded
                : Icons.arrow_downward_rounded)
            : (isReady
                ? Icons.keyboard_double_arrow_up_rounded
                : Icons.arrow_upward_rounded))
        : (isNext
            ? (isReady
                ? Icons.keyboard_double_arrow_right_rounded
                : Icons.arrow_forward_rounded)
            : (isReady
                ? Icons.keyboard_double_arrow_left_rounded
                : Icons.arrow_back_rounded));

    return Positioned(
      top: isVertical ? (isNext ? null : 0) : 0,
      bottom: isVertical ? (isNext ? 0 : null) : 0,
      left: isVertical ? 0 : (isNext ? null : 0),
      right: isVertical ? 0 : (isNext ? 0 : null),
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: AnimatedContainer(
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
                      ? scheme.primary.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.12),
                  blurRadius: isReady ? 16 : 8,
                  offset: shadowOffset,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Center(
                child: targetChapter == null
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
                            // 圆形进度指示环
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: CircularProgressIndicator(
                                value: isReady ? 1.0 : progress,
                                strokeWidth: 2.8,
                                backgroundColor: isReady
                                    ? scheme.onPrimary.withValues(alpha: 0.25)
                                    : scheme.outlineVariant.withValues(alpha: 0.4),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isReady ? scheme.onPrimary : scheme.primary,
                                ),
                              ),
                            ),

                            // 方向/就绪图标
                            AnimatedScale(
                              scale: isReady ? 1.2 : 0.95,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutBack,
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
          ),
        ),
      ),
    );
  }
}
