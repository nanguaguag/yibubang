import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_page.dart';
import '../constants/app_strings.dart';
import 'subjects_list_page.dart';
import '../db/subject.dart';

class ChoosedSubjectsPage extends StatefulWidget {
  @override
  _ChoosedSubjectsPageState createState() => _ChoosedSubjectsPageState();
}

// 题库页面，展示用户现在正在刷的题库
class _ChoosedSubjectsPageState extends State<ChoosedSubjectsPage> {
  Future<List<Subject>> selectedSubjects = fetchSelectedSubjects();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.selectedSubjectsTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<List<Subject>>(
        future: selectedSubjects,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 正在加载时显示进度条
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            // 出现错误时显示错误信息
            return Center(child: Text('加载失败: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // 没有数据时显示提示
            return const Center(child: Text('您还没有正在学习的课程~'));
          } else {
            // 获取数据
            List<Subject> selectedSubjects = snapshot.data!;
            return ListView.builder(
              itemCount: selectedSubjects.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(selectedSubjects[index].name),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QuestionGridPage(
                          chapterName: selectedSubjects[index].name,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SubjectsListPage(),
            ),
          );
          setState(() {
            selectedSubjects = fetchSelectedSubjects();
          });
        },
        tooltip: '添加课程',
        child: const Icon(Icons.add),
      ),
    );
  }
}
