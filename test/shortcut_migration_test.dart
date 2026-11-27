import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/shortcut_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy Space browsing and saved priority survive loading', () async {
    SharedPreferences.setMockInitialValues({
      'shortcut_bindings_v1': jsonEncode({
        'next_question': [const KeyBinding(LogicalKeyboardKey.space).toJson()],
      }),
      'shortcut_action_priority_v1': [
        'next_question',
        'unknown',
        'next_question',
      ],
    });
    await ShortcutConfig.load();
    expect(ShortcutConfig.bindingsFor(ShortcutAction.nextQuestion), [
      const KeyBinding(LogicalKeyboardKey.space),
    ]);
    expect(ShortcutConfig.bindingsFor(ShortcutAction.submitAnswer), [
      const KeyBinding(LogicalKeyboardKey.enter),
    ]);
    expect(ShortcutConfig.actionsByPriority.first, ShortcutAction.nextQuestion);
    expect(
      ShortcutConfig.actionsByPriority.length,
      ShortcutAction.values.length,
    );
    // 新增共享绑定不会删除原来的翻题键。
    await ShortcutConfig.assignBinding(
      ShortcutAction.submitAnswer,
      const KeyBinding(LogicalKeyboardKey.space),
    );
    expect(
      ShortcutConfig.bindingsFor(ShortcutAction.nextQuestion),
      contains(const KeyBinding(LogicalKeyboardKey.space)),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('shortcut_shared_keys_v1'), isTrue);
    await ShortcutConfig.resetAll();
    expect(ShortcutConfig.actionsByPriority.first, ShortcutAction.submitAnswer);
  });
}
