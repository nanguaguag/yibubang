import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';
import 'package:yibubang/widgets/app_fullscreen_shortcut.dart';
import 'package:yibubang/widgets/navigation_shortcuts.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ShortcutConfig.load();
    await ShortcutConfig.resetAll();
  });

  Future<GlobalKey<NavigatorState>> mount(
    WidgetTester tester,
    ValueChanged<int> onSelected, {
    Map<ShortcutAction, int?>? tabIndexes,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (_, child) => AppBackShortcut(
          navigatorKey: navigatorKey,
          child: AppFullscreenShortcut(
            navigatorKey: navigatorKey,
            child: child!,
          ),
        ),
        home: HomeTabShortcuts(
          tabIndexes:
              tabIndexes ??
              const {
                ShortcutAction.homeCourses: 0,
                ShortcutAction.homeDailyPlan: 1,
                ShortcutAction.homeAiSearch: 2,
                ShortcutAction.homeStatistics: 3,
                ShortcutAction.homeMyPage: 4,
              },
          onSelected: onSelected,
          child: const Scaffold(body: TextField()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return navigatorKey;
  }

  testWidgets(
    'home tabs accept number row and numpad, ignore repeat and input',
    (tester) async {
      final selected = <int>[];
      await mount(tester, selected.add);
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad2,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad4,
        LogicalKeyboardKey.numpad5,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(selected, [0, 1, 2, 3, 4, 0, 1, 2, 3, 4]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      expect(selected.length, 11);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      expect(selected.length, 11);
    },
  );

  testWidgets(
    'reordered, disabled and shared tab shortcuts follow current mapping',
    (tester) async {
      final selected = <int>[];
      await mount(
        tester,
        selected.add,
        tabIndexes: const {
          ShortcutAction.homeCourses: 2,
          ShortcutAction.homeStatistics: 0,
          ShortcutAction.homeMyPage: null,
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      expect(selected, [2, 0]);

      await ShortcutConfig.assignBinding(
        ShortcutAction.toggleFullscreen,
        const KeyBinding(LogicalKeyboardKey.f6),
      );
      await ShortcutConfig.assignBinding(
        ShortcutAction.homeStatistics,
        const KeyBinding(LogicalKeyboardKey.f6),
      );
      await ShortcutConfig.moveAction(
        ShortcutAction.toggleFullscreen,
        -ShortcutConfig.actionsByPriority.indexOf(
          ShortcutAction.toggleFullscreen,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      expect(selected, [2, 0]);
    },
  );

  testWidgets(
    'Esc returns one route and respects PopScope; tabs stay on home',
    (tester) async {
      final selected = <int>[];
      final navigator = await mount(tester, selected.add);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      expect(selected, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const PopScope(
            canPop: false,
            child: Scaffold(body: Text('blocked')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('blocked'), findsOneWidget);
    },
  );

  testWidgets(
    'dialog closes before page and custom home binding takes effect',
    (tester) async {
      final selected = <int>[];
      final navigator = await mount(tester, selected.add);
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('dialog')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      expect(selected, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      await ShortcutConfig.assignBinding(
        ShortcutAction.homeStatistics,
        const KeyBinding(LogicalKeyboardKey.f6),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      expect(selected, [3]);
    },
  );
}
