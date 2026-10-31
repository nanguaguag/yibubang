import 'package:flutter/material.dart';

import '../common/adaptive_route.dart';
import '../models/answer_statistics.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import 'question_detail_page.dart';

/// 刷题记录详情列表页
class AnsweredRecordsPage extends StatefulWidget {
  final String title;
  final int startMs;
  final int endMs;
  final String? bankId;

  const AnsweredRecordsPage({
    super.key,
    required this.title,
    required this.startMs,
    required this.endMs,
    this.bankId,
  });

  @override
  State<AnsweredRecordsPage> createState() => _AnsweredRecordsPageState();
}

class _AnsweredRecordsPageState extends State<AnsweredRecordsPage> {
  late Future<List<AnsweredRecordItem>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = getAnsweredRecordsInRange(
      startMs: widget.startMs,
      endMs: widget.endMs,
      bankId: widget.bankId,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
    });
    await _future;
  }

  void _openQuestionDetail(List<AnsweredRecordItem> items, int index) {
    final validItems = items.where((it) => it.question != null).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到对应题库中的题目内容')),
      );
      return;
    }

    final targetItem = items[index];
    final targetIndex = validItems.indexWhere(
      (it) => it.questionId == targetItem.questionId,
    );

    final questions = validItems.map((it) => it.question!).toList();
    final userQuestions = validItems.map((it) {
      if (it.userQuestion != null) return it.userQuestion!;
      return UserQuestion(
        id: it.questionId,
        chapterId: it.chapterId ?? '',
        chapterParentId: it.subjectId ?? '',
        userAnswer: it.userAnswer,
        status: it.isRight ? 1 : 2,
        collection: 0,
      );
    }).toList();

    final firstQ = questions[targetIndex >= 0 ? targetIndex : 0];
    final chapter = Chapter(
      id: firstQ.chapterId ?? 'history',
      name: widget.title,
      subjectId: firstQ.chapterParentId ?? '',
      correct: validItems.where((it) => it.isRight).length,
      incorrect: validItems.where((it) => !it.isRight).length,
      total: validItems.length,
      identityId: firstQ.identityId,
    );

    Navigator.push(
      context,
      adaptivePageRoute(
        builder: (_) => QuestionDetailPage(
          chapter: chapter,
          questions: questions,
          userQuestions: userQuestions,
          questionIndex: targetIndex >= 0 ? targetIndex : 0,
          bankId: targetItem.bankId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: FutureBuilder<List<AnsweredRecordItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.history_toggle_off,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '该时间段内暂无作答记录',
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final total = items.length;
          final correct = items.where((it) => it.isRight).length;
          final accuracy = total > 0 ? (correct / total * 100).round() : 0;
          final totalMs = items.fold<int>(0, (sum, it) => sum + it.durationMs);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSummaryCard(
                    theme: theme,
                    total: total,
                    correct: correct,
                    accuracy: accuracy,
                    totalMs: totalMs,
                  );
                }

                final item = items[index - 1];
                return _buildRecordItemTile(
                  theme: theme,
                  item: item,
                  index: index,
                  onTap: () => _openQuestionDetail(items, index - 1),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({
    required ThemeData theme,
    required int total,
    required int correct,
    required int accuracy,
    required int totalMs,
  }) {
    final scheme = theme.colorScheme;
    final min = (totalMs / 60000).floor();
    final durStr = min < 60
        ? '$min 分钟'
        : '${min ~/ 60}小时${min % 60}分钟';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryCol(theme, '$total', '刷题数', scheme.primary),
          Container(
            width: 1,
            height: 32,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _summaryCol(theme, '$accuracy%', '正确率', scheme.tertiary),
          Container(
            width: 1,
            height: 32,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _summaryCol(theme, durStr, '用时', scheme.secondary),
        ],
      ),
    );
  }

  Widget _summaryCol(ThemeData theme, String val, String label, Color color) {
    return Column(
      children: [
        Text(
          val,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordItemTile({
    required ThemeData theme,
    required AnsweredRecordItem item,
    required int index,
    required VoidCallback onTap,
  }) {
    final scheme = theme.colorScheme;
    final q = item.question;
    final title = q?.title?.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final typeText = q?.typeLabel ?? '题目';
    final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isRight
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.isRight ? '正确' : '错误',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: item.isRight ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.access_time,
                    size: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title?.isNotEmpty == true
                    ? title!
                    : '题目 ID: ${item.questionId}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '我的答案: ${item.userAnswer.isNotEmpty ? item.userAnswer : "-"}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: item.isRight ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                  if (q?.answer?.isNotEmpty == true) ...[
                    const SizedBox(width: 12),
                    Text(
                      '正确答案: ${q!.answer}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (item.durationMs > 0)
                    Text(
                      '用时 ${(item.durationMs / 1000).round()}秒',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
