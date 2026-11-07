import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/question_bank.dart';
import '../models/bank_source.dart';
import '../repositories/question_bank_repository.dart';
import '../services/question_bank_file_service.dart';
import '../services/bank_subscription_service.dart';
import '../common/platform_adaptive.dart';
import '../common/app_shapes.dart';
import '../widgets/bank_export_button.dart';
import '../widgets/bank_link_import_dialog.dart';
import '../widgets/bank_update_dialog.dart';
import '../models/bank_download_task.dart';
import '../widgets/bank_action_button.dart';
import '../widgets/bank_check_feedback.dart';
import 'bank_subscriptions_page.dart';
import 'bank_creation_page.dart';
import 'bank_detail_page.dart';

class QuestionBankPage extends StatefulWidget {
  const QuestionBankPage({super.key, this.subscriptionService});

  final BankSubscriptionService? subscriptionService;
  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> {
  late final _service =
      widget.subscriptionService ?? BankSubscriptionService.instance;
  final QuestionBankRepository _repository = QuestionBankRepository();
  late Future<List<QuestionBank>> _banksFuture;
  String? _activeBankId;
  final Set<String> _downloading = <String>{};
  BankDownloadTask? _task;
  bool _busy = false;
  String? _operation;
  bool _exporting = false;
  final _updates = <String, BankUpdateInfo>{};

  bool get _controlsDisabled => _busy || _exporting || _downloading.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _service.addListener(_sourceChanged);
    _reload();
  }

  void _sourceChanged() {
    if (mounted && !_controlsDisabled) setState(_reload);
  }

  Future<void> _editSubscriptions() async {
    await pushAdaptiveModalPage<bool>(
      context,
      builder: (_) => BankSubscriptionsPage(subscriptionService: _service),
    );
    if (mounted) {
      setState(_reload);
    }
  }

  Future<void> _createBank() async {
    await pushAdaptiveModalPage<bool>(
      context,
      builder: (_) => const BankCreationPage(),
    );
    // A cancelled multi-bank task may have completed some banks already.
    if (mounted) setState(_reload);
  }

