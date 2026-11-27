import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/services/cloud_textbook_fallback_service.dart';
import 'package:yibubang/services/textbook_client.dart';

class _FakeTextbookGateway implements TextbookGateway {
  final List<Map<String, dynamic>> catalogBooks;
  final Map<String, TextbookResults> responsesByBookId;
  final List<(String query, String bookId)> calls = [];

  _FakeTextbookGateway({
    required this.catalogBooks,
    required this.responsesByBookId,
  });

  @override
  Future<List<Map<String, dynamic>>> books() async => catalogBooks;

  @override
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  }) async {
    calls.add((query, bookId));
    return responsesByBookId[bookId] ??
        const TextbookResults(
          [],
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

AiCitation _citation(String bookId, String bookTitle, int pdfPage) {
  return AiCitation(
    number: 1,
    questionId: '',
    title: '$bookTitle · PDF 第 $pdfPage 页',
    kind: 'textbook',
    bookId: bookId,
    bookTitle: bookTitle,
    sourceVersion: '0123456789abcdef',
    pdfPage: pdfPage,
    pageCount: 688,
  );
}

void main() {
  test('extractSearchQuery extracts exact quote without answer annotations', () {
    const restore =
        '（P13）“血小板减少出血的特点为同时有瘀点、紫癜和瘀斑（A对）、鼻出血、齿龈出血、月经过多血尿及黑便等”。'
        '（P14）“因凝血功能障碍引起的出血常表现有内脏（B错）、肌肉出血或软组织血肿，亦常有关节腔出血（D错）”。';

    expect(
      CloudTextbookFallbackService.extractSearchQuery(restore, 0),
      '血小板减少出血的特点为同时有瘀点、紫癜和瘀斑、鼻出血、齿龈出血、月经过多血尿及黑便等',
    );
    expect(
      CloudTextbookFallbackService.extractSearchQuery(restore, 1),
      '因凝血功能障碍引起的出血常表现有内脏、肌肉出血或软组织血肿，亦常有关节腔出血',
    );
  });

  test('extractSearchQuery handles 1236056 and fallback text', () {
    const restore =
        '（P29）“伴呛咳见于脑神经疾病（B对），食管憩室和贲门失弛缓症致潴留食物反流”。';

    expect(
      CloudTextbookFallbackService.extractSearchQuery(restore, 0),
      '伴呛咳见于脑神经疾病，食管憩室和贲门失弛缓症致潴留食物反流',
    );

    expect(
      CloudTextbookFallbackService.extractSearchQuery(
        '（P29）（B对）。',
        0,
        fallbackText: '延髓麻痹者（B对）饮水由鼻孔反流。',
      ),
      '延髓麻痹者饮水由鼻孔反流。',
    );
  });

  test('matchBooks maps 诊断学 to 诊断学 and 口腔颌面医学影像诊断学', () {
    const catalog = [
      {'book_id': 'tb_1', 'title': '内科学'},
      {'book_id': 'tb_2', 'title': '口腔颌面医学影像诊断学'},
      {'book_id': 'tb_3', 'title': '诊断学'},
      {'book_id': 'tb_4', 'title': '耳鼻咽喉头颈外科学'},
      {'book_id': 'tb_5', 'title': '卫生法'},
    ];

    final dxMatches = CloudTextbookFallbackService.matchBooks('诊断学', catalog);
    expect(
      dxMatches.map((b) => b['title']),
      ['诊断学', '口腔颌面医学影像诊断学'],
    );

    final entMatches = CloudTextbookFallbackService.matchBooks(
      '耳鼻喉头颈外科学',
      catalog,
    );
    expect(entMatches.map((b) => b['title']), ['耳鼻咽喉头颈外科学']);

    final lawMatches = CloudTextbookFallbackService.matchBooks(
      '卫生法学',
      catalog,
    );
    expect(lawMatches.map((b) => b['title']), ['卫生法']);
  });

  test('extractBookHint strips version and page suffix', () {
    expect(CloudTextbookFallbackService.extractBookHint('P13'), isNull);
    expect(
      CloudTextbookFallbackService.extractBookHint('10版病理生理学P61'),
      '病理生理学',
    );
    expect(
      CloudTextbookFallbackService.extractBookHint('第8版口腔颌面外科学P130-P131'),
      '口腔颌面外科学',
    );
  });

  test('search filters multi-book results and falls back to primary book if missed', () async {
    const catalog = [
      {'book_id': 'tb_dx', 'title': '诊断学'},
      {'book_id': 'tb_oral_dx', 'title': '口腔颌面医学影像诊断学'},
      {'book_id': 'tb_im', 'title': '内科学'},
    ];

    final gateway = _FakeTextbookGateway(
      catalogBooks: catalog,
      responsesByBookId: {
        '': TextbookResults(
          [
            TextbookHit(_citation('tb_im', '内科学', 500), '内科学无关命中'),
            TextbookHit(_citation('tb_dx', '诊断学', 15), '血小板减少出血的特点'),
          ],
          '',
          const AiQuota(remaining: 190, day: '2026-11-27'),
        ),
      },
    );

    final outcome = await CloudTextbookFallbackService().search(
      query: '血小板减少出血的特点',
      subjectName: '诊断学',
      gateway: gateway,
    );

    expect(gateway.calls, [('血小板减少出血的特点', '')]);
    expect(outcome.matchedBooks.map((b) => b['book_id']), [
      'tb_dx',
      'tb_oral_dx',
    ]);
    expect(outcome.firstCitation?.bookId, 'tb_dx');
    expect(outcome.firstCitation?.pdfPage, 15);

    // When global top-10 contains no matched book, falls back to primary matched book.
    final missGateway = _FakeTextbookGateway(
      catalogBooks: catalog,
      responsesByBookId: {
        '': TextbookResults(
          [TextbookHit(_citation('tb_im', '内科学', 10), '其他书')],
          '',
          const AiQuota(remaining: 189, day: '2026-11-27'),
        ),
        'tb_dx': TextbookResults(
          [TextbookHit(_citation('tb_dx', '诊断学', 32), '伴呛咳见于脑神经疾病')],
          '',
          const AiQuota(remaining: 188, day: '2026-11-27'),
        ),
      },
    );

    final fallbackOutcome = await CloudTextbookFallbackService().search(
      query: '伴呛咳见于脑神经疾病',
      subjectName: '诊断学',
      gateway: missGateway,
    );

    expect(missGateway.calls, [
      ('伴呛咳见于脑神经疾病', ''),
      ('伴呛咳见于脑神经疾病', 'tb_dx'),
    ]);
    expect(fallbackOutcome.firstCitation?.bookId, 'tb_dx');
    expect(fallbackOutcome.firstCitation?.pdfPage, 32);
  });
}
