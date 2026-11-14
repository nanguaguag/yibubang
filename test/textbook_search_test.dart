import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/screens/textbook_search_page.dart';
import 'package:yibubang/services/textbook_client.dart';
import 'package:yibubang/widgets/textbook_thumbnail.dart';

class FakeTextbooks implements TextbookGateway {
  final requests = <String>[];
  @override
  Future<List<Map<String, dynamic>>> books() async => [
    {'book_id': 'tb_123456789abc', 'title': '生理学'},
  ];
  @override
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  }) async {
    requests.add('$query|$bookId|$pageToken');
    return const TextbookResults(
      [
        TextbookHit(
          AiCitation(
            number: 1,
            questionId: '',
            title: '生理学 · PDF第28页',
            kind: 'textbook',
            bookId: 'tb_123456789abc',
            bookTitle: '生理学',
            sourceVersion: '123456789abcdef0',
            pdfPage: 28,
            pageCount: 530,
            printedPage: '12',
            needsReview: true,
          ),
          '钾离子外流参与心肌复极化。',
        ),
      ],
      '',
      AiQuota(remaining: 99, day: '2026-11-13'),
    );
  }

  @override
  Future<Map<String, dynamic>> page(AiCitation citation, int page) async => {};
  @override
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) async => {};
  @override
  void dispose() {}
}

void main() {
  test('old question citations and textbook versions round trip locally', () {
    final old = AiCitation.fromJson({
      'number': 1,
      'question_id': 'q',
      'title': '题',
    });
    expect(old.isTextbook, false);
    final book = AiCitation.fromJson({
      'number': 2,
      'kind': 'textbook',
      'book_id': 'tb_123456789abc',
      'source_version': '123456789abcdef0',
      'pdf_page': 28,
      'printed_page': 'I',
      'page_count': 530,
      'needs_review': true,
    });
    final saved = AiTurn(
      id: 't',
      question: 'q',
      createdAt: DateTime.now(),
      citations: [old, book],
    );
    final restored = AiTurn.fromJson(saved.toJson()).citations.last;
    expect(restored.sourceVersion, book.sourceVersion);
    expect(restored.pdfPage, 28);
    expect(restored.printedPage, 'I');
    expect(restored.needsReview, true);
  });
  for (final width in [320.0, 1000.0]) {
    testWidgets('textbook retrieval opens exact page at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeTextbooks();
      AiCitation? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: TextbookSearchPage(
            gateway: gateway,
            openPage: (_, c) async {
              opened = c;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (width == 1000) {
        await tester.tap(find.text('全部教材'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('生理学').last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('确定'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), '钾离子');
      await tester.tap(find.byTooltip('检索教材'));
      await tester.pumpAndSettle();
      expect(gateway.requests, [
        width == 1000 ? '钾离子|tb_123456789abc|' : '钾离子||',
      ]);
      expect(find.text('符号、公式请核对原页'), findsOneWidget);
      expect(find.text('今日剩余 99'), findsOneWidget);
      expect(find.textContaining('PDF 第 28 页'), findsOneWidget);
      expect(find.byType(TextbookThumbnail), findsOneWidget);
      final snippet = tester.widget<Text>(find.text('钾离子外流参与心肌复极化。'));
      final spans = (snippet.textSpan! as TextSpan).children!
          .whereType<TextSpan>();
      expect(spans.first.text, '钾离子');
      expect(spans.first.style!.backgroundColor, isNotNull);
      await tester.tap(find.text('《生理学》'));
      expect(opened!.pdfPage, 28);
      expect(opened!.sourceVersion, '123456789abcdef0');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('direct page lookup opens exact page of chosen book', (tester) async {
    final gateway = FakeTextbooks();
    AiCitation? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: TextbookSearchPage(
          gateway: gateway,
          openPage: (_, c) async {
            opened = c;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接查页'));
    await tester.pumpAndSettle();
    expect(find.text('直接查阅教材原页'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '15');
    await tester.tap(find.text('立即查阅'));
    await tester.pumpAndSettle();
    expect(opened, isNotNull);
    expect(opened!.bookId, 'tb_123456789abc');
    expect(opened!.pdfPage, 15);
  });
}
