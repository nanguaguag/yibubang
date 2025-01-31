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
  List<String> _selectedAnswer = [];

  @override
  void initState() {
    super.initState();
    for (Question q in widget.questions) {
      _selectedAnswer.add(q.userAnswer ?? '');
    }
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

  Widget unansweredQuestion(int questionIndex) {
    final Question question = widget.questions[questionIndex];
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.typeStr ?? '未知题型',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Icon(option['icon'], color: option['color']),
              ),
              Expanded(
                child: Text(
                  "${option['key']}. ${option['title']}",
                  style: TextStyle(
                    fontSize: 18,
                    color: option['color'],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget buildRestore(String restoreText) {
    return Container(
      color: Color(0xFFF9F4E9), // 设置背景颜色 #f9f4e9
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on, // 坐标图标
                color: Color(0xFFB39D6B), // 图标颜色
                size: 24,
              ),
              SizedBox(width: 6), // 图标与文字间距
              Text(
                '考点还原', // 标题文字
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB39D6B), // 标题颜色
                ),
              ),
            ],
          ),
          SizedBox(height: 6), // 标题与内容间距
          Divider(
            color: Color(0xAAB39D6B), // 分割线颜色
            thickness: 1, // 分割线厚度
          ),
          SizedBox(height: 6), // 分割线与内容间距
          Text(
            restoreText,
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
          Text(
            question.typeStr ?? '未知题型',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
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
          SizedBox(height: 10),
          Row(
            children: [
              Text('难度'),
              SizedBox(width: 10),
              Icon(Icons.star, color: Colors.orange),
              Icon(Icons.star, color: Colors.orange),
              Icon(Icons.star_border),
              Icon(Icons.star_border),
              Icon(Icons.star_border),
            ],
          ),
          SizedBox(height: 30),
          buildRestore(question.restore ?? ''),
          SizedBox(height: 10),
          buildRestore(question.explain ?? ''),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapter.name),
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
