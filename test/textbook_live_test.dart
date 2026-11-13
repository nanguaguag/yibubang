// Opt-in UI -> production client -> Cloud Run -> actual Google textbook index.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/services/ai_search_client.dart';
import 'package:yibubang/services/textbook_client.dart';
import 'package:yibubang/screens/textbook_search_page.dart';
import 'package:yibubang/models/ai_search.dart';
import 'dart:ui' as ui;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
    'live textbook index works through the App search page',
    (tester) async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final identity = jsonDecode(
        File('ai_backend/.local/smoke-device.json').readAsStringSync(),
      );
      SharedPreferences.setMockInitialValues({
        'ai_installation_id': identity['installation_id'],
        'ai_installation_secret': identity['secret'],
        'ai_device_registered': AiSearchClient.endpoint,
      });
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            paths,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null),
      );
      final gateway = TextbookClient();
      final shots = GlobalKey();
      AiCitation? opened;
      List<Map<String, dynamic>>? books;
      await tester.runAsync(() async {
        books = await gateway.books();
      });
      expect(books!.length, 53);
      final loader = FontLoader('TextbookChinese')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('/System/Library/Fonts/PingFang.ttc').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      final iconPath = Platform.environment['TEXTBOOK_ICONS_FONT'];
      if (iconPath != null) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(iconPath).readAsBytesSync()),
            ),
          );
        await icons.load();
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'TextbookChinese'),
          home: RepaintBoundary(
            key: shots,
            child: TextbookSearchPage(
              gateway: gateway,
              openPage: (_, c) async {
                opened = c;
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'HLA I类分子 CD8 T细胞');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('检索教材'));
        await Future<void>.delayed(const Duration(seconds: 12));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 10)),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(Card);
      expect(cards, findsWidgets);
      await tester.tap(cards.first);
      expect(opened!.isTextbook, true);
      expect(opened!.pdfPage, greaterThan(0));
      expect(opened!.sourceVersion, isNotEmpty);
      expect(opened!.imageKey, endsWith('.webp'));
      final boundary =
          shots.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'ai_backend/.local/screenshots/textbook-live.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        File('ai_backend/.local/textbook-app-live.json').writeAsStringSync(
          jsonEncode({
            'status': 'PASS',
            'book_count': books!.length,
            'citation': opened!.toJson(),
            'chain':
                'TextbookSearchPage -> TextbookClient -> Cloud Run -> Vertex AI Search',
          }),
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.dispose();
    },
    skip: Platform.environment['TEXTBOOK_LIVE_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
