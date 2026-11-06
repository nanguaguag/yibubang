import 'package:flutter/material.dart';

import '../services/bank_subscription_service.dart';

class BankSubscriptionsPage extends StatefulWidget {
  const BankSubscriptionsPage({super.key});

  @override
  State<BankSubscriptionsPage> createState() => _BankSubscriptionsPageState();
}

class _BankSubscriptionsPageState extends State<BankSubscriptionsPage> {
  final _controller = TextEditingController();
  final _service = BankSubscriptionService.instance;
  List<String> _urls = [];
  bool _automatic = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final urls = await _service.urls();
    final automatic = await _service.automatic();
    if (mounted) setState(() { _urls = urls; _automatic = automatic; _busy = false; });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _service.save(_urls, _automatic);
      await _service.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('题库订阅')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('添加题库 JSON 清单地址。应用启动及运行期间每六小时检查一次，可在题库管理页随时手动更新。'),
      const SizedBox(height: 16),
      TextField(controller: _controller, enabled: !_busy,
        decoration: const InputDecoration(labelText: 'HTTPS 订阅地址', border: OutlineInputBorder())),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: _busy ? null : () {
          try {
            final url = BankSubscriptionService.validateUrl(_controller.text);
            setState(() { if (!_urls.contains(url)) _urls.add(url); _error = null; });
            _controller.clear();
          } catch (error) { setState(() => _error = error.toString()); }
        }, icon: const Icon(Icons.add), label: const Text('添加'))),
      for (final url in _urls) ListTile(title: Text(url), trailing: IconButton(
        tooltip: '移除', icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => setState(() => _urls.remove(url)))),
      SwitchListTile(title: const Text('自动检查并更新已安装的订阅题库'),
        value: _automatic, onChanged: _busy ? null : (value) => setState(() => _automatic = value)),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_busy) const LinearProgressIndicator(),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('保存并检查')),
    ]),
  );
}
