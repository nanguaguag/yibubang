import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/shortcut_config.dart';

class AppFullscreenShortcut extends StatefulWidget {
  const AppFullscreenShortcut({super.key, required this.child});
  final Widget child;
  @override
  State<AppFullscreenShortcut> createState() => _AppFullscreenShortcutState();
}

class _AppFullscreenShortcutState extends State<AppFullscreenShortcut> {
  static const _channel = MethodChannel('yibubang/window');
  bool _busy = false;
  bool _mobileFullscreen = false;

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await _channel.invokeMethod<bool>('toggleFullscreen');
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        _mobileFullscreen = !_mobileFullscreen;
        await SystemChrome.setEnabledSystemUIMode(
          _mobileFullscreen
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge,
        );
      }
    } on PlatformException catch (error) {
      debugPrint('全屏切换失败：$error');
    } finally {
      _busy = false;
    }
  }

  KeyEventResult _handle(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final matches = ShortcutConfig.bindingsFor(
      ShortcutAction.toggleFullscreen,
    ).where((binding) => binding.matches(event.logicalKey));
    if (matches.isEmpty) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    // 普通文字键作为自定义全屏键时，也不能抢走输入框的键盘输入。
    if ((focusContext?.widget is EditableText ||
            focusContext?.findAncestorWidgetOfExactType<EditableText>() !=
                null) &&
        matches.first.key.keyLabel.length == 1 &&
        !matches.first.ctrl &&
        !matches.first.alt &&
        !matches.first.meta) {
      return KeyEventResult.ignored;
    }
    unawaited(_toggle());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, onKeyEvent: _handle, child: widget.child);
}
