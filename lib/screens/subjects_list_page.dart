import 'package:flutter/material.dart';
import '../constants/app_strings.dart';
import '../db/subject.dart';

class SubjectsListPage extends StatefulWidget {
  @override
  _SubjectsListPageState createState() => _SubjectsListPageState();
}

class _SubjectsListPageState extends State<SubjectsListPage> {
  Future<List<Subject>> subjects = fetchAllSubjects();
  Set<String> selectedItems = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.subjectsListTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context); // 返回上一页
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
                  tileColor: selectedItems.contains(subjectsList[index].id)
                      ? Colors.blue.shade100
                      : null,
                  onTap: () {
                    setState(() {
                      if (selectedItems.contains(subjectsList[index].id)) {
                        selectedItems.remove(subjectsList[index].id); // 取消选择
                      } else {
                        selectedItems.add(subjectsList[index].id); // 选择该项
                      }
                    });
                  },
                  trailing: selectedItems.contains(subjectsList[index].id)
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
