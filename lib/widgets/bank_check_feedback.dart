import 'package:flutter/material.dart';
import '../models/bank_source.dart';

/// Failed checks are results, not thrown exceptions; make them visible at the
/// initiating action while retaining each source's last successful metadata.
Future<bool> showBankCheckErrors(
  BuildContext context,
  List<BankSource> results,
) async {
  final failures = results
      .where((source) => source.status == BankSourceStatus.failed)
      .toList();
  if (failures.isEmpty || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(failures.length == results.length ? '检查更新失败' : '部分来源检查失败'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final source in failures) ...[
              Text(source.name, style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                Uri.parse(
                  source.url,
                ).replace(query: '', fragment: '').toString(),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SelectableText(source.error ?? '来源暂时无法访问'),
              const SizedBox(height: 16),
            ],
            const Text('已安装题库保持不变；上次成功的来源信息会保留。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  return true;
}
