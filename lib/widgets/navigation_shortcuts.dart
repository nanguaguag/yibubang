import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/shortcut_config.dart';
import 'app_fullscreen_shortcut.dart';

bool runGlobalShortcut(BuildContext context, ShortcutAction action) {
  if (action == ShortcutAction.toggleFullscreen) {
    return AppFullscreenShortcut.toggleOf(context);
  }
  if (action == ShortcutAction.goBack) {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return false;
    unawaited(navigator.maybePop());
    return true;
  }
  return false;
}

bool _matches(ShortcutAction action, KeyEvent event) =>
    ShortcutConfig.bindingsFor(
      action,
    ).any((binding) => binding.matches(event.logicalKey));

bool isShortcutTextInputFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.widget is EditableText ||
      context?.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Handles the application-level back key outside the active Navigator route.
class AppBackShortcut extends StatelessWidget {
  const AppBackShortcut({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent || !_matches(ShortcutAction.goBack, event)) {
        return KeyEventResult.ignored;
      }
      if (isShortcutTextInputFocused() &&
          event.logicalKey.keyLabel.length == 1 &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      final navigator = navigatorKey.currentState;
      if (navigator == null || !navigator.canPop()) {
        return KeyEventResult.ignored;
      }
      unawaited(navigator.maybePop());
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// Maps the home tab shortcuts to IDs in the currently configured nav list.
/// Missing or disabled destinations have a null index and are ignored.
class HomeTabShortcuts extends StatelessWidget {
  const HomeTabShortcuts({
    super.key,
    required this.tabIndexes,
    required this.onSelected,
    required this.child,
  });

  final Map<ShortcutAction, int?> tabIndexes;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent ||
          ModalRoute.of(context)?.isCurrent != true ||
          isShortcutTextInputFocused()) {
        return KeyEventResult.ignored;
      }
      for (final action in ShortcutConfig.actionsByPriority) {
        if (!_matches(action, event)) continue;
        final index = tabIndexes[action];
        if (index != null) {
          onSelected(index);
          return KeyEventResult.handled;
        }
        if (runGlobalShortcut(context, action)) return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}
