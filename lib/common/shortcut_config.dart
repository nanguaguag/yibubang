import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 选项键位模式：决定键盘上用哪些键来选择题目选项。
enum OptionKeyMode {
  number('数字 1-10', '按 1-9、0 依次选择第 1-10 个选项'),
  letter('字母 A-Z', '按 A-Z 选择对应字母的选项'),
  both('数字 + 字母', '数字与字母同时生效，例如 1 与 A 都会选中第一个选项');

  const OptionKeyMode(this.label, this.description);

  final String label;
  final String description;
}

/// 一个可持久化的按键绑定（按键 + 修饰键）。
///
/// 修饰键采用精确匹配：例如绑定 [Ctrl] + [C] 时，单独按 C 不会触发。
@immutable
class KeyBinding {
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  const KeyBinding(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  /// 从当前键盘事件与修饰键状态构造绑定。
  factory KeyBinding.fromEvent(KeyEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    return KeyBinding(
      event.logicalKey,
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  /// 判断某个按下的逻辑键是否与当前绑定匹配。
  ///
  /// [ignoreShift] 用于选项选择键：大小写不影响选项映射。
  bool matches(LogicalKeyboardKey pressedKey, {bool ignoreShift = false}) {
    if (pressedKey != key) return false;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed != ctrl) return false;
    if (keyboard.isAltPressed != alt) return false;
    if (keyboard.isMetaPressed != meta) return false;
    if (!ignoreShift && keyboard.isShiftPressed != shift) return false;
    return true;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'keyId': key.keyId,
      'ctrl': ctrl,
      'alt': alt,
      'shift': shift,
      'meta': meta,
    };
  }

  static KeyBinding? fromJson(Map<String, dynamic> json) {
    final Object? rawKeyId = json['keyId'];
    final int? keyId = rawKeyId is num
        ? rawKeyId.toInt()
        : int.tryParse(rawKeyId?.toString() ?? '');
    if (keyId == null) return null;
    final LogicalKeyboardKey? logicalKey = LogicalKeyboardKey.findKeyByKeyId(
      keyId,
    );
    if (logicalKey == null) return null;
    return KeyBinding(
      logicalKey,
      ctrl: json['ctrl'] == true,
      alt: json['alt'] == true,
      shift: json['shift'] == true,
      meta: json['meta'] == true,
    );
  }

  /// 用于设置页展示的可读标签，例如 “Ctrl + Shift + A”、“→”。
  String get label {
    final List<String> parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    if (meta) parts.add(_metaLabel);
    parts.add(keyLabel(key));
    return parts.join(' + ');
  }

  String get _metaLabel {
    if (kIsWeb) return 'Meta';
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => '⌘',
      TargetPlatform.windows => 'Win',
      _ => 'Meta',
    };
  }

  static final Map<LogicalKeyboardKey, String> _friendlyKeyLabels =
      <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.arrowLeft: '←',
        LogicalKeyboardKey.arrowRight: '→',
        LogicalKeyboardKey.arrowUp: '↑',
        LogicalKeyboardKey.arrowDown: '↓',
        LogicalKeyboardKey.pageUp: 'PgUp',
        LogicalKeyboardKey.pageDown: 'PgDn',
        LogicalKeyboardKey.home: 'Home',
        LogicalKeyboardKey.end: 'End',
        LogicalKeyboardKey.insert: 'Insert',
        LogicalKeyboardKey.delete: 'Delete',
        LogicalKeyboardKey.backspace: 'Backspace',
        LogicalKeyboardKey.enter: 'Enter',
        LogicalKeyboardKey.numpadEnter: 'Num Enter',
        LogicalKeyboardKey.space: 'Space',
        LogicalKeyboardKey.escape: 'Esc',
        LogicalKeyboardKey.tab: 'Tab',
        LogicalKeyboardKey.capsLock: 'CapsLock',
      };

  static String keyLabel(LogicalKeyboardKey key) {
    final String? friendly = _friendlyKeyLabels[key];
    if (friendly != null) return friendly;
    final String label = key.keyLabel.trim();
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return '0x${key.keyId.toRadixString(16).toUpperCase()}';
  }

  @override
  bool operator ==(Object other) {
    return other is KeyBinding &&
        other.key == key &&
        other.ctrl == ctrl &&
        other.alt == alt &&
        other.shift == shift &&
        other.meta == meta;
  }

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, meta);
}

