import 'package:shared_preferences/shared_preferences.dart';

/// Local preferences; the server independently validates and charges allowance.
class AiSearchOptions {
  static const rephraseKey = 'ai_search_rephrase';
  static const streamingKey = 'ai_search_streaming';
  static const textbookCountKey = 'ai_search_textbook_count';
  static const evidenceCount = 12;
  final bool rephrase;
  final bool streaming;

  /// Maximum evidence split, not a promise that every search has enough hits.
  final int textbookCount;
  const AiSearchOptions({
    this.rephrase = true,
    this.streaming = true,
    this.textbookCount = 8,
  });
  int get quotaCost => 1 + (rephrase ? 1 : 0) + (streaming ? 1 : 0);
  int get questionCount => evidenceCount - textbookCount;
  String get ratioLabel => '$textbookCount : $questionCount';

  AiSearchOptions copyWith({
    bool? rephrase,
    bool? streaming,
    int? textbookCount,
  }) => AiSearchOptions(
    rephrase: rephrase ?? this.rephrase,
    streaming: streaming ?? this.streaming,
    textbookCount: textbookCount ?? this.textbookCount,
  );

  factory AiSearchOptions.fromPreferences(SharedPreferences prefs) {
    final rephrase = prefs.getBool(rephraseKey) ?? true;
    return AiSearchOptions(
      rephrase: rephrase,
      streaming: rephrase && (prefs.getBool(streamingKey) ?? true),
      textbookCount: (prefs.getInt(textbookCountKey) ?? 8).clamp(
        0,
        evidenceCount,
      ),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    // Avoid persisting streaming=true/rephrase=false between the two writes.
    final saved = rephrase
        ? await prefs.setBool(rephraseKey, rephrase) &&
              await prefs.setBool(streamingKey, streaming)
        : await prefs.setBool(streamingKey, false) &&
              await prefs.setBool(rephraseKey, false);
    if (!saved || !await prefs.setInt(textbookCountKey, textbookCount)) {
      throw StateError('AI settings could not be saved');
    }
  }
}
