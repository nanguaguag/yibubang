import 'package:flutter/material.dart';
import '../models/ai_search.dart';
import 'app_markdown.dart';

/// Markdown AST rendered natively; incomplete streamed syntax stays as text.
/// Only citations present in this turn can navigate.
class AiAnswerText extends StatelessWidget {
  final String text;
  final List<AiCitation> citations;
  final ValueChanged<AiCitation> onCitation;
  final bool animateReveal;

  const AiAnswerText({
    super.key,
    required this.text,
    required this.citations,
    required this.onCitation,
    this.animateReveal = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppMarkdown(
      text: text,
      citations: citations,
      onCitation: onCitation,
      animateReveal: animateReveal,
      // AI 搜索原逻辑不解析远程图片，保持纯文本或允许图片
      allowImages: false,
    );
  }
}
