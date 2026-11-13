import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/screens/textbook_reader_page.dart';
import 'textbook_search_test.dart' show FakeTextbooks;
import 'support/startup_fixture.dart' show pumpUntil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CacheManager cache;
  const citation = AiCitation(
    number: 1,
    questionId: '',
    title: '教材',
    kind: 'textbook',
    bookId: 'gesture_fixture',
    sourceVersion: 'v1',
    pdfPage: 2,
    pageCount: 3,
  );
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('reader_gestures_');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    cache = CacheManager(Config('reader-gesture-fixture'));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 240, 400),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final page = await picture.toImage(240, 400);
    final png = await page.toByteData(format: ui.ImageByteFormat.png);
    page.dispose();
    picture.dispose();
    for (var n = 1; n <= 3; n++) {
      await cache.putFile(
        'https://fixture.example/$n',
        png!.buffer.asUint8List(),
        key:
            'textbooks/gesture_fixture/v1/pages/${n.toString().padLeft(4, '0')}.webp',
      );
    }
  });
  tearDown(() async {
    await cache.dispose();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: TextbookReaderPage(
          citation: citation,
          gateway: FakeTextbooks(),
          cacheManager: cache,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(Image).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await settle(tester);
  }

  double imageWidth(WidgetTester tester) => tester
      .widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('textbook_page_2')),
          matching: find.byType(Image),
        ),
      )
      .width!;
  testWidgets(
    'Android two-finger pinch and double tap enlarge the actual page',
    (tester) async {
      await mount(tester, TargetPlatform.android);
      final initial = imageWidth(tester);
      final center = tester.getCenter(
        find.byKey(const ValueKey('textbook_page_2')),
      );
      final left = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      for (var n = 1; n <= 5; n++) {
        await left.moveTo(center - Offset(40.0 + n * 14, 0));
        await right.moveTo(center + Offset(40.0 + n * 14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await left.up();
      await right.up();
      await settle(tester);
      final zoomed = imageWidth(tester);
      expect(zoomed, greaterThan(initial * 1.5));
      expect(find.text('PDF 第 2 / 3 页'), findsOneWidget);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await settle(tester);
      expect(imageWidth(tester), isNot(zoomed));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'desktop arrows flip within bounds, also after button focus; dialog keeps text keys',
    (tester) async {
      await mount(tester, TargetPlatform.macOS);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(find.text('PDF 第 1 / 3 页'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(find.text('PDF 第 1 / 3 页'), findsOneWidget);
      await tester.tap(find.byTooltip('跳转页码'));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(find.text('PDF 第 1 / 3 页'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2');
      await tester.tap(find.text('跳转'));
      await settle(tester);
      expect(find.text('PDF 第 2 / 3 页'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
