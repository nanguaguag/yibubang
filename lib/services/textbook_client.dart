import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
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
  void invalidateSession() {}
  void dispose();
}

class _TextbookImageSession {
  final String endpoint;
  final int expires;
  final String signature;
  const _TextbookImageSession({
    required this.endpoint,
    required this.expires,
    required this.signature,
  });

  bool get isValid =>
      endpoint.isNotEmpty &&
      signature.isNotEmpty &&
      DateTime.now().millisecondsSinceEpoch ~/ 1000 < expires - 60;

  String signUrl(String key) =>
      '$endpoint/$key?scope=session&expires=$expires&signature=$signature';

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'expires': expires,
    'signature': signature,
  };

  static _TextbookImageSession? fromJson(Map<String, dynamic> json) {
    final endpoint = json['endpoint'];
    final expires = json['expires'];
    final signature = json['signature'];
    if (endpoint is! String || expires is! int || signature is! String) {
      return null;
    }
    return _TextbookImageSession(
      endpoint: endpoint.endsWith('/')
          ? endpoint.substring(0, endpoint.length - 1)
          : endpoint,
      expires: expires,
      signature: signature,
    );
  }
}

class TextbookClient implements TextbookGateway {
  static const _sessionPrefsKey = 'textbook_image_session_v1';
  final AiSearchClient client;
  Future<List<Map<String, dynamic>>>? _catalog;
  _TextbookImageSession? _session;
  Future<_TextbookImageSession?>? _sessionFuture;
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
  void invalidateSession() {
    _session = null;
    _sessionFuture = null;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.remove(_sessionPrefsKey))
        .catchError((_) => false);
  }

  Future<_TextbookImageSession?> _getSession() async {
    final cached = _session;
    if (cached != null && cached.isValid) return cached;
    return _sessionFuture ??= _loadOrFetchSession().whenComplete(() {
      _sessionFuture = null;
    });
  }

  Future<_TextbookImageSession?> _loadOrFetchSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = _TextbookImageSession.fromJson(decoded);
          if (parsed != null && parsed.isValid) {
            _session = parsed;
            return parsed;
          }
        }
      }
    } catch (_) {}
    try {
      final data = await client.requestJson('/v1/textbooks/session');
      final parsed = _TextbookImageSession.fromJson(data);
      if (parsed != null && parsed.isValid) {
        _session = parsed;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_sessionPrefsKey, jsonEncode(parsed.toJson()));
        } catch (_) {}
        return parsed;
      }
    } catch (_) {}
    return null;
  }

  void _validatePage(AiCitation citation, int page) {
    if (!RegExp(r'^tb_[a-f0-9]{12}$').hasMatch(citation.bookId) ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(citation.sourceVersion) ||
        page < 1 ||
        page > citation.pageCount) {
      throw const AiSearchException('教材页码无效');
    }
  }

  @override
  Future<Map<String, dynamic>> page(AiCitation citation, int page) async {
    _validatePage(citation, page);
    final session = await _getSession();
    final key =
        'textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${page.toString().padLeft(4, '0')}.webp';
    if (session != null) {
      return {
        'url': session.signUrl(key),
        'image_key': key,
        'pdf_page': page,
        'page_count': citation.pageCount,
      };
    }
    return client.requestJson(
      '/v1/textbooks/${citation.bookId}/${citation.sourceVersion}/pages/$page',
    );
  }

  @override
  Future<Map<String, dynamic>> thumbnail(AiCitation citation) async {
    _validatePage(citation, citation.pdfPage);
    final session = await _getSession();
    final key =
        'textbooks/${citation.bookId}/${citation.sourceVersion}/thumbnails/${citation.pdfPage.toString().padLeft(4, '0')}.webp';
    if (session != null) {
      return {
        'url': session.signUrl(key),
        'image_key': key,
        'pdf_page': citation.pdfPage,
        'page_count': citation.pageCount,
      };
    }
    return client.requestJson(
      '/v1/textbooks/${citation.bookId}/${citation.sourceVersion}/pages/${citation.pdfPage}?variant=thumbnail',
    );
  }

  @override
  void dispose() => client.dispose();
}
