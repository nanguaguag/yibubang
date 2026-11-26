import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/screens/font_settings_page.dart';
import 'package:yibubang/widgets/font_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FontController.instance.load();
  });

  test(
    'system font persists, missing imported font falls back safely',
    () async {
      final fonts = FontController.instance;
      await fonts.setSystemFont('  Microsoft YaHei  ');
      await fonts.load();
      expect(fonts.family, 'Microsoft YaHei');
      expect(fonts.label, 'Microsoft YaHei');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_font_path', 'missing-font-for-test.ttf');
      await fonts.load();
      expect(fonts.family, isNull);
      expect(fonts.label, '系统默认');
      expect(prefs.getString('app_font_path'), isNull);
      await expectLater(
        fonts.importFont('bad.ttf', Uint8List(16)),
        throwsFormatException,
      );
      expect(fonts.family, isNull);
    },
  );

  testWidgets('font page applies a family and restores default', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FontSettingsPage()));
    await tester.enterText(find.byType(TextField), 'Microsoft YaHei');
    await tester.tap(find.text('应用系统字体'));
    await tester.pumpAndSettle();
    expect(FontController.instance.family, 'Microsoft YaHei');
    expect(find.text('当前字体：Microsoft YaHei'), findsOneWidget);
    await tester.ensureVisible(find.text('恢复系统默认'));
    await tester.tap(find.text('恢复系统默认'));
    await tester.pumpAndSettle();
    expect(FontController.instance.family, isNull);
    expect(find.text('当前字体：系统默认'), findsOneWidget);
  });
}
