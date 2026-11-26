import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';
import 'package:yibubang/screens/shortcut_settings_page.dart';

void main() {
  testWidgets('priority controls work on a narrow settings page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await ShortcutConfig.load();
    await ShortcutConfig.resetAll();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ShortcutSettingsPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final submit = find.text('提交答案');
    await tester.scrollUntilVisible(submit, 300);
    final row = find.ancestor(of: submit, matching: find.byType(Row)).first;
    final down = find.descendant(of: row, matching: find.byTooltip('降低优先级'));
    await tester.ensureVisible(down);
    await tester.pumpAndSettle();
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(ShortcutConfig.actionsByPriority.first, ShortcutAction.goBack);
    expect(tester.takeException(), isNull);
  });

  testWidgets('认知状态选择可独立添加评分快捷键', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ShortcutConfig.load();
    await ShortcutConfig.resetAll();
    addTearDown(ShortcutConfig.resetAll);
    await tester.pumpWidget(const MaterialApp(home: ShortcutSettingsPage()));
    await tester.pumpAndSettle();
    final good = find.text('良好');
    await tester.scrollUntilVisible(good, 250);
    final row = find.ancestor(of: good, matching: find.byType(Row)).first;
    final add = find.descendant(of: row, matching: find.text('添加按键'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('设置「良好」快捷键'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(
      ShortcutConfig.bindingsFor(ShortcutAction.reviewGood),
      contains(const KeyBinding(LogicalKeyboardKey.keyG)),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shortcut_bindings_v1'), contains('review_good'));
  });
}
