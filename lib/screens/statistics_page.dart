import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/platform_adaptive.dart';
import '../models/answer_statistics.dart';
import '../services/cloud_sync_service.dart';
import 'answered_records_page.dart';

/// 做题统计页
///
/// 结构自上而下：
/// 1. 显眼的“今日 / 本周 / 本月”三张指标卡（总用时、累计作答数、正确率）
/// 2. 刷题格子墙（GitHub 风格年度热力墙）
/// 3. 刷题数量 / 刷题时长图表（可按今日、本周、本月切换，带动画）
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

enum _Period { today, week, month }

class _StatisticsPageState extends State<StatisticsPage> {
  _Period _chartPeriod = _Period.today;

  late Future<_AllStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    CloudSyncService.instance.addListener(_onSyncChanged);
    answersChangedNotifier.addListener(_onAnswersChanged);
  }

  @override
  void dispose() {
    CloudSyncService.instance.removeListener(_onSyncChanged);
    answersChangedNotifier.removeListener(_onAnswersChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  void _onAnswersChanged() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<_AllStats> _load() async {
    final now = DateTime.now();
    // 统计为跨题库聚合：不区分当前激活题库，反映整体刷题量，
    // 使「重新统计」补记的历史记录无论当时激活哪个题库都能计入。

    final todayStats = await getPeriodStats(
      startMs: todayStartMs(now),
      endMs: tomorrowStartMs(now),
    );
    final weekStats = await getPeriodStats(
      startMs: weekStartMs(now),
      endMs: nextWeekStartMs(now),
    );
    final monthStats = await getPeriodStats(
      startMs: monthStartMs(now),
      endMs: nextMonthStartMs(now),
    );

    // 年度格子墙：从去年今天到今日（共一年），使用标准化日期起点
    final today0 = DateTime(now.year, now.month, now.day);
    final yearStart = today0.subtract(const Duration(days: 364));
    final heat = await getDailyAggregation(
      startMs: yearStart.millisecondsSinceEpoch,
      endMs: tomorrowStartMs(now),
    );
    final heatByDay = {for (final d in heat) formatDayKey(d.date): d.count};

    // 三个周期的图表数据
    final todayChart = await _loadChart(_Period.today, now);
    final weekChart = await _loadChart(_Period.week, now);
    final monthChart = await _loadChart(_Period.month, now);

    return _AllStats(
      today: todayStats,
      week: weekStats,
      month: monthStats,
      heatByDay: heatByDay,
      charts: {
        _Period.today: todayChart,
        _Period.week: weekChart,
        _Period.month: monthChart
      },
    );
  }

  Future<_ChartData> _loadChart(
    _Period period,
    DateTime now,
  ) async {
    switch (period) {
      case _Period.today:
        final hourly = await getHourlyAggregation(
          dayStartMs: todayStartMs(now),
        );
        return _ChartData(
          labels: [for (var i = 0; i < 24; i++) '$i时'],
          counts: [for (final h in hourly) h.count],
          durationsMs: [for (final h in hourly) h.durationMs],
        );
      case _Period.week:
        final start = weekStartMs(now);
        final daily = await getDailyAggregation(
          startMs: start,
          endMs: start + const Duration(days: 7).inMilliseconds,
        );
        const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
        return _ChartData(
          labels: [for (var i = 0; i < 7; i++) '周${weekdayNames[i]}'],
          counts: [for (final d in daily) d.count],
          durationsMs: [for (final d in daily) d.durationMs],
        );
      case _Period.month:
        final start = monthStartMs(now);
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final daily = await getDailyAggregation(
          startMs: start,
          endMs: start + Duration(days: daysInMonth).inMilliseconds,
        );
        return _ChartData(
          labels: [for (var i = 1; i <= daysInMonth; i++) '$i'],
          counts: [for (final d in daily) d.count],
          durationsMs: [for (final d in daily) d.durationMs],
        );
    }
  }

  Future<void> _handleRefresh() async {
    if (CloudSyncService.instance.isConfigured) {
      await CloudSyncService.instance.sync();
    }
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('做题统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新统计',
            onPressed: _handleRefresh,
          ),
        ],
      ),
      body: FutureBuilder<_AllStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildMetricCards(data),
                const SizedBox(height: 24),
                _buildHeatTitle(context),
                const SizedBox(height: 12),
                _ContributionWall(days: data.heatByDay),
                const SizedBox(height: 8),
                _buildHeatLegend(context, data.maxDayCount()),
                const SizedBox(height: 24),
                _buildChartToggle(context),
                const SizedBox(height: 16),
                _ChartCard(
                  title: '刷题数量',
                  chart: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey('count_${_chartPeriod.name}'),
                      child: _buildCountChart(data.charts[_chartPeriod]!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  title: '刷题时长',
                  chart: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey('dur_${_chartPeriod.name}'),
                      child: _buildDurationChart(data.charts[_chartPeriod]!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 顶部指标卡
  // ---------------------------------------------------------------------
  Widget _buildMetricCards(_AllStats data) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            period: '今日',
            stats: data.today,
            onTap: () {
              pushAdaptiveModalPage(
                context,
                builder: (_) => AnsweredRecordsPage(
                  title: '今日刷题记录',
                  startMs: todayStartMs(now),
                  endMs: tomorrowStartMs(now),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            period: '本周',
            stats: data.week,
            onTap: () {
              pushAdaptiveModalPage(
                context,
                builder: (_) => AnsweredRecordsPage(
                  title: '本周刷题记录',
                  startMs: weekStartMs(now),
                  endMs: nextWeekStartMs(now),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            period: '本月',
            stats: data.month,
            onTap: () {
              pushAdaptiveModalPage(
                context,
                builder: (_) => AnsweredRecordsPage(
                  title: '本月刷题记录',
                  startMs: monthStartMs(now),
                  endMs: nextMonthStartMs(now),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 格子墙标题
  Widget _buildHeatTitle(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.grid_view_rounded,
            color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 6),
        Text(
          '刷题格子墙',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildHeatLegend(BuildContext context, int maxCount) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('少', style: theme.textTheme.bodySmall),
        const SizedBox(width: 4),
        // 0、1/4、1/2、3/4、1 五档强度，与格子墙配色一致
        for (var lv = 0; lv <= 4; lv++) ...[
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _heatColor(theme, lv / 4, maxCount <= 0 ? 0 : lv),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        const SizedBox(width: 4),
        Text('多', style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// 按强度 (0~1) 生成格子颜色；无数据时为浅底色。
  Color _heatColor(ThemeData theme, double intensity, int level) {
    if (level <= 0 || intensity <= 0) {
      return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    }
    return theme.colorScheme.primary.withValues(
      alpha: (0.25 + 0.75 * intensity).clamp(0.0, 1.0),
    );
  }

  // 图表切换
  Widget _buildChartToggle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SegmentedButton<_Period>(
        segments: const [
          ButtonSegment(
              value: _Period.today, label: Text('今日'), icon: Icon(Icons.today)),
          ButtonSegment(
              value: _Period.week,
              label: Text('本周'),
              icon: Icon(Icons.calendar_view_week)),
          ButtonSegment(
              value: _Period.month,
              label: Text('本月'),
              icon: Icon(Icons.calendar_month)),
        ],
        selected: {_chartPeriod},
        onSelectionChanged: (selection) =>
            setState(() => _chartPeriod = selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }

  Widget _buildCountChart(_ChartData d) {
    final theme = Theme.of(context);
    final maxCount = d.counts.fold<int>(0, (m, e) => e > m ? e : m);
    final bars = <BarChartGroupData>[
      for (var i = 0; i < d.counts.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: d.counts[i].toDouble(),
              color: theme.colorScheme.primary,
              width: d.counts.length > 20 ? 4 : 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
    ];
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxCount == 0 ? 10 : (maxCount * 1.2).ceilToDouble(),
        alignment: BarChartAlignment.spaceAround,
        barGroups: bars,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: _bottomTitles(d.labels),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              '${rod.toY.toInt()} 题',
              TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildDurationChart(_ChartData d) {
    final theme = Theme.of(context);
    final maxDur = d.durationsMs.fold<int>(0, (m, e) => e > m ? e : m);
    final spots = [
      for (var i = 0; i < d.durationsMs.length; i++)
        FlSpot(i.toDouble(), _msToMin(d.durationsMs[i]).toDouble()),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxDur == 0 ? 10 : _msToMin(maxDur) * 1.2,
        minX: 0,
        maxX: d.durationsMs.isEmpty ? 1 : (d.durationsMs.length - 1).toDouble(),
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            preventCurveOvershootingThreshold: 10.0,
            barWidth: 3,
            color: theme.colorScheme.tertiary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _bottomTitles(d.labels).copyWith(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                _fmtMin(s.y, isDuration: true, comma: false),
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  FlTitlesData _bottomTitles(List<String> labels) {
    final theme = Theme.of(context);
    AxisTitles bottomAxis() => AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              // 标签过多时每隔几位显示，避免拥挤
              if (labels.length > 20 && i % 4 != 0) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  labels[i],
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                ),
              );
            },
          ),
        );
    return FlTitlesData(
      bottomTitles: bottomAxis(),
      topTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: labels.length <= 15,
          reservedSize: 40,
          getTitlesWidget: (value, meta) => Text(
            value.toInt().toString(),
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
          ),
        ),
      ),
      rightTitles: const AxisTitles(),
    );
  }
}

// ---------------------------------------------------------------------
// 指标卡
// ---------------------------------------------------------------------
class _MetricCard extends StatelessWidget {
  final String period;
  final PeriodStats stats;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.period,
    required this.stats,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    period,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: scheme.primary.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _metricRow(theme, Icons.timer_outlined,
                  _fmtDuration(stats.totalDuration.inMilliseconds)),
              const SizedBox(height: 6),
              _metricRow(
                  theme, Icons.rate_review_outlined, '${stats.answeredCount} 题'),
              const SizedBox(height: 6),
              _metricRow(theme, Icons.check_circle_outline,
                  '${(stats.accuracy * 100).round()}% 正确'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 刷题格子墙（GitHub 风格）
// ---------------------------------------------------------------------
class _ContributionWall extends StatefulWidget {
  final Map<String, int> days;

  const _ContributionWall({required this.days});

  @override
  State<_ContributionWall> createState() => _ContributionWallState();
}

class _ContributionWallState extends State<_ContributionWall> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // 默认滚动到最右侧，让用户直接看到“今天”的格子。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // 起始：恰好一年前，并回溯到所在周的周一
    final startDay = todayDate.subtract(const Duration(days: 364));
    final mondayStart = startDay.subtract(Duration(days: startDay.weekday - 1));

    // 按周分组（每列 7 天，周一 ~ 周日），使用安全的 DateTime 累加避免时区漂移
    final weeks = <List<DateTime>>[];
    var currentDay = DateTime(mondayStart.year, mondayStart.month, mondayStart.day);
    while (!currentDay.isAfter(todayDate)) {
      final week = <DateTime>[];
      for (var i = 0; i < 7; i++) {
        week.add(currentDay);
        currentDay = DateTime(currentDay.year, currentDay.month, currentDay.day + 1);
      }
      weeks.add(week);
    }

    final maxCount = widget.days.isEmpty
        ? 0
        : widget.days.values.reduce((a, b) => a > b ? a : b);

    const cell = 14.0;
    const gap = 3.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WeekdayLabels(cell: cell, gap: gap),
                for (var w = 0; w < weeks.length; w++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Padding(
                            padding: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                            child: _HeatCell(
                              date: weeks[w][d],
                              count: widget.days[formatDayKey(weeks[w][d])] ?? 0,
                              maxCount: maxCount,
                              size: cell,
                              isToday: formatDayKey(weeks[w][d]) == formatDayKey(todayDate),
                              isFuture: weeks[w][d].isAfter(todayDate),
                              onTap: () => _showDayStatsBottomSheet(context, weeks[w][d]),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _MonthLabels(
              weeks: weeks,
              cell: cell,
              gap: gap,
              leadingWidth: 18.0,
            ),
          ],
        ),
      ),
    );
  }
}

/// 下方月份横坐标标签（Jan, Feb, Mar ...）
class _MonthLabels extends StatelessWidget {
  final List<List<DateTime>> weeks;
  final double cell;
  final double gap;
  final double leadingWidth;

  const _MonthLabels({
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.leadingWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final labels = <Widget>[];
    int? lastMonth;

    for (var w = 0; w < weeks.length; w++) {
      final week = weeks[w];
      int monthToLabel = -1;
      for (final day in week) {
        if (day.day <= 7 && day.month != lastMonth) {
          monthToLabel = day.month;
          break;
        }
      }
      if (w == 0 && lastMonth == null) {
        monthToLabel = week.first.month;
      }

      if (monthToLabel != -1 && monthToLabel != lastMonth) {
        lastMonth = monthToLabel;
        final left = leadingWidth + w * (cell + gap);
        labels.add(
          Positioned(
            left: left,
            top: 0,
            child: Text(
              monthNames[monthToLabel],
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ),
        );
      }
    }

    final totalWidth = leadingWidth + weeks.length * (cell + gap);
    return SizedBox(
      width: totalWidth,
      height: 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: labels,
      ),
    );
  }
}

/// 左侧星期标签（一 / 三 / 五 / 日）。
class _WeekdayLabels extends StatelessWidget {
  final double cell;
  final double gap;

  const _WeekdayLabels({required this.cell, required this.gap});

  @override
  Widget build(BuildContext context) {
    const labels = ['一', '三', '五', '日'];
    final items = <Widget>[];
    for (var i = 0; i < 4; i++) {
      items.add(SizedBox(
        width: 14,
        child: Text(
          labels[i],
          style: const TextStyle(fontSize: 8, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ));
      if (i != 3) {
        items.add(SizedBox(height: cell + gap));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child:
          SizedBox(height: cell * 7 + gap * 6, child: Column(children: items)),
    );
  }
}

class _HeatCell extends StatefulWidget {
  final DateTime date;
  final int count;
  final int maxCount;
  final double size;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  const _HeatCell({
    required this.date,
    required this.count,
    required this.maxCount,
    required this.size,
    this.isToday = false,
    this.isFuture = false,
    this.onTap,
  });

  @override
  State<_HeatCell> createState() => _HeatCellState();
}

class _HeatCellState extends State<_HeatCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    if (widget.isFuture) {
      color = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15);
    } else if (widget.maxCount <= 0 || widget.count <= 0) {
      color = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    } else {
      final t = (widget.count / widget.maxCount).clamp(0.0, 1.0);
      color = theme.colorScheme.primary.withValues(
        alpha: (0.25 + 0.75 * t).clamp(0.0, 1.0),
      );
    }

    final tooltipMsg = widget.isFuture
        ? '${formatDayKey(widget.date)} (未来)'
        : '${formatDayKey(widget.date)}: ${widget.count} 题';

    return MouseRegion(
      cursor: widget.isFuture ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: tooltipMsg,
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: widget.isFuture ? null : widget.onTap,
          child: AnimatedScale(
            scale: _isHovered && !widget.isFuture ? 1.35 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _isHovered && !widget.isFuture
                    ? (widget.count > 0 ? theme.colorScheme.primary : theme.colorScheme.outlineVariant)
                    : color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: _isHovered && !widget.isFuture
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
                border: widget.isToday
                    ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      )
                    : (widget.isFuture
                        ? Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                            width: 0.5,
                          )
                        : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部弹出当天的详细刷题情况
void _showDayStatsBottomSheet(BuildContext context, DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  final startMs = start.millisecondsSinceEpoch;
  final endMs = end.millisecondsSinceEpoch;

  const weekdays = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  final dateStr = '${date.year}年${date.month}月${date.day}日 ${weekdays[date.weekday]}';

  final now = DateTime.now();
  final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

  showAdaptiveModalSheet<void>(
    context: context,
    title: dateStr,
    builder: (ctx) {
      return _DayDetailSheet(
        date: date,
        dateStr: dateStr,
        isToday: isToday,
        startMs: startMs,
        endMs: endMs,
        onViewAll: () {
          if (!context.mounted) return;
          pushAdaptiveModalPage(
            context,
            builder: (_) => AnsweredRecordsPage(
              title: '${date.year}年${date.month}月${date.day}日 刷题记录',
              startMs: startMs,
              endMs: endMs,
            ),
          );
        },
      );
    },
  );
}

class _DayDetailSheet extends StatefulWidget {
  final DateTime date;
  final String dateStr;
  final bool isToday;
  final int startMs;
  final int endMs;
  final VoidCallback? onViewAll;

  const _DayDetailSheet({
    required this.date,
    required this.dateStr,
    required this.isToday,
    required this.startMs,
    required this.endMs,
    this.onViewAll,
  });

  @override
  State<_DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<_DayDetailSheet> {
  late final Future<PeriodStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    // 缓存 Future，避免底部弹窗在拖动把手悬浮 (hover) 触发重绘时重新创建 Future 导致尺寸抖动与闪烁
    _statsFuture = getDayStats(widget.date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<PeriodStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final isLoading = snapshot.connectionState != ConnectionState.done;
        final count = stats?.answeredCount ?? 0;
        final duration = stats?.totalDuration ?? Duration.zero;
        final accuracy = stats?.accuracy ?? 0.0;
        final correctCount = stats?.correctCount ?? 0;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题行：0. 日期
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_month_rounded,
                        color: scheme.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.dateStr,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.isToday) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '今日',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '单日做题统计',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (isLoading)
                  const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  // 1. 刷题量、2. 用时、3. 正确率 三指标卡
                  Row(
                    children: [
                      Expanded(
                        child: _DayDetailMetricTile(
                          icon: Icons.rate_review_outlined,
                          iconColor: scheme.primary,
                          title: '刷题量',
                          value: '$count 题',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DayDetailMetricTile(
                          icon: Icons.timer_outlined,
                          iconColor: Colors.orange,
                          title: '用时',
                          value: _fmtDuration(duration.inMilliseconds),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DayDetailMetricTile(
                          icon: Icons.check_circle_outline,
                          iconColor: Colors.green,
                          title: '正确率',
                          value: count > 0 ? '${(accuracy * 100).round()}%' : '--',
                          subValue: count > 0 ? '$correctCount对 / ${count - correctCount}错' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 操作按钮
                  if (count > 0)
                    FilledButton.icon(
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('查看全部题目'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onViewAll?.call();
                      },
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('关闭 (当天无作答记录)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayDetailMetricTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String? subValue;

  const _DayDetailMetricTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------
// 图表卡片
// ---------------------------------------------------------------------
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;

  const _ChartCard({required this.title, required this.chart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: chart),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 数据容器与工具函数
// ---------------------------------------------------------------------
class _AllStats {
  final PeriodStats today;
  final PeriodStats week;
  final PeriodStats month;
  final Map<String, int> heatByDay;
  final Map<_Period, _ChartData> charts;

  const _AllStats({
    required this.today,
    required this.week,
    required this.month,
    required this.heatByDay,
    required this.charts,
  });

  int maxDayCount() =>
      heatByDay.isEmpty ? 0 : heatByDay.values.reduce((a, b) => a > b ? a : b);
}

class _ChartData {
  final List<String> labels;
  final List<int> counts;
  final List<int> durationsMs;

  const _ChartData({
    required this.labels,
    required this.counts,
    required this.durationsMs,
  });
}

String _fmtDuration(int ms) {
  final min = (ms / 60000).floor();
  if (min < 60) return '$min 分';
  final h = min ~/ 60;
  final mm = min % 60;
  return mm == 0 ? '$h 时' : '$h时$mm分';
}

String _fmtMin(double minutes, {bool isDuration = false, bool comma = true}) =>
    isDuration ? _fmtDuration((minutes * 60000).round()) : minutes.toString();

int _msToMin(int ms) => (ms / 60000).round();
