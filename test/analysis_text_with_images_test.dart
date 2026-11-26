import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/question_section_config.dart';
import 'package:yibubang/screens/question_detail/analysis_text_with_images.dart';
import 'package:yibubang/screens/question_detail/question_detail_controller.dart';
import 'package:yibubang/screens/question_detail/question_explain_view.dart';
import 'package:yibubang/services/analysis_image_loader.dart';
import 'package:yibubang/services/local_textbook_service.dart';
import 'package:yibubang/widgets/image_view.dart';

void main() {
  testWidgets('缺失网络图回退打开本地教材且保留图片入口', (tester) async {
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        throw HttpExceptionWithStatus(404, 'NoSuchKey', uri: Uri.parse(url));
      },
    );
    var localOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text: '（系统解剖学P87）内脏学（A对）。',
            legacyBaseUrl: 'https://example.com/40/BK45004DX004',
            imageLoader: loader,
            openLocalReference: (reference) async {
              expect(reference, '系统解剖学P87');
              localOpened = true;
              return const LocalTextbookOpenResult(
                status: LocalTextbookOpenStatus.opened,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('系统解剖学P87'));
    await tester.pumpAndSettle();
    expect(localOpened, isTrue);
    expect(find.byType(FullScreenImageView), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.textContaining('系统解剖学P87', findRichText: true), findsOneWidget);
  });

  testWidgets('网络失败尝试本地PDF，入口保留且可重试', (tester) async {
    var attempts = 0;
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        attempts++;
        throw const SocketException('offline');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text: '（系统解剖学P87）正文',
            legacyBaseUrl: 'https://example.com/40/BK45004DX004',
            imageLoader: loader,
            openLocalReference: (_) async => const LocalTextbookOpenResult(
              status: LocalTextbookOpenStatus.notFound,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('系统解剖学P87'));
    await tester.pumpAndSettle();
    expect(find.text('图片暂时无法加载；无法打开本地教材 PDF'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.text('系统解剖学P87'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('非解剖学引用保留通用网络错误提示', (tester) async {
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        throw const SocketException('offline');
      },
    );
    var localOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text: '（内科学P87）正文',
            legacyBaseUrl: 'https://example.com/question',
            imageLoader: loader,
            openLocalReference: (_) async {
              localOpened = true;
              return const LocalTextbookOpenResult(
                status: LocalTextbookOpenStatus.notFound,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('内科学P87'));
    await tester.pumpAndSettle();

    expect(localOpened, isFalse);
    expect(find.text('图片加载失败，请检查网络连接'), findsOneWidget);
  });

  testWidgets('图片可用时仍打开画廊浏览', (tester) async {
    final loader = AnalysisImageLoader(loadImage: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text: '（系统解剖学P87）正文',
            legacyBaseUrl: 'https://example.com/40/BK45004DX004',
            imageLoader: loader,
          ),
        ),
      ),
    );
    await tester.tap(find.text('系统解剖学P87'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FullScreenImageView), findsOneWidget);
  });

  testWidgets('考点和解析分别传入真实图片字段，支持只有图片的解析', (tester) async {
    final original = QuestionSectionConfig.configNotifier.value;
    QuestionSectionConfig.configNotifier.value =
        QuestionSectionConfig.getDefaultSections()..removeWhere(
          (section) => !['restore', 'explain'].contains(section.id),
        );
    addTearDown(() => QuestionSectionConfig.configNotifier.value = original);
    final question = Question(
      id: 'q1',
      userAnswer: '',
      title: '题目',
      option: '[]',
      nativeAppId: '',
      appId: '40',
      number: 'BK45011XZ479',
      restore: '（系统解剖学P8）正文',
      restoreImg: 'https://example.com/P217-2.jpg',
      explainImg: 'https://example.com/explain.bmp',
    );
    final userQuestion = UserQuestion(
      id: 'q1',
      chapterId: 'c1',
      chapterParentId: 's1',
      userAnswer: '',
      status: 1,
      collection: 0,
    );
    final controller = QuestionDetailController(
      chapter: Chapter(
        id: 'c1',
        name: '章节',
        subjectId: 's1',
        correct: 0,
        incorrect: 0,
        total: 1,
      ),
      questions: [question],
      userQuestions: [userQuestion],
      initialIndex: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionExplainView(
            question: question,
            userQuestion: userQuestion,
            index: 0,
            controller: controller,
            onStateChanged: () {},
          ),
        ),
      ),
    );
    final sections = tester
        .widgetList<AnalysisTextWithImages>(find.byType(AnalysisTextWithImages))
        .toList();
    expect(sections, hasLength(2));
    expect(sections[0].storedImages, question.restoreImg);
    expect(sections[1].storedImages, question.explainImg);
    expect(
      sections[0].legacyBaseUrl,
      'https://ykb-app-files.yikaobang.com.cn/question/restore/40/BK45011XZ479',
    );
    expect(find.text('查看配图'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
