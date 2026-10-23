import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/screens/question_detail/question_detail_controller.dart';
import 'package:yibubang/screens/question_detail/question_page_item.dart';

void main() {
  testWidgets('QuestionPageItem cut and reveal state test', (tester) async {
    final chapter = Chapter(
      id: 'c1',
      name: '测试章节',
      subjectId: 's1',
      correct: 0,
      incorrect: 0,
      total: 1,
    );
    final question = Question(
      id: 'q1',
      title: '下列哪项属于牙体硬组织？',
      type: '1',
      typeStr: '单选题',
      answer: 'A',
      userAnswer: '',
      option: '[{"key":"A","title":"牙釉质"},{"key":"B","title":"牙髓"}]',
    );
    final userQuestion = UserQuestion(
      id: 'q1',
      chapterId: 'c1',
      chapterParentId: 's1',
      cutQuestion: '1', // 初始为已斩
      userAnswer: '',
      status: 0,
      collection: 0,
    );

    final controller = QuestionDetailController(
      chapter: chapter,
      questions: [question],
      userQuestions: [userQuestion],
      initialIndex: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPageItem(
            question: question,
            userQuestion: userQuestion,
            index: 0,
            controller: controller,
          ),
        ),
      ),
    );

    // 1. 验证斩题后 100% 显示“该题目已斩”和“显示题目内容”按钮
    expect(find.text('该题目已斩'), findsOneWidget);
    expect(find.text('显示题目内容'), findsOneWidget);
    expect(find.textContaining('牙釉质'), findsNothing);

    // 2. 点击“显示题目内容”按钮
    await tester.tap(find.text('显示题目内容'));
    await tester.pumpAndSettle();

    // 验证题目选项已显示，且顶部显示提示条
    expect(find.textContaining('牙釉质'), findsOneWidget);
    expect(find.text('隐藏题目内容'), findsOneWidget);

    // 3. 点击“隐藏题目内容”按钮
    await tester.tap(find.text('隐藏题目内容'));
    await tester.pumpAndSettle();

    expect(find.text('显示题目内容'), findsOneWidget);
    expect(find.textContaining('牙釉质'), findsNothing);

    // 4. 取消斩题
    userQuestion.isCut = false;
    controller.notifyListeners();
    await tester.pumpAndSettle();

    // 验证立刻显示所有内容，不再显示“该题目已斩”
    expect(find.text('该题目已斩'), findsNothing);
    expect(find.textContaining('牙釉质'), findsOneWidget);
  });
}
