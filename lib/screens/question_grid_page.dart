import 'package:flutter/material.dart';
import 'question_detail_page.dart';
import '../db/chapter.dart';
import '../db/question.dart';

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
  String selectedCut = '全部';
  String selectedType = '全部';
  String selectedCategory = '全部';
  String selectedMode = '练习模式';

  // 可选项
  final List<String> cutTypes = ['全部', '已斩', '未斩'];
  final List<String> questionTypes = ['全部', '多选题', '单选题'];
  final List<String> categories = ['全部', '做错的', '收藏的', '未做的'];
  final List<String> modes = ['练习模式', '快刷模式', '测试模式', '背题模式'];

  @override
  void initState() {
    super.initState();
    // 初始化 Future 在 initState 中，这样可以访问 widget
    allQuestions = getQuestionsFromChapter(widget.chapter);
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
        final int? questionState = questions[index].status;
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
          default:
            buttonColor = Colors.white70;
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
        title: Text(widget.chapter.name),
      ),
      endDrawer: Drawer(
        width: 360,
        child: ListView(
          padding: EdgeInsets.symmetric(vertical: 10),
          children: <Widget>[
            //UserAccountsDrawerHeader(
            //  accountName: Text('John Doe'),
            //  accountEmail: Text('johndoe@example.com'),
            //  currentAccountPicture: CircleAvatar(
            //    backgroundColor: Colors.orange,
            //    child: Text('J'),
            //  ),
            //),
            // 关闭按钮放置在侧边栏的顶部
            Row(children: [
              Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.tune),
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
                child: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    Navigator.pop(context); // 关闭侧边栏
                  },
                ),
              ),
            ]),
            _buildFilterSection('斩题', cutTypes, selectedCut, (value) {
              setState(() => selectedCut = value);
            }),
            _buildFilterSection('题型', questionTypes, selectedType, (value) {
              setState(() => selectedType = value);
            }),
            _buildFilterSection('分类', categories, selectedCategory, (value) {
              setState(() => selectedCategory = value);
            }),
            _buildFilterSection('模式', modes, selectedMode, (value) {
              setState(() => selectedMode = value);
            }),
          ],
        ),
      ),
      body: Column(
        children: [
          // 题目列表
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FutureBuilder<List<Question>>(
                future: allQuestions,
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
