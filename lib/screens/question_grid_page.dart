import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'question_detail_page.dart';

import '../common/app_strings.dart';
import '../models/chapter.dart';
import '../models/question.dart';

// Question Status: 题目状态
// - 0: 未做
// - 1: 正确
// - 2: 错误
// - 3: 已斩

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
    _loadSettings();
    _jump2Question();
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

    // 根据不同的筛选条件进行筛选
    userQuestions = userQuestions.where((q) {
      if (category == 1 && q.status != 2) return false; // 只保留做错的题目
      if (category == 2 && q.collection != 1) return false; // 只保留收藏的题目
      if (category == 3 && q.status != 0) return false; // 只保留未做的题目
      if (cutType != 0 && q.cutQuestion != "") return false; // 过滤 cutType
      return true;
    }).toList();

    questions = questions.where((q) {
      // 过滤q.id不在userQuestions里的题目
      if (userQuestions.where((userQ) => userQ.id == q.id).isEmpty) {
        return false;
      }
      if (questionType != 0 && int.parse(q.type!) != questionType) {
        return false; // 过滤 单选题、多选题
      }
      return true;
    }).toList();

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
      await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => QuestionDetailPage(
            chapter: widget.chapter,
            questions: questions,
            userQuestions: userQuestions,
            questionIndex: lastQIndex,
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

  void clearUserAnswers() async {
    final futureQuestions = getQuestionsFromChapter(widget.chapter);
    List<UserQuestion> userQuestions = await getUserQuestions(futureQuestions);
    List<Question> questions = await futureQuestions;
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
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
                for (int i = 0; i < questions.length; i++) {
                  final uq = userQuestions[i];
                  final q = questions[i];
                  if (uq.status == 1 || uq.status == 2) {
                    bool prevCorrect = uq.status == 1; // 储存之前的状态
                    uq.userAnswer += ';'; // 末尾加上 ; 表示清除前面的做题记录
                    uq.status = 0;
                    updateQuestion(uq, q, prevCorrect: prevCorrect);
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
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
    final futureQuestions = getQuestionsFromChapter(widget.chapter);
    List<UserQuestion> userQuestions = await getUserQuestions(futureQuestions);
    List<Question> questions = await futureQuestions;
    for (UserQuestion q in userQuestions) {
      if (q.userAnswer.isEmpty || q.status == 0) {
        doneAll = false;
        break;
      }
    }
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
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
                for (int i = 0; i < questions.length; i++) {
                  final uq = userQuestions[i];
                  final q = questions[i];
                  if (uq.status == 2) {
                    uq.userAnswer += ';'; // 末尾加上 ; 表示清除前面的做题记录
                    uq.status = 0;
                    updateQuestion(uq, q, prevCorrect: false);
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
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

  /// 构建筛选部分
  Widget _buildFilterSection(
    String title,
    List<String> items,
    String selectedValue,
    Function(String) onSelected,
  ) {
    return Padding(
      padding: EdgeInsets.all(8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: EdgeInsets.all(5),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: 6),
            ...items.map((item) {
              final isSelected = selectedValue == item;
              return Padding(
                padding: EdgeInsets.fromLTRB(2, 0, 2, 0),
                child: ElevatedButton(
                  onPressed: () => onSelected(item),
                  style: isSelected
                      ? ElevatedButton.styleFrom(
                          padding: EdgeInsets.all(10),
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.deepPurple,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(13),
                            ),
                          ),
                        )
                      : ElevatedButton.styleFrom(
                          padding: EdgeInsets.all(10),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent, // Remove shadow
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
          ]),
        ),
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
            buttonColor = Colors.black26;
            break;
          default:
            buttonColor = Colors.black26;
            break;
        }

        return ElevatedButton(
          onPressed: () async {
            _savedScrollOffset = _scrollController.offset;
            await Navigator.push(
              context,
              CupertinoPageRoute(
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
        widthFactor: 0.7, // 宽度占父容器的70%
        child: Drawer(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero, // 设为0，去掉圆角
          ),
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 5),
              children: <Widget>[
                // 关闭按钮放置在侧边栏的顶部
                Row(children: [
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 10),
                    width: 4, // 控制竖条的宽度
                    height: 25, // 控制竖条的高度
                    color: Colors.deepOrange, // 竖条颜色
                  ),
                  Text(
                    '筛选',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () {
                          Navigator.pop(context); // 关闭侧边栏
                        },
                      ),
                    ),
                  ),
                ]),
                _buildFilterSection(
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
                _buildFilterSection(
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
                _buildFilterSection(
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
                _buildFilterSection(
                  '模式',
                  modesList,
                  modesList[mode],
                  (value) {
                    saveSettings();
                    setState(() {
                      mode = modesList.indexOf(value);
                    });
                  },
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
                    return _buildEmptyMessage('本章节中还没有题目哦~');
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
