import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<LogicalKeyboardKey> keysOf(ShortcutAction action) {
    return ShortcutConfig.bindingsFor(
      action,
    ).map((KeyBinding binding) => binding.key).toList();
  }

  test('数字键与字母键映射到选项序号', () {
    expect(ShortcutConfig.numberOptionIndex(LogicalKeyboardKey.digit1), 0);
    expect(ShortcutConfig.numberOptionIndex(LogicalKeyboardKey.digit0), 9);
    expect(ShortcutConfig.numberOptionIndex(LogicalKeyboardKey.numpad5), 4);
    expect(ShortcutConfig.numberOptionIndex(LogicalKeyboardKey.keyA), isNull);

    expect(ShortcutConfig.letterOptionKey(LogicalKeyboardKey.keyA), 'A');
    expect(ShortcutConfig.letterOptionKey(LogicalKeyboardKey.keyZ), 'Z');
    expect(ShortcutConfig.letterOptionKey(LogicalKeyboardKey.digit1), isNull);
  });

  test('默认键位符合预期', () {
    expect(keysOf(ShortcutAction.previousQuestion), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowLeft,
    ]);
    expect(keysOf(ShortcutAction.nextQuestion), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowRight,
    ]);
    expect(keysOf(ShortcutAction.submitAnswer), <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
    ]);
    expect(keysOf(ShortcutAction.scrollPageDown), <LogicalKeyboardKey>[
      LogicalKeyboardKey.pageDown,
    ]);
    expect(keysOf(ShortcutAction.scrollPageUp), <LogicalKeyboardKey>[
      LogicalKeyboardKey.pageUp,
    ]);
    expect(keysOf(ShortcutAction.scrollLineDown), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowDown,
    ]);
    expect(keysOf(ShortcutAction.scrollLineUp), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowUp,
    ]);
    // 其它按钮留空，由用户在设置中自行绑定
    expect(keysOf(ShortcutAction.toggleCut), isEmpty);
    expect(keysOf(ShortcutAction.toggleCollection), isEmpty);
    expect(keysOf(ShortcutAction.copyQuestion), isEmpty);
  });

  test('滚动步长可配置并持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(ShortcutConfig.pageScrollPercent, 90);
    expect(ShortcutConfig.lineScrollPixels, 40);

    await ShortcutConfig.setPageScrollPercent(75);
    await ShortcutConfig.setLineScrollPixels(120);
    expect(ShortcutConfig.pageScrollPercent, 75);
    expect(ShortcutConfig.lineScrollPixels, 120);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('shortcut_page_scroll_percent'), 75);
    expect(prefs.getInt('shortcut_line_scroll_pixels'), 120);

    // 非法值就近归一到可选项
    await ShortcutConfig.setPageScrollPercent(77);
    expect(ShortcutConfig.pageScrollPercent, 75);
    await ShortcutConfig.setLineScrollPixels(999);
    expect(ShortcutConfig.lineScrollPixels, 120);

    // 恢复默认，避免影响其它用例
    await ShortcutConfig.setPageScrollPercent(90);
    await ShortcutConfig.setLineScrollPixels(40);
  });

  test('KeyBinding 标签与序列化往返', () {
    const KeyBinding arrow = KeyBinding(LogicalKeyboardKey.arrowRight);
    expect(arrow.label, '→');
    expect(KeyBinding.fromJson(arrow.toJson()), arrow);

    const KeyBinding combo = KeyBinding(
      LogicalKeyboardKey.keyC,
      ctrl: true,
      shift: true,
    );
    expect(combo.label, 'Ctrl + Shift + C');
    expect(KeyBinding.fromJson(combo.toJson()), combo);
  });

  test('同一动作可绑定多个键位，支持新增与移除', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const KeyBinding c = KeyBinding(LogicalKeyboardKey.keyC);
    const KeyBinding d = KeyBinding(LogicalKeyboardKey.keyD);

    await ShortcutConfig.assignBinding(ShortcutAction.toggleCut, c);
    await ShortcutConfig.assignBinding(ShortcutAction.toggleCut, d);
    expect(keysOf(ShortcutAction.toggleCut), <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
    ]);

    await ShortcutConfig.removeBinding(ShortcutAction.toggleCut, c);
    expect(keysOf(ShortcutAction.toggleCut), <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyD,
    ]);

    await ShortcutConfig.resetAll();
    expect(keysOf(ShortcutAction.toggleCut), isEmpty);
  });

  test('绑定冲突时自动从旧动作移除，恢复默认后还原', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ShortcutConfig.assignBinding(
      ShortcutAction.toggleCut,
      const KeyBinding(LogicalKeyboardKey.arrowRight),
    );

    expect(keysOf(ShortcutAction.toggleCut), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowRight,
    ]);
    // 与「下一题」的默认键位冲突，旧绑定被移除
    expect(keysOf(ShortcutAction.nextQuestion), isEmpty);

    await ShortcutConfig.resetAll();
    expect(keysOf(ShortcutAction.toggleCut), isEmpty);
    expect(keysOf(ShortcutAction.nextQuestion), <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowRight,
    ]);
  });
}
