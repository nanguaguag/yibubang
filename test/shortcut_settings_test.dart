import 'package:flutter/material.dart';
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
    final down = find.byTooltip('降低优先级').first;
    await tester.ensureVisible(down);
    await tester.pumpAndSettle();
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(ShortcutConfig.actionsByPriority.first, ShortcutAction.goBack);
    expect(tester.takeException(), isNull);
  });
}
