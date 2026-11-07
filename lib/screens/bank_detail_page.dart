import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import '../models/bank_source.dart';
import '../services/question_bank_file_service.dart';
import '../widgets/bank_update_dialog.dart';
import '../models/bank_download_task.dart';
import '../widgets/bank_action_button.dart';
import '../widgets/bank_check_feedback.dart';
import '../repositories/question_bank_repository.dart';
import '../services/bank_subscription_service.dart';
import '../widgets/bank_export_button.dart';
import '../widgets/bank_link_dialog.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';
import '../widgets/bank_tag.dart';

class BankDetailPage extends StatefulWidget {
  const BankDetailPage({
    super.key,
    required this.bank,
    this.subscriptionService,
  });
  final QuestionBank bank;

  final BankSubscriptionService? subscriptionService;
  @override
  State<BankDetailPage> createState() => _BankDetailPageState();
}

class _BankDetailPageState extends State<BankDetailPage> {
  late final _service =
      widget.subscriptionService ?? BankSubscriptionService.instance;
  BankDownloadTask? _task;
  bool _saving = false;
  String _operation = '';
  late Future<_BankDetails> _details = _load();

  @override
  void initState() {
    super.initState();
    _service.addListener(_sourceChanged);
  }

  void _sourceChanged() {
    if (mounted && !_saving) {
      setState(() {
        _details = _load();
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_sourceChanged);
    _task?.cancel();
    super.dispose();
  }

  Future<_BankDetails> _load() async {
    final bank =
        await QuestionBankRepository().find(widget.bank.bankId) ?? widget.bank;
    final history = await QuestionBankRepository().history(bank.bankId);
    final service = _service;
    final catalog = await service.store.read();
    final info = await service.updateInfo(bank);
    final source = catalog.sourceFor(bank.bankId)?.url;
    if (!bank.isInstalled) {
      return _BankDetails({}, [], [], [], history, source, bank, catalog, info);
    }
    // Legacy combined files predate BankMeta and cannot pass schema-v1 validation.
    final db = bank.bankId == 'legacy_combined'
        ? await openDatabase(
            bank.localPath,
            readOnly: true,
            singleInstance: false,
          )
        : await QuestionBankDatabaseManager().openBank(
            bank.bankId,
            filePath: bank.localPath,
          );
    try {
      final meta = bank.bankId == 'legacy_combined'
          ? <String, dynamic>{
              'subject_count': Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM Subject'),
              ),
              'chapter_count': Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM Chapter'),
              ),
              'question_count': Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM Question'),
              ),
            }
          : (await db.query('BankMeta')).first;
      final identities = await db.query('Identity');
      // Shared questions may belong to several chapters. Count distinct IDs.
      final subjects = await db.rawQuery('''
        SELECT s.id, s.name, x.identity_id, COALESCE(q.total, 0) AS total
        FROM IdentitySubject x JOIN Subject s ON s.id = x.subject_id
        LEFT JOIN (
          SELECT identity_id, subject_id, COUNT(DISTINCT question_id) AS total
          FROM IdentityQuestion GROUP BY identity_id, subject_id
        ) q ON q.identity_id = x.identity_id AND q.subject_id = x.subject_id
      ''');
      final chapters = await db.rawQuery('''
        SELECT c.id, c.name, x.identity_id, x.subject_id, COALESCE(q.total, 0) AS total
        FROM IdentityChapter x JOIN Chapter c ON c.id = x.chapter_id
        LEFT JOIN (
          SELECT identity_id, subject_id, chapter_id, COUNT(DISTINCT question_id) AS total
          FROM IdentityQuestion GROUP BY identity_id, subject_id, chapter_id
        ) q ON q.identity_id = x.identity_id AND q.subject_id = x.subject_id AND q.chapter_id = x.chapter_id
      ''');
      return _BankDetails(
        meta,
        identities,
        subjects,
        chapters,
        history,
        source,
        bank,
        catalog,
        info,
      );
    } finally {
      if (bank.bankId == 'legacy_combined') await db.close();
    }
  }

  List<Widget> _identity(
    Map<String, dynamic> identity,
    _BankDetails details,
    Set<String> visited,
  ) {
    final id = identity['id'].toString();
    if (!visited.add(id)) return [];
    final subjects = details.subjects
        .where((r) => r['identity_id'] == id)
        .toList();
    final children = details.identities
        .where((r) => r['parent_id'] == id)
        .expand((child) => _identity(child, details, visited))
        .toList();
    // Hide empty grouping subjects while retaining descendants with courses.
    if (subjects.isEmpty) return children;
    return [
      ExpansionTile(
        key: PageStorageKey('identity-$id'),
        leading: const TileIcon(icon: Icons.school_outlined),
        title: Text('${identity['name']}'),
        subtitle: Text('${subjects.length} 门课程 · $id'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        children: [
          for (final subject in subjects)
            ExpansionTile(
              key: PageStorageKey('subject-$id-${subject['id']}'),
              title: Text('${subject['name']}'),
              subtitle: Text('${subject['total']} 道题'),
              tilePadding: const EdgeInsets.only(left: 32, right: 20),
              children: [
                for (final chapter in details.chapters.where(
                  (r) =>
                      r['identity_id'] == id &&
                      r['subject_id'] == subject['id'],
                ))
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 44, right: 20),
                    title: Text(
                      '${chapter['name']}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    trailing: Text(
                      '${chapter['total']} 题',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ...children,
        ],
      ),
    ];
  }

  Future<void> _editSubscription(String? source) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) =>
          BankLinkDialog(title: '修改订阅链接', initialValue: source ?? ''),
    );
    if (url == null || !mounted) return;
    setState(() {
      _saving = true;
      _operation = 'edit';
    });
    try {
      await _service.proposeBankSource(widget.bank, url);
      if (mounted) {
        setState(() {
          _details = _load();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('新来源已保存，请检查后确认')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('修改失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    BankDownloadTask? task,
    String operation = 'more',
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _task = task;
      _operation = operation;
    });
    try {
      await action();
      task?.finish();
      if (mounted && success != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } on BankImportCancelled {
      task?.finish();
      // Closing a choice keeps the current file and its baseline.
    } catch (error) {
      task?.finish(error: '$error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _details = _load();
        });
      }
    }
  }

  Future<BankImportMode?> _resolve(
    QuestionBank bank,
    BankUpdateInfo info,
    BankContentDiff diff,
  ) async {
    if (!mounted) return null;
    return showBankUpdateDialog(context, bank, info, diff);
  }

  Future<void> _update(_BankDetails details) async {
    final task =
        details.info.canApply ||
            details.info.status == BankUpdateStatus.needsDownload ||
            !details.bank.isInstalled
        ? BankDownloadTask()
        : null;
    await _run(
      () async {
        if (details.info.status == BankUpdateStatus.needsDownload) {
          await _service.confirmSource(details.info.source!.id, task: task);
        } else if (details.info.canApply || !details.bank.isInstalled) {
          await _service.install(
            details.bank.bankId,
            onResolve: _resolve,
            task: task,
          );
        } else {
          final results = await _service.check(bankId: details.bank.bankId);
          if (mounted && await showBankCheckErrors(context, results)) return;
        }
        final bank = await QuestionBankRepository().find(details.bank.bankId);
        if (bank != null && mounted) {
          final result = await _service.updateInfo(bank);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.message ?? result.label)),
            );
          }
        }
      },
      task: task,
      operation: 'update',
    );
  }

  Future<void> _redownload() async {
    final task = BankDownloadTask();
    await _run(
      () async {
        await _service.install(
          widget.bank.bankId,
          redownload: true,
          onResolve: _resolve,
          task: task,
        );
      },
      task: task,
      success: '题库已重新下载',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${widget.bank.name}」？'),
        content: const Text(
          '将删除本地题库及其补充题目。作答记录、收藏、笔记和选课信息会保留。'
          '有订阅来源的题库仍可重新下载；未导出的本地补充无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除题库'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() {
      _saving = true;
      _operation = 'more';
    });
    try {
      await _service.deleteBank(widget.bank.bankId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _checkPending(BankSource source) async {
    final task = source.status == BankSourceStatus.needsDownload
        ? BankDownloadTask()
        : null;
    await _run(
      () async {
        if (task != null) {
          await _service.confirmSource(source.id, task: task);
        } else {
          final results = await _service.check(sourceId: source.id);
          if (mounted) await showBankCheckErrors(context, results);
        }
      },
      task: task,
      operation: 'pending',
    );
  }

  Future<void> _integrity() => _run(() async {
    final bank =
        await QuestionBankRepository().find(widget.bank.bankId) ?? widget.bank;
    String message;
    if (bank.bankId == 'legacy_combined') {
      final db = await openDatabase(
        bank.localPath,
        readOnly: true,
        singleInstance: false,
      );
      try {
        message =
            (await db.rawQuery(
                  'PRAGMA integrity_check',
                )).every((r) => r.values.single == 'ok') &&
                (await db.rawQuery('PRAGMA foreign_key_check')).isEmpty
            ? '题库完整性检查通过'
            : '题库文件有损坏';
      } finally {
        await db.close();
      }
    } else {
      final result = await QuestionBankRepository().validatePath(
        bank.localPath,
        expectedBankId: bank.bankId,
      );
      message = result.isValid ? '题库完整性检查通过' : result.message;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本地完整性检查'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  });

  Future<void> _chooseSource() async {
    final details = await _details;
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择更新来源'),
        children: [
          for (final source in details.catalog.candidates(details.bank.bankId))
            ListTile(
              title: Text(source.name),
              subtitle: Text(
                '${source.url}\nv${source.entry(details.bank.bankId)?['version']} · ${source.statusLabel}',
              ),
              trailing:
                  details.catalog.bindings[details.bank.bankId] == source.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: source.status == BankSourceStatus.ready
                  ? () => Navigator.pop(ctx, source.id)
                  : null,
            ),
          if (details.catalog.candidates(details.bank.bankId).isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('暂无已识别来源，请先添加并检查订阅。'),
            ),
        ],
      ),
    );
    if (selected != null && mounted) {
      await _run(
        () => _service.selectSource(details.bank, selected),
        success: '更新来源已切换',
      );
    }
  }

  List<Widget> _subscriptionSection(_BankDetails details) {
    final theme = Theme.of(context);
    final info = details.info;
    final pending =
        details.catalog.sources[details.catalog.pending[details.bank.bankId]];
    final local =
        info.content?.hasLocalChanges(details.bank.contentHash) == true;
    return [
      _heading('订阅更新'),
      InfoCard(
        children: [
          if (details.subscription == null)
            IconTile(
              icon: Icons.add_link_rounded,
              label: '添加订阅链接',
              onTap: _saving ? null : () => _editSubscription(null),
            )
          else
            BaseTile(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TileIcon(icon: Icons.link_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('订阅链接', style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        SelectableText(
                          details.subscription!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  BankActionButton(
                    tooltip: '修改订阅链接',
                    busy: _saving && _operation == 'edit',
                    enabled: !_saving,
                    onPressed: () =>
                        _editSubscription(pending?.url ?? details.subscription),
                    icon: Icons.edit_outlined,
                  ),
                ],
              ),
            ),
          if (info.source != null)
            IconTile(
              icon: Icons.update_rounded,
              label: info.canApply
                  ? '${info.label} · v${info.entry?['version']}'
                  : info.label,
              trailing: BankActionButton(
                key: const ValueKey('bank-detail-update'),
                tooltip: details.bank.isInstalled ? info.actionLabel : '下载题库',
                busy: _saving && _operation == 'update',
                task: _task,
                enabled: !_saving,
                onPressed: () => _update(details),
                icon:
                    info.canApply ||
                        info.status == BankUpdateStatus.needsDownload ||
                        !details.bank.isInstalled
                    ? Icons.download_rounded
                    : Icons.sync_rounded,
              ),
            ),
          if (info.source?.checkedAt != null && info.source!.checkedAt > 0)
            BaseTile(
              child: Row(
                children: [
                  const TileIcon(icon: Icons.schedule_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('最近检查', style: theme.textTheme.bodyLarge),
                        Text(
                          _time(info.source!.checkedAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (info.message != null)
            BaseTile(
              child: Text(
                info.message!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (info.content?.hasBaseline == true &&
              (local || info.content!.baseVersion != details.bank.version))
            IconTile(
              icon: Icons.cloud_done_outlined,
              label: '已应用订阅版本',
              value: 'v${info.content!.baseVersion}',
            ),
          if (local)
            IconTile(
              icon: Icons.edit_note_rounded,
              label: '本地有补充',
              value: '修订 ${info.content!.localRevision}',
            ),
          if (pending != null)
            BaseTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '新来源 · ${pending.statusLabel}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(pending.url, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BankActionButton(
                        key: const ValueKey('bank-pending-check'),
                        tooltip:
                            pending.status == BankSourceStatus.needsDownload
                            ? '下载确认'
                            : '检查新来源',
                        busy: _saving && _operation == 'pending',
                        task: _task,
                        enabled: !_saving,
                        onPressed: () => _checkPending(pending),
                        icon: pending.status == BankSourceStatus.needsDownload
                            ? Icons.download_rounded
                            : Icons.sync_rounded,
                      ),
                      if (pending.status == BankSourceStatus.ready &&
                          pending.entry(details.bank.bankId) != null)
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _run(
                                  () => _service.selectSource(
                                    details.bank,
                                    pending.id,
                                  ),
                                  success: '更新来源已切换',
                                ),
                          child: const Text('使用新来源'),
                        ),
                    ],
                  ),
                  if (pending.status == BankSourceStatus.ready &&
                      pending.entry(details.bank.bankId) == null)
                    const Text('此来源不包含当前题库，原订阅继续可用。'),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  String _time(int timestamp) => DateTime.fromMillisecondsSinceEpoch(timestamp)
      .toLocal()
      .toIso8601String()
      .substring(0, 16)
      .replaceAll('T', ' ')
      .replaceAll('-', '/');

  String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _history(Map<String, dynamic> event, bool last) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch(
      event['timestamp'] as int,
    ).toLocal();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
                if (!last)
                  Expanded(
                    child: VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${event['action']}', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    event['action'] == '删除本地题库'
                        ? '个人作答、收藏和笔记已保留'
                        : '新增 ${event['added']} 道题 · 共 ${event['question_count']} 道题',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${time.toIso8601String().substring(0, 16).replaceAll('T', ' ').replaceAll('-', '/')} · v${event['version']}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('题库详情'),
      actions: [
        if (widget.bank.isInstalled)
          BankExportButton(bank: widget.bank, enabled: !_saving),
        if (_saving && _operation == 'more')
          BankActionButton(
            tooltip: '更多题库操作',
            icon: Icons.more_vert,
            busy: true,
            task: _task,
          )
        else
          PopupMenuButton<String>(
            enabled: !_saving,
            tooltip: '更多题库操作',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => value == 'integrity'
                ? _integrity()
                : value == 'source'
                ? _chooseSource()
                : value == 'delete'
                ? _delete()
                : _redownload(),
            itemBuilder: (_) => [
              if (widget.bank.localPath.isNotEmpty)
                const PopupMenuItem(value: 'integrity', child: Text('检查本地完整性')),
              const PopupMenuItem(value: 'source', child: Text('选择更新来源')),
              const PopupMenuItem(value: 'redownload', child: Text('重新下载')),
              if (widget.bank.localPath.isNotEmpty)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '删除题库',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: FutureBuilder<_BankDetails>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('详情读取失败：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: BankActionProgress(label: '正在加载题库'));
            }
            final details = snapshot.data!;
            final bank = details.bank;
            final courses = details.identities
                .where((r) => r['parent_id'] == '-1')
                .expand((root) => _identity(root, details, {}))
                .toList();
            final source = details.subscription != null
                ? '订阅题库'
                : details.meta['source'] == 'ykb-created'
                ? '医考帮自建题库'
                : bank.builtIn
                ? '内置题库'
                : '文件导入';
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                InfoCard(
                  children: [
                    BaseTile(
                      child: Row(
                        key: const ValueKey('bank-detail-header'),
                        children: [
                          const TileIcon(icon: Icons.menu_book_rounded),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bank.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (bank.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    bank.description,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (RegExp(r'^\d+$').hasMatch(bank.identityId)) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message: '学科编号',
                              child: BankTag(
                                bank.identityId,
                                key: const ValueKey('bank-detail-identity'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    BaseTile(
                      child: Row(
                        key: const ValueKey('bank-detail-totals'),
                        children: [
                          for (final item in const [
                            ('课程总数', 'subject_count'),
                            ('章节总数', 'chapter_count'),
                            ('题目总数', 'question_count'),
                          ])
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    '${details.meta[item.$2] ?? details.info.entry?[item.$2] ?? '—'}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.$1,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                _heading('题库信息'),
                InfoCard(
                  children: [
                    IconTile(
                      icon: Icons.layers_outlined,
                      label: bank.isInstalled ? '版本' : '可下载版本',
                      value:
                          'v${bank.isInstalled ? bank.version : details.info.source?.entry(bank.bankId)?['version'] ?? bank.version}',
                    ),
                    IconTile(
                      icon: Icons.source_outlined,
                      label: '来源',
                      value: source,
                    ),
                    if (bank.isInstalled && bank.size > 0)
                      IconTile(
                        icon: Icons.storage_rounded,
                        label: '题库文件大小',
                        value: _fileSize(bank.size),
                      ),
                  ],
                ),
                ..._subscriptionSection(details),
                _heading('覆盖课程'),
                InfoCard(
                  children: courses.isEmpty
                      ? [
                          const IconTile(
                            icon: Icons.school_outlined,
                            label: '暂无课程',
                          ),
                        ]
                      : courses,
                ),
                _heading('更新记录'),
                InfoCard(
                  children: [
                    if (details.history.isEmpty)
                      const IconTile(
                        icon: Icons.history_rounded,
                        label: '暂无更新记录',
                      )
                    else
                      BaseTile(
                        child: Column(
                          children: [
                            for (var i = 0; i < details.history.length; i++)
                              _history(
                                details.history[i],
                                i == details.history.length - 1,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _BankDetails {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> identities, subjects, chapters, history;
  final String? subscription;
  final QuestionBank bank;
  final BankSourceCatalog catalog;
  final BankUpdateInfo info;
  _BankDetails(
    this.meta,
    this.identities,
    this.subjects,
    this.chapters,
    this.history,
    this.subscription,
    this.bank,
    this.catalog,
    this.info,
  );
}
