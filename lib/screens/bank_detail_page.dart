import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import '../services/bank_subscription_service.dart';
import '../widgets/bank_export_button.dart';
import '../widgets/bank_link_dialog.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';

class BankDetailPage extends StatefulWidget {
  const BankDetailPage({super.key, required this.bank});
  final QuestionBank bank;

  @override
  State<BankDetailPage> createState() => _BankDetailPageState();
}

class _BankDetailPageState extends State<BankDetailPage> {
  bool _saving = false;
  late Future<_BankDetails> _details = _load();

  Future<_BankDetails> _load() async {
    final bank = widget.bank;
    final history = await QuestionBankRepository().history(bank.bankId);
    final source = await BankSubscriptionService.instance.sourceFor(bank);
    if (!bank.isInstalled) return _BankDetails({}, [], [], [], history, source);
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
    setState(() => _saving = true);
    try {
      await BankSubscriptionService.instance.setBankSource(widget.bank, url);
      if (mounted) {
        setState(() => _details = _load());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('订阅链接已修改')));
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
                    '新增 ${event['added']} 道题 · 共 ${event['question_count']} 道题',
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
      ],
    ),
    body: FutureBuilder<_BankDetails>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('详情读取失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final details = snapshot.data!;
        final bank = widget.bank;
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
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Chip(
                                  label: Text(
                                    bank.isInstalled
                                        ? '${details.meta['question_count'] ?? 0} 道题'
                                        : '未安装',
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                if (bank.identityId.isNotEmpty)
                                  Chip(
                                    label: Text(bank.identityId),
                                    shape: const StadiumBorder(),
                                  ),
                              ],
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
                  label: '版本',
                  value: 'v${bank.version}',
                ),
                IconTile(
                  icon: Icons.source_outlined,
                  label: '来源',
                  value: source,
                ),
                if (details.subscription != null)
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
                              Text(
                                '订阅链接',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                details.subscription!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '修改订阅链接',
                          onPressed: _saving
                              ? null
                              : () => _editSubscription(details.subscription),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
            _heading('覆盖课程'),
            InfoCard(
              children: courses.isEmpty
                  ? [const IconTile(icon: Icons.school_outlined, label: '暂无课程')]
                  : courses,
            ),
            _heading('更新记录'),
            InfoCard(
              children: [
                if (details.history.isEmpty)
                  const IconTile(icon: Icons.history_rounded, label: '暂无更新记录')
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
  );
}

class _BankDetails {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> identities, subjects, chapters, history;
  final String? subscription;
  _BankDetails(
    this.meta,
    this.identities,
    this.subjects,
    this.chapters,
    this.history,
    this.subscription,
  );
}