/// 刷题页可绑定快捷键的动作。
///
/// 仅用户明确要求的动作提供默认键位，其余动作留空，由用户在设置中自行绑定。
/// 每个动作支持绑定多个按键；同一按键只会绑定到一个动作。
enum ShortcutAction {
  toggleFullscreen(
    id: 'toggle_fullscreen',
    label: '全屏 / 退出全屏',
    description: '在应用内切换全屏（Windows），默认 F11',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.f11)],
  ),
  nextQuestion(
    id: 'next_question',
    label: '下一题',
    description: '切换到下一道题目',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.arrowRight)],
  ),
  previousQuestion(
    id: 'previous_question',
    label: '上一题',
    description: '切换到上一道题目',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.arrowLeft)],
  ),
  submitAnswer(
    id: 'submit_answer',
    label: '提交答案',
    description: '提交多选题答案（单选题按选项键后自动判题）',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.enter)],
  ),
  scrollPageDown(
    id: 'scroll_page_down',
    label: '向下翻页',
    description: '在当前题目内容中向下翻页（阅读长解析、评论时使用）',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.pageDown)],
  ),
  scrollPageUp(
    id: 'scroll_page_up',
    label: '向上翻页',
    description: '在当前题目内容中向上翻页',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.pageUp)],
  ),
  scrollLineDown(
    id: 'scroll_line_down',
    label: '向下滚动',
    description: '在当前题目内容中连续向下滚动（可长按）',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.arrowDown)],
  ),
  scrollLineUp(
    id: 'scroll_line_up',
    label: '向上滚动',
    description: '在当前题目内容中连续向上滚动（可长按）',
    defaultBindings: <KeyBinding>[KeyBinding(LogicalKeyboardKey.arrowUp)],
  ),
  toggleCut(id: 'toggle_cut', label: '斩题', description: '斩掉 / 取消斩掉当前题目'),
  toggleCollection(
    id: 'toggle_collection',
    label: '收藏',
    description: '收藏 / 取消收藏当前题目',
  ),
  copyQuestion(id: 'copy_question', label: '复制题目', description: '复制题目、答案与解析'),
  toggleCutContent(
    id: 'toggle_cut_content',
    label: '显示已斩题目',
    description: '显示 / 隐藏当前已斩题目的内容',
  ),
  submitTest(id: 'submit_test', label: '交卷', description: '测试模式下交卷');

  const ShortcutAction({
    required this.id,
    required this.label,
    required this.description,
    this.defaultBindings = const <KeyBinding>[],
  });

  /// 持久化用的稳定标识，不要随意改动。
  final String id;
  final String label;
  final String description;
  final List<KeyBinding> defaultBindings;

  /// 是否允许长按连续触发（仅滚动类动作）。
  bool get allowsRepeat {
    return this == scrollPageDown ||
        this == scrollPageUp ||
        this == scrollLineDown ||
        this == scrollLineUp;
  }
}

/// 刷题快捷键配置：负责默认键位、用户自定义键位的读写与冲突处理。
class ShortcutConfig {
  ShortcutConfig._();

  static const String _bindingsPrefsKey = 'shortcut_bindings_v1';
  static const String _optionModePrefsKey = 'shortcut_option_key_mode';
  static const String _pageScrollPercentPrefsKey =
      'shortcut_page_scroll_percent';
  static const String _lineScrollPixelsPrefsKey = 'shortcut_line_scroll_pixels';

  /// 翻页步长可选项（占可视区域高度的百分比）。
  static const List<int> pageScrollPercentOptions = <int>[50, 75, 90, 100];

  /// 连续滚动步长可选项（每次按键滚动的像素）。
  static const List<int> lineScrollPixelsOptions = <int>[20, 40, 80, 120];

  static bool _loaded = false;
  static final Map<ShortcutAction, List<KeyBinding>> _overrides =
      <ShortcutAction, List<KeyBinding>>{};
  static OptionKeyMode _optionKeyMode = OptionKeyMode.both;
  static int _pageScrollPercent = 90;
  static int _lineScrollPixels = 40;

