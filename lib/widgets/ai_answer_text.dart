import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/ai_search.dart';

/// Markdown AST rendered natively; incomplete streamed syntax stays as text.
/// Only citations present in this turn can navigate. Remote images/URLs cannot.
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
    final base = Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.65);
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [const _DisplayMathSyntax()],
      inlineSyntaxes: [
        _CjkStrongSyntax(),
        _InlineMathSyntax(),
        _CitationSyntax(),
      ],
      encodeHtml: false,
    );
    final blocks = document.parseLines(text.split('\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < blocks.length; index++)
          _reveal(
            context,
            ValueKey(index),
            _block(context, blocks[index], base),
          ),
      ],
    );
  }

  Widget _reveal(BuildContext context, Key key, Widget child) {
    if (!animateReveal || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
    );
  }

  Widget _math(String source, TextStyle style, {bool display = false}) =>
      Math.tex(
        source,
        textStyle: style,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        onErrorFallback: (_) =>
            Text(display ? '\$\$$source\$\$' : '\$$source\$', style: style),
      );

  Widget _block(BuildContext context, md.Node node, TextStyle base) {
    if (node is md.Text) return Text(node.text, style: base);
    final e = node as md.Element;
    final children = e.children ?? [];
    switch (e.tag) {
      case 'blockquote':
        final scheme = Theme.of(context).colorScheme;
        return Container(
          key: const ValueKey('ai_blockquote'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children.map((n) => _block(context, n, base)).toList(),
          ),
        );
      case 'math-display':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _math(e.textContent, base, display: true),
          ),
        );
      case 'pre':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              e.textContent,
              style: base.copyWith(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        );
      case 'ul':
      case 'ol':
        var number = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++)
              _reveal(
                context,
                ValueKey(index),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          e.tag == 'ol' ? '${number++}.' : '•',
                          style: base,
                        ),
                      ),
                      Expanded(child: _block(context, children[index], base)),
                    ],
                  ),
                ),
              ),
          ],
        );
      case 'li':
        // Tight lists mix inline nodes with nested block nodes. Keep each
        // inline run together, so a bold label and its colon share a paragraph.
        final blocks = <Widget>[];
        final inline = <md.Node>[];
        void flush() {
          if (inline.isEmpty) return;
          blocks.add(
            Text.rich(
              TextSpan(style: base, children: _inline(context, inline, base)),
            ),
          );
          inline.clear();
        }
        for (final child in children) {
          if (child is md.Element &&
              const {
                'p',
                'ul',
                'ol',
                'blockquote',
                'pre',
                'table',
                'hr',
                'h1',
                'h2',
                'h3',
                'h4',
                'h5',
                'h6',
                'math-display',
              }.contains(child.tag)) {
            flush();
            blocks.add(_block(context, child, base));
          } else {
            inline.add(child);
          }
        }
        flush();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: blocks,
        );
      case 'table':
        final rows = <List<md.Element>>[];
        void collect(md.Element n) {
          if (n.tag == 'tr') {
            rows.add((n.children ?? []).whereType<md.Element>().toList());
          } else {
            for (final c in (n.children ?? []).whereType<md.Element>()) {
              collect(c);
            }
          }
        }
        collect(e);
        return _table(context, rows, base);
      case 'hr':
        return const Divider(height: 24);
      default:
        final heading = RegExp(r'^h[1-6]$').hasMatch(e.tag);
        final style = heading
            ? base.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: (base.fontSize ?? 16) + (e.tag == 'h1' ? 6 : 2),
              )
            : base;
        return Padding(
          padding: EdgeInsets.only(top: heading ? 8 : 0, bottom: 8),
          child: Text.rich(
            TextSpan(style: style, children: _inline(context, children, style)),
          ),
        );
    }
  }

  List<InlineSpan> _inline(
    BuildContext context,
    List<md.Node> nodes,
    TextStyle base,
  ) => [for (final node in nodes) _span(context, node, base)];

  InlineSpan _span(BuildContext context, md.Node node, TextStyle base) {
    if (node is md.Text) return TextSpan(text: node.text);
    final e = node as md.Element;
    if (e.tag == 'citation') {
      final parts = <InlineSpan>[];
      final numbers = RegExp(
        r'\d+',
      ).allMatches(e.textContent).map((m) => int.parse(m[0]!)).toList();
      for (final number in numbers) {
        final citation = citations.where((c) => c.number == number).firstOrNull;
        if (citation == null) {
          parts.add(TextSpan(text: '[$number]'));
          continue;
        }
        final scheme = Theme.of(context).colorScheme;
        parts.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            // Inline controls must not register their inner labels as separate
            // selectable paragraphs in Text.rich's paragraph delegate.
            child: SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: citation.title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onCitation(citation),
                    child: Semantics(
                      label:
                          '引用 $number，${citation.isTextbook ? '查看教材原页' : '查看原题'}',
                      button: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$number',
                          style: base.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return TextSpan(children: parts);
    }
    if (e.tag == 'math-inline' || e.tag == 'math-inline-display') {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SelectionContainer.disabled(
          child: _math(
            e.textContent,
            base,
            display: e.tag == 'math-inline-display',
          ),
        ),
      );
    }
    if (e.tag == 'br') return const TextSpan(text: '\n');
    if (e.tag == 'img') return TextSpan(text: e.attributes['alt'] ?? '');
    final style = switch (e.tag) {
      'strong' => const TextStyle(fontWeight: FontWeight.w700),
      'em' => const TextStyle(fontStyle: FontStyle.italic),
      'del' => const TextStyle(decoration: TextDecoration.lineThrough),
      'code' => TextStyle(
        fontFamily: 'monospace',
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      _ => null,
    };
    return TextSpan(
      style: style,
      children: _inline(context, e.children ?? [], base.merge(style)),
    );
  }

  Widget _table(
    BuildContext context,
    List<List<md.Element>> rows,
    TextStyle base,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.first.length.clamp(1, 8);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(
            columns * 155.0,
            double.infinity,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (width > constraints.maxWidth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '左右滑动查看表格',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: width,
                    child: Table(
                      border: TableBorder.all(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        for (var r = 0; r < rows.length; r++)
                          TableRow(
                            decoration: BoxDecoration(
                              color: r == 0
                                  ? scheme.surfaceContainerHigh
                                  : scheme.surfaceContainerLow,
                            ),
                            children: [
                              for (var c = 0; c < columns; c++)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text.rich(
                                    TextSpan(
                                      style: base.copyWith(
                                        fontSize: 14,
                                        fontWeight: r == 0
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                      children: c < rows[r].length
                                          ? _inline(
                                              context,
                                              rows[r][c].children ?? [],
                                              base,
                                            )
                                          : [],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// AI prose often puts Chinese parentheses inside bold text without surrounding
/// spaces. Extend only that punctuation boundary; leave ordinary/nested
/// CommonMark emphasis, escaped delimiters and code to the standard parser.
class _CjkStrongSyntax extends md.InlineSyntax {
  _CjkStrongSyntax() : super(r'\*\*(?!\*)([^*\n]+?)\*\*(?!\*)');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final match = pattern.matchAsPrefix(
      parser.source,
      startMatchPos ?? parser.pos,
    );
    if (match == null) return false;
    final content = match[1]!;
    if (content.trim() != content ||
        !RegExp(r'[\u3400-\u9fff]').hasMatch(content)) {
      return false;
    }
    final start = match.start;
    final end = match.end;
    if (start > 0 && parser.source[start - 1] == '*') return false;
    final punctuation = RegExp(r'[（）【】《》「」『』，。；：！？、]');
    // A colon after an existing bold label belongs to the surrounding prose.
    // Do not mistake that closing delimiter for a new bold opener.
    final openingBracket = RegExp(r'[（【《「『]');
    final han = RegExp(r'[\u3400-\u9fff]');
    final brokenOpen =
        start > 0 &&
        han.hasMatch(parser.source[start - 1]) &&
        openingBracket.hasMatch(content[0]);
    final brokenClose =
        end < parser.source.length &&
        punctuation.hasMatch(content[content.length - 1]) &&
        han.hasMatch(parser.source[end]);
    if (!brokenOpen && !brokenClose) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('strong', md.InlineParser(match[1]!, parser.document).parse()),
    );
    return true;
  }
}

class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax() : super(r'\[\d{1,3}(?:\s*[,，]\s*\d{1,3})*\](?!\()');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('citation', match[0]!));
    return true;
  }
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax()
    : super(r'\$\$(.+?)\$\$|\$(?!\$)([^\n$]+)\$(?!\$)|\\\((.+?)\\\)');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text(
        match[1] == null ? 'math-inline' : 'math-inline-display',
        match[1] ?? match[2] ?? match[3]!,
      ),
    );
    return true;
  }
}

class _DisplayMathSyntax extends md.BlockSyntax {
  const _DisplayMathSyntax();
  @override
  RegExp get pattern => RegExp(r'^\s*(\$\$|\\\[)');
  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final line = parser.current.content.trim();
    final delimiter = line.startsWith(r'$$') ? r'$$' : r'\]';
    final closing = line.indexOf(delimiter, 2);
    // Preserve prose after an inline display formula instead of dropping it.
    return closing < 0 || line.substring(closing + 2).trim().isEmpty;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final first = parser.current.content.trimLeft();
    final end = first.startsWith(r'$$') ? r'$$' : r'\]';
    var rest = first.substring(2);
    final parts = <String>[];
    while (true) {
      final close = rest.indexOf(end);
      if (close >= 0) {
        parts.add(rest.substring(0, close));
        parser.advance();
        return md.Element.text('math-display', parts.join('\n').trim());
      }
      parts.add(rest);
      parser.advance();
      if (parser.isDone) {
        // Unclosed streaming formula remains legible until its delimiter arrives.
        return md.Element('p', [
          md.Text(first.substring(0, 2) + parts.join('\n')),
        ]);
      }
      rest = parser.current.content;
    }
  }
}
