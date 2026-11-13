import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/widgets/ai_answer_text.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    String text, {
    ValueChanged<AiCitation>? onCitation,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiAnswerText(
            text: text,
            citations: [
              for (var i = 1; i <= 6; i++)
                AiCitation(number: i, questionId: 'q$i', title: '题$i'),
            ],
            onCitation: onCitation ?? (_) {},
          ),
        ),
      ),
    ),
  );
  testWidgets('display delimiters inside prose preserve trailing text', (
    tester,
  ) async {
    await mount(tester, r'$$x^2$$ 后文与 $$y^2$$。');
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('后文与', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('tight nested lists keep bold labels and colons in one paragraph', (
    tester,
  ) async {
    await mount(
      tester,
      '* **机制**：\n'
      '   * **基因转录调节**：激活后的C亚基可从胞质进入胞核，使**cAMP反应元件结合蛋白（CREB）**等转录因子磷酸化，进而介导和调节靶基因的表达。[4, 8]',
    );
    final label = find.text('机制：', findRichText: true);
    expect(label, findsOneWidget);
    final text = tester.widget<RichText>(label).text as TextSpan;
    final strong =
        (text.children!.first as TextSpan).children!.first as TextSpan;
    expect(strong.style!.fontWeight, FontWeight.w700);
    expect(strong.toPlainText(), '机制');
    final body = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('基因转录调节：'),
      ),
    );
    final terms = <(String, FontWeight?)>[];
    void collect(InlineSpan span, [FontWeight? weight]) {
      if (span is! TextSpan) return;
      final current = span.style?.fontWeight ?? weight;
      if (span.text != null) terms.add((span.text!, current));
      for (final child in span.children ?? <InlineSpan>[]) {
        collect(child, current);
      }
    }

    collect(body.text);
    expect(terms, contains(('cAMP反应元件结合蛋白（CREB）', FontWeight.w700)));
    expect(body.text.toPlainText(), isNot(contains('**')));
    expect(find.byTooltip('题4'), findsOneWidget);
    expect(find.text('[8]', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Chinese emphasis extension preserves code, escaping and partial syntax',
    (tester) async {
      await mount(
        tester,
        r'使**结合蛋白（CREB）**等磷酸化。`**结合蛋白（CREB）**` 与 \*\*结合蛋白（CREB）\*\*',
      );
      expect(
        find.textContaining('**结合蛋白（CREB）**', findRichText: true),
        findsOneWidget,
      );
      await mount(tester, r'使**结合蛋白（CREB）');
      expect(
        find.textContaining('**结合蛋白（CREB）', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'blockquote, nested emphasis, inline and display math render natively',
    (tester) async {
      await mount(
        tester,
        r'> 引用 **重点** 与 $\text{CO}_2$'
        '\n\n'
        r'$$x=\frac{-b+\sqrt{b^2-4ac}}{2a}$$',
      );
      expect(find.byKey(const ValueKey('ai_blockquote')), findsOneWidget);
      expect(find.byType(Math), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('grouped citation numbers each open their own real source', (
    tester,
  ) async {
    final opened = <int>[];
    await mount(
      tester,
      '三角肌粗隆[3, 4, 5, 6]。止点[1,3,5,6]。无效[99]。',
      onCitation: (c) => opened.add(c.number),
    );
    for (final number in [3, 4, 5, 6]) {
      await tester.tap(find.byTooltip('题$number').first);
    }
    expect(opened, [3, 4, 5, 6]);
    expect(find.byTooltip('题99'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'code, escaped dollars, streaming partial and invalid math remain legible',
    (tester) async {
      for (final text in [
        r'`[1] $x$` 与 \$20',
        r'$$\frac{a}{',
        r'$\unknown{x}$',
        '**未结束',
        r'> $x',
      ]) {
        await mount(tester, text);
        expect(tester.takeException(), isNull);
      }
      await mount(tester, r'`[1] $x$` 与 \$20');
      expect(find.byType(Math), findsNothing);
      expect(find.byTooltip('题1'), findsNothing);
    },
  );
}
