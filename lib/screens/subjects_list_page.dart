import 'package:flutter/material.dart';
import '../common/app_strings.dart';
import '../db/subject.dart';

class SubjectsListPage extends StatefulWidget {
  @override
  _SubjectsListPageState createState() => _SubjectsListPageState();
}

class _SubjectsListPageState extends State<SubjectsListPage> {
  Future<List<Subject>> subjects = fetchAllSubjects();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.subjectsListTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: FutureBuilder<List<Subject>>(
        future: subjects, // 使用Future
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 正在加载时显示进度条
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            // 出现错误时显示错误信息
            return Center(child: Text('加载失败: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // 没有数据时显示提示
            return const Center(child: Text('没有数据'));
          } else {
            // 获取数据
            List<Subject> subjectsList = snapshot.data!;
            return ListView.builder(
              itemCount: subjectsList.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(subjectsList[index].name),
                  tileColor: subjectsList[index].selected == 1
                      ? Colors.blue.shade50
                      : null,
                  onTap: () {
                    setState(() {
                      toggleSubjectSelected(subjectsList[index].id); // 在数据库中修改
                      if (subjectsList[index].selected == 1) {
                        subjectsList[index].selected = 0;
                      } else if (subjectsList[index].selected == 0) {
                        subjectsList[index].selected = 1;
                      } else {
                        subjectsList[index].selected = 0;
                      }
                    });
                  },
                  trailing: subjectsList[index].selected == 1
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.check_circle_outline),
                );
              },
            );
          }
        },
      ),
    );
  }
}
