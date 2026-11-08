import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../common/adaptive_route.dart';
import '../common/app_shapes.dart';
import '../common/platform_adaptive.dart';
import '../models/daily_review_session.dart';
import '../screens/daily_review_page.dart';
import '../services/daily_review_service.dart';
import 'daily_review_plan_dialog.dart';

/// 首页“每日记忆计划”百词斩打卡卡片
class DailyReviewCard extends StatefulWidget {
  final DailyReviewService? service;
  final VoidCallback? onSessionCompleted;

  const DailyReviewCard({
    super.key,
    this.service,
    this.onSessionCompleted,
  });

  @override
  State<DailyReviewCard> createState() => _DailyReviewCardState();
}

class _DailyReviewCardState extends State<DailyReviewCard> {
  late final DailyReviewService _service;
  bool _loading = true;
  DailyReviewSummary? _summary;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DailyReviewService();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final summary = await _service.getTodaySummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _navigateToDailyReview({bool isExtra = false}) async {
    final result = isDesktopLayout(context)
        ? await pushAdaptiveModalPage<bool>(
            context,
            builder: (_) => DailyReviewPage(
              service: _service,
              isExtraSession: isExtra,
            ),
          )
        : await Navigator.push<bool>(
            context,
            adaptivePageRoute(
              builder: (_) => DailyReviewPage(
                service: _service,
                isExtraSession: isExtra,
              ),
            ),
          );

    await _loadSummary();
    if (result == true) {
      widget.onSessionCompleted?.call();
    }
  }

  Future<void> _openPlanSettings() async {
    final updated = await DailyReviewPlanDialog.show(context);
    if (updated != null) {
      _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading && _summary == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        height: 120,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final summary = _summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final isAchieved = summary.isCompleted;
    final totalCompleted = summary.completedNewToday + summary.completedReviewToday;
    final totalTarget = math.max(
      1,
      summary.dailyNewTarget + summary.remainingDueCount + summary.completedReviewToday,
    );
    final progress = math.min(1.0, totalCompleted / totalTarget);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isAchieved
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        border: Border.all(
          color: isAchieved
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏：计划名称 + 连击打卡天数 + 设置按钮
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAchieved
                        ? scheme.primary.withValues(alpha: 0.15)
                        : scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAchieved ? Icons.check_circle_rounded : Icons.psychology_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.planName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            color: Colors.deepOrange.shade600,
                            size: 15,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '已连续打卡 ${math.max(1, summary.streakDays)} 天',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '计划设置',
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  onPressed: _openPlanSettings,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 中间：进度状态说明
            if (isAchieved) ...[
              Row(
                children: [
                  const Icon(Icons.celebration_rounded, color: Colors.teal, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '今日计划已圆满打卡！',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已学 $totalCompleted 题',
                    style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Text(
                    '今日待刷: ${summary.remainingNewCount} 新题 · ${summary.remainingDueCount} 复习',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$totalCompleted / $totalTarget 题',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShapes.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // 底栏操作按钮
            SizedBox(
              width: double.infinity,
              child: isAchieved
                  ? FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () => _navigateToDailyReview(isExtra: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('再学一组 / 继续巩固'),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () => _navigateToDailyReview(isExtra: false),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('开始今日打卡'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
