import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question_bank.dart';
import '../models/bank_source.dart';
import '../repositories/question_bank_repository.dart';
import '../services/question_bank_file_service.dart';
import '../services/bank_subscription_service.dart';
import '../common/platform_adaptive.dart';
import '../widgets/bank_export_button.dart';
import '../widgets/bank_link_import_dialog.dart';
import 'bank_subscriptions_page.dart';
import 'bank_creation_page.dart';
import 'bank_detail_page.dart';

class QuestionBankPage extends StatefulWidget {
  const QuestionBankPage({super.key});

  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> {
  final QuestionBankRepository _repository = QuestionBankRepository();
  late Future<List<QuestionBank>> _banksFuture;
  String? _activeBankId;
  Map<String, dynamic> _remoteBanks = {};
  final Set<String> _downloading = <String>{};
  final Map<String, double?> _downloadProgress = <String, double?>{};
  bool _busy = false;
  bool _exporting = false;
  final _updates = <String, BankUpdateInfo>{};

  bool get _controlsDisabled => _busy || _exporting || _downloading.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _remoteBanks = {
      for (final entry in QuestionBankRepository.configuredRemoteBanks.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    _reload();
    _loadSubscriptions();
    _maybeAutoSync();
  }

  Future<void> _loadSubscriptions() async {
    final entries = await BankSubscriptionService.instance.cached();
    if (!mounted) return;
    setState(() {
      for (final entry in entries) {
        _remoteBanks[entry['bank_id'] as String] = entry;
      }
    });
  }

  Future<void> _editSubscriptions() async {
    await pushAdaptiveModalPage<bool>(
      context,
      builder: (_) => const BankSubscriptionsPage(),
    );
    if (mounted) {
      setState(() {
        _remoteBanks = Map<String, dynamic>.from(
          QuestionBankRepository.configuredRemoteBanks,
        );
        _reload();
      });
      await _loadSubscriptions();
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
      builder: (_) => BankDetailPage(bank: bank),
    );
    if (!mounted) return;
    setState(() {
      _remoteBanks = Map<String, dynamic>.from(
        QuestionBankRepository.configuredRemoteBanks,
      );
      _reload();
    });
    await _loadSubscriptions();
  }

  Future<void> _updateSubscription(QuestionBank bank) async {
    if (_controlsDisabled) return;
    setState(() {
      _downloading.add(bank.bankId);
      _downloadProgress[bank.bankId] = null;
    });
    try {
      await BankSubscriptionService.instance.check(bankId: bank.bankId);
      final info = await BankSubscriptionService.instance.updateInfo(bank);
      if (!mounted) return;
      setState(_reload);
      await _loadSubscriptions();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(info.message ?? info.label)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading.remove(bank.bankId);
          _downloadProgress.remove(bank.bankId);
        });
      }
    }
  }

  // 「同步题库」开关开启时，进入题库管理页自动拉取远程清单。
  Future<void> _maybeAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('sync_question_bank') ?? false)) return;
    if (!mounted) return;
    await _refreshManifest();
  }

  void _reload() {
    _banksFuture = _loadBanks();
  }

  Future<List<QuestionBank>> _loadBanks() async {
    final banks = await _repository.listBanks();
    _activeBankId = await _repository.activeBankId();
    _updates.clear();
    for (final bank in banks) {
      _updates[bank.bankId] = await BankSubscriptionService.instance.updateInfo(
        bank,
      );
    }
    return banks;
  }

  Future<void> _refreshManifest() async {
    setState(() => _busy = true);
    try {
      final results = await BankSubscriptionService.instance.check();
      final catalog = await BankSubscriptionService.instance.store.read();
      final entries = <String, dynamic>{
        for (final source in catalog.sources.values)
          for (final entry in source.entries)
            if (catalog.bindings[entry['bank_id']] == source.id)
              entry['bank_id'] as String: entry,
      };
      if (!mounted) return;
      setState(() {
        _remoteBanks = entries;
        _reload();
      });
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
    await _runOperation(
      () => BankSubscriptionService.instance.importLink(
        choice.url,
        subscribe: choice.subscribe,
        onConflict: _chooseImportMode,
      ),
      '题库导入成功',
    );
    await _loadSubscriptions();
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
    setState(() {
      _downloading.add(bankId);
      _downloadProgress[bankId] = 0;
    });
    try {
      await BankSubscriptionService.instance.install(
        bankId,
        onConflict: _chooseImportMode,
        onResolve: _resolveUpdate,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted) return;
          final progress = totalBytes == null || totalBytes <= 0
              ? null
              : (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
          setState(() => _downloadProgress[bankId] = progress);
        },
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bank.isInstalled ? '题库更新成功' : '题库下载成功')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading.remove(bankId);
          _downloadProgress.remove(bankId);
        });
      }
    }
  }

  Future<BankImportMode?> _resolveUpdate(
    QuestionBank existing,
    BankUpdateInfo info,
    BankContentDiff diff,
  ) async {
    if (!mounted) return null;
    return showDialog<BankImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('更新「${existing.name}」'),
        content: Text(
          '${info.label}\n新包新增 ${diff.added} 道题、${diff.changed} 道内容不同，本地独有 ${diff.localExtras} 道题。\n\n'
          '合并保留本地独有题目和课程关系；同一道题采用订阅内容。替换使用完整订阅版本。个人作答、收藏和笔记会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('暂不更新'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, BankImportMode.replace),
            child: const Text('使用订阅版本'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, BankImportMode.merge),
            child: const Text('保留本地补充'),
          ),
        ],
      ),
    );
  }

  Future<void> _runOperation(
    Future<QuestionBank> Function() operation,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      await operation();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on BankImportCancelled {
      // Closing the import choice is a normal cancellation.
    } catch (error) {
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
    return Chip(
      label: Text('v${bank.version}'),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _bankCard(QuestionBank bank) {
    final remote = _remoteBanks[bank.bankId] as Map<String, dynamic>?;
    final hasUpdate =
        bank.isInstalled &&
        _updates[bank.bankId]?.status == BankUpdateStatus.available;
    final canDownload =
        !bank.isInstalled &&
        (remote?['url']?.toString().isNotEmpty == true ||
            bank.remoteUrl?.isNotEmpty == true);
    final canUpdate = bank.isInstalled && hasUpdate;
    final hasSubscription =
        bank.isInstalled &&
        (remote?['subscription_url']?.toString().isNotEmpty == true ||
            bank.remoteUrl?.isNotEmpty == true);
    final downloading = _downloading.contains(bank.bankId);
    final downloadProgress = _downloadProgress[bank.bankId];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _controlsDisabled ? null : () => _select(bank),
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
                              ? '独立 SQLite 题库'
                              : bank.description,
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
                            if (hasUpdate) const Chip(label: Text('有更新')),
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
                  IconButton(
                    tooltip: '题库详情',
                    onPressed: _controlsDisabled ? null : () => _details(bank),
                    icon: const Icon(Icons.info_outline),
                  ),
                  if (hasSubscription)
                    IconButton(
                      tooltip: '检查更新',
                      onPressed: _controlsDisabled
                          ? null
                          : () => _updateSubscription(bank),
                      icon: const Icon(Icons.sync_rounded),
                    ),
                  if (bank.isInstalled)
                    BankExportButton(
                      bank: bank,
                      enabled: !_controlsDisabled,
                      onBusyChanged: (busy) {
                        if (mounted) setState(() => _exporting = busy);
                      },
                    ),
                  if (downloading)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(value: downloadProgress),
                          Text(
                            downloadProgress == null
                                ? '下载中'
                                : '${(downloadProgress * 100).round()}%',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    )
                  else if (canDownload || canUpdate)
                    IconButton(
                      tooltip: canUpdate ? '下载并更新' : '下载题库',
                      onPressed: _controlsDisabled
                          ? null
                          : () => _download(bank),
                      icon: Icon(canUpdate ? Icons.update : Icons.download),
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
          IconButton(
            tooltip: '检查全部更新',
            onPressed: _controlsDisabled ? null : _refreshManifest,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '从文件导入',
            onPressed: _controlsDisabled ? null : _importFile,
            icon: const Icon(Icons.file_open_outlined),
          ),
          PopupMenuButton<String>(
            enabled: !_controlsDisabled,
            tooltip: '更多导入方式',
            onSelected: (_) => _importLink(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'link', child: Text('从链接导入')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<QuestionBank>>(
        future: _banksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
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
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
