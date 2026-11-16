import 'package:shared_preferences/shared_preferences.dart';

/// Local preferences; the server independently validates and charges allowance.
class AiSearchOptions {
  static const rephraseKey = 'ai_search_rephrase';
  static const streamingKey = 'ai_search_streaming';
  static const textbookCountKey = 'ai_search_textbook_count';
  static const resultCountKey = 'ai_search_result_count';
  static const contextWindowTurnsKey = 'ai_search_context_window_turns';
  static const defaultResultCount = 12;
  static const maxResultCount = 25;
  static const defaultContextWindowTurns = 20;
  static const minContextWindowTurns = 5;
  static const maxContextWindowTurns = 50;
  final bool rephrase;
  final bool streaming;

  /// Maximum evidence split, not a promise that every search has enough hits.
  final int textbookCount;
  final int resultCount;

  /// 多轮上下文对话滑动窗口轮数（默认 20 轮，防止 Token 消耗失控）
  final int contextWindowTurns;

  const AiSearchOptions({
    this.rephrase = true,
    this.streaming = true,
    this.textbookCount = 8,
    this.resultCount = defaultResultCount,
    this.contextWindowTurns = defaultContextWindowTurns,
  });
  int get quotaCost => 1 + (rephrase ? 1 : 0) + (streaming ? 1 : 0);
  int get questionCount => resultCount - textbookCount;
  String get ratioLabel => '$textbookCount : $questionCount';

  AiSearchOptions copyWith({
    bool? rephrase,
    bool? streaming,
    int? textbookCount,
    int? resultCount,
    int? contextWindowTurns,
  }) {
    final total = (resultCount ?? this.resultCount).clamp(1, maxResultCount);
    // Retain the selected source ratio when the overall evidence limit changes.
    final books =
        textbookCount ??
        (this.textbookCount * total / this.resultCount).round();
    final turns = (contextWindowTurns ?? this.contextWindowTurns).clamp(
      minContextWindowTurns,
      maxContextWindowTurns,
    );
    return AiSearchOptions(
      rephrase: rephrase ?? this.rephrase,
      streaming: streaming ?? this.streaming,
      resultCount: total,
      textbookCount: books.clamp(0, total),
      contextWindowTurns: turns,
    );
  }

  factory AiSearchOptions.fromPreferences(SharedPreferences prefs) {
    final rephrase = prefs.getBool(rephraseKey) ?? true;
    final total = (prefs.getInt(resultCountKey) ?? defaultResultCount).clamp(
      1,
      maxResultCount,
    );
    final turns = (prefs.getInt(contextWindowTurnsKey) ??
            defaultContextWindowTurns)
        .clamp(minContextWindowTurns, maxContextWindowTurns);
    return AiSearchOptions(
      rephrase: rephrase,
      streaming: rephrase && (prefs.getBool(streamingKey) ?? true),
      textbookCount: (prefs.getInt(textbookCountKey) ?? 8).clamp(0, total),
      resultCount: total,
      contextWindowTurns: turns,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    if (resultCount < 1 ||
        resultCount > maxResultCount ||
        textbookCount < 0 ||
        textbookCount > resultCount ||
        contextWindowTurns < minContextWindowTurns ||
        contextWindowTurns > maxContextWindowTurns) {
      throw StateError('Invalid AI options limits');
    }
    // Avoid persisting streaming=true/rephrase=false between the two writes.
    final saved = rephrase
        ? await prefs.setBool(rephraseKey, rephrase) &&
              await prefs.setBool(streamingKey, streaming)
        : await prefs.setBool(streamingKey, false) &&
              await prefs.setBool(rephraseKey, false);
    if (!saved ||
        !await prefs.setInt(textbookCountKey, textbookCount) ||
        !await prefs.setInt(resultCountKey, resultCount) ||
        !await prefs.setInt(contextWindowTurnsKey, contextWindowTurns)) {
      throw StateError('AI settings could not be saved');
    }
  }
}