  static OptionKeyMode get optionKeyMode => _optionKeyMode;

  /// PgUp / PgDn 每次翻页滚动的可视高度百分比。
  static int get pageScrollPercent => _pageScrollPercent;

  /// ↑ / ↓ 每次连续滚动的像素距离。
  static int get lineScrollPixels => _lineScrollPixels;

  /// 从本地设置加载。应用启动时调用一次；重复调用会直接返回。
  static Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final int modeIndex =
        prefs.getInt(_optionModePrefsKey) ?? OptionKeyMode.both.index;
    _optionKeyMode = modeIndex >= 0 && modeIndex < OptionKeyMode.values.length
        ? OptionKeyMode.values[modeIndex]
        : OptionKeyMode.both;
    _pageScrollPercent = _normalizeScrollOption(
      prefs.getInt(_pageScrollPercentPrefsKey) ?? 90,
      pageScrollPercentOptions,
    );
    _lineScrollPixels = _normalizeScrollOption(
      prefs.getInt(_lineScrollPixelsPrefsKey) ?? 40,
      lineScrollPixelsOptions,
    );

    _overrides.clear();
    final String? rawBindings = prefs.getString(_bindingsPrefsKey);
    if (rawBindings != null && rawBindings.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawBindings);
        if (decoded is Map) {
          for (final ShortcutAction action in ShortcutAction.values) {
            if (!decoded.containsKey(action.id)) continue;
            _overrides[action] = _decodeBindings(decoded[action.id]);
          }
        }
      } catch (error) {
        debugPrint('[shortcut] 快捷键配置解析失败: $error');
      }
    }

    _loaded = true;
  }

  static List<KeyBinding> _decodeBindings(Object? value) {
    if (value is List) {
      final List<KeyBinding> bindings = <KeyBinding>[];
      for (final Object? item in value) {
        if (item is Map) {
          final KeyBinding? binding = KeyBinding.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (binding != null) bindings.add(binding);
        }
      }
      return bindings;
    }
    // 兼容旧版本以单个对象保存的格式
    if (value is Map) {
      final KeyBinding? binding = KeyBinding.fromJson(
        Map<String, dynamic>.from(value),
      );
      return binding == null ? <KeyBinding>[] : <KeyBinding>[binding];
    }
    // null / 其它值表示用户主动清空了该动作的键位
    return <KeyBinding>[];
  }

  /// 动作当前生效的全部键位；空列表表示未绑定。
  static List<KeyBinding> bindingsFor(ShortcutAction action) {
    return _overrides[action] ?? action.defaultBindings;
  }

  /// 已绑定的动作数量，用于设置页展示。
  static int get boundActionCount {
    return ShortcutAction.values
        .where((ShortcutAction action) => bindingsFor(action).isNotEmpty)
        .length;
  }

  /// 查找绑定了 [binding] 的其它动作。
  static List<ShortcutAction> actionsSharing(
    KeyBinding binding, {
    ShortcutAction? except,
  }) {
    return ShortcutAction.values.where((ShortcutAction action) {
      if (action == except) return false;
      return bindingsFor(action).contains(binding);
    }).toList();
  }

  /// 为 [action] 新增 [binding]。
  ///
  /// 同一键位在其它动作上的绑定会被自动移除，避免一次按键触发多个动作。
  static Future<void> assignBinding(
    ShortcutAction action,
    KeyBinding binding,
  ) async {
    for (final ShortcutAction other in ShortcutAction.values) {
      if (other == action) continue;
      final List<KeyBinding> otherBindings = bindingsFor(other);
      if (!otherBindings.contains(binding)) continue;
      _overrides[other] = List<KeyBinding>.of(otherBindings)..remove(binding);
    }
    final List<KeyBinding> current = List<KeyBinding>.of(bindingsFor(action));
    if (!current.contains(binding)) current.add(binding);
    _overrides[action] = current;
    await _persist();
  }

  /// 移除 [action] 上的 [binding]。
  static Future<void> removeBinding(
    ShortcutAction action,
    KeyBinding binding,
  ) async {
    final List<KeyBinding> updated = List<KeyBinding>.of(bindingsFor(action))
      ..remove(binding);
    _overrides[action] = updated;
    await _persist();
  }

  /// 清空某个动作的全部键位（默认键位也会被清除）。
  static Future<void> clearBinding(ShortcutAction action) async {
    _overrides[action] = <KeyBinding>[];
    await _persist();
  }

  /// 恢复全部默认键位。
  static Future<void> resetAll() async {
    _overrides.clear();
    await _persist();
  }

  static Future<void> setOptionKeyMode(OptionKeyMode mode) async {
    if (_optionKeyMode == mode) return;
    _optionKeyMode = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_optionModePrefsKey, mode.index);
  }

  /// 设置翻页步长（百分比）。非法值会就近归一到可选项。
  static Future<void> setPageScrollPercent(int percent) async {
    final int normalized = _normalizeScrollOption(
      percent,
      pageScrollPercentOptions,
    );
    if (_pageScrollPercent == normalized) return;
    _pageScrollPercent = normalized;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageScrollPercentPrefsKey, normalized);
  }

  /// 设置连续滚动步长（像素）。非法值会就近归一到可选项。
  static Future<void> setLineScrollPixels(int pixels) async {
    final int normalized = _normalizeScrollOption(
      pixels,
      lineScrollPixelsOptions,
    );
    if (_lineScrollPixels == normalized) return;
    _lineScrollPixels = normalized;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lineScrollPixelsPrefsKey, normalized);
  }

  static int _normalizeScrollOption(int value, List<int> options) {
    if (options.contains(value)) return value;
    int best = options.first;
    for (final int option in options) {
      if ((option - value).abs() < (best - value).abs()) best = option;
    }
    return best;
  }

  static Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, Object?> data = <String, Object?>{
      for (final MapEntry<ShortcutAction, List<KeyBinding>> entry
          in _overrides.entries)
        entry.key.id: entry.value
            .map((KeyBinding binding) => binding.toJson())
            .toList(),
    };
    await prefs.setString(_bindingsPrefsKey, jsonEncode(data));
  }

  // ------------------------------------------------------------------
  // 选项键位映射（数字 / 字母）
  // ------------------------------------------------------------------

  static final Map<LogicalKeyboardKey, int> _numberOptionKeys =
      <LogicalKeyboardKey, int>{
        LogicalKeyboardKey.digit1: 0,
        LogicalKeyboardKey.digit2: 1,
        LogicalKeyboardKey.digit3: 2,
        LogicalKeyboardKey.digit4: 3,
        LogicalKeyboardKey.digit5: 4,
        LogicalKeyboardKey.digit6: 5,
        LogicalKeyboardKey.digit7: 6,
        LogicalKeyboardKey.digit8: 7,
        LogicalKeyboardKey.digit9: 8,
        LogicalKeyboardKey.digit0: 9,
        LogicalKeyboardKey.numpad1: 0,
        LogicalKeyboardKey.numpad2: 1,
        LogicalKeyboardKey.numpad3: 2,
        LogicalKeyboardKey.numpad4: 3,
        LogicalKeyboardKey.numpad5: 4,
        LogicalKeyboardKey.numpad6: 5,
        LogicalKeyboardKey.numpad7: 6,
        LogicalKeyboardKey.numpad8: 7,
        LogicalKeyboardKey.numpad9: 8,
        LogicalKeyboardKey.numpad0: 9,
      };

  /// 数字键对应的选项序号（0 起）；非数字键返回 null。
  static int? numberOptionIndex(LogicalKeyboardKey key) {
    return _numberOptionKeys[key];
  }

  /// 字母键对应的选项字母（A-Z）；非字母键返回 null。
  static String? letterOptionKey(LogicalKeyboardKey key) {
    // LogicalKeyboardKey.keyA ~ keyZ 的 keyId 连续对应 Unicode 'a' ~ 'z'
    final int id = key.keyId;
    final int start = LogicalKeyboardKey.keyA.keyId;
    final int end = LogicalKeyboardKey.keyZ.keyId;
    if (id < start || id > end) return null;
    return String.fromCharCode(65 + (id - start));
  }
}
