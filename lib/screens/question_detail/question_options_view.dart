import 'package:flutter/material.dart';

import '../../models/question.dart';
import 'question_detail_controller.dart';

/// 选项列表组件
///
/// 包含两种展示模式：
/// 1. 选择题交互作答（单选 RadioListTile、多选 CheckboxListTile 及提交按钮）
/// 2. 选择题已作答/背题只读模式（高亮正确项、错误项，显示对勾与叉叉图标）
/// 3. 主观题（填空/名词解释/简答/论述/病例分析等）自评与参考答案核对模式
class QuestionOptionsView extends StatefulWidget {
  final Question question;
  final UserQuestion userQuestion;
  final int index;
  final QuestionDetailController controller;
  final VoidCallback onStateChanged;

  const QuestionOptionsView({
    super.key,
    required this.question,
    required this.userQuestion,
    required this.index,
    required this.controller,
    required this.onStateChanged,
  });

  @override
  State<QuestionOptionsView> createState() => _QuestionOptionsViewState();
}

class _QuestionOptionsViewState extends State<QuestionOptionsView> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    if (widget.question.isSubjective) {
      return _buildSubjectiveView(context);
    }

    final mode = widget.controller.mode;
    final isAnswered =
        (widget.userQuestion.status == 1 || widget.userQuestion.status == 2);
    final isMemoryMode = (mode == 3);

    if (isAnswered || isMemoryMode) {
      return _buildReadOnlyOptions();
    }

    return _buildCheckableOptions(context);
  }

  /// 构建主观题（填空/名词解释/简答/论述/病例分析等）专属自评视图
  Widget _buildSubjectiveView(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = widget.controller.mode;
    final uq = widget.userQuestion;
    final q = widget.question;
    final isAnswered = (uq.status == 1 || uq.status == 2);
    final isMemoryMode = (mode == 3);

    // 提取填空题挖空词（若存在）
    final blanks = <String>[];
    final regex = RegExp(r'#@(.*?)(?:@#|$)');
    for (final m in regex.allMatches(q.title ?? '')) {
      final b = m.group(1);
      if (b != null && b.isNotEmpty) blanks.add(b);
    }

    // 提取参考答案解析
    final explain = q.explain?.trim() ?? '';
    final answer = q.answer?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 已作答状态横幅（支持重新自评）
          if (isAnswered)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: uq.status == 1
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: uq.status == 1
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    uq.status == 1
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: uq.status == 1 ? Colors.green : Colors.red,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      uq.status == 1 ? '自评：已掌握 (回答正确)' : '自评：未掌握 (回答错误)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: uq.status == 1 ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text(uq.status == 1 ? '改判未掌握' : '改判已掌握'),
                    onPressed: () {
                      widget.controller.updateSubjectiveStatus(
                        q,
                        uq,
                        widget.index,
                        isCorrect: uq.status != 1,
                        onStateChanged: widget.onStateChanged,
                      );
                    },
                  ),
                ],
              ),
            ),

          // 2. 填空题提取答案展示（当展开或已作答/背题时）
          if (blanks.isNotEmpty && (_showAnswer || isAnswered || isMemoryMode))
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 20, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '标准填空答案',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < blanks.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '空 ${i + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              blanks[i],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // 3. 参考答案折叠卡片（未作答状态下供核对）
          if (!isAnswered && !isMemoryMode) ...[
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(
                _showAnswer ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              label: Text(
                _showAnswer ? '收起参考答案' : '查看参考答案与解析',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                setState(() {
                  _showAnswer = !_showAnswer;
                });
              },
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 20, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '参考要点 / 解析',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      explain.isNotEmpty
                          ? explain
                          : (answer.isNotEmpty ? answer : '题库中暂无本题解析文本，请参考教材。'),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // 4. 自评作答操作栏
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      '已掌握 (记对)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      widget.controller.submitSubjectiveAnswer(
                        q,
                        uq,
                        widget.index,
                        context,
                        isCorrect: true,
                        onStateChanged: widget.onStateChanged,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text(
                      '未掌握 (需复习)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      widget.controller.submitSubjectiveAnswer(
                        q,
                        uq,
                        widget.index,
                        context,
                        isCorrect: false,
                        onStateChanged: widget.onStateChanged,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 只读高亮选项列表
  Widget _buildReadOnlyOptions() {
    final List<dynamic> optionJson =
        QuestionDetailController.getOptionJson(widget.question);
    final String answer = widget.question.answer ?? '';
    final String currentLastAnswer =
        getLastAnswer(widget.userQuestion.userAnswer);
    final mode = widget.controller.mode;

    final List<Map<String, dynamic>> resolvedOptions = [];
    for (final dynamic item in optionJson) {
      final Map<String, dynamic> option =
          Map<String, dynamic>.from(item as Map);
      final String key = option['key'] as String? ?? '';
      final bool answerContains = answer.isNotEmpty && answer.contains(key);
      final bool userAnswerContains = currentLastAnswer.contains(key);

      if ((mode == 3 && widget.userQuestion.status == 0) ||
          widget.userQuestion.status == 4) {
        if (answerContains) {
          option['color'] = null;
          option['icon'] = Icons.check_circle;
        } else {
          option['color'] = Colors.grey;
          option['icon'] = Icons.circle_outlined;
        }
      } else if (answerContains && userAnswerContains) {
        option['color'] = Colors.green;
        option['icon'] = Icons.check_circle;
      } else if (answerContains && !userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.check_circle;
      } else if (!answerContains && userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.cancel;
      } else {
        option['color'] = Colors.grey;
        option['icon'] = Icons.circle_outlined;
      }
      resolvedOptions.add(option);
    }

    return Column(
      children: resolvedOptions.map((option) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                option['icon'] as IconData,
                color: option['color'] as Color?,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "${option['key']}. ${option['title']}",
                    style: TextStyle(
                      fontSize: 16.5,
                      color: option['color'] as Color?,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 交互式作答选项列表
  Widget _buildCheckableOptions(BuildContext context) {
    final List<dynamic> optionJson =
        QuestionDetailController.getOptionJson(widget.question);
    final mode = widget.controller.mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...optionJson.map((item) {
          final Map<String, dynamic> option = item as Map<String, dynamic>;
          final String optKey = option['key'] as String? ?? '';
          final String optTitle = option['title'] as String? ?? '';

          switch (widget.question.type) {
            case '1': // 单选题
              return RadioListTile<String>(
                title: Text("$optKey. $optTitle"),
                value: optKey,
                // ignore: deprecated_member_use
                groupValue: getLastAnswer(widget.userQuestion.userAnswer),
                // ignore: deprecated_member_use
                onChanged: (String? value) {
                  widget.userQuestion.userAnswer = changeLastAnswer(
                    widget.userQuestion.userAnswer,
                    value ?? '',
                  );
                  widget.onStateChanged();
                  // 单选题选择后即时提交判题并记录流水
                  widget.controller.submitAnswer(
                    widget.question,
                    widget.userQuestion,
                    widget.index,
                    context,
                    onStateChanged: widget.onStateChanged,
                  );
                },
              );
            case '2': // 多选题
              final String currentAns =
                  getLastAnswer(widget.userQuestion.userAnswer);
              final bool checked = currentAns.contains(optKey);
              return CheckboxListTile(
                title: Text("$optKey. $optTitle"),
                value: checked,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) {
                  if (value == true && !checked) {
                    widget.userQuestion.userAnswer = changeLastAnswer(
                      widget.userQuestion.userAnswer,
                      currentAns + optKey,
                    );
                  } else if (value == false && checked) {
                    widget.userQuestion.userAnswer = changeLastAnswer(
                      widget.userQuestion.userAnswer,
                      currentAns.replaceAll(optKey, ''),
                    );
                  }
                  if (mode == 2) {
                    widget.userQuestion.status = 4;
                    widget.controller.userQuestions[widget.index].status = 4;
                    updateQuestionSimple(widget.userQuestion, widget.question);
                  }
                  widget.onStateChanged();
                },
              );
            default:
              return const SizedBox.shrink();
          }
        }),
        _buildSubmitButton(context),
      ],
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    final mode = widget.controller.mode;
    // 测试模式下不显示「提交」按钮（交卷统一在底部）；单选点击即提交也不显示「提交」按钮
    if (mode == 2 || widget.question.type == '1') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 200,
          height: 60,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(40),
              ),
              elevation: 3,
            ),
            onPressed: () {
              widget.controller.submitAnswer(
                widget.question,
                widget.userQuestion,
                widget.index,
                context,
                onStateChanged: widget.onStateChanged,
              );
            },
            child: const Text(
              '提交',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }
}
