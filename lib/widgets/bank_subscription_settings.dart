import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bank_subscription_service.dart';
import 'common/info_card.dart';
import 'common/styled_tile.dart';

String bankCheckIntervalLabel(int minutes) {
  if (minutes % 1440 == 0) return '每 ${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) return '每 ${minutes ~/ 60} 小时';
  return '每 $minutes 分钟';
}

class BankSubscriptionSettings extends StatefulWidget {
  const BankSubscriptionSettings({super.key});

  @override
  State<BankSubscriptionSettings> createState() =>
      _BankSubscriptionSettingsState();
}

class _BankSubscriptionSettingsState extends State<BankSubscriptionSettings> {
  final _service = BankSubscriptionService.instance;
  bool _enabled = false;
  bool _install = false;
  int _minutes = 360;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _service.automatic();
    final minutes = await _service.intervalMinutes();
    final install = await _service.automaticInstallation();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _minutes = minutes;
        _install = install;
        _loaded = true;
      });
    }
  }

  Future<void> _save(bool enabled, int minutes, {bool? install}) async {
    setState(() => _saving = true);
    try {
      await _service.configureAutomatic(enabled, minutes, install: install);
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _minutes = minutes;
          if (install != null) _install = install;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseInterval() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('检查更新间隔'),
        children: [
          for (final minutes in [30, 60, 180, 360, 720, 1440])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, minutes),
              child: Row(
                children: [
                  Expanded(child: Text(bankCheckIntervalLabel(minutes))),
                  if (_minutes == minutes)
                    Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('自定义…'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result != -1) {
      await _save(_enabled, result);
      return;
    }
    final custom = await showDialog<int>(
      context: context,
      builder: (_) => _BankIntervalDialog(minutes: _minutes),
    );
    if (mounted && custom != null) await _save(_enabled, custom);
  }

  @override
  Widget build(BuildContext context) => InfoCard(
    children: [
      IconTile(
        icon: Icons.update_rounded,
        label: '自动检查更新',
        trailing: Switch(
          value: _enabled,
          onChanged: !_loaded || _saving
              ? null
              : (value) => _save(value, _minutes),
        ),
      ),
      IconTile(
        icon: Icons.download_rounded,
        label: '发现更新后自动安装',
        trailing: Switch(
          value: _install,
          onChanged: !_loaded || _saving || !_enabled
              ? null
              : (value) => _save(_enabled, _minutes, install: value),
        ),
      ),
      IconTile(
        icon: Icons.schedule_rounded,
        label: '检查更新间隔',
        value: bankCheckIntervalLabel(_minutes),
        onTap: !_loaded || _saving ? null : _chooseInterval,
      ),
      BaseTile(
        child: Text(
          '应用打开时检查来源。有本地补充、来源内容变更或版本回退的题库，需要手动确认后更新。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

class _BankIntervalDialog extends StatefulWidget {
  const _BankIntervalDialog({required this.minutes});
  final int minutes;
  @override
  State<_BankIntervalDialog> createState() => _BankIntervalDialogState();
}

class _BankIntervalDialogState extends State<_BankIntervalDialog> {
  late final _controller = TextEditingController(text: '${widget.minutes}');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义检查间隔'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '间隔（分钟）',
          helperText: '1～10080 分钟',
        ),
        validator: (text) {
          final value = int.tryParse(text ?? '');
          return value == null || value < 1 || value > 10080
              ? '请输入 1～10080 之间的整数'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, int.parse(_controller.text));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
