import 'package:flutter/material.dart';

import '../models/bank_creation_report.dart';

Future<BankCreationErrorAction> showBankCreationIssue(
  BuildContext context,
  BankCreationIssue issue,
) async =>
    await showDialog<BankCreationErrorAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error,
          ),
          title: const Text('题库创建遇到问题'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${issue.bankName} · ${issue.stage}',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(issue.item),
                const SizedBox(height: 12),
                Text(
                  issue.code == '203'
                      ? '当前账号没有查看权限（203）。'
                      : '${issue.code == null || issue.code!.isEmpty ? '' : '错误 ${issue.code}：'}${issue.message}',
                ),
                const SizedBox(height: 12),
                const Text('忽略后将跳过此条目；忽略全部对本次创建的所有题库生效。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, BankCreationErrorAction.terminate),
              child: const Text('终止'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, BankCreationErrorAction.ignoreAll),
              child: const Text('忽略全部'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, BankCreationErrorAction.ignore),
              child: const Text('忽略'),
            ),
          ],
        ),
      ),
    ) ??
    BankCreationErrorAction.terminate;

class BankCreationReportDialog extends StatelessWidget {
  const BankCreationReportDialog({
    super.key,
    required this.report,
    required this.terminated,
  });
  final BankCreationReport report;
  final bool terminated;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AlertDialog(
      title: Text(terminated ? '已终止创建' : '创建完成'),
      content: SizedBox(
        width: 440,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已保存 ${report.savedBanks.length} 个题库 · ${report.savedQuestionCount} 道题',
            ),
            if (report.savedBanks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                report.savedBanks.map((b) => b.name).join('、'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (report.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('失败条目未写入题库，可在下方查看详情。'),
            ],
            const SizedBox(height: 12),
            TabBar(
              tabs: [
                Tab(text: '成功（${report.successes.length}）'),
                Tab(text: '失败（${report.failures.length}）'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  report.successes.isEmpty
                      ? const Center(child: Text('暂无成功条目'))
                      : ListView.builder(
                          itemCount: report.successes.length,
                          itemBuilder: (ctx, i) {
                            final entry = report.successes[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.check_circle_outline,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                              title: Text(entry.item),
                              subtitle: Text(
                                '${entry.bankName} · ${entry.stage}${entry.stage == '章节' ? ' · ${entry.questions} 道题' : ''}',
                              ),
                            );
                          },
                        ),
                  report.failures.isEmpty
                      ? const Center(child: Text('没有失败条目'))
                      : ListView.builder(
                          itemCount: report.failures.length,
                          itemBuilder: (ctx, i) {
                            final entry = report.failures[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.error_outline,
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                              title: Text(entry.item),
                              subtitle: Text(
                                '${entry.bankName} · ${entry.stage}\n${entry.code == null ? '' : '${entry.code} · '}${entry.message}',
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}
