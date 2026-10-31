import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/shortcut_config.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';

/// 刷题快捷键设置页
///
/// 集中配置选项键位模式（数字 / 字母）以及刷题页各按钮的快捷键。
class ShortcutSettingsPage extends StatefulWidget {
  const ShortcutSettingsPage({super.key});

  @override
  State<ShortcutSettingsPage> createState() => _ShortcutSettingsPageState();
}

class _ShortcutSettingsPageState extends State<ShortcutSettingsPage> {
  OptionKeyMode _optionKeyMode = ShortcutConfig.optionKeyMode;
  int _pageScrollPercent = ShortcutConfig.pageScrollPercent;
  int _lineScrollPixels = ShortcutConfig.lineScrollPixels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ShortcutConfig.load();
    if (!mounted) return;
    setState(() {
      _optionKeyMode = ShortcutConfig.optionKeyMode;
      _pageScrollPercent = ShortcutConfig.pageScrollPercent;
      _lineScrollPixels = ShortcutConfig.lineScrollPixels;
    });
  }

  Future<void> _changeOptionKeyMode(OptionKeyMode mode) async {
    if (mode == _optionKeyMode) return;
    setState(() => _optionKeyMode = mode);
    await ShortcutConfig.setOptionKeyMode(mode);
  }

  Future<void> _changePageScrollPercent(int value) async {
    if (value == _pageScrollPercent) return;
    setState(() => _pageScrollPercent = value);
    await ShortcutConfig.setPageScrollPercent(value);
  }

  Future<void> _changeLineScrollPixels(int value) async {
    if (value == _lineScrollPixels) return;
    setState(() => _lineScrollPixels = value);
    await ShortcutConfig.setLineScrollPixels(value);
  }

  Future<KeyBinding?> _captureBinding(ShortcutAction action) {
    return showDialog<KeyBinding>(
      context: context,
      builder: (context) => _ShortcutCaptureDialog(
        action: action,
        existingBindings: ShortcutConfig.bindingsFor(action),
      ),
    );
  }

  Future<void> _addBinding(ShortcutAction action) async {
    final KeyBinding? binding = await _captureBinding(action);
    if (binding == null || !mounted) return;
    if (ShortcutConfig.bindingsFor(action).contains(binding)) {
      _showMessage('「${action.label}」已绑定 ${binding.label}');
      return;
    }

    final List<ShortcutAction> conflicts = ShortcutConfig.actionsSharing(
      binding,
      except: action,
    );
    await ShortcutConfig.assignBinding(action, binding);
    if (!mounted) return;
    setState(() {});

    final String conflictText = conflicts.isEmpty
        ? ''
        : '，已从「${conflicts.map((ShortcutAction a) => a.label).join('、')}」移除';
    _showMessage(
      '「${action.label}」新增 ${binding.label}$conflictText${_optionKeyWarning(binding)}',
    );
  }

  Future<void> _replaceBinding(
    ShortcutAction action,
    KeyBinding oldBinding,
  ) async {
    final KeyBinding? binding = await _captureBinding(action);
    if (binding == null || !mounted || binding == oldBinding) return;

    final List<ShortcutAction> conflicts = ShortcutConfig.actionsSharing(
      binding,
      except: action,
    );
    await ShortcutConfig.removeBinding(action, oldBinding);
    await ShortcutConfig.assignBinding(action, binding);
    if (!mounted) return;
    setState(() {});

    final String conflictText = conflicts.isEmpty
        ? ''
        : '，已从「${conflicts.map((ShortcutAction a) => a.label).join('、')}」移除';
    _showMessage(
      '「${action.label}」按键 ${oldBinding.label} 已改为 ${binding.label}'
      '$conflictText${_optionKeyWarning(binding)}',
    );
  }

  Future<void> _removeBinding(ShortcutAction action, KeyBinding binding) async {
    await ShortcutConfig.removeBinding(action, binding);
    if (!mounted) return;
    setState(() {});
    _showMessage('已移除「${action.label}」的 ${binding.label}');
  }

  /// 绑定的键被选项选择占用时的提醒。
  String _optionKeyWarning(KeyBinding binding) {
    if (binding.ctrl || binding.alt || binding.meta) return '';
    final bool isNumber = ShortcutConfig.numberOptionIndex(binding.key) != null;
    final bool isLetter = ShortcutConfig.letterOptionKey(binding.key) != null;
    final bool numberActive = _optionKeyMode != OptionKeyMode.letter;
    final bool letterActive = _optionKeyMode != OptionKeyMode.number;
    if ((isNumber && numberActive) || (isLetter && letterActive)) {
      return '；注意：该键同时用于选项选择，选项键优先';
    }
    return '';
  }

  Future<void> _confirmResetAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认快捷键'),
        content: const Text(
          '将清除所有自定义键位，恢复默认按键映射'
          '（选项键位模式与滚动步长不受影响）。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ShortcutConfig.resetAll();
    if (!mounted) return;
    setState(() {});
    _showMessage('已恢复默认快捷键');
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('快捷键')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _sectionTitle('选项选择'),
          InfoCard(
            children: [
              for (final OptionKeyMode mode in OptionKeyMode.values)
                _buildOptionModeTile(mode),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '单选题：按选项键直接判题；多选题：按选项键勾选，'
              '再按「提交答案」键（默认 Enter）提交。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('滚动'),
          InfoCard(
            children: [
              _buildScrollStepTile(
                icon: Icons.swap_vert,
                label: '翻页步长',
                value: _pageScrollPercent,
                options: ShortcutConfig.pageScrollPercentOptions,
                format: (int value) => '$value%',
                onChanged: _changePageScrollPercent,
              ),
              _buildScrollStepTile(
                icon: Icons.keyboard_double_arrow_down_rounded,
                label: '连续滚动步长',
                value: _lineScrollPixels,
                options: ShortcutConfig.lineScrollPixelsOptions,
                format: (int value) => '$value 像素',
                onChanged: _changeLineScrollPixels,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '「翻页步长」控制 PgUp / PgDn 每次滚动的距离；'
              '「连续滚动步长」控制 ↑ / ↓（长按可连续滚动）每次滚动的距离。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('功能快捷键'),
          InfoCard(
            children: [
              for (final ShortcutAction action in ShortcutAction.values)
                _buildActionTile(action),
              IconTile(
                icon: Icons.restart_alt,
                label: '恢复默认快捷键',
                onTap: _confirmResetAll,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '← / → 切换上一题 / 下一题；PgUp / PgDn 在当前题目内上下翻页；'
              '↑ / ↓ 连续滚动（可长按）。快捷键仅在刷题页面生效，'
              '输入笔记、评论时自动让位给输入框。选项键优先于功能快捷键。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionModeTile(OptionKeyMode mode) {
    final ThemeData theme = Theme.of(context);
    final bool selected = _optionKeyMode == mode;
    return InkWell(
      onTap: () => _changeOptionKeyMode(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(ShortcutAction action) {
    final ThemeData theme = Theme.of(context);
    final List<KeyBinding> bindings = ShortcutConfig.bindingsFor(action);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(icon: _iconFor(action)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.label, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _addBinding(action),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加按键'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 50, top: 8),
            child: bindings.isEmpty
                ? Text(
                    '未设置',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final KeyBinding binding in bindings)
                        InputChip(
                          label: Text(binding.label),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _replaceBinding(action, binding),
                          onDeleted: () => _removeBinding(action, binding),
                          deleteButtonTooltipMessage: '移除',
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollStepTile({
    required IconData icon,
    required String label,
    required int value,
    required List<int> options,
    required String Function(int value) format,
    required ValueChanged<int> onChanged,
  }) {
    return IconTile(
      icon: icon,
      label: label,
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        onChanged: (int? selected) {
          if (selected != null) onChanged(selected);
        },
        items: [
          for (final int option in options)
            DropdownMenuItem<int>(value: option, child: Text(format(option))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  static IconData _iconFor(ShortcutAction action) {
    return switch (action) {
      ShortcutAction.nextQuestion => Icons.keyboard_arrow_right,
      ShortcutAction.previousQuestion => Icons.keyboard_arrow_left,
      ShortcutAction.submitAnswer => Icons.send_rounded,
      ShortcutAction.scrollPageDown => Icons.keyboard_double_arrow_down_rounded,
      ShortcutAction.scrollPageUp => Icons.keyboard_double_arrow_up_rounded,
      ShortcutAction.scrollLineDown => Icons.keyboard_arrow_down_rounded,
      ShortcutAction.scrollLineUp => Icons.keyboard_arrow_up_rounded,
      ShortcutAction.toggleCut => Icons.content_cut,
      ShortcutAction.toggleCollection => Icons.favorite_outline,
      ShortcutAction.copyQuestion => Icons.copy_rounded,
      ShortcutAction.toggleCutContent => Icons.visibility_outlined,
      ShortcutAction.submitTest => Icons.assignment_turned_in_outlined,
    };
  }
}

/// 按键捕获对话框：按下任意键后立即返回该键位。
class _ShortcutCaptureDialog extends StatefulWidget {
  final ShortcutAction action;
  final List<KeyBinding> existingBindings;

  const _ShortcutCaptureDialog({
    required this.action,
    required this.existingBindings,
  });

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  static final Set<LogicalKeyboardKey> _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final LogicalKeyboardKey key = event.logicalKey;

    // Esc 取消，不占用键位
    if (key == LogicalKeyboardKey.escape &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    // 单独的修饰键不构成绑定
    if (_modifierKeys.contains(key)) return KeyEventResult.handled;

    Navigator.of(context).pop(KeyBinding.fromEvent(event));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String currentBindings = widget.existingBindings.isEmpty
        ? '未设置'
        : widget.existingBindings
              .map((KeyBinding binding) => binding.label)
              .join(' / ');

    return AlertDialog(
      title: Text('设置「${widget.action.label}」快捷键'),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.action.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '请按下要绑定的按键…',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前：$currentBindings',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '按 Esc 取消；可按住 Ctrl / Alt / Shift 组合键。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
