import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_screen.dart';
import '../constants/app_strings.dart';

// 题库页面，展示用户现在正在刷的题库

class QuizScreen extends StatelessWidget {
  final List<String> quizCategories;

  QuizScreen({required this.quizCategories});

  void addQuizList() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.quizCategoryTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: quizCategories.length, // Use the length of the passed list
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(quizCategories[index]),
            onTap: () {
              // Navigate to a detailed quiz screen (not implemented here)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuestionGridPage(
                    quizCategoryName: quizCategories[index],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addQuizList,
        tooltip: '添加题库',
        child: const Icon(Icons.add),
      ),
    );
  }
}
