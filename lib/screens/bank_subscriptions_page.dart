import 'package:flutter/material.dart';

import '../services/bank_subscription_service.dart';
import '../models/bank_source.dart';
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
  Map<String, BankSource> _sources = {};
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool keepEdits = false}) async {
    final allSources = await _service.sources();
    final urls = allSources
        .where((s) => !s.official)
        .map((s) => s.url)
        .toList();
    if (mounted) {
      setState(() {
        if (!keepEdits) _urls = urls;
        _sources = {for (final source in allSources) source.url: source};
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
        if (_urls.contains(url) && (index == null || _urls[index] != url)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('该订阅已存在')));
        } else if (index != null) {
          _urls[index] = url;
        } else if (!_urls.contains(url)) {
          _urls.add(url);
        }
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
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkSource(BankSource source, {bool download = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (download) {
        await _service.confirmSource(source.id);
      } else {
        await _service.check(sourceId: source.id);
      }
      await _load(keepEdits: true);
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
          '保存后可在题库管理中检查更新。支持题库文件链接和订阅清单。',
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
                            '${_urls[i]}\n${_sources[_urls[i]]?.statusLabel ?? '待检查'}',
                            maxLines: 3,
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
                    PopupMenuButton<String>(
                      enabled: !_busy,
                      tooltip: '来源操作',
                      onSelected: (action) {
                        final source = _sources[_urls[i]];
                        if (action == 'remove') {
                          setState(() => _urls.removeAt(i));
                        } else if (source != null) {
                          _checkSource(source, download: action == 'download');
                        }
                      },
                      itemBuilder: (_) => [
                        if (_sources[_urls[i]] != null) ...[
                          const PopupMenuItem(
                            value: 'check',
                            child: Text('检查更新'),
                          ),
                          if (_sources[_urls[i]]!.status ==
                              BankSourceStatus.needsDownload)
                            const PopupMenuItem(
                              value: 'download',
                              child: Text('下载确认题库'),
                            ),
                        ],
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('移除订阅'),
                        ),
                      ],
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
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    ),
  );
}
