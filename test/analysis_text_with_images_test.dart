import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/question_section_config.dart';
import 'package:yibubang/screens/question_detail/analysis_text_with_images.dart';
import 'package:yibubang/screens/question_detail/question_detail_controller.dart';
import 'package:yibubang/screens/question_detail/question_explain_view.dart';
import 'package:yibubang/screens/question_detail_page.dart';
import 'package:yibubang/screens/textbook_reader_page.dart';
import 'package:yibubang/services/analysis_image_loader.dart';
import 'package:yibubang/services/cloud_textbook_fallback_service.dart';
import 'package:yibubang/services/local_textbook_service.dart';
import 'package:yibubang/services/textbook_client.dart';
import 'package:yibubang/widgets/image_view.dart';

import 'support/startup_fixture.dart' show pumpUntil;

class _FakeFallbackGateway implements TextbookGateway {
  final List<(String query, String bookId)> searchCalls = [];

  @override
  Future<List<Map<String, dynamic>>> books() async => const [
    {
      'book_id': 'tb_1cdd8401a378',
      'title': '诊断学',
      'source_version': '403838ef7b54c45d',
      'page_count': 688,
    },
    {
      'book_id': 'tb_7f8904b1c7cc',
      'title': '口腔颌面医学影像诊断学',
      'source_version': '86e3ab712c5765d7',
      'page_count': 226,
    },
    {
      'book_id': 'tb_e088ee5185c4',
      'title': '内科学',
      'source_version': 'bac91c808b2ec5d6',
      'page_count': 982,
    },
  ];

