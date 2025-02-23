import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../db/question.dart';
import '../db/chapter.dart';

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
  List<String> _selectedAnswer = [];
  List<String> modesList = ['练习模式', '快刷模式', '测试模式', '背题模式'];

  @override
  void initState() {
    loadSettings();
    super.initState();
    for (Question q in widget.questions) {
      _selectedAnswer.add(q.userAnswer ?? '');
    }
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
    final String answer = widget.questions[questionIndex].answer ?? '';
    final String userAnswer = _selectedAnswer[questionIndex];
    for (Map<String, dynamic> option in optionJson) {
      final String key = option['key'];
      final bool answerContains = answer.contains(key);
      final bool userAnswerContains = userAnswer.contains(key);
      if (answerContains && userAnswerContains) {
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

  Widget buildAnalysis(String title, IconData icon, String analysisText) {
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
          Text(
            analysisText,
            style: TextStyle(
              fontSize: 16,
              height: 1.8,
              color: Colors.black87, // 内容文字颜色
            ),
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
          const SizedBox(height: 10),
          Text(
            '答案：正确答案 ${question.answer}, 你的答案 $userAnswer',
            style: TextStyle(
              fontSize: 14,
              color: sortString(userAnswer) == sortString(answer)
                  ? Colors.green
                  : Colors.red,
            ),
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
          SizedBox(height: 30),
          buildAnalysis(
            '考点还原',
            Icons.location_on_outlined,
            question.restore ?? '',
          ),
          SizedBox(height: 10),
          buildAnalysis(
            '答案解析',
            Icons.lightbulb_outlined,
            question.explain ?? '',
          ),
        ],
      ),
    );
  }

  Widget buildQuestion(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    switch (question.status) {
      case 0:
        return unansweredQuestion(questionIndex);
      case 1:
        return answeredQuestion(questionIndex);
      case 2:
        return answeredQuestion(questionIndex);
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
              shape: CircleBorder(), //圆形
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
        controller: PageController(initialPage: widget.questionIndex),
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
    if (question.type == '1' && userAnswer.isEmpty) {
      Fluttertoast.showToast(
        msg: "不能不填答案哦~",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    } else if (question.type == '2' && userAnswer.length <= 1) {
      Fluttertoast.showToast(
        msg: "多选题要选择多个选项哦~",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    } else {
      if (sortString(userAnswer) == sortString(answer)) {
        question.status = 1;
      } else {
        question.status = 2;
      }
      updateQuestion(question, userAnswer);
      setState(() {
        widget.questions[questionIndex].status = question.status;
      });
    }
  }
}
