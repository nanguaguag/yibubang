import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';
import 'package:yibubang/services/course_sync_actions.dart';
import 'package:yibubang/widgets/app_fullscreen_shortcut.dart';
import 'package:yibubang/widgets/course_sync_buttons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yibubang/window');
  var toggles = 0;
  Future<void> bindFullscreen(LogicalKeyboardKey key) async {
    for (final binding in ShortcutConfig.bindingsFor(
      ShortcutAction.toggleFullscreen,
    )) {
      await ShortcutConfig.removeBinding(
        ShortcutAction.toggleFullscreen,
        binding,
      );
    }
    await ShortcutConfig.assignBinding(
      ShortcutAction.toggleFullscreen,
      KeyBinding(key),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ShortcutConfig.load();
    await ShortcutConfig.resetAll();
    await CourseSyncActions.instance.load();
    toggles = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'toggleFullscreen');
          toggles++;
          return toggles.isOdd;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'F11 reaches native window on home and pushed routes, and ignores repeat',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AppFullscreenShortcut(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('另一页')),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(toggles, 1);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(toggles, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'fullscreen rebinding works immediately and F11 works in text fields',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AppFullscreenShortcut(child: child!),
          home: const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(toggles, 1);
      await bindFullscreen(LogicalKeyboardKey.f10);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(toggles, 2);
      await bindFullscreen(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(toggles, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'desktop sync buttons follow individual persisted visibility settings',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(appBar: null, body: CourseSyncButtons()),
        ),
      );
      expect(find.byTooltip('智能增量同步题库'), findsOneWidget);
      expect(find.byTooltip('拉取医考帮做题记录'), findsOneWidget);
      expect(find.byTooltip('全量重建题库'), findsOneWidget);
      await CourseSyncActions.instance.setVisible(
        CourseSyncAction.records,
        false,
      );
      await tester.pump();
      expect(find.byTooltip('拉取医考帮做题记录'), findsNothing);
      await CourseSyncActions.instance.load();
      await tester.pump();
      expect(
        CourseSyncActions.instance.isVisible(CourseSyncAction.records),
        false,
      );
      expect(find.byTooltip('智能增量同步题库'), findsOneWidget);
      for (final action in CourseSyncAction.values) {
        await CourseSyncActions.instance.setVisible(action, false);
      }
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'narrow screens show only enabled sync actions in a compact menu',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 800)),
            child: const Scaffold(body: CourseSyncButtons()),
          ),
        ),
      );
      await CourseSyncActions.instance.setVisible(
        CourseSyncAction.rebuild,
        false,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('同步操作'));
      await tester.pumpAndSettle();
      expect(find.text('智能增量同步题库'), findsOneWidget);
      expect(find.text('拉取医考帮做题记录'), findsOneWidget);
      expect(find.text('全量重建题库'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
