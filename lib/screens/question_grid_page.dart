import '../common/adaptive_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'question_detail_page.dart';

import '../common/app_strings.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../models/answer_statistics.dart';

// Question Status: 题目状态
// - 0: 未做
// - 1: 正确
// - 2: 错误
// - 3: 已斩
// - 4: 待提交

class QuestionGridPage extends StatefulWidget {
  final Chapter chapter;
  final bool directJump;

  const QuestionGridPage({
    super.key,
    required this.chapter,
    this.directJump = false,
  });

  @override
  _QuestionGridPageState createState() => _QuestionGridPageState();
}

class _QuestionGridPageState extends State<QuestionGridPage> {
  late Future<List<Question>> allQuestions;
  late Future<List<UserQuestion>> allUserQuestions;
  final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0.0;

  // 筛选选项
  int cutType = 0;
  int questionType = 0;
  int category = 0;
  int mode = 0;

  // 本章节统计
  late Future<PeriodStats> _chapterStats;

  // 可选项
  final List<String> cutTypes = AppStrings.cutTypes;
  final List<String> questionTypes = AppStrings.questionTypes;
  final List<String> categories = AppStrings.categories;
  final List<String> modesList = AppStrings.modesList;

  @override
  void initState() {
    super.initState();
    // 初始化 Future 在 initState 中，这样可以访问 widget
    allQuestions = getQuestionsFromChapter(widget.chapter);
    allUserQuestions = getUserQuestions(allQuestions);
    _chapterStats = _loadChapterStats();
    _loadSettings();
    _jump2Question();
  }

  Future<PeriodStats> _loadChapterStats() async {
    try {
      final bankId = await activeBankId();
      return await getChapterPeriodStats(
        subjectId: widget.chapter.subjectId,
        chapterId: widget.chapter.id,
        bankId: bankId,
        startMs: 0,
        endMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('本章节统计加载失败：$error');
      return const PeriodStats(
        totalDuration: Duration.zero,
        answeredCount: 0,
        correctCount: 0,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshPage() async {
    final questions = getQuestionsFromChapter(widget.chapter);
    final userQuestions = getUserQuestions(questions);

    setState(() {
      allQuestions = questions;
      allUserQuestions = userQuestions;
      _chapterStats = _loadChapterStats();
    });

    await questions;
    await userQuestions;

    // 延迟恢复滚动位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_savedScrollOffset);
      }
    });
  }

  Future<MapEntry<List<Question>, List<UserQuestion>>> _filter(
    Future<List<Question>> questionsFuture,
    Future<List<UserQuestion>> userQuestionsFuture,
  ) async {
    List<Question> questions = await questionsFuture;
    List<UserQuestion> userQuestions = await userQuestionsFuture;
    // 1️⃣ 根据 category 和 cutType 先过滤 userQuestions
    userQuestions = userQuestions.where((uq) {
      if (category == 1 && uq.status != 2) return false; // 只保留做错的题目
      if (category == 2 && uq.collection != 1) return false; // 只保留收藏的题目
      if (category == 3 && uq.status != 0) return false; // 只保留未做的题目
      if (cutType == 1 && !uq.isCut) return false; // 过滤 cutType: 仅保留已斩
      if (cutType == 2 && uq.isCut) return false; // 过滤 cutType: 仅保留未斩
      return true;
    }).toList();
    // 2️⃣ 根据 questionType 先过滤 questions
    questions = questions.where((q) {
      final qType = int.tryParse(q.type ?? '');
      if (questionType != 0 && qType != questionType) {
        return false; // 过滤单选题、多选题
      }
      return true;
    }).toList();
    // 3️⃣ 构造两个 id 集合
    final Set<String> userIds = userQuestions.map((q) => q.id).toSet();
    final Set<String> questionIds = questions.map((q) => q.id).toSet();
    // 4️⃣ 取交集
    final Set<String> commonIds = userIds.intersection(questionIds);
    // 5️⃣ 双向同步过滤
    userQuestions =
        userQuestions.where((uq) => commonIds.contains(uq.id)).toList();
    questions = questions.where((q) => commonIds.contains(q.id)).toList();

    return MapEntry(questions, userQuestions);
  }

  /// 获取数据
  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 获取设置数据并更新状态
    setState(() {
      cutType = prefs.getInt('cutType') ?? 0;
      questionType = prefs.getInt('questionType') ?? 0;
      category = prefs.getInt('category') ?? 0;
      mode = prefs.getInt('mode') ?? 0;
    });
  }

