import 'package:flutter/material.dart';

import '../models/bank_creation_report.dart';

Future<bool> showBankCreationConfirmation(
  BuildContext context, {
  required int bankCount,
}) async {
  var acknowledged = false;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            icon: const Icon(Icons.info_outline_rounded),
            title: const Text('创建前确认'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本次将创建 $bankCount 个题库。'),
                  const SizedBox(height: 12),
                  const Text(
                    '自动抓取可能涉及著作权、平台服务协议及相关法律责任。请仅在获得授权的范围内使用，勿未经许可传播题库。',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请确认当前登录的医考帮账号已开通会员，并拥有所选内容的查看权限。会员或课程权限不足会导致受限内容抓取失败（203）；会员身份不代表所有课程均可访问。',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('bank-creation-acknowledgement'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('我已了解风险，并确认当前账号为会员且具有所选内容的访问权限。'),
                    value: acknowledged,
                    onChanged: (value) =>
                        setDialogState(() => acknowledged = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('bank-creation-confirm'),
                onPressed: acknowledged ? () => Navigator.pop(ctx, true) : null,
                child: const Text('确认并开始'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

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
