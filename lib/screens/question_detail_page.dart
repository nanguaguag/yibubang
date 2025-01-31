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

  Widget submitBtn(int questionIndex) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: 60.0, // 按钮的高度
        child: ElevatedButton(
          onPressed: () {
            _submitAnswer(questionIndex);
          },
          child: const Text(
            '提交',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }

  Widget optionsList(int questionIndex) {
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
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.questions[index].typeStr ?? '未知题型',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.questions[index].title ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                optionsList(index),
                submitBtn(index),
              ],
            ),
          );
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

  void _submitAnswer(int questionIndex) {
    final String userAnswer = _selectedAnswer[questionIndex];
    //final List<dynamic> optionJson = getOptionJson(questionIndex);
    final answer = widget.questions[questionIndex].answer;
    //for (Map<String, dynamic> option in optionJson) {}
    print(userAnswer);
  }
}
