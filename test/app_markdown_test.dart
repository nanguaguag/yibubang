import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/widgets/app_markdown.dart';
import 'package:yibubang/widgets/common/app_network_image.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  testWidgets('renders basic markdown syntax: bold, italic, code, blockquote', (
    tester,
  ) async {
    const text = '''
# 一级标题
这是一个段落，包含 **粗体文字** 和 *斜体* 以及 `inline code`。

> 这是引用块内容

* 列表项 1
* 列表项 2
''';

    await tester.pumpWidget(buildApp(const AppMarkdown(text: text)));
    await tester.pumpAndSettle();

    expect(find.text('一级标题', findRichText: true), findsOneWidget);
    expect(find.textContaining('粗体文字', findRichText: true), findsOneWidget);
    expect(find.textContaining('列表项 1', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_blockquote')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders LaTeX formulas natively using Math.tex', (tester) async {
    const text = r'''
行内公式：$E = mc^2$，块级公式：

$$\int_{0}^{\infty} e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$
''';

    await tester.pumpWidget(buildApp(const AppMarkdown(text: text)));
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders image in markdown when allowImages is true', (tester) async {
    const text = '题干插图说明：\n\n![解剖图示](https://cdn.example.com/anatomy.jpg)';

    await tester.pumpWidget(
      buildApp(
        const AppMarkdown(
          text: text,
          allowImages: true,
        ),
      ),
    );
    await tester.pump();

    // 应该渲染 AppNetworkImage 组件与放大镜图标
    expect(find.byType(AppNetworkImage), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to alt text when allowImages is false', (tester) async {
    const text = '题干插图说明：![解剖图示](https://cdn.example.com/anatomy.jpg)';

    await tester.pumpWidget(
      buildApp(
        const AppMarkdown(
          text: text,
          allowImages: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppNetworkImage), findsNothing);
    expect(find.textContaining('解剖图示', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
