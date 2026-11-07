import 'package:flutter/material.dart';
import '../models/bank_download_task.dart';

/// A shared icon-sized indicator keeps actions in place during asynchronous work.
class BankActionProgress extends StatelessWidget {
  const BankActionProgress({super.key, this.value, this.label});
  final double? value;
  final String? label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(
      value: value,
      strokeWidth: 2,
      semanticsLabel: label,
    ),
  );
}

class BankActionButton extends StatelessWidget {
  const BankActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.enabled = true,
    this.busy = false,
    this.task,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled, busy;
  final BankDownloadTask? task;

  Widget _button() {
    final canCancel = busy && task?.canCancel == true;
    return IconButton(
      tooltip: busy
          ? '${task?.stage ?? tooltip}${canCancel ? '（点击取消）' : '…'}'
          : tooltip,
      onPressed: busy
          ? (canCancel ? task!.cancel : null)
          : (enabled ? onPressed : null),
      icon: busy
          ? BankActionProgress(
              value: task?.stage == '正在下载' ? task?.progress : null,
              label: task?.stage ?? '$tooltip进行中',
            )
          : Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) => task == null
      ? _button()
      : ListenableBuilder(listenable: task!, builder: (_, _) => _button());
}
