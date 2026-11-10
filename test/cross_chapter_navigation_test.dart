import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/screens/question_detail/chapter_cross_indicator.dart';
import 'package:yibubang/screens/question_detail_page.dart';
import 'package:yibubang/screens/question_grid_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Chapter Sorting & Sibling Model Tests', () {
    test('sortChaptersById accurately sorts numeric and mixed chapter IDs', () {
      final chapters = [
        Chapter(id: '10', name: '第十章', subjectId: 's1', correct: 0, incorrect: 0, total: 10),
        Chapter(id: '2', name: '第二章', subjectId: 's1', correct: 0, incorrect: 0, total: 10),
        Chapter(id: '1', name: '第一章', subjectId: 's1', correct: 0, incorrect: 0, total: 10),
        Chapter(id: '101', name: '第一百零一章', subjectId: 's1', correct: 0, incorrect: 0, total: 10),
        Chapter(id: '20', name: '第二十章', subjectId: 's1', correct: 0, incorrect: 0, total: 10),
      ];

      sortChaptersById(chapters);

      expect(chapters.map((c) => c.id).toList(), ['1', '2', '10', '20', '101']);
    });
  });

  group('ChapterCrossIndicator Widget Tests', () {
    final chapter2 = Chapter(
      id: '2',
      name: '第二章 细胞的基本功能',
      subjectId: 's1',
      correct: 0,
      incorrect: 0,
      total: 20,
    );

    testWidgets('renders nothing when overscrollDistance is tiny or zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  isNext: true,
                  overscrollDistance: 1.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('第二章 细胞的基本功能'), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('renders sliding in indicator with progress ring when dragging below threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  isNext: true,
                  overscrollDistance: 35.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });

    testWidgets('transforms to double chevron and high energy state when overscroll passes threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  isNext: true,
                  overscrollDistance: 95.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_right_rounded), findsOneWidget);
    });

    testWidgets('displays end of chapter block icon when targetChapter is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const ChapterCrossIndicator(
                  isNext: true,
                  overscrollDistance: 50.0,
                  targetChapter: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.do_not_disturb_on_rounded), findsOneWidget);
    });

    testWidgets('displays start of chapter block icon when dragging backward and targetChapter is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const ChapterCrossIndicator(
                  isNext: false,
                  overscrollDistance: 50.0,
                  targetChapter: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.do_not_disturb_on_rounded), findsOneWidget);
    });

    testWidgets('supports vertical axis indicator when pulling down (previous chapter)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  axis: Axis.vertical,
                  isNext: false,
                  overscrollDistance: 35.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('transforms to double up chevron when vertical pulling down passes threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  axis: Axis.vertical,
                  isNext: false,
                  overscrollDistance: 95.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('supports vertical axis indicator when pulling up (next chapter)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  axis: Axis.vertical,
                  isNext: true,
                  overscrollDistance: 35.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('transforms to double down chevron when vertical pulling up passes threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ChapterCrossIndicator(
                  axis: Axis.vertical,
                  isNext: true,
                  overscrollDistance: 95.0,
                  threshold: 85.0,
                  targetChapter: chapter2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_down_rounded), findsOneWidget);
    });
  });

  group('QuestionDetailPage Cross-Chapter Navigation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'mode': 0,
        'lastQIndex': 0,
      });
    });

    final chapter1 = Chapter(
      id: '1',
      name: '第一章 绪论',
      subjectId: 'sub_physiology',
      correct: 0,
      incorrect: 0,
      total: 2,
    );

    final questions = <Question>[
      Question(
        id: 'q_c1_1',
        title: '第一章第一题：人体生命活动最基本的特征是？',
        option: '[{"key":"A","value":"新陈代谢"},{"key":"B","value":"兴奋性"}]',
        answer: 'A',
        explain: '新陈代谢是生命活动最基本特征',
        chapterId: '1',
        type: '1',
        userAnswer: '',
      ),
      Question(
        id: 'q_c1_2',
        title: '第一章第二题：下列生理过程中属于正反馈的是？',
        option: '[{"key":"A","value":"排尿反射"},{"key":"B","value":"减压反射"}]',
        answer: 'A',
        explain: '排尿反射是正反馈',
        chapterId: '1',
        type: '1',
        userAnswer: '',
      ),
    ];

    final userQuestions = [
      UserQuestion(
        id: 'q_c1_1',
        chapterId: '1',
        chapterParentId: 'sub_physiology',
        userAnswer: '',
        status: 0,
        collection: 0,
      ),
      UserQuestion(
        id: 'q_c1_2',
        chapterId: '1',
        chapterParentId: 'sub_physiology',
        userAnswer: '',
        status: 0,
        collection: 0,
      ),
    ];

    testWidgets('renders QuestionDetailPage and handles forward/backward swiping', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionDetailPage(
            chapter: chapter1,
            questions: questions,
            userQuestions: userQuestions,
            questionIndex: 0,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证当前章节标题与第一题渲染
      expect(find.text('第一章 绪论'), findsOneWidget);
      expect(find.textContaining('第一章第一题'), findsOneWidget);

      // 使用右方向键或滚动切到下一题 (index 1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.textContaining('第一章第二题'), findsOneWidget);

      // 验证在首题/末题支持键盘与边缘手势无缝响应
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('第一章第一题'), findsOneWidget);
    });
  });

  group('QuestionGridPage Vertical Cross-Chapter Navigation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'mode': 0,
        'cutType': 0,
        'questionType': 0,
        'category': 0,
      });
    });

    final chapterA = Chapter(
      id: '1',
      name: '第一章 绪论',
      subjectId: 'sub_physiology',
      correct: 0,
      incorrect: 0,
      total: 5,
    );

    testWidgets('renders QuestionGridPage with chapter name and cross-chapter indicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionGridPage(
            chapter: chapterA,
          ),
        ),
      );

      await tester.pump();

      // 验证章节名展示在 AppBar
      expect(find.text('第一章 绪论'), findsOneWidget);

      // 验证垂直滑动指示器挂载在页面中
      final indicatorFinder = find.byType(ChapterCrossIndicator);
      expect(indicatorFinder, findsOneWidget);

      final ChapterCrossIndicator indicator = tester.widget(indicatorFinder);
      expect(indicator.axis, equals(Axis.vertical));
    });

    testWidgets('handles narrow/zero width constraints without asserting on crossAxisCount > 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 0,
            height: 100,
            child: QuestionGridPage(
              chapter: chapterA,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports macOS trackpad PointerPanZoomEnd and release handling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionGridPage(
            chapter: chapterA,
          ),
        ),
      );

      await tester.pump();
      // 验证页面 Listener 正确接收 PointerPanZoomEnd 事件并不发生崩溃
      final listenerFinder = find.byType(Listener);
      expect(listenerFinder, findsWidgets);

      final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await gesture.panZoomStart(const Offset(200, 200));
      await gesture.panZoomUpdate(const Offset(200, 200), pan: const Offset(0, 100));
      await tester.pump();
      await gesture.panZoomEnd();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancels cross-chapter dwell timer when releasing before 500ms threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionGridPage(
            chapter: chapterA,
          ),
        ),
      );

      await tester.pump();
      final TestGesture gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 200));

      // 提前松手（在 500ms 达到前）
      await gesture.up();
      await tester.pump();

      // 等待 700ms，确认不会发生延迟误切
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('第一章 绪论'), findsOneWidget);
    });
  });
}