  Future<void> _jump2Question() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int lastQIndex = prefs.getInt('lastQIndex') ?? -1;
    if (widget.directJump && lastQIndex >= 0) {
      //WidgetsBinding.instance.addPostFrameCallback((_) {
      //  // 延迟跳转到指定题目
      //  _scrollController.jumpTo(
      //    (lastQIndex / 5).floor() * 100.0,
      //  );
      //});
      List<Question> questions = await allQuestions;
      List<UserQuestion> userQuestions = await allUserQuestions;
      if (!mounted) return;
      if (questions.isEmpty) return;
      // lastQIndex 是上次的页码。题库更新后题量可能变化，或该记录可能来自
      // 其它章节，这里做边界保护，避免 PageController(initialPage: 越界) 崩溃。
      final int targetIndex = lastQIndex.clamp(0, questions.length - 1).toInt();
      await Navigator.push(
        context,
        adaptivePageRoute(
          builder: (context) => QuestionDetailPage(
            chapter: widget.chapter,
            questions: questions,
            userQuestions: userQuestions,
            questionIndex: targetIndex,
          ),
        ),
      );
    }
  }

  /// 保存设置
  Future<void> saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 保存设置数据
    await prefs.setInt('cutType', cutType);
    await prefs.setInt('questionType', questionType);
    await prefs.setInt('category', category);
    await prefs.setInt('mode', mode);
  }

  /// 切换模式：离开测试模式时，自动判分本章节遗留的「待提交」灰格，避免残留
  Future<void> _onModeChanged(int newMode) async {
    if (newMode == mode) return;
    final bool leavingTest = mode == 2 && newMode != 2;
    if (leavingTest) {
      final bool? confirmed = await _confirmLeaveTest();
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      mode = newMode;
    });
    await saveSettings();
    if (!leavingTest) return;
    // 放弃测试：清零累计用时并判分遗留待提交题
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('testElapsedMs', 0);
    final List<Question> questions = await allQuestions;
    final List<UserQuestion> userQuestions = await allUserQuestions;
    await gradePendingQuestions(questions, userQuestions);
    if (!mounted) return;
    _refreshPage();
  }

  /// 切换离开测试模式前的确认弹窗
  Future<bool?> _confirmLeaveTest() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出测试模式'),
          content: const Text('退出测试将自动判分已作答内容，确定继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
  }

  void clearUserAnswers() async {
    final List<Question> questions = await allQuestions;
    final List<UserQuestion> userQuestions = await allUserQuestions;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("重做本章节？"),
          content: Text("您确定要重做吗？该操作不可撤销！"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
              },
              child: Text("取消"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 关闭对话框
                for (int i = 0; i < questions.length; i++) {
                  final uq = userQuestions[i];
                  final q = questions[i];
                  if (uq.status == 1 || uq.status == 2) {
                    bool prevCorrect = uq.status == 1; // 储存之前的状态
                    uq.userAnswer += ';'; // 末尾加上 ; 表示清除前面的做题记录
                    uq.status = 0;
                    await updateQuestion(uq, q, prevCorrect: prevCorrect);
                  }
                }
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('已清除作答记录'),
                    duration: Duration(seconds: 1),
                  ),
                );
                _refreshPage();
              },
              child: Text("确认"),
            ),
          ],
        );
      },
    );
  }

  void clearWrongAnswers() async {
    bool doneAll = true;
    final MapEntry<List<Question>, List<UserQuestion>> filteredQuestions =
        await _filter(allQuestions, allUserQuestions);
    final List<Question> questions = filteredQuestions.key;
    final List<UserQuestion> userQuestions = filteredQuestions.value;
    for (UserQuestion q in userQuestions) {
      if (q.userAnswer.isEmpty || q.status == 0) {
        doneAll = false;
        break;
      }
    }
    if (!mounted) return;
    if (!doneAll) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先做完所有题目！'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("重做全部错题？"),
          content: Text("您确定要重做吗？该操作不可撤销！"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
              },
              child: Text("取消"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // 关闭对话框
                for (int i = 0; i < questions.length; i++) {
                  final uq = userQuestions[i];
                  final q = questions[i];
                  if (uq.status == 2) {
                    uq.userAnswer += ';'; // 末尾加上 ; 表示清除前面的做题记录
                    uq.status = 0;
                    await updateQuestion(uq, q, prevCorrect: false);
                  }
                }
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('已清除做错题目'),
                    duration: Duration(seconds: 1),
                  ),
                );
                _refreshPage();
              },
              child: Text("确认"),
            ),
          ],
        );
      },
    );
  }

  /// 显示加载进度条
  Widget _buildLoadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  /// 显示无数据提示
  Widget _buildEmptyMessage(String msg) {
    return Center(child: Text(msg));
  }

  /// 构建筛选部分（Material 3 ChoiceChip）
  Widget _buildFilterSection(
    String title,
    List<String> items,
    String selectedValue,
    Function(String) onSelected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              final isSelected = selectedValue == item;
              return ChoiceChip(
                label: Text(item),
                selected: isSelected,
                onSelected: (_) => onSelected(item),
                showCheckmark: false,
                selectedColor: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                ),
                side: BorderSide(
                  color: isSelected ? scheme.primary : scheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 本章节统计卡片
  Widget _buildChapterStatsCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '本章节统计',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<PeriodStats>(
            future: _chapterStats,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final stats = snapshot.data ??
                  const PeriodStats(
                    totalDuration: Duration.zero,
                    answeredCount: 0,
                    correctCount: 0,
                  );
              return Row(
                children: [
                  _StatItem(
                    icon: Icons.timer_outlined,
                    value: _fmtDuration(stats.totalDuration.inMilliseconds),
                    label: '总用时',
                    scheme: scheme,
                  ),
                  _StatItem(
                    icon: Icons.rate_review_outlined,
                    value: '${stats.answeredCount}',
                    label: '作答数',
                    scheme: scheme,
                  ),
                  _StatItem(
                    icon: Icons.check_circle_outline,
                    value: '${(stats.accuracy * 100).round()}%',
                    label: '正确率',
                    scheme: scheme,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionGrid(
    List<Question> questions,
    List<UserQuestion> userQuestions,
    int crossAxisCount,
    double crossSpacing,
    double buttonSize,
  ) {
    return GridView.builder(
      controller: _scrollController,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.0, // 设置 item 宽高比例,
        crossAxisSpacing: crossSpacing, // 横向间距
        mainAxisSpacing: 16, // 纵向间距
      ),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final int questionState = userQuestions[index].status;
        final bool cutted = userQuestions[index].isCut;
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
          case 3:
            buttonColor = Colors.orange;
            break;
          case 4:
            buttonColor = Colors.grey.withValues(alpha: 0.5);
            break;
          default:
            buttonColor = Colors.grey.withValues(alpha: 0.5);
            break;
        }

        return ElevatedButton(
          onPressed: () async {
            _savedScrollOffset = _scrollController.offset;
            await Navigator.push(
              context,
              adaptivePageRoute(
                builder: (context) => QuestionDetailPage(
                  chapter: widget.chapter,
                  questions: questions,
                  userQuestions: userQuestions,
                  questionIndex: index,
                ),
              ),
            );
            await _loadSettings();
            _refreshPage();
          },
          style: cutted
              ? ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: questionState == 0
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.white,
                  backgroundColor: buttonColor.withValues(alpha: 0.2),
                  shadowColor: Colors.grey.withValues(alpha: 0.2),
                  minimumSize: Size(buttonSize, buttonSize),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                )
              : ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor:
                      questionState == 0 ? Colors.black : Colors.white,
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
    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: Icon(Icons.restart_alt),
            onSelected: (String value) {
              if (value == 'redoAll') {
                clearUserAnswers();
              } else if (value == 'redoWrong') {
                clearWrongAnswers();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'redoAll',
                child: Text('全部重做'),
              ),
              const PopupMenuItem<String>(
                value: 'redoWrong',
                child: Text('重做错题'),
              ),
            ],
          ),
          Builder(
            builder: (context) => Padding(
              padding: EdgeInsets.only(right: 5),
              child: IconButton(
                icon: Icon(Icons.tune), // 自定义 Drawer 图标
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              ),
            ),
          ),
        ],
        title: Wrap(
          children: [
            Text(widget.chapter.name),
          ],
        ),
      ),
      endDrawer: FractionallySizedBox(
        widthFactor: 0.72, // 宽度占父容器的72%
        child: Drawer(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero, // 设为0，去掉圆角
          ),
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                // 头部
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  child: Row(
                    children: [
                      //Icon(
                      //  Icons.tune,
                      //  size: 22,
                      //  color: Theme.of(context).colorScheme.primary,
                      //),
                      //const SizedBox(width: 8),
                      //const Text(
                      //  '内容与筛选',
                      //  style: TextStyle(
                      //    fontSize: 20,
                      //    fontWeight: FontWeight.w700,
                      //  ),
                      //),
                      //const Spacer(),
                      //IconButton(
                      //  icon: const Icon(Icons.close),
                      //  onPressed: () {
                      //    Navigator.pop(context); // 关闭侧边栏
                      //  },
                      //),
                    ],
                  ),
                ),
                //const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: _buildChapterStatsCard(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '筛选',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFilterSection(
                    '斩题',
                    cutTypes,
                    cutTypes[cutType],
                    (value) {
                      saveSettings();
                      setState(() {
                        cutType = cutTypes.indexOf(value);
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFilterSection(
                    '题型',
                    questionTypes,
                    questionTypes[questionType],
                    (value) {
                      saveSettings();
                      setState(() {
                        questionType = questionTypes.indexOf(value);
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFilterSection(
                    '分类',
                    categories,
                    categories[category],
                    (value) {
                      saveSettings();
                      setState(() {
                        category = categories.indexOf(value);
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFilterSection(
                    '模式',
                    modesList,
                    modesList[mode],
                    (value) {
                      _onModeChanged(modesList.indexOf(value));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 题目列表
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child:
                  FutureBuilder<MapEntry<List<Question>, List<UserQuestion>>>(
                future: _filter(allQuestions, allUserQuestions),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingIndicator();
                  } else if (snapshot.hasError) {
                    return _buildErrorMessage(snapshot.error);
                  } else if (!snapshot.hasData || snapshot.data!.key.isEmpty) {
                    return _buildEmptyMessage('在当前筛选条件下\n本章节中还没有题目哦~');
                  } else {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // 每个按钮的固定宽度和高度
                        const double btnSize = 52.0;
                        double width = constraints.maxWidth;
                        // 计算每行可以显示的按钮数量 (24: 横向间距最小值)
                        final int count =
                            ((width + 24) / (btnSize + 24)).floor();
                        double crossSpacing =
                            (width - count * btnSize) / (count - 1);
                        return _buildQuestionGrid(
                          snapshot.data!.key,
                          snapshot.data!.value,
                          count,
                          crossSpacing,
                          btnSize,
                        );
                      },
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 章节统计卡片内的单个指标项。
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final ColorScheme scheme;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDuration(int ms) {
  final min = (ms / 60000).round();
  if (min < 60) return '$min分';
  final h = min ~/ 60;
  final mm = min % 60;
  return mm == 0 ? '$h小时' : '$h小时$mm分';
}
