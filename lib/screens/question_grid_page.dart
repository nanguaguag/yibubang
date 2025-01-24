import 'package:flutter/material.dart';

// Question Status: 题目状态
// - 0: 未做
// - 1: 正确
// - 2: 错误
// - 3: 已斩

class QuestionGridPage extends StatelessWidget {
  final String chapterName;

  const QuestionGridPage({super.key, required this.chapterName});

  @override
  Widget build(BuildContext context) {
    final List<int> questions = List.generate(99, (index) {
      return index % 3;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(chapterName),
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
                } else if (questionState == 2) {
                  buttonColor = Colors.red.shade600; // 错误
                } else if (questionState == 0) {
                  buttonColor = Colors.white70; // 未做
                } else {
                  buttonColor = Colors.white70;
                }

                return ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor:
                        questionState == 0 ? Colors.black : Colors.white,
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
