import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_page.dart';
import '../common/app_strings.dart';
import 'subjects_list_page.dart';
import 'identity_list_page.dart';
import '../models/subject.dart';
import '../models/chapter.dart';
import '../widgets/theme_controller.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubjectWithChapters {
  final Subject subject;
  final List<Chapter> chapters;

  SubjectWithChapters({required this.subject, required this.chapters});
}

Future<List<SubjectWithChapters>> getSubjectsWithChapters() async {
  List<Subject> subjects = await getSelectedSubjects();
  List<SubjectWithChapters> subjectWithChapters = [];

  for (final subject in subjects) {
    List<Chapter> chapters = await getChaptersBySubject(subject);
    subjectWithChapters.add(
      SubjectWithChapters(subject: subject, chapters: chapters),
    );
  }

  return subjectWithChapters;
}

class ChoosedSubjectsPage extends StatefulWidget {
  const ChoosedSubjectsPage({super.key});

  @override
  _ChoosedSubjectsPageState createState() => _ChoosedSubjectsPageState();
}

/// 题库页面，展示用户现在正在刷的题库
class _ChoosedSubjectsPageState extends State<ChoosedSubjectsPage> {
  String? _lastSubjectId;
  late Future<List<SubjectWithChapters>> subjectsWithChapters;

  @override
  void initState() {
    super.initState();
    _loadLastProgress();
    subjectsWithChapters = getSubjectsWithChapters();
  }

  void _refreshData() {
    setState(() {
      subjectsWithChapters = getSubjectsWithChapters();
    });
  }

  Future<void> _loadLastProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('lastSubjectId');
    if (id != null && id.isNotEmpty) {
      setState(() {
        _lastSubjectId = id;
      });
    }
  }

  Future<void> _saveLastProgress(
      String lastSubjectId, String lastChapterId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('lastSubjectId')) {
      await prefs.setString('lastSubjectId', lastSubjectId);
    }
    if (prefs.containsKey('lastChapterId')) {
      await prefs.setString('lastChapterId', lastChapterId);
    }
    debugPrint('保存上次做题记录: $lastSubjectId, $lastChapterId');
  }

  Future<void> _resumeLastQuestion() async {
    final prefs = await SharedPreferences.getInstance();

    final String? subjectId = prefs.getString('lastSubjectId');
    final String? chapterId = prefs.getString('lastChapterId');
    final int? lastQIndex = prefs.getInt('lastQIndex');

    debugPrint('读取上次做题记录: $subjectId, $chapterId, $lastQIndex');

    if (subjectId == null ||
        chapterId == null ||
        subjectId.isEmpty ||
        chapterId.isEmpty) {
      debugPrint('提示: 暂无上次做题记录');
      return;
    }

    final data = await getSubjectsWithChapters();

    final subjectWithChapters = data.firstWhereOrNull(
      (e) => e.subject.id == subjectId,
    );

    if (subjectWithChapters == null) {
      debugPrint('提示: 未找到对应课程');
      return;
    }

    final chapter = subjectWithChapters.chapters.firstWhereOrNull(
      (c) => c.id == chapterId,
    );

    if (chapter == null) {
      debugPrint('提示: 未找到对应章节');
      return;
    }

    // 直接跳转到题目页
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => QuestionGridPage(
          chapter: chapter,
          directJump: true,
        ),
      ),
    );

    _refreshData();
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) =>
      Center(child: Text('加载失败: $error'));

  /// 显示无数据提示
  Widget _buildEmptyMessage(String msg) => Center(child: Text(msg));

  /// 构建章节列表
  Widget _buildChapterList(
    BuildContext context,
    List<Chapter> chapters,
    Subject subject,
  ) {
    double correctProgress = subject.correct / (subject.total + 0.001);
    double incorrectProgress = subject.incorrect / (subject.total + 0.001);

    return ExpansionTile(
      key: PageStorageKey(subject.id), // ← 关键：稳定的 key
      initiallyExpanded: subject.id == _lastSubjectId,
      title: Row(
        children: [
          Expanded(
            flex: 80,
            child: Text(
              subject.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 20,
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
                        child: Container(height: 4, color: Colors.green),
                      ),
                      Expanded(
                        flex: (incorrectProgress * 100).toInt(),
                        child: Container(height: 4, color: Colors.red),
                      ),
                      Expanded(
                        flex: ((1 - correctProgress - incorrectProgress) * 100)
                            .toInt(),
                        child: Container(height: 4, color: Colors.grey[200]),
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

  /// 构建单个章节项
  Widget _buildChapterItem(BuildContext context, Chapter chapter) {
    double correctProgress = chapter.correct / (chapter.total + 0.001);
    double incorrectProgress = chapter.incorrect / (chapter.total + 0.001);

    return ListTile(
      title: Row(
        children: [
          SizedBox(width: 10),
          Expanded(
            flex: 85,
            child: Text(
              chapter.name,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 15,
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
                        child: Container(height: 4, color: Colors.green),
                      ),
                      Expanded(
                        flex: (incorrectProgress * 100).toInt(),
                        child: Container(height: 4, color: Colors.red),
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
        _saveLastProgress(chapter.subjectId, chapter.id);
        await Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (context) => QuestionGridPage(
              chapter: chapter,
              directJump: false,
            ),
          ),
        );
        _refreshData();
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
        leading: IconButton(
          icon: Icon(Icons.apps),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => (IdentityListPage()),
              ),
            );
            _refreshData();
          },
        ),
        actions: [
          Obx(() {
            return IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Icon(
                  themeController.getIcon(),
                  key: ValueKey(themeController.themeMode.value),
                ),
              ),
              // 切换主题模式
              onPressed: themeController.toggleTheme,
            );
          })
        ],
      ),
      body: FutureBuilder<List<SubjectWithChapters>>(
        future: subjectsWithChapters,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container();
          } else if (snapshot.hasError) {
            return _buildErrorMessage(snapshot.error);
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyMessage('您还没有正在学习的课程~');
          } else {
            final data = snapshot.data!;
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final subject = data[index].subject;
                final chapters = data[index].chapters;
                return Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                  child: _buildChapterList(context, chapters, subject),
                );
              },
            );
          }
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'resume',
            onPressed: _resumeLastQuestion,
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SubjectsListPage(),
                ),
              );
              _refreshData();
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
