import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/image_view.dart';
import '../db/chapter.dart';
import '../db/question.dart';

class QuestionDetailPage extends StatefulWidget {
  final Chapter chapter;
  final List<Question> questions;
  final int questionIndex;

  const QuestionDetailPage({
    super.key,
    required this.chapter,
    required this.questions,
    required this.questionIndex,
  });

  @override
  _QuestionDetailPageState createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  int mode = 0;
  final List<String> _selectedAnswer = [];
  List<String> modesList = ['练习模式', '快刷模式', '测试模式', '背题模式'];
  // 创建 PageController
  PageController _pageController = PageController();

  @override
  void initState() {
    loadSettings();
    super.initState();
    _pageController = PageController(initialPage: widget.questionIndex);
    for (Question q in widget.questions) {
      _selectedAnswer.add(q.userAnswer ?? '');
    }
  }

  // 控制翻到下一页的方法
  void _nextPage() {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 获取数据
  Future<void> loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      mode = prefs.getInt('mode') ?? 0;
    });
  }

  Future<void> saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', mode);
  }

  Widget submitButton(int questionIndex) {
    // 如果是快刷/测试模式且为单选题，不显示提交按钮
    if ((mode == 1 || mode == 2) &&
        widget.questions[questionIndex].type == '1') {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: 60.0, // 按钮的高度
        child: ElevatedButton(
          onPressed: () {
            submitAnswer(questionIndex);
          },
          child: const Text(
            '提交',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }

  Widget checkableOptionsList(int questionIndex) {
    final List<dynamic> optionJson = getOptionJson(questionIndex);
    return Expanded(
      child: ListView.builder(
        itemCount: optionJson.length,
        itemBuilder: (context, index) {
          final Map<String, dynamic> option = optionJson[index];
          switch (widget.questions[questionIndex].type) {
            case '1': // 单选题
              return RadioListTile<String>(
                title: Text("${option['key']}. ${option['title']}"),
                value: option['key'],
                groupValue: _selectedAnswer[questionIndex],
                onChanged: (String? value) {
                  setState(() {
                    _selectedAnswer[questionIndex] = value ?? '';
                  });
                  if (mode == 1 || mode == 2) {
                    // 快刷模式 && 测试模式, 单选题自动提交
                    submitAnswer(questionIndex);
                  }
                },
              );
            case '2': // 多选题
              return CheckboxListTile(
                title: Text("${option['key']}. ${option['title']}"),
                value: _selectedAnswer[questionIndex].contains(option['key']),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) {
                  setState(() {
                    bool checked = _selectedAnswer[questionIndex].contains(
                      option['key'],
                    );
                    if (value == true && !checked) {
                      _selectedAnswer[questionIndex] += option['key'];
                    } else if (value == false && checked) {
                      _selectedAnswer[questionIndex] =
                          _selectedAnswer[questionIndex]
                              .replaceAll(option['key'], '');
                    }
                  });
                },
              );
            default:
              return const Text('未知的题目类型');
          }
        },
      ),
    );
  }

  Widget questionHeaders(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              question.typeStr ?? '未知题型',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            Spacer(),
            Padding(
              // 3: (22-16)/2
              padding: EdgeInsets.fromLTRB(5, 0, 5, 3),
              child: Text(
                '${questionIndex + 1}',
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '/ ${widget.questions.length}',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          question.title ?? '',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget unansweredQuestion(int questionIndex) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          questionHeaders(questionIndex),
          checkableOptionsList(questionIndex),
          submitButton(questionIndex),
        ],
      ),
    );
  }

  Widget buildOptions(int questionIndex) {
    final List<dynamic> optionJson = getOptionJson(questionIndex);
    final Question question = widget.questions[questionIndex];
    final String answer = question.answer ?? '';
    final String userAnswer = _selectedAnswer[questionIndex];
    for (Map<String, dynamic> option in optionJson) {
      final String key = option['key'];
      final bool answerContains = answer.contains(key);
      final bool userAnswerContains = userAnswer.contains(key);
      if ((mode == 3 && question.status == 0) || question.status == 4) {
        if (answerContains) {
          option['color'] = Colors.black87;
          option['icon'] = Icons.check_circle;
        } else {
          option['color'] = Colors.grey;
          option['icon'] = Icons.circle_outlined;
        }
      } else if (answerContains && userAnswerContains) {
        option['color'] = Colors.green;
        option['icon'] = Icons.check_circle;
      } else if (answerContains && !userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.check_circle;
      } else if (!answerContains && userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.cancel;
      } else {
        option['color'] = Colors.grey;
        option['icon'] = Icons.circle_outlined;
      }
    }
    return Column(
      children: List.generate(optionJson.length, (index) {
        final Map<String, dynamic> option = optionJson[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                option['icon'],
                color: option['color'],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "${option['key']}. ${option['title']}",
                    style: TextStyle(
                      fontSize: 16.5,
                      color: option['color'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageView(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget buildTextWithImage(String text, String imgUrl) {
    // split text with regex: (?:[\u4e00-\u9fa5]+)?P\d+(?:-P\d+)?
    // 1. (?:[\u4e00-\u9fa5]+)? : optional chinese characters
    // 2. P\d+ : P + digits
    // 3. (?:-P\d+)? : optional -P + digits
    final RegExp regex = RegExp(r'(?:[\u4e00-\u9fa5]+)?P\d+(?:-P\d+)?');
    final List<String> parts = text.split(regex);
    final List<String> imageUrls = [];
    List<String> matches =
        regex.allMatches(text).map((match) => match.group(0)!).toList();
    // merge parts and matches
    for (int i = 0; i < matches.length; i++) {
      parts.insert(2 * i + 1, matches[i]);
      imageUrls.insert(
        i,
        "$imgUrl${matches[i]}-${i + 1}.jpg?x-oss-process=style/water_mark",
      );
    }
    return Text.rich(
      TextSpan(
        children: List.generate(parts.length, (index) {
          if (index.isEven) {
            return TextSpan(
              text: parts[index],
              style: TextStyle(
                fontSize: 16,
                height: 1.8,
                color: Colors.black87,
              ),
            );
          } else {
            return WidgetSpan(
              child: ElevatedButton(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(
                    EdgeInsets.zero,
                  ),
                  minimumSize: WidgetStateProperty.all(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                  elevation: WidgetStateProperty.all(0), // 去掉阴影
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      parts[index],
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.deepOrange,
                      ),
                    ),
                    Icon(
                      Icons.photo,
                      size: 18,
                      color: Colors.deepOrange,
                    )
                  ],
                ),
                onPressed: () {
                  _showFullScreenImage(
                    context,
                    imageUrls,
                    index ~/ 2,
                  );
                },
              ),
            );
          }
        }),
      ),
    );
  }

  Widget buildAnalysis(
      String title, IconData icon, String analysisText, Question q) {
    Color orangeAccent = Color(0xFFB39D6B);
    return Container(
      color: Color(0xFFF9F4E9), // 设置背景颜色 #f9f4e9
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: orangeAccent, size: 24),
              SizedBox(width: 6), // 图标与文字间距
              Text(
                title, // 标题文字
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: orangeAccent, // 标题颜色
                ),
              ),
            ],
          ),
          SizedBox(height: 6), // 标题与内容间距
          Divider(
            color: orangeAccent, // 分割线颜色
            thickness: 1, // 分割线厚度
          ),
          SizedBox(height: 6), // 分割线与内容间距
          buildTextWithImage(
            analysisText,
            'https://ykb-app-files.yikaobang.com.cn/question/restore/${q.nativeAppId}/${q.number}',
          ),
        ],
      ),
    );
  }

  Widget answeredQuestion(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    final String userAnswer = _selectedAnswer[questionIndex];
    final String answer = question.answer ?? '';
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        shrinkWrap: true, // 让外层 ListView 适应内容
        physics: ClampingScrollPhysics(), // 正常滚动
        children: [
          questionHeaders(questionIndex),
          buildOptions(questionIndex),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '答案：正确答案 $answer, 你的答案 ',
                style: TextStyle(fontSize: 14),
              ),
              Text(
                userAnswer,
                style: TextStyle(
                  fontSize: 14,
                  color: question.status == 1 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          //SizedBox(height: 10),
          //Row(
          //  children: [
          //    Text('难度'),
          //    SizedBox(width: 10),
          //    Icon(Icons.star, color: Colors.orange),
          //    Icon(Icons.star, color: Colors.orange),
          //    Icon(Icons.star_border),
          //    Icon(Icons.star_border),
          //    Icon(Icons.star_border),
          //  ],
          //),
          SizedBox(height: 20),
          buildAnalysis(
            '考点还原',
            Icons.location_on_outlined,
            question.restore ?? '',
            question,
          ),
          SizedBox(height: 10),
          buildAnalysis(
            '答案解析',
            Icons.lightbulb_outlined,
            question.explain ?? '',
            question,
          ),
        ],
      ),
    );
  }

  Widget cuttedQuestion(int questionIndex) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text("该题目已斩"),
    );
  }

  Widget buildQuestion(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    if (mode == 3) {
      // 背题模式, 直接显示正确答案
      return answeredQuestion(questionIndex);
    }
    switch (question.status) {
      case 0: // 未作答
        return unansweredQuestion(questionIndex);
      case 1: // 正确作答
        return answeredQuestion(questionIndex);
      case 2: // 错误回答
        return answeredQuestion(questionIndex);
      case 3: // 已斩题
        return cuttedQuestion(questionIndex);
      case 4: // 测试模式 - 已作答
        return unansweredQuestion(questionIndex);
      default:
        return const Text('未知的题目状态');
    }
  }

  // 额外的图标按钮功能
  void _onQuestionCutted() {
    print('额外的按钮被点击了！');
  }

  void _onCalulateSatistics() {
    print('另一个按钮被点击了！');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapter.name),
        actions: <Widget>[
          // 额外的图标按钮 1
          //IconButton(
          //  icon: Icon(Icons.visibility_off),
          //  onPressed: _onQuestionCutted,
          //),
          ElevatedButton(
            onPressed: _onQuestionCutted,
            style: ElevatedButton.styleFrom(
              shape: CircleBorder(), // 圆形
              backgroundColor: Colors.transparent, // 设置透明背景
              shadowColor: Colors.transparent, // 去掉阴影
              elevation: 4, // 按钮阴影
              padding: EdgeInsets.all(0), // 去掉内边距
            ),
            child: Padding(
              padding: EdgeInsets.all(7),
              child: Text(
                "斩",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: _onCalulateSatistics,
          ),
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              setState(() {
                mode = value;
              });
              saveSettings();
            },
            itemBuilder: (context) {
              return List.generate(modesList.length, (index) {
                return PopupMenuItem<int>(
                  value: index,
                  child: Row(
                    children: [
                      Text(modesList[index]),
                      SizedBox(width: 8),
                      if (mode == index) Icon(Icons.check, size: 20),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          return buildQuestion(index);
        },
      ),
    );
  }

  List<dynamic> getOptionJson(int questionIndex) {
    const defaultOptionString = '''[{
        "title": "A选项加载失败",
        "img": "",
        "key": "A",
        "img_height": "0",
        "img_width": "0"
      },
      {
        "title": "B选项加载失败",
        "img": "",
        "key": "B",
        "img_height": "0",
        "img_width": "0"
      },
      {
        "title": "C选项加载失败",
        "img": "",
        "key": "C",
        "img_height": "0",
        "img_width": "0"
      }
    ]''';

    return json.decode(
      widget.questions[questionIndex].option ?? defaultOptionString,
    );
  }

  String sortString(String str) {
    // 将字符串转换为字符列表并排序
    List<String> chars = str.split('')..sort();
    // 将字符列表转换回字符串
    String sortedStr = chars.join();
    return sortedStr;
  }

  void submitAnswer(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    final String userAnswer = _selectedAnswer[questionIndex];
    //final List<dynamic> optionJson = getOptionJson(questionIndex);
    final String answer = question.answer ?? '';
    question.userAnswer = userAnswer;
    if (question.type == '1' && userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不能不填答案哦~')),
      );
    } else if (question.type == '2' && userAnswer.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('多选题要选择多个选项哦~')),
      );
    } else if (mode == 2) {
      question.status = 4; // 测试模式 - 已作答
      updateQuestion(question);
      setState(() {
        widget.questions[questionIndex].status = question.status;
      });
      _nextPage();
    } else {
      if (sortString(userAnswer) == sortString(answer)) {
        question.status = 1; // 回答正确
      } else {
        question.status = 2; // 回答错误
      }
      updateQuestion(question);
      setState(() {
        widget.questions[questionIndex].status = question.status;
      });
      if (question.status == 1 && mode == 1) {
        // 快刷模式自动翻页 || 测试模式自动翻页
        _nextPage();
      }
    }
  }
}
