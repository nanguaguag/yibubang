import 'package:flutter/material.dart';
import '../models/ai_search.dart';

/// Lightweight streaming-safe Markdown subset with validated citation links.
/// No HTML/webview and no links invented by a model can open an arbitrary URL.
class AiAnswerText extends StatelessWidget {
  final String text;
  final List<AiCitation> citations;
  final ValueChanged<AiCitation> onCitation;
  const AiAnswerText({
    super.key,
    required this.text,
    required this.citations,
    required this.onCitation,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.65);
    final lines = text.split('\n');
    final blocks = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i + 1 < lines.length &&
          line.trim().startsWith('|') &&
          RegExp(r'^\s*\|?[\s:|\-]+\|\s*$').hasMatch(lines[i + 1])) {
        final rows = <List<String>>[_cells(line)];
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(_cells(lines[i]));
          i++;
        }
        i--;
        blocks.add(_table(context, rows, base));
      } else if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
      } else {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _line(
              context,
              line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• '),
              base,
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  List<String> _cells(String line) => line
      .trim()
      .replaceFirst(RegExp(r'^\|'), '')
      .replaceFirst(RegExp(r'\|$'), '')
      .split('|')
      .map((c) => c.trim())
      .take(8)
      .toList();

  Widget _table(BuildContext context, List<List<String>> rows, TextStyle base) {
    final scheme = Theme.of(context).colorScheme;
    final columns = rows.first.length;
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
                                  child: _line(
                                    context,
                                    c < rows[r].length ? rows[r][c] : '',
                                    base.copyWith(
                                      fontSize: 14,
                                      fontWeight: r == 0
                                          ? FontWeight.w700
                                          : FontWeight.normal,
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

  Widget _line(BuildContext context, String raw, TextStyle base) {
    final heading = RegExp(r'^#{1,3}\s+').firstMatch(raw);
    final line = heading == null ? raw : raw.substring(heading.end);
    final style = heading == null
        ? base
        : base.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: (base.fontSize ?? 16) + 2,
          );
    final parts = <InlineSpan>[];
    final pattern = RegExp(r'(\[\d{1,2}\])|(\*\*[^*]+\*\*)|(`[^`]+`)');
    var offset = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > offset) {
        parts.add(TextSpan(text: line.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      if (match.group(1) != null) {
        final number = int.parse(token.substring(1, token.length - 1));
        final citation = citations.where((c) => c.number == number).firstOrNull;
        if (citation == null) {
          parts.add(TextSpan(text: token));
        } else {
          final scheme = Theme.of(context).colorScheme;
          final chip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
          );
          parts.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: citation.title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onCitation(citation),
                    child: Semantics(
                      label: '引用 $number，查看原题',
                      button: true,
                      child: chip,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      } else if (match.group(2) != null) {
        parts.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        parts.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      }
      offset = match.end;
    }
    parts.add(TextSpan(text: line.substring(offset)));
    return Text.rich(TextSpan(style: style, children: parts));
  }
}
