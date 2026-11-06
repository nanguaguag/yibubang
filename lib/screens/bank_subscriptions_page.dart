import 'package:flutter/material.dart';

import '../services/bank_subscription_service.dart';
import '../widgets/common/info_card.dart';
import '../widgets/bank_link_dialog.dart';
import '../widgets/common/styled_tile.dart';

class BankSubscriptionsPage extends StatefulWidget {
  const BankSubscriptionsPage({super.key});

  @override
  State<BankSubscriptionsPage> createState() => _BankSubscriptionsPageState();
}

class _BankSubscriptionsPageState extends State<BankSubscriptionsPage> {
  final _service = BankSubscriptionService.instance;
  List<String> _urls = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final urls = await _service.urls();
    if (mounted) {
      setState(() {
        _urls = urls;
        _busy = false;
      });
    }
  }

  Future<void> _edit([int? index]) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => BankLinkDialog(
        title: index == null ? '添加订阅' : '修改订阅链接',
        initialValue: index == null ? '' : _urls[index],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final url = BankSubscriptionService.validateUrl(result);
        if (index != null) {
          _urls[index] = url;
        } else if (!_urls.contains(url))
          _urls.add(url);
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.saveSources(_urls);
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
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Text('订阅来源', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '支持 ZIP、SQLite 题库下载链接和 JSON 订阅清单。自动更新及检查间隔可在设置中调整。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          children: [
            for (var i = 0; i < _urls.length; i++)
              BaseTile(
                child: Row(
                  children: [
                    const TileIcon(icon: Icons.rss_feed_rounded),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Uri.parse(_urls[i]).host,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            _urls[i],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '修改订阅链接',
                      onPressed: _busy ? null : () => _edit(i),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '移除订阅',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _urls.removeAt(i)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
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
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存并检查'),
        ),
      ],
    ),
  );
}
