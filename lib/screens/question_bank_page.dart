import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';

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

  bool get _controlsDisabled => _busy || _downloading.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _remoteBanks = {
      for (final entry in QuestionBankRepository.configuredRemoteBanks.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    _reload();
  }

  void _reload() {
    _banksFuture = _loadBanks();
  }

  Future<List<QuestionBank>> _loadBanks() async {
    final banks = await _repository.listBanks();
    _activeBankId = await _repository.activeBankId();
    return banks;
  }

  Future<void> _refreshManifest() async {
    setState(() => _busy = true);
    try {
      final manifest = await _repository.checkRemoteManifest();
      final entries = <String, dynamic>{};
      for (final raw in (manifest?['banks'] as List? ?? const [])) {
        if (raw is Map && raw['bank_id'] != null) {
          entries[raw['bank_id'].toString()] = Map<String, dynamic>.from(raw);
        }
      }
      if (!mounted) return;
      setState(() {
        _remoteBanks = entries;
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('题库清单已更新')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('暂时无法获取远程题库清单：$error')),
        );
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
    await _runOperation(() => _repository.importFile(filePath), '题库导入成功');
  }

  Future<void> _download(QuestionBank bank) async {
    if (_downloading.isNotEmpty) return;
    final bankId = bank.bankId;
    final remote = _remoteBanks[bankId] as Map<String, dynamic>?;
    setState(() {
      _downloading.add(bankId);
      _downloadProgress[bankId] = 0;
    });
    try {
      await _repository.downloadBank(
        bankId,
        remoteEntry: remote,
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
        SnackBar(
          content: Text(bank.isInstalled ? '题库更新成功' : '题库下载成功'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$error')),
        );
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

  Future<void> _runOperation(
    Future<QuestionBank> Function() operation,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      await operation();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$error')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到${bank.name}')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败：$error')),
        );
      }
    }
  }

  Future<void> _toggle(QuestionBank bank, bool value) async {
    try {
      await _repository.setEnabled(bank.bankId, value);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法修改题库状态：$error')),
        );
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
    final hasUpdate = bank.isInstalled &&
        remote != null &&
        _repository.hasUpdate(bank, remote);
    final canDownload = !bank.isInstalled &&
        (remote?['url']?.toString().isNotEmpty == true ||
            bank.remoteUrl?.isNotEmpty == true);
    final canUpdate = bank.isInstalled && hasUpdate;
    final downloading = _downloading.contains(bank.bankId);
    final downloadProgress = _downloadProgress[bank.bankId];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(bank),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(bankSpec(bank.bankId)?.icon ?? Icons.menu_book),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bank.name,
                        style: Theme.of(context).textTheme.titleMedium),
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
                        _status(bank),
                        if (hasUpdate) const Chip(label: Text('有更新')),
                        if (!bank.isInstalled && !canDownload)
                          const Chip(label: Text('等待远程直链')),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (bank.isInstalled)
                    Switch(
                      value: bank.enabled,
                      onChanged: _controlsDisabled
                          ? null
                          : (value) => _toggle(bank, value),
                    ),
                  if (downloading)
                    SizedBox(
                      width: 58,
                      height: 58,
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
                    TextButton.icon(
                      onPressed:
                          _controlsDisabled ? null : () => _download(bank),
                      icon: Icon(canUpdate ? Icons.update : Icons.download),
                      label: Text(canUpdate ? '更新' : '下载'),
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
            tooltip: '检查题库更新',
            onPressed: _controlsDisabled ? null : _refreshManifest,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '从文件导入',
            onPressed: _controlsDisabled ? null : _importFile,
            icon: const Icon(Icons.file_open_outlined),
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
                Text(
                  '管理独立题库',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '题目状态在题库之间共享，课程和章节统计按当前题库分别计算。默认题库不可删除，只能启用或禁用。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
