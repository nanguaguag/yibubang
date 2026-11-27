import '../models/ai_search.dart';
import '../models/analysis_image.dart';
import 'textbook_client.dart';

class CloudTextbookSearchOutcome {
  final List<Map<String, dynamic>> matchedBooks;
  final String query;
  final List<TextbookHit> hits;
  final bool usedUnscopedFallback;

  const CloudTextbookSearchOutcome({
    required this.matchedBooks,
    required this.query,
    required this.hits,
    this.usedUnscopedFallback = false,
  });

  AiCitation? get firstCitation => hits.isNotEmpty ? hits.first.citation : null;
}

/// 考点还原 / 解析教材图片缺失或需要核对原书时，回退至医不帮云端教材搜索。
class CloudTextbookFallbackService {
  static final RegExp _answerAnnotationPattern = RegExp(
    r'[（(]\s*[A-Za-z]+[对错](?:\s*[，,、；;]?\s*(?:[A-Za-z]+[对错]|为?本题正确答案))*\s*[）)]',
  );
  static final RegExp _quotePattern = RegExp(
    r'“([^”]+)”|"([^"]+)"|「([^」]+)」',
  );
  static final RegExp _editionPattern = RegExp(
    r'第?[0-9一二三四五六七八九十]+版',
  );
  static final RegExp _parentheticalPattern = RegExp(r'[（(][^）)]*[）)]');

  final TextbookGateway Function() _gatewayFactory;

  CloudTextbookFallbackService({TextbookGateway Function()? gatewayFactory})
    : _gatewayFactory = gatewayFactory ?? TextbookClient.new;

  /// 提取当前教材引用后面的原书文本，去除（A对）等答题标注。
  static String extractSearchQuery(
    String text,
    int matchIndex, {
    String? fallbackText,
  }) {
    final matches = analysisImageReferencePattern.allMatches(text).toList();
    if (matchIndex >= 0 && matchIndex < matches.length) {
      final start = matches[matchIndex].end;
      final end = matchIndex + 1 < matches.length
          ? matches[matchIndex + 1].start
          : text.length;
      var segment = text.substring(start, end);
      segment = segment.replaceFirst(RegExp(r'^[）)\s：:]+'), '');
      segment = segment.replaceFirst(RegExp(r'[（(\s]+$'), '');

      final quoteMatches = _quotePattern.allMatches(segment).toList();
      if (quoteMatches.isNotEmpty) {
        segment = quoteMatches
            .map((m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '')
            .where((part) => part.isNotEmpty)
            .join(' ');
      }

      final cleaned = cleanFallbackText(segment);
      if (cleaned.isNotEmpty) return _clampQuery(cleaned);
    }

    if (fallbackText != null && fallbackText.trim().isNotEmpty) {
      final cleaned = cleanFallbackText(fallbackText);
      if (cleaned.isNotEmpty) return _clampQuery(cleaned);
    }
    return '';
  }

  /// 清理文本中的页码引用、选项标注和多余省略号，生成适合教材搜索的纯文本。
  static String cleanFallbackText(String text) {
    var cleaned = text.replaceAll(_answerAnnotationPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'[…]+|\.{3,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^[“"「]+'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'[”"」]+$'), '');
    cleaned = cleaned.trim();
    if (cleaned.isEmpty || RegExp(r'^[。，、；：！？.,;:!?\s]+$').hasMatch(cleaned)) {
      return '';
    }
    return cleaned;
  }

  /// 若引用自带教材名称（如「10版病理生理学P61」），提取书名提示。
  static String? extractBookHint(String? reference) {
    if (reference == null || reference.trim().isEmpty) return null;
    var hint = reference.trim();
    hint = hint.replaceFirst(
      RegExp(r'P\d+(?:[-~～—–－]P?\d+)?$', caseSensitive: false),
      '',
    );
    hint = normalizeBookQuery(hint);
    if (hint.length < 2) return null;
    const genericHints = {'教材', '参见', '详见', '见书', '上册', '下册', '全书'};
    if (genericHints.contains(hint)) return null;
    return hint;
  }

  static String normalizeBookQuery(String raw) {
    var value = raw.trim();
    value = value.replaceAll(_parentheticalPattern, '');
    value = value.replaceAll(_editionPattern, '');
    value = value.replaceAll(RegExp(r'[《》\s]+'), '');
    return value;
  }

