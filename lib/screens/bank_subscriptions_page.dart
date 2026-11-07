import 'package:flutter/material.dart';

import '../common/platform_adaptive.dart';
import '../models/bank_source.dart';
import '../repositories/question_bank_repository.dart';
import '../services/bank_subscription_service.dart';
import '../services/question_bank_file_service.dart';
import '../widgets/bank_link_dialog.dart';
import '../models/bank_download_task.dart';
import '../widgets/bank_download_progress.dart';
import '../widgets/bank_check_feedback.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';
import 'bank_detail_page.dart';

class BankSubscriptionsPage extends StatefulWidget {
  const BankSubscriptionsPage({super.key, this.subscriptionService});
  final BankSubscriptionService? subscriptionService;
  @override
  State<BankSubscriptionsPage> createState() => _BankSubscriptionsPageState();
}

class _BankSubscriptionsPageState extends State<BankSubscriptionsPage> {
  late final _service =
      widget.subscriptionService ?? BankSubscriptionService.instance;
  List<BankSource> _sources = [];
  BankDownloadTask? _task;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.addListener(_sourceChanged);
    _load();
  }

  void _sourceChanged() {
    if (mounted && !_busy) _load();
  }

  @override
  void dispose() {
    _service.removeListener(_sourceChanged);
    _task?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sources = await _service.sources();
      if (mounted) {
        setState(() {
          _sources = sources;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _edit([BankSource? source]) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => BankLinkDialog(
        title: source == null ? '添加订阅' : '修改订阅链接',
        initialValue: source?.url ?? '',
      ),
    );
    if (value == null || !mounted) return;
    await _run(() async {
      if (source == null) {
        final added = await _service.addSource(value);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(added ? '来源已保存，可随时检查' : '该订阅已存在')),
          );
        }
      } else {
        await _service.editSource(source, value);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('新来源已保存；原来源保持可用，检查后可在题库详情切换')),
          );
        }
      }
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    BankDownloadTask? task,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _task = task;
    });
    try {
      await action();
      task?.finish();
    } on BankImportCancelled {
      task?.finish();
    } catch (error) {
      task?.finish(error: '$error');
      if (mounted) setState(() => _error = '$error');
    } finally {
      await _load();
    }
  }

  Future<void> _downloadSource(BankSource source) async {
    final task = BankDownloadTask();
    await _run(() async {
      await _service.confirmSource(source.id, task: task);
    }, task: task);
  }

  Future<void> _remove(BankSource source) async {
    final catalog = await _service.store.read();
    final count = catalog.bindings.values.where((id) => id == source.id).length;
    if (!mounted) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除订阅来源？'),
        content: Text('$count 个题库将取消此来源的后续检查。已安装题库、作答和笔记会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) {
      await _run(() => _service.removeSource(source.id));
    }
  }

  Future<void> _details(String bankId) async {
    final bank = await QuestionBankRepository().find(bankId);
    if (bank == null || !mounted) return;
    await pushAdaptiveModalPage<void>(
      context,
      builder: (_) => BankDetailPage(bank: bank, subscriptionService: _service),
    );
    await _load();
  }

  Widget _source(BankSource source) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InfoCard(
      children: [
        ExpansionTile(
          key: PageStorageKey(source.id),
          tilePadding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          leading: TileIcon(
            icon: source.official
                ? Icons.verified_outlined
                : Icons.rss_feed_rounded,
          ),
          title: Text(source.name),
          subtitle: Text(source.statusLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '检查来源',
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final results = await _service.check(
                          sourceId: source.id,
                        );
                        if (mounted) {
                          await showBankCheckErrors(context, results);
                        }
                      }),
                icon: const Icon(Icons.sync_rounded),
              ),
              if (!source.official)
                PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: '来源操作',
                  onSelected: (value) =>
                      value == 'edit' ? _edit(source) : _remove(source),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('修改订阅链接')),
                    const PopupMenuItem(value: 'remove', child: Text('移除订阅')),
                  ],
                ),
            ],
          ),
          children: [
            BaseTile(
              child: SelectableText(
                key: PageStorageKey('source-url-${source.id}'),
                source.url,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (source.error != null)
              BaseTile(
                child: Text(
                  '检查失败，保留上次结果。\n${source.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (source.status == BankSourceStatus.needsDownload)
              BaseTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('远端文件需要下载后才能确认内容。'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _downloadSource(source),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载确认题库'),
                    ),
                  ],
                ),
              ),
            for (final entry in source.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text('${entry['name'] ?? entry['bank_id']}'),
                subtitle: Text(
                  'v${entry['version']} · ${entry['identity_id']}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _busy
                    ? null
                    : () => _details(entry['bank_id'] as String),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('题库订阅')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: const PageStorageKey('bank-subscriptions-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              '来源保存后即可检查，检查不会安装题库。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ..._sources.map(_source),
            InfoCard(
              children: [
                IconTile(
                  icon: Icons.add_link_rounded,
                  label: '添加订阅',
                  onTap: _busy ? null : _edit,
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_task != null)
              BankDownloadProgress(task: _task!)
            else if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    ),
  );
}
