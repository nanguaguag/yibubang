import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/widgets/ai_answer_text.dart';

void main() {
  testWidgets(
    'paragraph selection across trailing citation and formula widgets',
    (tester) async {
      for (final text in [
        '正文证据[1]',
        r'末尾公式 $x^2$',
        '正文证据[1]\n\n后一段',
        r'文字 $x^2$ 与引用[1]',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: AiAnswerText(
                  text: text,
                  citations: const [
                    AiCitation(number: 1, questionId: 'q', title: '题目'),
                  ],
                  onCitation: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final render = tester.renderObject<RenderParagraph>(
          find
              .byWidgetPredicate(
                (w) =>
                    w is RichText &&
                    (w.text.toPlainText().startsWith('正文') ||
                        w.text.toPlainText().startsWith('末尾') ||
                        w.text.toPlainText().startsWith('文字')),
              )
              .first,
        );
        final container = find
            .descendant(
              of: find.byType(AiAnswerText),
              matching: find.byType(SelectionContainer),
            )
            .first;
        final delegate = tester.state(container) as SelectionHandler;
        // Selection of a paragraph beyond its text is how an enclosing scroll
        // delegate asks this child to extend a triple-click drag. This triggered
        // the user's exact lastSelectionResult assertion before the fix.
        for (final point in [
          Offset(render.size.width + 5, 8),
          Offset(1, render.size.height + 5),
        ]) {
          delegate.dispatchSelectionEvent(
            SelectParagraphSelectionEvent(
              globalPosition: render.localToGlobal(point),
            ),
          );
          await tester.pump();
        }
        final positions = [
          render.localToGlobal(
            render.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero) +
                const Offset(1, 8),
          ),
          render.localToGlobal(Offset(render.size.width - 2, 8)),
          render.localToGlobal(const Offset(1, 8)),
        ];
        for (final position in positions) {
          final gesture = await tester.startGesture(
            position,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.up();
          await tester.pump();
          await gesture.down(position);
          await tester.pump();
          await gesture.up();
          await tester.pump();
          await gesture.down(position);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$text at $position');
          if (position == positions.first) {
            expect(render.selections, isNotEmpty);
          }
          await gesture.up();
          await gesture.removePointer();
          await tester.pump(const Duration(milliseconds: 500));
        }
        if (text.contains('[1]')) {
          await tester.tap(find.byTooltip('题目'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      }
    },
  );
}
