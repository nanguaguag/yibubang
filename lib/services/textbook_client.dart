import 'dart:math';
import '../models/ai_search.dart';
import 'ai_search_client.dart';

class TextbookHit {
  final AiCitation citation;
  final String snippet;
  const TextbookHit(this.citation, this.snippet);
}

class TextbookResults {
  final List<TextbookHit> items;
  final String nextPageToken;
  final AiQuota quota;
  const TextbookResults(this.items, this.nextPageToken, this.quota);
}

abstract class TextbookGateway {
  Future<List<Map<String, dynamic>>> books();
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  });
  Future<Map<String, dynamic>> page(AiCitation citation, int page);
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) =>
      page(citation, citation.pdfPage);
  void dispose();
}

class TextbookClient implements TextbookGateway {
  final AiSearchClient client;
  Future<List<Map<String, dynamic>>>? _catalog;
  TextbookClient({AiSearchClient? client})
    : client = client ?? AiSearchClient();
  @override
  Future<List<Map<String, dynamic>>> books() =>
      _catalog ??= _loadBooks().catchError((Object error) {
        _catalog = null;
        throw error;
      });
  Future<List<Map<String, dynamic>>> _loadBooks() async {
    final data = await client.requestJson('/v1/textbooks');
    return (data['books'] as List)
        .map((b) => Map<String, dynamic>.from(b))
        .toList();
  }

  @override
  Future<TextbookResults> search(
    String query, {
    String bookId = '',
    String pageToken = '',
  }) async {
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final data = await client.requestJson(
      '/v1/textbooks/search',
      body: {
        'question': query,
        'request_id': id,
        'book_id': bookId,
        'page_token': pageToken,
      },
    );
    return TextbookResults(
      (data['items'] as List)
          .map(
            (r) => TextbookHit(
              AiCitation.fromJson(Map<String, dynamic>.from(r)),
              r['snippet'] as String? ?? '',
            ),
          )
          .toList(),
      data['next_page_token'] as String? ?? '',
      AiQuota.fromJson(Map<String, dynamic>.from(data['quota'])),
    );
  }

  @override
  Future<Map<String, dynamic>> page(AiCitation citation, int page) {
    if (!RegExp(r'^tb_[a-f0-9]{12}$').hasMatch(citation.bookId) ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(citation.sourceVersion) ||
        page < 1 ||
        page > citation.pageCount) {
      throw const AiSearchException('教材页码无效');
    }
    return client.requestJson(
      '/v1/textbooks/${citation.bookId}/${citation.sourceVersion}/pages/$page',
    );
  }

  @override
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) {
    if (!RegExp(r'^tb_[a-f0-9]{12}$').hasMatch(citation.bookId) ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(citation.sourceVersion) ||
        citation.pdfPage < 1 ||
        citation.pdfPage > citation.pageCount) {
      throw const AiSearchException('教材页码无效');
    }
    return client.requestJson(
      '/v1/textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${citation.pdfPage}?variant=thumbnail',
    );
  }

  @override
  void dispose() => client.dispose();
}
