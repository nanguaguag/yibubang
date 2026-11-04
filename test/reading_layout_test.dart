import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/screens/question_detail/question_detail_controller.dart';
import 'package:yibubang/screens/question_detail/question_page_item.dart';
import 'package:yibubang/screens/typography_settings_page.dart';
import 'package:yibubang/widgets/reading_layout.dart';

void main() {
  final layout = ReadingLayoutController.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await layout.load();
  });

  test('layout persists and invalid settings recover safely', () async {
    await layout.update(
      maxWidth: 720,
      horizontalInset: 24,
      position: ContentPosition.right,
      textAlign: TextAlign.justify,
      lineHeight: 1.9,
      letterSpacing: .5,
    );
    await layout.load();
    expect(layout.maxWidth, 720);
    expect(layout.horizontalInset, 24);
    expect(layout.position, ContentPosition.right);
    expect(layout.textAlign, TextAlign.justify);
    expect(layout.lineHeight, 1.9);
    expect(layout.letterSpacing, .5);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ReadingLayoutController.prefsKey,
      '{"maxWidth":-2,"lineHeight":"bad","position":"invalid"}',
    );
    await layout.load();
    expect(layout.maxWidth, 0);
    expect(layout.lineHeight, 1.5);
    expect(layout.position, ContentPosition.center);
    await prefs.setString(ReadingLayoutController.prefsKey, 'invalid json');
    await layout.load();
    expect(layout.maxWidth, 960);
  });

  testWidgets(
    'question width and text alignment update without resizing surrounding UI',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final question = Question(
        id: 'layout-q',
        title: '排版测试题干',
        type: '2',
        typeStr: '多选题',
        answer: 'AB',
        userAnswer: '',
        option: '[{"key":"A","title":"测试选项甲"},{"key":"B","title":"测试选项乙"}]',
      );
      final uq = UserQuestion(
        id: 'layout-q',
        chapterId: 'c',
        chapterParentId: 's',
        cutQuestion: '0',
        userAnswer: '',
        status: 0,
        collection: 0,
      );
      final controller = QuestionDetailController(
        chapter: Chapter(
          id: 'c',
          name: '排版',
          subjectId: 's',
          correct: 0,
          incorrect: 0,
          total: 1,
        ),
        questions: [question],
        userQuestions: [uq],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: QuestionPageItem(
                    question: question,
                    userQuestion: uq,
                    index: 0,
                    controller: controller,
                  ),
                ),
                const SizedBox(
                  key: ValueKey('outside'),
                  width: double.infinity,
                  height: 40,
                  child: Text('外部区域'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text('排版测试题干')).width, 960);
      expect(tester.getTopLeft(find.text('排版测试题干')).dx, 220);
      final outsideBefore = tester.getRect(
        find.byKey(const ValueKey('outside')),
      );
      await layout.update(
        maxWidth: 640,
        position: ContentPosition.right,
        textAlign: TextAlign.center,
        lineHeight: 1.9,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text('排版测试题干')).width, 640);
      expect(tester.getTopLeft(find.text('排版测试题干')).dx, 744);
      final title = tester.widget<RichText>(
        find.descendant(
          of: find.text('排版测试题干'),
          matching: find.byType(RichText),
        ),
      );
      expect(title.textAlign, TextAlign.center);
      expect(title.text.style!.height, 1.9);
      expect(
        tester.getRect(find.byKey(const ValueKey('outside'))),
        outsideBefore,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow viewport adapts padding and full width can be restored', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await layout.update(horizontalInset: 80);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadingContent(
            child: SizedBox(
              key: ValueKey('content'),
              height: 80,
              child: Text('窄屏正文'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 192);
    await layout.update(maxWidth: 0, horizontalInset: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typography submenu opens font settings on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: TypographySettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('排版'), findsOneWidget);
    expect(find.text('限制正文最大宽度'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('字体'));
    await tester.pumpAndSettle();
    expect(find.text('系统字体名称'), findsOneWidget);
    expect(find.text('导入字体 TTF / OTF'), findsOneWidget);
  });
}
