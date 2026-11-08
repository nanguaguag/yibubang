import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../common/app_shapes.dart';

/// 百词斩风格“今日打卡成功”结题仪式弹窗
class DailyReviewCelebrationDialog extends StatefulWidget {
  final int newCount;
  final int reviewCount;
  final int streakDays;
  final double? accuracy;
  final VoidCallback? onMoreSession;

  const DailyReviewCelebrationDialog({
    super.key,
    required this.newCount,
    required this.reviewCount,
    this.streakDays = 1,
    this.accuracy,
    this.onMoreSession,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int newCount,
    required int reviewCount,
    int streakDays = 1,
    double? accuracy,
    VoidCallback? onMoreSession,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'DailyCelebration',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => DailyReviewCelebrationDialog(
        newCount: newCount,
        reviewCount: reviewCount,
        streakDays: streakDays,
        accuracy: accuracy,
        onMoreSession: onMoreSession,
      ),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  @override
  State<DailyReviewCelebrationDialog> createState() =>
      _DailyReviewCelebrationDialogState();
}

class _DailyReviewCelebrationDialogState
    extends State<DailyReviewCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _badgeScale;
  late Animation<double> _shineRotation;

  static const List<String> _encouragingQuotes = [
    '医者仁心，笃学敏行。今日复习任务圆满达成！',
    '日拱一卒，功不唐捐。每一次重复都是向卓越迈进！',
    '博学而后成医，厚德而后为医，今日打卡成功！',
    '坚持是战胜遗忘的唯一捷径，明天继续加油！',
  ];

  late final String _quote;

  @override
  void initState() {
    super.initState();
    _quote = _encouragingQuotes[
        math.Random().nextInt(_encouragingQuotes.length)];
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.2).chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_animController);

    _shineRotation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = widget.newCount + widget.reviewCount;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: math.min(MediaQuery.of(context).size.width - 48, 380),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 庆祝动画徽章
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _shineRotation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _shineRotation.value,
                        child: Icon(
                          Icons.flare_rounded,
                          size: 110,
                          color: Colors.amber.withValues(alpha: 0.35),
                        ),
                      );
                    },
                  ),
                  ScaleTransition(
                    scale: _badgeScale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '今日计划打卡成功！',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppShapes.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '已连续打卡 ${widget.streakDays} 天',
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 数据仪表盘
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppShapes.large),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('新学题数', '${widget.newCount} 题', scheme.primary),
                    Container(height: 30, width: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    _buildStatItem('巩固复习', '${widget.reviewCount} 题', Colors.teal),
                    Container(height: 30, width: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    _buildStatItem('今日总量', '$total 题', Colors.amber.shade800),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _quote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (widget.onMoreSession != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppShapes.medium),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop(false);
                          widget.onMoreSession?.call();
                        },
                        child: const Text('再学一组'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('完成打卡'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
