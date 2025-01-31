import 'package:flutter/material.dart';
import 'question_detail_page.dart';
import '../db/chapter.dart';
import '../db/question.dart';

// Question Status: 题目状态
// - 0: 未做
// - 1: 正确
// - 2: 错误
// - 3: 已斩

class QuestionGridPage extends StatefulWidget {
  final Chapter chapter;

  const QuestionGridPage({super.key, required this.chapter});

  //const SubjectsListPage({super.key});

  @override
  _QuestionGridPageState createState() => _QuestionGridPageState();
}

class _QuestionGridPageState extends State<QuestionGridPage> {
  // 显示加载进度条
  Widget _buildLoadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  // 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  // 显示无数据提示
  Widget _buildEmptyMessage(String msg) {
    return Center(child: Text(msg));
  }

  Widget buildQuestionGrid(
      List<Question> questions, int crossAxisCount, double buttonSize) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 32,
        mainAxisSpacing: 16,
      ),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final int? questionState = questions[index].status;
        Color buttonColor;

        switch (questionState) {
          case 0:
            buttonColor = Colors.white70;
            break;
          case 1:
            buttonColor = Colors.lightGreen;
            break;
          case 2:
            buttonColor = Colors.red.shade600;
            break;
          default:
            buttonColor = Colors.white70;
            break;
        }

        return ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuestionDetailPage(
                  chapter: widget.chapter,
                  questions: questions,
                  questionIndex: index,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: questionState == 0 ? Colors.black : Colors.white,
            backgroundColor: buttonColor,
            minimumSize: Size(buttonSize, buttonSize),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
          child: Text('${index + 1}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Future<List<Question>> allQuestions =
        getQuestionsFromChapter(widget.chapter);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapter.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder<List<Question>>(
          future: allQuestions,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingIndicator();
            } else if (snapshot.hasError) {
              return _buildErrorMessage(snapshot.error);
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyMessage('本章节中还没有题目哦~');
            } else {
              return LayoutBuilder(
                builder: (context, constraints) {
                  // 每个按钮的固定宽度和高度
                  const double buttonSize = 80.0;
                  // 计算每行可以显示的按钮数量
                  final int crossAxisCount =
                      (constraints.maxWidth / buttonSize).floor();
                  return buildQuestionGrid(
                      snapshot.data!, crossAxisCount, buttonSize);
                },
              );
            }
          },
        ),
      ),
    );
  }
}
