import 'package:flutter/material.dart';
import '../models/bank_download_task.dart';

class BankDownloadProgress extends StatelessWidget {
  const BankDownloadProgress({super.key, required this.task});
  final BankDownloadTask task;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: task,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(task.stage)),
              if (task.canCancel)
                TextButton(onPressed: task.cancel, child: const Text('取消')),
            ],
          ),
          if (!task.finished)
            LinearProgressIndicator(
              value: task.stage == '正在下载' ? task.progress : null,
            ),
          if (task.received > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${(task.received / 1048576).toStringAsFixed(1)} MB${task.total == null ? '' : ' / ${(task.total! / 1048576).toStringAsFixed(1)} MB'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
}
