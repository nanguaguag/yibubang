// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:yibubang/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Use sqflite on MacOS/iOS/Android.
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) {
      // Use web implementation on the web.
      databaseFactory = databaseFactoryFfiWeb;
    } else {
      // Use ffi on Linux and Windows.
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        databaseFactory = databaseFactoryFfi;
        sqfliteFfiInit();
      }
    }

    // Build our app and trigger a frame.
    await tester.pumpWidget(const Yibubang());

    // Verify that our counter starts at 0.
    expect(find.text('我的课程'), findsWidgets);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('失败'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
  });
}
