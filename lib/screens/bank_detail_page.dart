import 'package:flutter/material.dart';

import '../db/question_bank_manager.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';
import '../services/bank_subscription_service.dart';

class BankDetailPage extends StatefulWidget {
  const BankDetailPage({super.key, required this.bank});
  final QuestionBank bank;

  @override
  State<BankDetailPage> createState() => _BankDetailPageState();
}

class _BankDetailPageState extends State<BankDetailPage> {
  late final Future<_BankDetails> _details = _load();

  Future<_BankDetails> _load() async {
    final bank = widget.bank;
    final history = await QuestionBankRepository().history(bank.bankId);
    final subscriptions = await BankSubscriptionService.instance.cached();
    final subscription = subscriptions.where((r) => r['bank_id'] == bank.bankId).firstOrNull;
    if (!bank.isInstalled) return _BankDetails({}, [], [], [], history, subscription?['subscription_url']?.toString());
    final db = await QuestionBankDatabaseManager().openBank(bank.bankId, filePath: bank.localPath);
    final meta = bank.bankId == 'legacy_combined' ? <String, dynamic>{} : (await db.query('BankMeta')).first;
    final identities = await db.query('Identity');
    final subjects = await db.rawQuery('''
      SELECT s.id, s.name, x.identity_id, x.total FROM IdentitySubject x
      JOIN Subject s ON s.id = x.subject_id
    ''');
    final chapters = await db.rawQuery('''
      SELECT c.id, c.name, x.identity_id, x.subject_id, x.total
      FROM IdentityChapter x JOIN Chapter c ON c.id = x.chapter_id
    ''');
    return _BankDetails(meta, identities, subjects, chapters, history, subscription?['subscription_url']?.toString());
  }

  Widget _identity(Map<String, dynamic> identity, _BankDetails details, Set<String> visited) {
    final id = identity['id'] as String;
    if (!visited.add(id)) return const SizedBox.shrink();
    return ExpansionTile(title: Text('${identity['name']} · $id'), children: [
      for (final subject in details.subjects.where((r) => r['identity_id'] == id))
        ExpansionTile(title: Text('${subject['name']}'), subtitle: Text('${subject['total']} 道章节关系'), children: [
          for (final chapter in details.chapters.where((r) => r['identity_id'] == id && r['subject_id'] == subject['id']))
            ListTile(title: Text('${chapter['name']}'), trailing: Text('${chapter['total']} 题')),
        ]),
      for (final child in details.identities.where((r) => r['parent_id'] == id)) _identity(child, details, visited),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.bank.name)),
    body: FutureBuilder<_BankDetails>(future: _details, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('详情读取失败：${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final details = snapshot.data!;
      final bank = widget.bank;
      return ListView(padding: const EdgeInsets.all(20), children: [
        Wrap(spacing: 8, children: [Chip(label: Text('v${bank.version}')),
          if (details.meta['question_count'] != null) Chip(label: Text('${details.meta['question_count']} 题'))]),
        ListTile(title: const Text('来源'), subtitle: Text(details.subscription != null ? '订阅题库' :
          details.meta['source'] == 'ykb-created' ? '医考帮自建题库' : bank.builtIn ? '内置题库' : '文件导入')),
        if (details.subscription != null) ListTile(title: const Text('订阅地址'), subtitle: SelectableText(details.subscription!)),
        if (bank.remoteUrl != null) ListTile(title: const Text('下载地址'), subtitle: SelectableText(bank.remoteUrl!)),
        const Divider(), const Text('覆盖课程', style: TextStyle(fontSize: 18)),
        for (final root in details.identities.where((r) => r['parent_id'] == '-1')) _identity(root, details, {}),
        const Divider(), const Text('变更时间轴', style: TextStyle(fontSize: 18)),
        if (details.history.isEmpty) const ListTile(title: Text('暂无历史记录'), subtitle: Text('此功能启用前的更新不会补造历史。')),
        for (final event in details.history) IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(width: 24, child: Column(children: [Icon(Icons.circle, size: 12), Expanded(child: VerticalDivider())])),
          Expanded(child: ListTile(title: Text('${event['action']} · +${event['added']} 题'),
            subtitle: Text('${DateTime.fromMillisecondsSinceEpoch(event['timestamp'] as int).toLocal()}\nv${event['version']} · 共 ${event['question_count']} 题'))),
        ])),
      ]);
    }),
  );
}

class _BankDetails {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> identities, subjects, chapters, history;
  final String? subscription;
  _BankDetails(this.meta, this.identities, this.subjects, this.chapters, this.history, this.subscription);
}
