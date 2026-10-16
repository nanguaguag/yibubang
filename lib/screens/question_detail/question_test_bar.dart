import 'package:flutter/material.dart';
import 'question_detail_controller.dart';

/// 测试模式顶部计时与进度条
///
/// 内部通过 [ValueListenableBuilder] 局部精准监听秒级流逝时间，
/// 彻底隔离定时器刷新，不引发整页重绘。
class QuestionTestInfoBar extends StatelessWidget {
  final QuestionDetailController controller;

  const QuestionTestInfoBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = controller.questions.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: controller.elapsedNotifier,
            builder: (context, _, __) {
              return Text(
                '已用时 ${controller.formatElapsed()}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              );
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: controller.answeredCountNotifier,
            builder: (context, answered, __) {
              return Text(
                '已作答 $answered/$total',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 测试模式底部交卷按钮
class QuestionTestSubmitBar extends StatelessWidget {
  final VoidCallback onSubmit;

  const QuestionTestSubmitBar({
    super.key,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text('交卷', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
