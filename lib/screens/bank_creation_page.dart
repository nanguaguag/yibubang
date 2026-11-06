import 'package:flutter/material.dart';

import '../models/bank_progress.dart';
import '../services/bank_creation_service.dart';
import '../widgets/bank_progress_view.dart';

class BankCreationPage extends StatefulWidget {
  const BankCreationPage({super.key});

  @override
  State<BankCreationPage> createState() => _BankCreationPageState();
}

class _BankCreationPageState extends State<BankCreationPage> {
  final _service = BankCreationService();
  late Future<List<BankIdentityNode>> _identities;
  final _selected = <String>{};
  BankTaskCancellation? _cancellation;
  BankProgress? _progress;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _identities = _service.identities();
  }

  Widget _node(BankIdentityNode node) {
    final checkbox = CheckboxListTile(
      title: Text(node.name), subtitle: Text(node.id),
      value: _selected.contains(node.id),
      onChanged: _busy ? null : (value) => setState(() {
        if (value == true) { _selected.add(node.id); } else { _selected.remove(node.id); }
      }),
    );
    if (node.children.isEmpty) return checkbox;
    return ExpansionTile(title: checkbox,
      children: node.children.map(_node).toList());
  }

  Future<void> _create(List<BankIdentityNode> nodes) async {
    final roots = nodes.expand((n) => n.selectedRoots(_selected)).toList();
    if (roots.isEmpty) return;
    final cancellation = BankTaskCancellation();
    setState(() { _busy = true; _error = null; _cancellation = cancellation; });
    var installed = 0;
    try {
      for (final root in roots) {
        await _service.create(root, cancellation: cancellation, onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        });
        installed++;
      }
      if (mounted) Navigator.pop(context, true);
    } on BankTaskCancelled {
      if (mounted) setState(() => _error = '已取消；已完成 $installed 个题库');
    } catch (error) {
      if (mounted) setState(() => _error = '已完成 $installed 个题库；$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('创建题库')),
      body: FutureBuilder<List<BankIdentityNode>>(
        future: _identities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${snapshot.error}'),
            TextButton(onPressed: () => setState(() => _identities = _service.identities()), child: const Text('重试')),
          ]));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('勾选身份后，将抓取其全部章节并保存为独立题库。父子重叠选择只制作一次；多个根分别制作。'),
            const SizedBox(height: 12),
            ...snapshot.data!.map(_node),
            if (_progress != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: BankProgressView(progress: _progress!)),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_busy) TextButton(onPressed: () => setState(() { _cancellation?.cancelled = true; }), child: const Text('取消抓取'))
            else FilledButton(onPressed: _selected.isEmpty ? null : () => _create(snapshot.data!), child: const Text('开始创建')),
          ]);
        },
      ),
    ),
  );
}
