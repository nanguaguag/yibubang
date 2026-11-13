import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/screens/ai_search_page.dart';
import 'package:yibubang/screens/question_detail_page.dart';
import 'package:yibubang/services/ai_search_controller.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'ai_search_test.dart' show FakeAiGateway;
import 'support/startup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late AiSearchController ai;
  late FakeAiGateway gateway;
  final shotKey = GlobalKey();
  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath);
    await AiSearchStore.install(db);
    gateway = FakeAiGateway();
    ai = AiSearchController(
      store: AiSearchStore(database: () async => db),
      gateway: gateway,
    )..loading = false;
  });
  tearDown(() async {
    ai.dispose();
    await db.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool dark = false,
    Future<void> Function(BuildContext, AiCitation)? open,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff4285f4),
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          fontFamily: 'AiTestFont',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: shotKey,
          child: AiSearchPage(controller: ai, openCitation: open),
        ),
      ),
    );
  }

  void conversation({String questionId = '1637906'}) {
    final now = DateTime.now();
    ai.turns = [
      AiTurn(
        id: 'turn',
        question: '为什么 HLA I 向 CD8 T 细胞提呈抗原？',
        answer: '## 关键联系\n**HLA I** 将内源性抗原肽提呈给 CD8 T 细胞。[1]\n\n这有助于识别被感染的细胞。',
        status: 'complete',
        createdAt: now,
        citations: [
          AiCitation(
            number: 1,
            questionId: questionId,
            title: 'HLA I 与 CD8 T 细胞',
          ),
        ],
      ),
    ];
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.environment['AI_SCREENSHOTS'] != '1') return;
    final boundary =
        shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final shot = await boundary.toImage(pixelRatio: 2);
      final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(p.join('ai_backend', '.local', 'screenshots'));
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, '$name.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      shot.dispose();
    });
  }

  setUpAll(() async {
    if (Platform.environment['AI_SCREENSHOTS'] == '1') {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final fontPath = p.join(
        Platform.pathSeparator,
        'System',
        'Library',
        'Fonts',
        'PingFang.ttc',
      );
      if (File(fontPath).existsSync()) {
        final font = FontLoader('AiTestFont')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          );
        await font.load();
      }
    }
  });
  testWidgets(
    'welcome suggestions populate composer with adaptive Material layout',
    (tester) async {
      await mount(tester);
      expect(find.text('让知识，\n从一个问题展开。'), findsOneWidget);
      await tester.tap(find.text('理解机制'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('CD8'),
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'welcome-mobile');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'desktop Shift+Enter sends; Enter, IME and repeat do not submit',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await mount(tester, width: 1000);
      final field = find.byKey(const ValueKey('ai_input'));
      await tester.enterText(field, '机制是什么？');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(gateway.requests, isEmpty);
      final controller = tester.widget<TextField>(field).controller!;
      controller.value = const TextEditingValue(
        text: '中文组词',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(gateway.requests, isEmpty);
      await tester.enterText(field, '机制是什么？');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await pumpUntil(tester, () => gateway.stream != null);
      expect(gateway.requests, hasLength(1));
      expect(ai.turns.single.question, '机制是什么？');
      expect(controller.text, isEmpty);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      expect(gateway.requests, hasLength(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      ai.stop();
      await pumpUntil(tester, () => !ai.busy);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final setting in [
    (320.0, 1.6, false),
    (390.0, 1.0, false),
    (1000.0, 1.0, true),
  ]) {
    testWidgets(
      'citation and actions fit ${setting.$1}px / scale ${setting.$2}',
      (tester) async {
        conversation();
        ai.quota = const AiQuota(remaining: 98, day: '2026-11-12');
        String? opened;
        await mount(
          tester,
          width: setting.$1,
          scale: setting.$2,
          dark: setting.$3,
          open: (context, citation) async {
            opened = citation.questionId;
          },
        );
        await tester.ensureVisible(find.byType(ActionChip));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ActionChip));
        await tester.pump();
        expect(opened, '1637906');
        expect(tester.takeException(), isNull);
        await screenshot(
          tester,
          setting.$3
              ? 'answer-desktop-dark'
              : setting.$1 == 320
              ? 'answer-mobile-large'
              : 'answer-mobile',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('medical comparison Markdown table scrolls inside mobile answer', (
    tester,
  ) async {
    conversation();
    ai.turns.single.answer =
        '| 项目 | HLA I | HLA II |\n| :--- | :--- | :--- |\n| 识别细胞 | CD8 [1] | CD4 |\n| 抗原 | 内源性 | 外源性 |';
    await mount(tester);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('左右滑动查看表格'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'comparison-mobile');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'edit, new conversation and local session deletion work through UI',
    (tester) async {
      conversation();
      final now = DateTime.now();
      final session = AiSession(
        id: 'session',
        title: 'HLA I',
        createdAt: now,
        updatedAt: now,
      );
      await tester.runAsync(() => ai.store.create(session));
      ai.session = session;
      ai.sessions = [session];
      await mount(tester, width: 1000);
      await tester.tap(find.byTooltip('修改问题'));
      await tester.pump();
      expect(find.text('修改后重新回答，后续追问将被替换'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ai.turns.single.question,
      );
      await tester.tap(find.byTooltip('取消修改'));
      await tester.tap(find.byTooltip('新会话'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('让知识，\n从一个问题展开。'), findsOneWidget);
      await tester.tap(find.byTooltip('会话记录'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('删除会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await pumpUntil(tester, () => ai.sessions.isEmpty);
      expect(await tester.runAsync(() => ai.store.sessions()), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'retrieval transitions to streamed text and stop retains partial answer',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'HLA I是什么');
      await tester.tap(find.byKey(const ValueKey('ai_send')));
      await pumpUntil(tester, () => gateway.stream != null);
      expect(find.text('正在检索医学题库'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 180));
      await screenshot(tester, 'retrieving-mobile');
      gateway.stream!.add(
        const AiStreamEvent('delta', {'text': 'HLA I提呈内源性抗原。'}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('正在生成回答'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai_stop')));
      await pumpUntil(tester, () => !ai.busy);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('回答已停止，内容已保留'), findsOneWidget);
      expect(ai.turns.single.answer, 'HLA I提呈内源性抗原。');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'citation opens actual read-only installed question and shared user answer',
    (tester) async {
      final fixture = await tester.runAsync(StartupFixture.create);
      try {
        await tester.runAsync(() => QuestionBankRepository().initialize());
        conversation(questionId: 'q');
        await mount(tester, width: 1000);
        await tester.tap(find.byType(ActionChip));
        await pumpReady(tester, find.byType(QuestionDetailPage));
        final page = tester.widget<QuestionDetailPage>(
          find.byType(QuestionDetailPage),
        );
        expect(page.questions.single.id, 'q');
        expect(page.userQuestions.single.userAnswer, 'A');
        expect(page.bankId, 'fixture');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() => fixture!.close());
      }
    },
  );
}
