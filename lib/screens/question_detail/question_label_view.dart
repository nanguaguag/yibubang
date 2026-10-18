import 'package:flutter/material.dart';
import '../../models/question.dart';
import '../../models/question_label.dart';

/// 题目标签展示组件
class QuestionLabelView extends StatefulWidget {
  final Question question;

  const QuestionLabelView({
    super.key,
    required this.question,
  });

  @override
  State<QuestionLabelView> createState() => _QuestionLabelViewState();
}

class _QuestionLabelViewState extends State<QuestionLabelView> {
  late Future<List<QuestionLabel>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchQuestionLabels(widget.question);
  }

  @override
  void didUpdateWidget(covariant QuestionLabelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _future = fetchQuestionLabels(widget.question);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color orangeAccent = Color(0xFFB39D6B);
    final theme = Theme.of(context);

    return FutureBuilder<List<QuestionLabel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        final labels = snapshot.data ?? [];
        if (labels.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined, color: orangeAccent, size: 22),
                SizedBox(width: 6),
                Text(
                  '题目标签',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: orangeAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: labels.map((label) {
                final bool hasVotes = label.count > 0;
                final bool isUserSelected = label.userLabel;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 5.0,
                  ),
                  decoration: BoxDecoration(
                    color: isUserSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : hasVotes
                            ? theme.colorScheme.secondaryContainer
                            : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isUserSelected
                          ? theme.colorScheme.primary
                          : hasVotes
                              ? theme.colorScheme.secondary.withValues(alpha: 0.5)
                              : Colors.transparent,
                      width: isUserSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              hasVotes ? FontWeight.w600 : FontWeight.normal,
                          color: isUserSelected
                              ? theme.colorScheme.primary
                              : hasVotes
                                  ? theme.colorScheme.onSecondaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasVotes) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isUserSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.secondary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${label.count}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0x22888888)),
          ],
        );
      },
    );
  }
}
