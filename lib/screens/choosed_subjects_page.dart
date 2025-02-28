import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_page.dart';
import '../common/app_strings.dart';
import 'subjects_list_page.dart';
import '../db/subject.dart';
import '../db/chapter.dart';
import '../widgets/theme_controller.dart';
import 'package:get/get.dart';

class ChoosedSubjectsPage extends StatefulWidget {
  const ChoosedSubjectsPage({super.key});

  @override
  _ChoosedSubjectsPageState createState() => _ChoosedSubjectsPageState();
}

// 题库页面，展示用户现在正在刷的题库
class _ChoosedSubjectsPageState extends State<ChoosedSubjectsPage> {
  Future<List<Subject>> selectedSubjects = fetchSelectedSubjects();

  Widget chapterList(Subject subject) {
    Future<List<Chapter>> chaptersInSubject =
        fetchChaptersBySubjectId(subject.id);

    return FutureBuilder<List<Chapter>>(
      future: chaptersInSubject,
      builder: (context, snapshot) {
        return _buildChapterListContent(context, snapshot, subject);
      },
    );
  }

  // 构建章节列表内容的函数
  Widget _buildChapterListContent(BuildContext context,
      AsyncSnapshot<List<Chapter>> snapshot, Subject subject) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _buildLoadingIndicator(); // 显示加载进度条
    } else if (snapshot.hasError) {
      return _buildErrorMessage(snapshot.error); // 显示错误信息
    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
      return _buildEmptyMessage('无数据'); // 显示无数据提示
    } else {
      return _buildChapterList(context, snapshot.data!, subject); // 构建章节列表
    }
  }

  // 显示加载进度条
  Widget _buildLoadingIndicator() {
    return const Center(child: LinearProgressIndicator());
  }

  // 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  // 显示无数据提示
  Widget _buildEmptyMessage(String msg) {
    return Center(child: Text(msg));
  }

  // 构建章节列表
  Widget _buildChapterList(
    BuildContext context,
    List<Chapter> chapters,
    Subject subject,
  ) {
    double correctProgress = subject.correct / (subject.total + 0.001);
    double incorrectProgress = subject.incorrect / (subject.total + 0.001);

    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            flex: 8,
            child: Text(
              subject.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${subject.correct + subject.incorrect}/${subject.total}",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (correctProgress * 100).toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.green,
                        ),
                      ),
                      Expanded(
                        flex: (incorrectProgress * 100).toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.red,
                        ),
                      ),
                      Expanded(
                        flex: ((1 - correctProgress - incorrectProgress) * 100)
                            .toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.grey[200],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      children: chapters.map((chapter) {
        return _buildChapterItem(context, chapter); // 构建单个章节项
      }).toList(),
    );
  }

  // 构建单个章节项
  Widget _buildChapterItem(BuildContext context, Chapter chapter) {
    double correctProgress = chapter.correct / (chapter.total + 0.001);
    double incorrectProgress = chapter.incorrect / (chapter.total + 0.001);

    return ListTile(
      title: Row(
        children: [
          Expanded(
            flex: 10,
            child: Text(
              chapter.name,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${chapter.correct + chapter.incorrect}/${chapter.total}",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (correctProgress * 100).toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.green,
                        ),
                      ),
                      Expanded(
                        flex: (incorrectProgress * 100).toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.red,
                        ),
                      ),
                      Expanded(
                        flex: ((1 - correctProgress - incorrectProgress) * 100)
                            .toInt(),
                        child: Container(
                          height: 4,
                          color: Colors.grey[200],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuestionGridPage(
              chapter: chapter,
            ),
          ),
        );
        setState(() {
          selectedSubjects = fetchSelectedSubjects();
        });
      },
    );
  }

  Widget subjectList(List<Subject> subjects) {
    return ListView.builder(
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        return chapterList(subjects[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.put(ThemeController());

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.selectedSubjectsTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Obx(() {
            return IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  themeController.getIcon(),
                  key: ValueKey(
                    themeController.themeMode.value,
                  ), // 使用Key确保图标切换有动画效果
                ),
              ),
              onPressed: () {
                themeController.toggleTheme(); // 切换主题模式
              },
            );
          })
        ],
      ),
      body: FutureBuilder<List<Subject>>(
        future: selectedSubjects,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingIndicator();
          } else if (snapshot.hasError) {
            return _buildErrorMessage(snapshot.error);
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyMessage('您还没有正在学习的课程~');
          } else {
            return subjectList(snapshot.data!);
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