  @override
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  }) async {
    searchCalls.add((query, bookId));
    return const TextbookResults(
      [
        TextbookHit(
          AiCitation(
            number: 1,
            questionId: '',
            title: '诊断学 · PDF 第 31 页',
            kind: 'textbook',
            bookId: 'tb_1cdd8401a378',
            bookTitle: '诊断学',
            sourceVersion: '403838ef7b54c45d',
            pdfPage: 31,
            pageCount: 688,
            printedPage: '29',
          ),
          '伴呛咳见于脑神经疾病，食管憩室和贲门失弛缓症致潴留食物反流。',
        ),
      ],
      '',
      AiQuota(remaining: 199, day: '2026-11-27'),
    );
  }

  @override
  Future<Map<String, dynamic>> page(AiCitation citation, int page) async => {};

  @override
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) async => {};

  @override
  void invalidateSession() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late CacheManager cache;
  late String samplePngPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmpDir = await Directory.systemTemp.createTemp('analysis_images_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmpDir.path,
        );
    cache = CacheManager(Config('analysis-images-reader-fixture'));

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 200, 300),
      Paint()..color = Colors.white,
    );
    final pic = recorder.endRecording();
    final img = await pic.toImage(200, 300);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    img.dispose();
    pic.dispose();

    samplePngPath = '${tmpDir.path}/sample_page.png';
    await File(samplePngPath).writeAsBytes(bytes);

    for (final p in [30, 31, 32]) {
      await cache.putFile(
        'https://fixture.example/$p',
        bytes,
        key:
            'textbooks/tb_1cdd8401a378/403838ef7b54c45d/pages/${p.toString().padLeft(4, '0')}.webp',
      );
    }
  });

  tearDown(() async {
    await cache.dispose();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets('缺失网络图在本地PDF打开成功时直接跳转，不弹出失败画廊', (tester) async {
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
  });

  testWidgets('404 失效图片进入失败页并在下方显示云端教材入口，点击检索首条并可左右翻页', (
    tester,
  ) async {
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        throw HttpExceptionWithStatus(404, 'NoSuchKey', uri: Uri.parse(url));
      },
    );
    final gateway = _FakeFallbackGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text:
                '（P29）“伴呛咳见于脑神经疾病（B对），食管憩室和贲门失弛缓症致潴留食物反流”。',
            legacyBaseUrl:
                'https://ykb-app-files.yikaobang.com.cn/question/restore/40/BK16111XZ002',
            imageLoader: loader,
            resolveSubjectName: () async => '诊断学',
            textbookGateway: gateway,
            openGallery: (
              context,
              urls,
              initialIndex,
              fallbacks,
              _,
            ) {
              return Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImageView(
                    imageUrls: urls,
                    initialIndex: initialIndex,
                    pageFallbacks: fallbacks,
                    onCloudTextbookFallback: (viewerCtx, pageIdx, fb) async {
                      final outcome = await CloudTextbookFallbackService()
                          .search(
                            query: fb.searchQuery!,
                            subjectName: '诊断学',
                            bookHint: fb.bookHint,
                            gateway: gateway,
                          );
                      if (!viewerCtx.mounted) return;
                      await Navigator.of(viewerCtx).push(
                        MaterialPageRoute(
                          builder: (_) => TextbookReaderPage(
                            citation: outcome.firstCitation!,
                            gateway: gateway,
                            cacheManager: cache,
                            searchHits: outcome.hits,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('P29'));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageView), findsOneWidget);
    expect(find.text('原教材图片已失效或已被移除'), findsOneWidget);
    expect(find.text('在医不帮云端教材中查看'), findsOneWidget);
    expect(find.byTooltip('更多选项'), findsNothing);

    await tester.tap(find.text('在医不帮云端教材中查看'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(TextbookReaderPage).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntil(
      tester,
      () =>
          find.byType(Image).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();

    expect(gateway.searchCalls, [
      ('伴呛咳见于脑神经疾病，食管憩室和贲门失弛缓症致潴留食物反流', ''),
    ]);
    expect(find.byType(TextbookReaderPage), findsOneWidget);
    expect(find.text('PDF 第 31 / 688 页'), findsOneWidget);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.text('PDF 第 32 / 688 页'), findsOneWidget);

    await tester.tap(find.byTooltip('上一页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.text('PDF 第 31 / 688 页'), findsOneWidget);
  });

  testWidgets('图片正常加载时将云端教材入口隐藏在右上角菜单中', (tester) async {
    final loader = AnalysisImageLoader(loadImage: (_) async {});
    String? searchedQuery;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisTextWithImages(
            text:
                '（P13）“血小板减少出血的特点为同时有瘀点、紫癜和瘀斑（A对）、鼻出血、齿龈出血、月经过多血尿及黑便等”。',
            legacyBaseUrl: 'https://example.com/40/BK16RWLXC004',
            imageLoader: loader,
            openGallery: (
              context,
              _,
              initialIndex,
              fallbacks,
              _,
            ) {
              return Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImageView(
                    imageUrls: [samplePngPath],
                    initialIndex: initialIndex,
                    pageFallbacks: fallbacks,
                    onCloudTextbookFallback: (_, _, fb) async {
                      searchedQuery = fb.searchQuery;
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('P13'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          find.byType(FullScreenImageView).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageView), findsOneWidget);
    expect(find.text('在医不帮云端教材中查看'), findsNothing);
    expect(find.byTooltip('更多选项'), findsOneWidget);

    await tester.tap(find.byTooltip('更多选项'));
    await tester.pumpAndSettle();
    expect(find.text('在医不帮云端教材中查看'), findsOneWidget);

    await tester.tap(find.text('在医不帮云端教材中查看'));
    await tester.pumpAndSettle();
    expect(
      searchedQuery,
      '血小板减少出血的特点为同时有瘀点、紫癜和瘀斑、鼻出血、齿龈出血、月经过多血尿及黑便等',
    );
  });

  testWidgets('网络失败进入失败页支持重新加载与云端教材回退', (tester) async {
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

    expect(attempts, 1);
    expect(find.byType(FullScreenImageView), findsOneWidget);
    expect(find.text('图片加载失败，请检查网络连接'), findsOneWidget);
    expect(find.text('在医不帮云端教材中查看'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
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

  testWidgets('失败页点击云端教材入口时加载动画居中显示', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenImageView(
          imageUrls: const ['https://example.com/404.jpg'],
          initialIndex: 0,
          pageFallbacks: const [
            FullScreenImagePageFallback(
              reference: 'P29',
              searchQuery: '伴呛咳见于脑神经疾病',
              initiallyFailed: true,
              failureMessage: '原教材图片已失效或已被移除',
            ),
          ],
          onCloudTextbookFallback: (_, _, _) => completer.future,
        ),
      ),
    );

    await tester.tap(find.text('在医不帮云端教材中查看'));
    await tester.pump();

    final indicatorFinder = find.byType(CircularProgressIndicator);
    expect(indicatorFinder, findsOneWidget);
    final screenCenter = tester.getCenter(find.byType(FullScreenImageView));
    final indicatorCenter = tester.getCenter(indicatorFinder);
    expect((indicatorCenter.dx - screenCenter.dx).abs(), lessThan(5));
    expect((indicatorCenter.dy - screenCenter.dy).abs(), lessThan(40));

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('单题详情禁用切章时桌面端上一题与下一题保持禁用', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({'loggedin': false});

    final question = Question(
      id: 'q_wrong_1',
      userAnswer: 'A',
      title: '测试错题',
      option: '[{"key":"A","title":"选项A"}]',
      answer: 'B',
      chapterId: '16111',
      chapterParentId: '16',
    );
    final uq = UserQuestion(
      id: 'q_wrong_1',
      chapterId: '16111',
      chapterParentId: '16',
      userAnswer: 'A',
      status: 2,
      collection: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionDetailPage(
          chapter: Chapter(
            id: '16111',
            name: '诊断学',
            subjectId: '16',
            correct: 0,
            incorrect: 1,
            total: 1,
          ),
          questions: [question],
          userQuestions: [uq],
          questionIndex: 0,
          enableChapterSwitch: false,
        ),
      ),
    );
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byTooltip('上一题').evaluate().isNotEmpty,
    );
    await tester.pump();

    expect(find.byTooltip('上一题'), findsOneWidget);
    expect(find.byTooltip('下一题'), findsOneWidget);
    expect(find.byTooltip('返回上一章：'), findsNothing);
    expect(find.byTooltip('进入下一章：'), findsNothing);

    final buttons = tester.widgetList<ElevatedButton>(
      find.byType(ElevatedButton),
    );
    expect(buttons, hasLength(2));
    for (final btn in buttons) {
      expect(btn.onPressed, isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}
