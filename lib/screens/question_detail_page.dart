import 'package:flutter/material.dart';
import 'dart:convert';
import '../db/question.dart';
import '../db/chapter.dart';

class QuestionDetailPage extends StatefulWidget {
  final Chapter chapter;
  final Question question;

  const QuestionDetailPage({
    super.key,
    required this.chapter,
    required this.question,
  });

  @override
  _QuestionDetailPageState createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  String? _selectedAnswer;

  @override
  void initState() {
    super.initState();
    // Set default selected answer if available
    _selectedAnswer = widget.question.userAnswer;
  }

  @override
  Widget build(BuildContext context) {
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
    final List<dynamic> optionsJson =
        json.decode(widget.question.option ?? defaultOptionString);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapter.name),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.question.typeStr ?? '未知题型',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Text(
              widget.question.title ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: optionsJson.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> option = optionsJson[index];
                  return RadioListTile<String>(
                    title: Text(option['key'] + '. ' + option['title']),
                    value: option['key'],
                    groupValue: _selectedAnswer,
                    onChanged: (value) {
                      setState(() {
                        _selectedAnswer = value;
                      });
                    },
                  );
                },
              ),
            ),
            // Submit button
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                height: 60.0, // 按钮的高度
                child: ElevatedButton(
                  onPressed: () {
                    _submitAnswer();
                  },
                  child: Text('提交', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitAnswer() {
    if (_selectedAnswer != null) {
      // 提交逻辑
      print('用户选择了：$_selectedAnswer');
    } else {
      // 未选择提示
      print('请选择一个选项');
    }
  }
}
