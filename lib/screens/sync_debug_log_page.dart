import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sync_debug_log.dart';

class SyncDebugLogPage extends StatelessWidget {
  const SyncDebugLogPage({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final log = SyncDebugLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries(preferences);
        return Scaffold(
          appBar: AppBar(
            title: const Text('同步调试日志'),
            actions: [
              IconButton(
                tooltip: '复制全部日志',
                icon: const Icon(Icons.copy_outlined),
                onPressed: entries.isEmpty ? null : () async {
                  await Clipboard.setData(ClipboardData(text: entries.join('\n')));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制同步日志')),
                    );
                  }
                },
              ),
              IconButton(
                tooltip: '清空日志',
                icon: const Icon(Icons.delete_outline),
                onPressed: entries.isEmpty ? null : () => log.clear(),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(child: Text('暂无记录。开启调试日志后运行一次同步。'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => SelectableText(
                    entries[entries.length - 1 - index],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                ),
        );
      },
    );
  }
}
