import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_page.dart';
import '../constants/app_strings.dart';
import 'subjects_list_page.dart';

// 题库页面，展示用户现在正在刷的题库
class ChoosedSubjectsPage extends StatelessWidget {
  final List<String> quizCategories;

  ChoosedSubjectsPage({required this.quizCategories});

  // This is where you could handle adding a new quiz category
  void navigateToSubjectsListPage(BuildContext context) {
    // Implement your logic to add a new quiz category
    // For example, navigate to a page that allows adding a new category:
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubjectsListPage(),
      ),
    );
  }

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
        onPressed: () => navigateToSubjectsListPage(context),
        tooltip: '添加题库',
        child: const Icon(Icons.add),
      ),
    );
  }
}
