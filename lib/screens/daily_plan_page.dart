import 'package:flutter/material.dart';

import '../common/app_shapes.dart';
import '../models/daily_review_session.dart';
import '../repositories/spaced_review_repository.dart';
import '../services/daily_review_service.dart';
import '../widgets/daily_review_card.dart';
import '../widgets/daily_review_plan_dialog.dart';

/// 独立的“每日复习计划”导航页（新 Tab）
class DailyPlanPage extends StatefulWidget {
  final DailyReviewService? service;
  final SpacedReviewRepository? repository;

  const DailyPlanPage({
    super.key,
    this.service,
    this.repository,
  });

  @override
  State<DailyPlanPage> createState() => _DailyPlanPageState();
}

class _DailyPlanPageState extends State<DailyPlanPage> {
  late final DailyReviewService _service;
  late final SpacedReviewRepository _repo;

  bool _loading = true;
  DailyReviewSummary? _summary;
  Map<String, int> _forecast = {};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DailyReviewService();
    _repo = widget.repository ?? SpacedReviewRepository();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final summary = await _service.getTodaySummary();
      final forecast = await _repo.getDueForecast(days: 7);
      if (mounted) {
        setState(() {
          _summary = summary;
          _forecast = forecast;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPlanSettings() async {
    final updated = await DailyReviewPlanDialog.show(context);
    if (updated != null) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日复习计划'),
        actions: [
          IconButton(
            tooltip: '计划与抽题范围设置',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openPlanSettings,
          ),
        ],
      ),
      body: _loading && _summary == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // 1. 顶部打卡核心操作卡片
                  DailyReviewCard(
                    service: _service,
                    onSessionCompleted: _loadData,
                  ),

                  // 2. 抽题来源与覆盖范围摘要条
                  if (_summary != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildScopeSummaryCard(context, _summary!, theme, scheme),
                    ),

                  const SizedBox(height: 16),

                  // 3. 卡片库沉淀分布（Anki 浓缩知识库视角）
                  if (_summary != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildPoolInsightsCard(context, _summary!, theme, scheme),
                    ),

                  const SizedBox(height: 16),

                  // 4. 未来 7 天到期预测
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildForecastCard(context, theme, scheme),
                  ),
                ],
              ),
            ),
    );
  }

  /// 抽题来源与覆盖范围说明条
  Widget _buildScopeSummaryCard(
    BuildContext context,
    DailyReviewSummary summary,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final sources = summary.sourceTypes;
    final sourceLabels = <String>[];
    if (sources.contains('wrong')) sourceLabels.add('错题');
    if (sources.contains('collected')) sourceLabels.add('收藏');
    if (sources.contains('note')) sourceLabels.add('笔记');
    if (sources.contains('all')) sourceLabels.add('包含新题');

    final subjectCount = summary.coveredSubjects.length;

    return InkWell(
      onTap: _openPlanSettings,
      borderRadius: BorderRadius.circular(AppShapes.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppShapes.medium),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '抽题范围: ${sourceLabels.isEmpty ? "未限制" : sourceLabels.join(" · ")} | 覆盖 ${subjectCount == 0 ? "全部课程" : "$subjectCount 门课程"}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  /// 知识库卡片池统计
  Widget _buildPoolInsightsCard(
    BuildContext context,
    DailyReviewSummary summary,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '记忆精粹卡片池',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatPill('错题攻克', '${summary.poolWrongCount}', Colors.red.shade700, scheme),
                const SizedBox(width: 8),
                _buildStatPill('星标收藏', '${summary.poolCollectedCount}', Colors.amber.shade800, scheme),
                const SizedBox(width: 8),
                _buildStatPill('速记笔记', '${summary.poolNoteCount}', Colors.blue.shade700, scheme),
                const SizedBox(width: 8),
                _buildStatPill('熟练斩题', '${summary.poolMasteredCount}', Colors.teal.shade700, scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppShapes.medium),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  /// 未来 7 天到期复习量预测
  Widget _buildForecastCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '未来 7 天到期预测',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final day = now.add(Duration(days: i));
                final dayKey = '${day.year.toString().padLeft(4, '0')}-'
                    '${day.month.toString().padLeft(2, '0')}-'
                    '${day.day.toString().padLeft(2, '0')}';
                final count = _forecast[dayKey] ?? 0;
                final isToday = i == 0;

                return Column(
                  children: [
                    Text(
                      isToday ? '今天' : '周${weekdays[day.weekday - 1]}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isToday ? scheme.primary : Colors.grey[600],
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: count > 0
                            ? (isToday
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isToday
                            ? Border.all(color: scheme.primary, width: 1.5)
                            : null,
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                          color: count > 0
                              ? (isToday ? scheme.primary : scheme.onSurface)
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
