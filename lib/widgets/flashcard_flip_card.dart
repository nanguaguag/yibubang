import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/app_shapes.dart';
import '../models/daily_review_session.dart';

/// 3D 物理翻牌动效闪卡组件（百词斩风格：轻触正面旋转 180° 翻至背面，背面揭晓后滑出自评）
class FlashcardFlipCard extends StatefulWidget {
  final DailyReviewQueueItem queueItem;
  final ValueChanged<bool>? onFlipped;
  final VoidCallback? onOpenOriginalQuestion;
  final bool enable3DAnimation;

  const FlashcardFlipCard({
    super.key,
    required this.queueItem,
    this.onFlipped,
    this.onOpenOriginalQuestion,
    this.enable3DAnimation = true,
  });

  @override
  State<FlashcardFlipCard> createState() => FlashcardFlipCardState();
}

class FlashcardFlipCardState extends State<FlashcardFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _isBackVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.addListener(() {
      final isBack = _controller.value >= 0.5;
      if (isBack != _isBackVisible) {
        setState(() {
          _isBackVisible = isBack;
        });
        widget.onFlipped?.call(isBack);
      }
    });
  }

  @override
  void didUpdateWidget(covariant FlashcardFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queueItem.questionId != widget.queueItem.questionId) {
      _controller.reset();
      _isBackVisible = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 翻转卡片
  void flip() {
    HapticFeedback.lightImpact();
    if (!widget.enable3DAnimation) {
      setState(() {
        _isBackVisible = !_isBackVisible;
      });
      widget.onFlipped?.call(_isBackVisible);
      return;
    }
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = widget.queueItem.customFlashcard;
    final question = widget.queueItem.question;

    final frontText = card?.front ??
        (question?.title != null && question!.title!.isNotEmpty
            ? question.title!
            : '（正面暂无提问内容）');
    final backText = card?.back ??
        (question?.answer != null && question!.answer!.isNotEmpty
            ? question.answer!
            : '（背面暂无答案解析）');

    final tags = card?.tags;

    // 若未开启 3D 翻转动效，直接切换平铺卡片，免去 3D 景深计算与镜像防转
    if (!widget.enable3DAnimation) {
      final isFront = !_isBackVisible;
      return InkWell(
        onTap: flip,
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
        child: Card(
          elevation: isFront ? 1.5 : 2.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            side: BorderSide(
              color: isFront
                  ? scheme.outlineVariant.withValues(alpha: 0.5)
                  : scheme.secondary.withValues(alpha: 0.4),
              width: isFront ? 1 : 1.5,
            ),
          ),
          color: isFront
              ? scheme.surfaceContainerLow
              : scheme.secondaryContainer.withValues(alpha: 0.25),
          child: isFront
              ? _buildFrontFace(context, frontText, tags, theme, scheme)
              : _buildBackFace(context, backText, tags, theme, scheme),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final angle = _animation.value * math.pi;
        final isFront = angle <= (math.pi / 2);

        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012) // 3D 透视透视度
            ..rotateY(angle),
          alignment: Alignment.center,
          child: InkWell(
            onTap: flip,
            borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            child: Card(
              elevation: isFront ? 1.5 : 2.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShapes.extraLarge),
                side: BorderSide(
                  color: isFront
                      ? scheme.outlineVariant.withValues(alpha: 0.5)
                      : scheme.secondary.withValues(alpha: 0.4),
                  width: isFront ? 1 : 1.5,
                ),
              ),
              color: isFront
                  ? scheme.surfaceContainerLow
                  : scheme.secondaryContainer.withValues(alpha: 0.25),
              child: isFront
                  ? _buildFrontFace(context, frontText, tags, theme, scheme)
                  : Transform(
                      // 旋转 180° 使背面文字正向呈现（防水平镜像倒置）
                      transform: Matrix4.identity()..rotateY(math.pi),
                      alignment: Alignment.center,
                      child: _buildBackFace(context, backText, tags, theme, scheme),
                    ),
            ),
          ),
        );
      },
    );
  }

  /// 正面视图 (Front Face)
  Widget _buildFrontFace(
    BuildContext context,
    String frontText,
    String? tags,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部徽章与原题关联
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '闪卡 · 正面',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (tags != null && tags.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tags.split(RegExp(r'[,，\s]+')).first,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
              const Spacer(),
              if (widget.queueItem.question != null && widget.onOpenOriginalQuestion != null)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onOpenOriginalQuestion,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '原题详情',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // 正面核心提问/知识点文本
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 140),
            child: Center(
              child: Text(
                frontText,
                textAlign: TextAlign.start,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  height: 1.6,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 底部触控翻转提示引导
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppShapes.medium),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  widget.enable3DAnimation
                      ? '轻触卡片 3D 翻转至背面查看解析 ✨'
                      : '轻触卡片查看背面解析 ✨',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 背面视图 (Back Face)
  Widget _buildBackFace(
    BuildContext context,
    String backText,
    String? tags,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部徽章
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.secondary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 14, color: scheme.secondary),
                    const SizedBox(width: 4),
                    Text(
                      '闪卡 · 背面 (答案与解析)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (widget.queueItem.question != null && widget.onOpenOriginalQuestion != null)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onOpenOriginalQuestion,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded, size: 14, color: scheme.secondary),
                        const SizedBox(width: 4),
                        Text(
                          '原题详情',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // 背面核心答案/解析文本
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 140),
            child: Text(
              backText,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                height: 1.6,
                color: scheme.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 底部自评引导
          //Container(
          //  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          //  decoration: BoxDecoration(
          //    color: scheme.secondary.withValues(alpha: 0.08),
          //    borderRadius: BorderRadius.circular(AppShapes.medium),
          //  ),
          //  child: Row(
          //    mainAxisAlignment: MainAxisAlignment.center,
          //    children: [
          //      Icon(Icons.arrow_downward_rounded, size: 15, color: scheme.secondary),
          //      const SizedBox(width: 6),
          //      Text(
          //        '轻触卡片可翻回正面',
          //        style: TextStyle(
          //          fontSize: 12,
          //          fontWeight: FontWeight.w600,
          //          color: scheme.secondary,
          //        ),
          //      ),
          //    ],
          //  ),
          //),
        ],
      ),
    );
  }
}
