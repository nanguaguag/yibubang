import '../common/adaptive_route.dart';
import '../common/platform_adaptive.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/screens/question_grid_page.dart';
import '../common/app_strings.dart';
import 'subjects_list_page.dart';
import 'question_bank_page.dart';
import 'search_page.dart';
import '../models/subject.dart';
import '../models/chapter.dart';
import '../widgets/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cloud_sync_service.dart';

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

T? _firstWhereOrNull<T>(Iterable<T> iterable, bool Function(T) test) {
  for (final e in iterable) {
    if (test(e)) return e;
  }
  return null;
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
  final ThemeController themeController = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    _loadLastProgress();
    themeController.recoverTheme(); // 恢复主题
    subjectsWithChapters = getSubjectsWithChapters();
    _maybeAutoResume();
    CloudSyncService.instance.addListener(_refreshData);
  }

  @override
  void dispose() {
    CloudSyncService.instance.removeListener(_refreshData);
    super.dispose();
  }

  bool _autoResumeTriggered = false;

  // 「启动自动继续上次进度」开关开启时，进入首页后自动跳到上次题目。
  Future<void> _maybeAutoResume() async {
    if (_autoResumeTriggered) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('autoResume') ?? false)) return;
    _autoResumeTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resumeLastQuestion();
    });
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
    final activeBankId = prefs.getString('activeBankId') ?? 'dental_final';
    await prefs.setString('lastProgressBankId', activeBankId);
    if (prefs.containsKey('lastSubjectId')) {
      await prefs.setString('lastSubjectId', lastSubjectId);
    }
    if (prefs.containsKey('lastChapterId')) {
      await prefs.setString('lastChapterId', lastChapterId);
    }
    // 重置题目索引
    if (prefs.containsKey('lastQIndex')) {
      await prefs.setInt('lastQIndex', -1);
    }
    debugPrint('保存上次做题记录: $lastSubjectId, $lastChapterId');
  }

  Future<void> _resumeLastQuestion() async {
    final prefs = await SharedPreferences.getInstance();
    final activeBankId = prefs.getString('activeBankId') ?? 'dental_final';
    final progressBankId = prefs.getString('lastProgressBankId');
    if (progressBankId != null && progressBankId != activeBankId) {
      debugPrint('上次做题记录属于其他题库，跳过自动恢复');
      return;
    }

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

    final subjectWithChapters = _firstWhereOrNull(
      data,
      (e) => e.subject.id == subjectId,
    );

    if (subjectWithChapters == null) {
      debugPrint('提示: 未找到对应课程');
      return;
    }

    final chapter = _firstWhereOrNull(
      subjectWithChapters.chapters,
      (c) => c.id == chapterId,
    );

    if (chapter == null) {
      debugPrint('提示: 未找到对应章节');
      return;
    }

    if (!mounted) return;

    // 直接跳转到题目页
    await Navigator.push(
      context,
      adaptivePageRoute(
        builder: (context) => QuestionGridPage(
          chapter: chapter,
          directJump: true,
        ),
      ),
    );

    _refreshData();
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, size: 56),
              const SizedBox(height: 16),
              const Text('当前还没有可用题库，请先导入或下载题库'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _navigateToBankManagement,
                icon: const Icon(Icons.storage_outlined),
                label: const Text('打开题库管理'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );

  /// 打开题库管理页（桌面端居中模态弹窗，移动端左侧滑入）
  Future<void> _navigateToBankManagement() async {
    if (isDesktopLayout(context)) {
      await pushAdaptiveModalPage(
        context,
        builder: (_) => const QuestionBankPage(),
      );
    } else {
      await Navigator.push(context, _openBankManagement());
    }
    _refreshData();
  }

  /// 题库管理页：从左侧滑入，更符合抽屉/侧边栏的直觉
  Route<void> _openBankManagement() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const QuestionBankPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    );
  }

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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
          adaptivePageRoute(
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
    // 显式依赖主题：主题切换时重建整棵子树，确保标题文字颜色即时刷新
    Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '题库管理',
          icon: const Icon(Icons.storage_outlined),
          onPressed: _navigateToBankManagement,
        ),
        title: const Text(AppStrings.selectedSubjectsTitle),
        actions: [
          IconButton(
            tooltip: '搜索题目',
            icon: const Icon(Icons.search),
            onPressed: () async {
              await pushAdaptiveModalPage(
                context,
                builder: (_) => const QuestionSearchPage(),
              );
            },
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeController,
            builder: (context, mode, _) {
              return IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
                  child: Icon(
                    themeController.getIcon(),
                    key: ValueKey(mode),
                  ),
                ),
                // 切换主题模式
                onPressed: themeController.toggleTheme,
              );
            },
          )
        ],
      ),
      body: FutureBuilder<List<SubjectWithChapters>>(
        future: subjectsWithChapters,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
              await pushAdaptiveModalPage(
                context,
                builder: (context) => const SubjectsListPage(),
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
