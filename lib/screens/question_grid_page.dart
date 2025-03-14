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

  const QuestionGridPage({super.key, required this.chapter});

  //const SubjectsListPage({super.key});

  @override
  _QuestionGridPageState createState() => _QuestionGridPageState();
}

class _QuestionGridPageState extends State<QuestionGridPage> {
  late Future<List<Question>> allQuestions;
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
    loadSettings();
  }

  Future<List<Question>> filter(Future<List<Question>> questionsFuture) async {
    List<Question> questions = await questionsFuture;

    // 根据不同的筛选条件进行筛选
    questions = questions.where((q) {
      if (category == 1 && q.status != 2) return false; // 只保留做错的题目
      if (category == 2 && q.collection != 1) return false; // 只保留收藏的题目
      if (category == 3 && q.status != 0) return false; // 只保留未做的题目
      if (cutType != 0 && q.cutQuestion != "") return false; // 过滤 cutType
      if (questionType != 0 && int.parse(q.type!) != questionType) {
        return false; // 过滤 单选题、多选题
      }
      return true;
    }).toList();

    return questions;
  }

  // 获取数据
  Future<void> loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 获取设置数据并更新状态
    setState(() {
      cutType = prefs.getInt('cutType') ?? 0;
      questionType = prefs.getInt('questionType') ?? 0;
      category = prefs.getInt('category') ?? 0;
      mode = prefs.getInt('mode') ?? 0;
    });
  }

  Future<void> saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 保存设置数据
    await prefs.setInt('cutType', cutType);
    await prefs.setInt('questionType', questionType);
    await prefs.setInt('category', category);
    await prefs.setInt('mode', mode);
  }

  void clearUserAnswers() async {
    List<Question> questions = await getQuestionsFromChapter(widget.chapter);
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
                for (Question q in questions) {
                  if (q.userAnswer.isNotEmpty) {
                    q.userAnswer += ';'; // 末尾加上 ; 表示清除前面的做题记录
                    q.status = 0;
                    updateQuestion(q);
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已清除作答记录'),
                    duration: Duration(seconds: 1),
                  ),
                );
                setState(() {
                  // 刷新所有题目
                  allQuestions = getQuestionsFromChapter(
                    widget.chapter,
                  );
                });
              },
              child: Text("确认"),
            ),
          ],
        );
      },
    );
  }

  // 显示加载进度条
  Widget _buildLoadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  // 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  // 显示无数据提示
  Widget _buildEmptyMessage(String msg) {
    return Center(child: Text(msg));
  }

  // 构建筛选部分
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

  Widget buildQuestionGrid(
    List<Question> questions,
    int crossAxisCount,
    double crossSpacing,
    double buttonSize,
  ) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.0, // 设置 item 宽高比例,
        crossAxisSpacing: crossSpacing, // 横向间距
        mainAxisSpacing: 16, // 纵向间距
      ),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final int questionState = questions[index].status;
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
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuestionDetailPage(
                  chapter: widget.chapter,
                  questions: questions,
                  questionIndex: index,
                ),
              ),
            );
            loadSettings();
            setState(() {
              allQuestions = getQuestionsFromChapter(
                widget.chapter,
              );
            });
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
        actions: [
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
        title: Row(
          children: [
            Text(widget.chapter.name),
            Spacer(),
            IconButton(
              icon: Icon(Icons.restart_alt),
              onPressed: clearUserAnswers,
            ),
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
              child: FutureBuilder<List<Question>>(
                future: filter(allQuestions),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingIndicator();
                  } else if (snapshot.hasError) {
                    return _buildErrorMessage(snapshot.error);
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                        return buildQuestionGrid(
                          snapshot.data!,
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