  Future<void> _details(QuestionBank bank) async {
    await pushAdaptiveModalPage<void>(
      context,
      builder: (_) => BankDetailPage(bank: bank, subscriptionService: _service),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _updateSubscription(QuestionBank bank) async {
    if (_controlsDisabled) return;
    final action = _updates[bank.bankId];
    if (action?.canApply == true) {
      await _download(bank);
      return;
    }
    final task = action?.status == BankUpdateStatus.needsDownload
        ? BankDownloadTask()
        : null;
    setState(() {
      _task = task;
      _downloading.add(bank.bankId);
    });
    try {
      if (action?.status == BankUpdateStatus.needsDownload &&
          action?.source != null) {
        await _service.confirmSource(action!.source!.id, task: task);
      } else {
        final results = await _service.check(bankId: bank.bankId);
        if (mounted && await showBankCheckErrors(context, results)) return;
      }
      final info = await _service.updateInfo(bank);
      if (!mounted) return;
      setState(_reload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(info.message ?? info.label)));
    } on BankImportCancelled {
      task?.finish();
    } catch (error) {
      task?.finish(error: '$error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查失败：$error')));
      }
    } finally {
      task?.finish();
      if (mounted) {
        setState(() {
          _downloading.remove(bank.bankId);
          _reload();
        });
      }
    }
  }

  @override
  void dispose() {
    _service.removeListener(_sourceChanged);
    _task?.cancel();
    super.dispose();
  }

  void _reload() {
    _banksFuture = _loadBanks();
  }

  Future<List<QuestionBank>> _loadBanks() async {
    final banks = await _repository.listBanks();
    _activeBankId = await _repository.activeBankId();
    _updates.clear();
    for (final bank in banks) {
      _updates[bank.bankId] = await _service.updateInfo(bank);
    }
    return banks;
  }

  Future<void> _refreshManifest() async {
    setState(() {
      _busy = true;
      _operation = 'all';
      _task = null;
    });
    try {
      final results = await _service.check();
      if (!mounted) return;
      setState(_reload);
      if (await showBankCheckErrors(context, results) || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '检查完成：${results.where((s) => s.status != BankSourceStatus.failed).length} 个来源成功，${results.where((s) => s.status == BankSourceStatus.failed).length} 个失败',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('暂时无法获取远程题库清单：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db', 'zip'],
      withData: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null || filePath.isEmpty) return;
    if (!mounted) return;
    await _runOperation(
      () => _repository.importFile(filePath, onConflict: _chooseImportMode),
      '题库导入成功',
    );
  }

  Future<void> _importLink() async {
    final choice = await showDialog<BankLinkImportChoice>(
      context: context,
      builder: (_) => const BankLinkImportDialog(),
    );
    if (choice == null || !mounted) return;
    final task = BankDownloadTask();
    await _runOperation(
      () => _service.importLink(
        choice.url,
        subscribe: choice.subscribe,
        task: task,
        onConflict: _chooseImportMode,
      ),
      '题库导入成功',
      task: task,
    );
  }

  Future<BankImportMode?> _chooseImportMode(QuestionBank existing) async {
    if (!mounted) return null;
    return showDialog<BankImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${existing.name}」已安装'),
        content: const Text(
          '增量合并保留本地额外题目，并采用导入文件的题目内容。'
          '完全覆盖用新文件替换题库。两种方式均保留个人作答、收藏和笔记。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, BankImportMode.replace),
            child: const Text('完全覆盖'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, BankImportMode.merge),
            child: const Text('增量合并'),
          ),
        ],
      ),
    );
  }

  Future<void> _download(QuestionBank bank) async {
    if (_downloading.isNotEmpty) return;
    final bankId = bank.bankId;
    final task = BankDownloadTask();
    setState(() => _task = task);
    setState(() {
      _downloading.add(bankId);
    });
    try {
      await _service.install(
        bankId,
        onConflict: _chooseImportMode,
        onResolve: _resolveUpdate,
        task: task,
      );
      task.finish();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bank.isInstalled ? '题库更新成功' : '题库下载成功')),
      );
    } on BankImportCancelled {
      task.finish();
    } catch (error) {
      task.finish(error: '$error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading.remove(bankId);
          _reload();
        });
      }
    }
  }

  Future<BankImportMode?> _resolveUpdate(
    QuestionBank bank,
    BankUpdateInfo info,
    BankContentDiff diff,
  ) async {
    if (!mounted) return null;
    return showBankUpdateDialog(context, bank, info, diff);
  }

  Future<void> _runOperation(
    Future<QuestionBank> Function() operation,
    String successMessage, {
    BankDownloadTask? task,
  }) async {
    setState(() {
      _busy = true;
      _operation = 'import';
      _task = task;
    });
    try {
      await operation();
      task?.finish();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on BankImportCancelled {
      task?.finish();
      // Closing the import choice is a normal cancellation.
    } catch (error) {
      task?.finish(error: '$error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(QuestionBank bank) async {
    if (!bank.isInstalled || !bank.enabled) return;
    try {
      await _repository.selectBank(bank.bankId);
      if (!mounted) return;
      setState(() => _activeBankId = bank.bankId);
      //ScaffoldMessenger.of(context).showSnackBar(
      //  SnackBar(content: Text('已切换到${bank.name}')),
      //);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换失败：$error')));
      }
    }
  }

  Future<void> _toggle(QuestionBank bank, bool value) async {
    try {
      await _repository.setEnabled(bank.bankId, value);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法修改题库状态：$error')));
      }
    }
  }

  Widget _status(QuestionBank bank) {
    if (!bank.isInstalled) {
      return const Chip(label: Text('未安装'));
    }
    if (_activeBankId == bank.bankId) {
      return const Chip(
        avatar: Icon(Icons.check, size: 16),
        label: Text('当前使用'),
      );
    }
    return Chip(label: const Text('已安装'), visualDensity: VisualDensity.compact);
  }

  Widget _bankCard(QuestionBank bank) {
    final info = _updates[bank.bankId];
    final displayVersion = bank.isInstalled
        ? bank.version
        : info?.source?.entry(bank.bankId)?['version']?.toString() ??
              bank.version;
    final hasSubscription = info?.source != null;
    final canDownload =
        !bank.isInstalled &&
        hasSubscription &&
        info!.source!.entry(bank.bankId) != null;
    final localChanges =
        info?.content?.hasLocalChanges(bank.contentHash) == true;
    final downloading = _downloading.contains(bank.bankId);
    return Card(
      key: ValueKey('bank-card-${bank.bankId}'),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        onTap: _controlsDisabled ? null : () => _details(bank),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(bankSpec(bank.bankId)?.icon ?? Icons.menu_book),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bank.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bank.description.isEmpty
                              ? 'v$displayVersion'
                              : 'v$displayVersion · ${bank.description}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (RegExp(r'^\d+$').hasMatch(bank.identityId))
                              Chip(
                                label: Text(bank.identityId),
                                shape: const StadiumBorder(),
                                visualDensity: VisualDensity.compact,
                              ),
                            _status(bank),
                            if (localChanges) const Chip(label: Text('本地有补充')),
                            if (hasSubscription && bank.isInstalled)
                              Chip(
                                label: Text(info!.label),
                                shape: const StadiumBorder(),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (!bank.isInstalled && !canDownload)
                              const Chip(label: Text('暂无下载链接')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (bank.isInstalled)
                    Switch(
                      value: bank.enabled,
                      onChanged: _controlsDisabled
                          ? null
                          : (value) => _toggle(bank, value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (bank.isInstalled &&
                      bank.enabled &&
                      bank.bankId != _activeBankId)
                    TextButton(
                      onPressed: _controlsDisabled ? null : () => _select(bank),
                      child: const Text('使用此题库'),
                    ),
                  IconButton(
                    tooltip: '题库详情',
                    onPressed: _controlsDisabled ? null : () => _details(bank),
                    icon: const Icon(Icons.info_outline),
                  ),
                  if (hasSubscription && bank.isInstalled)
                    BankActionButton(
                      key: ValueKey('bank-update-${bank.bankId}'),
                      tooltip: info!.actionLabel,
                      busy: downloading,
                      task: downloading ? _task : null,
                      enabled: !_controlsDisabled,
                      onPressed: () => _updateSubscription(bank),
                      icon:
                          info.status == BankUpdateStatus.needsDownload ||
                              info.canApply
                          ? Icons.download_rounded
                          : Icons.sync_rounded,
                    ),
                  if (bank.isInstalled)
                    BankExportButton(
                      bank: bank,
                      enabled: !_controlsDisabled,
                      onBusyChanged: (busy) {
                        if (mounted) setState(() => _exporting = busy);
                      },
                    ),
                  if (canDownload)
                    BankActionButton(
                      key: ValueKey('bank-download-${bank.bankId}'),
                      tooltip: '下载题库',
                      busy: downloading,
                      task: downloading ? _task : null,
                      enabled: !_controlsDisabled,
                      onPressed: () => _download(bank),
                      icon: Icons.download_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  QuestionBankSpec? bankSpec(String bankId) =>
      QuestionBankDefaults.byId(bankId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('题库管理'),
        actions: [
          IconButton(
            tooltip: '创建题库',
            onPressed: _controlsDisabled ? null : _createBank,
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: '管理订阅',
            onPressed: _controlsDisabled ? null : _editSubscriptions,
            icon: const Icon(Icons.rss_feed),
          ),
          BankActionButton(
            key: const ValueKey('bank-check-all'),
            tooltip: '检查全部更新',
            busy: _busy && _operation == 'all',
            enabled: !_controlsDisabled,
            onPressed: _refreshManifest,
            icon: Icons.sync,
          ),
          if (_busy && _operation == 'import')
            BankActionButton(
              tooltip: '导入题库',
              icon: Icons.more_vert,
              busy: true,
              task: _task,
            )
          else
            PopupMenuButton<String>(
              enabled: !_controlsDisabled,
              tooltip: '更多导入方式',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) =>
                  value == 'link' ? _importLink() : _importFile(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'link', child: Text('从链接导入')),
                const PopupMenuItem(value: 'file', child: Text('从文件导入')),
              ],
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: FutureBuilder<List<QuestionBank>>(
            future: _banksFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData &&
                  snapshot.connectionState != ConnectionState.done) {
                return const Center(child: BankActionProgress(label: '正在加载题库'));
              }
              if (snapshot.hasError) {
                return Center(child: Text('题库目录加载失败：${snapshot.error}'));
              }
              final banks = snapshot.data ?? const <QuestionBank>[];
              return RefreshIndicator(
                onRefresh: () async => setState(_reload),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    //Text(
                    //  '管理独立题库',
                    //  style: Theme.of(context).textTheme.headlineSmall,
                    //),
                    //const SizedBox(height: 6),
                    //Text(
                    //  '题目状态在题库之间共享，课程和章节统计按当前题库分别计算。默认题库不可删除，只能启用或禁用。',
                    //  style: Theme.of(context).textTheme.bodyMedium,
                    //),
                    const SizedBox(height: 18),
                    ...banks.map(_bankCard),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
