// Native App test: typed AI citation -> signed R2 image -> page navigation/cache.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/screens/ai_search_page.dart';
import 'package:yibubang/screens/textbook_reader_page.dart';
import 'package:yibubang/screens/textbook_search_page.dart';
import 'package:yibubang/services/ai_search_controller.dart';
import 'package:yibubang/services/textbook_client.dart';

const citation = AiCitation(
  number: 1,
  questionId: '',
  kind: 'textbook',
  bookId: 'tb_0cec4bbd9344',
  bookTitle: '医学免疫学',
  sourceVersion: '5d0778d98acc63a0',
  title: '医学免疫学 · PDF第100页',
  pdfPage: 100,
  pageCount: 258,
  printedPage: '73',
);

class OfflineGateway implements TextbookGateway {
  int requests = 0;
  @override
  Future<List<Map<String, dynamic>>> books() async => [];
  @override
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  }) async => throw StateError('offline');
  @override
  Future<Map<String, dynamic>> page(AiCitation citation, int page) async {
    requests++;
    throw StateError('offline');
  }

  @override
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) async => {};
  @override
  void dispose() {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native textbook search loads actual page thumbnails',
    (tester) async {
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(key: shot, child: const TextbookSearchPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'HLA I类分子 CD8 T细胞');
      await tester.tap(find.byTooltip('检索教材'));
      bool downloaded() => tester
          .widgetList<Image>(find.byType(Image))
          .any((i) => i.image is FileImage);
      for (var i = 0; i < 90 && !downloaded(); i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        downloaded(),
        true,
        reason: 'A real thumbnail must replace the placeholder',
      );
      await tester.pumpAndSettle();
      final boundary =
          shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = p.join(
        Directory.systemTemp.path,
        'textbook-native-thumbnails.png',
      );
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('TEXTBOOK_THUMBNAIL_SCREENSHOT=$path');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  testWidgets(
    'native citation, R2 reader, navigation and offline cache',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await openDatabase(inMemoryDatabasePath);
      await AiSearchStore.install(db);
      final ai =
          AiSearchController(store: AiSearchStore(database: () async => db))
            ..loading = false
            ..turns = [
              AiTurn(
                id: 'native-book-turn',
                question: '教材中的HLA分子有什么作用？',
                answer: 'HLA分子参与抗原提呈。[1]',
                status: 'complete',
                createdAt: DateTime.now(),
                citations: [citation],
              ),
            ];
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(
            key: shot,
            child: AiSearchPage(controller: ai),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(citation.title));
      for (
        var i = 0;
        i < 60 && find.byType(PhotoView).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(TextbookReaderPage), findsOneWidget);
      expect(find.byType(PhotoView), findsWidgets);
      expect(find.text('PDF 第 100 / 258 页'), findsOneWidget);
      expect(find.text('书页 73'), findsOneWidget);
      final photo = find.byType(PhotoView).first;
      final imageFinder = find
          .descendant(of: photo, matching: find.byType(Image))
          .first;
      final beforeWidth = tester.widget<Image>(imageFinder).width!;
      final center = tester.getCenter(photo);
      final left = await tester.createGesture(pointer: 1);
      final right = await tester.createGesture(pointer: 2);
      await left.down(center - const Offset(30, 0));
      await right.down(center + const Offset(30, 0));
      for (var distance = 40.0; distance <= 150; distance += 20) {
        await left.moveTo(center - Offset(distance, 0));
        await right.moveTo(center + Offset(distance, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(imageFinder).width!,
        greaterThan(beforeWidth * 1.1),
      );
      await tester.tap(find.byTooltip('下一页'));
      for (
        var i = 0;
        i < 60 && find.text('PDF 第 101 / 258 页').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.text('PDF 第 101 / 258 页'), findsOneWidget);
      await tester.tap(find.byTooltip('跳转页码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '125');
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('PDF 第 125 / 258 页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
      await db.close();

      final offline = OfflineGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: shot,
            child: TextbookReaderPage(citation: citation, gateway: offline),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhotoView), findsWidgets);
      expect(
        offline.requests,
        0,
        reason: 'An immutable cached page should open without Google or R2',
      );
      final boundary =
          shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = p.join(
        Directory.systemTemp.path,
        'textbook-native-reader.png',
      );
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('TEXTBOOK_NATIVE_SCREENSHOT=$path');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
