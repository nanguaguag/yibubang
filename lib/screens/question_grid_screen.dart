import 'package:flutter/material.dart';
import '../constants/app_strings.dart';

class QuestionGridPage extends StatelessWidget {
  final String quizCategoryName;

  QuestionGridPage({required this.quizCategoryName});

  @override
  Widget build(BuildContext context) {
    // 模拟题目的状态（1: 正确, 0: 错误, -1: 未做）
    final List<int> questions = List.generate(99, (index) {
      if (index % 4 == 0) return 0; // 错误
      if (index % 3 == 0) return 1; // 正确
      return -1; // 未做
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(quizCategoryName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 每个按钮的固定宽度和高度
            const double buttonSize = 80.0;
            // 计算每行可以显示的按钮数量
            final int crossAxisCount =
                (constraints.maxWidth / buttonSize).floor();

            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 32,
                mainAxisSpacing: 16,
              ),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final questionState = questions[index];
                Color buttonColor;

                if (questionState == 1) {
                  buttonColor = Colors.lightGreen; // 正确
                } else if (questionState == 0) {
                  buttonColor = Colors.red; // 错误
                } else {
                  buttonColor = Colors.white70; // 未做
                }

                return ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor:
                        questionState == -1 ? Colors.black : Colors.white,
                    backgroundColor: buttonColor, // 背景颜色
                    minimumSize: const Size(buttonSize, buttonSize), // 固定按钮大小
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  child: Text('${index + 1}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
