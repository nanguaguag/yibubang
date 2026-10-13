import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/answer_statistics.dart';

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

    // 年度格子墙：从去年今天到今日（共一年）
    final yearStart = now.subtract(const Duration(days: 364));
    final heat = await getDailyAggregation(
      startMs: yearStart.millisecondsSinceEpoch,
      endMs: tomorrowStartMs(now),
    );
    final heatByDay = {for (final d in heat) d.date: d.count};

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('做题统计'),
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
          return ListView(
            padding: const EdgeInsets.all(16),
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
                chart: _buildCountChart(data.charts[_chartPeriod]!),
              ),
              const SizedBox(height: 16),
              _ChartCard(
                title: '刷题时长',
                chart: _buildDurationChart(data.charts[_chartPeriod]!),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 顶部指标卡
  // ---------------------------------------------------------------------
  Widget _buildMetricCards(_AllStats data) {
    return Row(
      children: [
        Expanded(child: _MetricCard(period: '今日', stats: data.today)),
        const SizedBox(width: 8),
        Expanded(child: _MetricCard(period: '本周', stats: data.week)),
        const SizedBox(width: 8),
        Expanded(child: _MetricCard(period: '本月', stats: data.month)),
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
        alignment: BarChartAlignment.spaceAround,
        barGroups: bars,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: _bottomTitles(d.labels),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              '${rod.toY.toInt()} 题',
              TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 800),
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
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.32,
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
      duration: const Duration(milliseconds: 800),
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

  const _MetricCard({required this.period, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
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
  final Map<DateTime, int> days;

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
    final today = DateTime.now();
    final todayKey = _dayKey(today);

    // 起始：恰好一年前，并回溯到所在周的周一
    var start = today.subtract(const Duration(days: 364));
    start = _dayKey(start).subtract(Duration(days: _dayKey(start).weekday - 1));

    // 按周分组（每列 7 天，周一 ~ 周日）
    final weeks = <List<DateTime>>[];
    var day = _dayKey(start);
    while (!day.isAfter(todayKey)) {
      final week = <DateTime>[];
      for (var i = 0; i < 7; i++) {
        week.add(day);
        day = day.add(const Duration(days: 1));
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
        child: Row(
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
                          count: widget.days[weeks[w][d]] ?? 0,
                          maxCount: maxCount,
                          size: cell,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
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

class _HeatCell extends StatelessWidget {
  final int count;
  final int maxCount;
  final double size;

  const _HeatCell({
    required this.count,
    required this.maxCount,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    if (maxCount <= 0 || count <= 0) {
      color = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    } else {
      final t = (count / maxCount).clamp(0.0, 1.0);
      color = theme.colorScheme.primary.withValues(
        alpha: (0.25 + 0.75 * t).clamp(0.0, 1.0),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

DateTime _dayKey(DateTime t) => DateTime(t.year, t.month, t.day);

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
  final Map<DateTime, int> heatByDay;
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
