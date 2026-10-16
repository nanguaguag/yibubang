import 'package:flutter/material.dart';

import '../../models/question.dart';
import 'question_detail_controller.dart';

/// 选项列表组件
///
/// 包含两种展示模式：
/// 1. 可交互作答模式（单选 RadioListTile、多选 CheckboxListTile 及提交按钮）
/// 2. 已作答/背题只读模式（高亮正确项、错误项，显示对勾与叉叉图标）
class QuestionOptionsView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final mode = controller.mode;
    final isAnswered = (userQuestion.status == 1 || userQuestion.status == 2);
    final isMemoryMode = (mode == 3);

    if (isAnswered || isMemoryMode) {
      return _buildReadOnlyOptions();
    }

    return _buildCheckableOptions(context);
  }

  /// 只读高亮选项列表
  Widget _buildReadOnlyOptions() {
    final List<dynamic> optionJson = QuestionDetailController.getOptionJson(question);
    final String answer = question.answer ?? '';
    final String currentLastAnswer = getLastAnswer(userQuestion.userAnswer);
    final mode = controller.mode;

    final List<Map<String, dynamic>> resolvedOptions = [];
    for (final dynamic item in optionJson) {
      final Map<String, dynamic> option = Map<String, dynamic>.from(item as Map);
      final String key = option['key'] as String? ?? '';
      final bool answerContains = answer.isNotEmpty && answer.contains(key);
      final bool userAnswerContains = currentLastAnswer.contains(key);

      if ((mode == 3 && userQuestion.status == 0) || userQuestion.status == 4) {
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
    final List<dynamic> optionJson = QuestionDetailController.getOptionJson(question);
    final mode = controller.mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...optionJson.map((item) {
          final Map<String, dynamic> option = item as Map<String, dynamic>;
          final String optKey = option['key'] as String? ?? '';
          final String optTitle = option['title'] as String? ?? '';

          switch (question.type) {
            case '1': // 单选题
              return RadioListTile<String>(
                title: Text("$optKey. $optTitle"),
                value: optKey,
                groupValue: getLastAnswer(userQuestion.userAnswer),
                onChanged: (String? value) {
                  userQuestion.userAnswer = changeLastAnswer(
                    userQuestion.userAnswer,
                    value ?? '',
                  );
                  onStateChanged();
                  if (mode == 1 || mode == 2) {
                    controller.submitAnswer(
                      question,
                      userQuestion,
                      index,
                      context,
                      onStateChanged: onStateChanged,
                    );
                  }
                },
              );
            case '2': // 多选题
              final String currentAns = getLastAnswer(userQuestion.userAnswer);
              final bool checked = currentAns.contains(optKey);
              return CheckboxListTile(
                title: Text("$optKey. $optTitle"),
                value: checked,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) {
                  if (value == true && !checked) {
                    userQuestion.userAnswer = changeLastAnswer(
                      userQuestion.userAnswer,
                      currentAns + optKey,
                    );
                  } else if (value == false && checked) {
                    userQuestion.userAnswer = changeLastAnswer(
                      userQuestion.userAnswer,
                      currentAns.replaceAll(optKey, ''),
                    );
                  }
                  if (mode == 2) {
                    userQuestion.status = 4;
                    controller.userQuestions[index].status = 4;
                    updateQuestionSimple(userQuestion, question);
                  }
                  onStateChanged();
                },
              );
            default:
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('未知的题目类型'),
              );
          }
        }),
        _buildSubmitButton(context),
      ],
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    final mode = controller.mode;
    // 测试模式下不显示「提交」按钮（交卷统一在底部）；快刷模式单选自动提交也不显示
    if (mode == 2 || (mode == 1 && question.type == '1')) {
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
              controller.submitAnswer(
                question,
                userQuestion,
                index,
                context,
                onStateChanged: onStateChanged,
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