  /// 根据科目名或引用书名，模糊匹配云端教材目录。
  static List<Map<String, dynamic>> matchBooks(
    String? subjectOrHint,
    List<Map<String, dynamic>> catalog,
  ) {
    if (subjectOrHint == null) return const [];
    final normalizedQuery = normalizeBookQuery(subjectOrHint);
    if (normalizedQuery.length < 2 || catalog.isEmpty) return const [];

    final directMatches = <({Map<String, dynamic> book, int tier, int diff})>[];
    for (final book in catalog) {
      final rawTitle = (book['title'] as String? ?? '').trim();
      final title = normalizeBookQuery(rawTitle);
      if (title.length < 2) continue;

      if (title == normalizedQuery) {
        directMatches.add((book: book, tier: 0, diff: 0));
      } else if (title.contains(normalizedQuery)) {
        directMatches.add((
          book: book,
          tier: 1,
          diff: (title.length - normalizedQuery.length).abs(),
        ));
      } else if (normalizedQuery.contains(title)) {
        directMatches.add((
          book: book,
          tier: 2,
          diff: (title.length - normalizedQuery.length).abs(),
        ));
      }
    }

    if (directMatches.isNotEmpty) {
      directMatches.sort((a, b) {
        final tierCmp = a.tier.compareTo(b.tier);
        if (tierCmp != 0) return tierCmp;
        return a.diff.compareTo(b.diff);
      });
      return directMatches.map((entry) => entry.book).toList(growable: false);
    }

    // 仅在直接子串未命中时退化为顺序子序列匹配（如「耳鼻喉头颈外科学」→「耳鼻咽喉头颈外科学」）。
    final fuzzyMatches = <({Map<String, dynamic> book, double ratio, int diff})>[];
    for (final book in catalog) {
      final title = normalizeBookQuery(book['title'] as String? ?? '');
      if (title.length < 4 || normalizedQuery.length < 4) continue;
      final shorter = title.length <= normalizedQuery.length
          ? title
          : normalizedQuery;
      final longer = title.length <= normalizedQuery.length
          ? normalizedQuery
          : title;
      if (_isOrderedSubsequence(shorter, longer)) {
        final ratio = shorter.length / longer.length;
        if (ratio >= 0.7) {
          fuzzyMatches.add((
            book: book,
            ratio: ratio,
            diff: longer.length - shorter.length,
          ));
        }
      }
    }
    fuzzyMatches.sort((a, b) {
      final ratioCmp = b.ratio.compareTo(a.ratio);
      if (ratioCmp != 0) return ratioCmp;
      return a.diff.compareTo(b.diff);
    });
    return fuzzyMatches.map((entry) => entry.book).toList(growable: false);
  }

  static bool _isOrderedSubsequence(String shorter, String longer) {
    var i = 0;
    for (var j = 0; j < longer.length && i < shorter.length; j++) {
      if (shorter[i] == longer[j]) i++;
    }
    return i == shorter.length;
  }

  static String _clampQuery(String query) {
    const maxLen = 500;
    if (query.length <= maxLen) return query;
    return query.substring(0, maxLen).trim();
  }

  /// 匹配云端教材并执行一次精确检索，优先返回匹配教材下的首条结果。
  Future<CloudTextbookSearchOutcome> search({
    required String query,
    String? subjectName,
    String? bookHint,
    TextbookGateway? gateway,
  }) async {
    final trimmedQuery = _clampQuery(query.trim());
    if (trimmedQuery.isEmpty) {
      return const CloudTextbookSearchOutcome(
        matchedBooks: [],
        query: '',
        hits: [],
      );
    }

    final ownsGateway = gateway == null;
    final client = gateway ?? _gatewayFactory();
    try {
      final catalog = await client.books();
      var matchedBooks = matchBooks(bookHint, catalog);
      if (matchedBooks.isEmpty) {
        matchedBooks = matchBooks(subjectName, catalog);
      }

      if (matchedBooks.length == 1) {
        final bookId = matchedBooks.first['book_id'] as String? ?? '';
        final result = await client.search(trimmedQuery, bookId: bookId);
        return CloudTextbookSearchOutcome(
          matchedBooks: matchedBooks,
          query: trimmedQuery,
          hits: result.items,
        );
      }

      if (matchedBooks.length > 1) {
        final matchedIds = matchedBooks
            .map((b) => b['book_id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final globalResult = await client.search(trimmedQuery, bookId: '');
        final filtered = globalResult.items
            .where((hit) => matchedIds.contains(hit.citation.bookId))
            .toList(growable: false);
        if (filtered.isNotEmpty) {
          return CloudTextbookSearchOutcome(
            matchedBooks: matchedBooks,
            query: trimmedQuery,
            hits: filtered,
          );
        }

        final primaryBookId = matchedBooks.first['book_id'] as String? ?? '';
        if (primaryBookId.isNotEmpty) {
          final targeted = await client.search(
            trimmedQuery,
            bookId: primaryBookId,
          );
          if (targeted.items.isNotEmpty) {
            return CloudTextbookSearchOutcome(
              matchedBooks: matchedBooks,
              query: trimmedQuery,
              hits: targeted.items,
            );
          }
        }

        return CloudTextbookSearchOutcome(
          matchedBooks: matchedBooks,
          query: trimmedQuery,
          hits: globalResult.items,
          usedUnscopedFallback: globalResult.items.isNotEmpty,
        );
      }

      final unscoped = await client.search(trimmedQuery, bookId: '');
      return CloudTextbookSearchOutcome(
        matchedBooks: const [],
        query: trimmedQuery,
        hits: unscoped.items,
        usedUnscopedFallback: unscoped.items.isNotEmpty,
      );
    } finally {
      if (ownsGateway) {
        client.dispose();
      }
    }
  }
}
