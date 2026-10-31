import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/screens/question_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Question> buildQuestions() {
    const String options =
        '[{"key":"A","title":"选项甲"},{"key":"B","title":"选项乙"},'
        '{"key":"C","title":"选项丙"}]';
    return <Question>[
      Question(
        id: 'q1',
        title: '第一题（多选）',
        type: '2',
        typeStr: '多选题',
        answer: 'AB',
        userAnswer: '',
        option: options,
      ),
      Question(
        id: 'q2',
        title: '第二题（多选）',
        type: '2',
        typeStr: '多选题',
        answer: 'AC',
        userAnswer: '',
        option: options,
      ),
    ];
  }

  List<UserQuestion> buildUserQuestions() {
    return <UserQuestion>[
      UserQuestion(
        id: 'q1',
        chapterId: 'c1',
        chapterParentId: 's1',
        cutQuestion: '0',
        userAnswer: '',
        status: 0,
        collection: 0,
      ),
      UserQuestion(
        id: 'q2',
        chapterId: 'c1',
        chapterParentId: 's1',
        cutQuestion: '0',
        userAnswer: '',
        status: 0,
        collection: 0,
      ),
    ];
  }

  Future<void> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionDetailPage(
          chapter: Chapter(
            id: 'c1',
            name: '快捷键测试章节',
            subjectId: 's1',
            correct: 0,
            incorrect: 0,
            total: 2,
          ),
          questions: buildQuestions(),
          userQuestions: buildUserQuestions(),
          questionIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('左右方向键切换题目', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.text('第一题（多选）'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('第二题（多选）'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('第一题（多选）'), findsOneWidget);
  });

  testWidgets('字母 / 数字选项键切换多选题勾选状态', (WidgetTester tester) async {
    await pumpPage(tester);

    List<bool?> checkboxValues() {
      return tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((CheckboxListTile tile) => tile.value)
          .toList();
    }

    expect(checkboxValues(), <bool?>[false, false, false]);

    // 字母模式：A 勾选，B 勾选，再按 A 取消
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(checkboxValues(), <bool?>[true, false, false]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(checkboxValues(), <bool?>[true, true, false]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(checkboxValues(), <bool?>[false, true, false]);

    // 数字模式：1 对应第一个选项
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(checkboxValues(), <bool?>[true, true, false]);

    // 恢复默认配置，避免影响其它用例
    await ShortcutConfig.resetAll();
  });

  testWidgets('已斩题目默认不响应选项键', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final List<Question> questions = buildQuestions();
    final List<UserQuestion> userQuestions = buildUserQuestions();
    userQuestions[0].cutQuestion = '1';

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionDetailPage(
          chapter: Chapter(
            id: 'c1',
            name: '斩题测试章节',
            subjectId: 's1',
            correct: 0,
            incorrect: 0,
            total: 2,
          ),
          questions: questions,
          userQuestions: userQuestions,
          questionIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('该题目已斩'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(find.text('该题目已斩'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(userQuestions[0].userAnswer, isEmpty);
  });

  testWidgets('PgUp / PgDn 翻页与 ↑ / ↓ 连续滚动题目内容', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final List<Question> questions = buildQuestions();
    final Question longQuestion = Question(
      id: 'q1',
      title: List<String>.filled(80, '这是一段很长的题干用于验证翻页滚动。').join('\n'),
      type: '2',
      typeStr: '多选题',
      answer: 'AB',
      userAnswer: '',
      option: questions.first.option,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionDetailPage(
          chapter: Chapter(
            id: 'c1',
            name: '滚动测试章节',
            subjectId: 's1',
            correct: 0,
            incorrect: 0,
            total: 2,
          ),
          questions: <Question>[longQuestion, questions.last],
          userQuestions: buildUserQuestions(),
          questionIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder listScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      listScrollable,
    );
    expect(scrollable.position.pixels, 0);

    // 连续滚动：↓ 每次滚动连续步长（默认 40 像素）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final double afterLineDown = scrollable.position.pixels;
    expect(afterLineDown, greaterThan(0));

    // 翻页：PgDn 的滚动距离明显大于连续滚动
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final double afterPageDown = scrollable.position.pixels;
    expect(afterPageDown, greaterThan(afterLineDown));
    expect(afterPageDown - afterLineDown, greaterThan(afterLineDown));

    // ↑ 向上连续滚动，PgUp 向上翻页
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final double afterLineUp = scrollable.position.pixels;
    expect(afterLineUp, lessThan(afterPageDown));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, lessThan(afterLineUp));

    // 确认 PageUp / PageDown 不会切换题目
    expect(find.text('第二题（多选）'), findsNothing);
  });
}
