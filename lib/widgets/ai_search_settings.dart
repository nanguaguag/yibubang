import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/platform_adaptive.dart';
import '../models/ai_search.dart';
import '../models/ai_search_options.dart';
import '../services/ai_search_client.dart';
import 'common/info_card.dart';
import 'common/styled_tile.dart';

/// The AI group below General settings. Opening it never requires networking.
class AiSearchSettingsGroup extends StatefulWidget {
  final AiModelGateway? gateway;
  const AiSearchSettingsGroup({super.key, this.gateway});
  @override
  State<AiSearchSettingsGroup> createState() => _AiSearchSettingsGroupState();
}

class _AiSearchSettingsGroupState extends State<AiSearchSettingsGroup> {
  late final AiModelGateway gateway = widget.gateway ?? AiSearchClient();
  SharedPreferences? prefs;
  AiSearchOptions options = const AiSearchOptions();
  AiModelCatalog? catalog;
  String selectedModel = 'stable';
  bool saving = false;
  bool refreshing = false;
  final changes = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final localPrefs = await SharedPreferences.getInstance();
    final localModels = await AiSearchClient.localModels();
    if (!mounted) return;
    setState(() {
      prefs = localPrefs;
      options = AiSearchOptions.fromPreferences(localPrefs);
      selectedModel = localPrefs.getString('ai_answer_model') ?? 'stable';
      catalog = localModels;
    });
  }

  Future<void> _saveOptions(AiSearchOptions value) async {
    if (prefs == null || saving) return;
    setState(() => saving = true);
    try {
      await value.save(prefs!);
      if (mounted) setState(() => options = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _notify() {
    if (!mounted) return;
    setState(() {});
    changes.value++;
  }

  Future<void> _refresh({bool force = false}) async {
    if (refreshing) return;
    refreshing = true;
    _notify();
    try {
      final result = await gateway.models(refresh: force);
      if (mounted) catalog = result;
    } catch (_) {
      /* Keep the immediately usable local directory. */
    }
    if (!mounted) return;
    refreshing = false;
    _notify();
  }

  Future<void> _models() async {
    unawaited(_refresh());
    final selected = await showAdaptiveModalSheet<String>(
      context: context,
      title: '回答模型',
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: changes,
        builder: (context, _, _) => SizedBox(
          height: (MediaQuery.sizeOf(context).height * .65).clamp(240.0, 480.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isDesktopLayout(sheetContext))
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '回答模型',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        catalog?.stale == true ? '使用本机备用目录' : '内置回答模型',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新模型',
                      onPressed: refreshing
                          ? null
                          : () => _refresh(force: true),
                      icon: refreshing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RadioGroup<String>(
                  groupValue: selectedModel,
                  onChanged: (id) {
                    if (id != null) Navigator.pop(sheetContext, id);
                  },
                  child: ListView(
                    children: [
                      for (final model in catalog?.models ?? <AiAnswerModel>[])
                        RadioListTile<String>(
                          value: model.id,
                          enabled: model.availability != 'unavailable',
                          title: Text(model.label),
                          subtitle: Text(
                            [
                              if (model.id == 'stable') '由 Google 选择稳定版本',
                              model.contextWindow,
                              if (model.preview) '预览版',
                              if (model.availability == 'unavailable') '暂不可用',
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Text(
                  '目录加载失败时仍可使用本机缓存。选择保存在本机，下次提问生效；刷新不消耗搜索额度。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    try {
      await gateway.selectModel(selected);
      if (mounted) setState(() => selectedModel = selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('模型选择保存失败，请重试')));
      }
    }
  }

  Future<void> _ratio() async {
    final total = options.resultCount;
    var count = options.textbookCount;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('教材与题目比例'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '教材 $count 条 · 题目 ${total - count} 条',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Slider(
                  value: count.toDouble(),
                  min: 0,
                  max: total.toDouble(),
                  divisions: total,
                  label: '$count : ${total - count}',
                  onChanged: (value) => update(() => count = value.round()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        update(() => count = (total * 2 / 3).round()),
                    child: const Text('恢复默认'),
                  ),
                ),
                Text(
                  '向右增加教材占比。每次回答最多使用 $total 条检索资料；实际条数取决于命中结果，不足的来源不会自动挤占另一来源。仅选择教材或题目时，只检索该来源。此设置不影响单独的教材检索。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, count),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      await _saveOptions(options.copyWith(textbookCount: selected));
    }
  }

  Future<void> _resultCount() async {
    var total = options.resultCount;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final split = options.copyWith(resultCount: total);
          return AlertDialog(
            title: const Text('检索条目数'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '最多 $total 条',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: total.toDouble(),
                    min: 1,
                    max: 25,
                    divisions: 24,
                    label: '$total 条',
                    onChanged: (value) => update(() => total = value.round()),
                  ),
                  Text(
                    '教材 ${split.textbookCount} 条 · 题目 ${split.questionCount} 条',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => update(() => total = 12),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const Text(
                    '检索会在整个知识库中查找，再把相关结果交给 AI；此数字限制本次回答的资料量。默认 12 条，最多 25 条。增加条数可能覆盖更多资料，也可能增加等待时间和无关内容，不能保证穷尽全部资料。调整时保持教材与题目原比例，不改变每次使用额度。',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, total),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && selected != null) {
      await _saveOptions(options.copyWith(resultCount: selected));
    }
  }

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('AI 搜索使用说明'),
      content: SingleChildScrollView(
        child: Text(
          '问题改写：先理解、改写问题，再生成回答。\n\n'
          '流式输出：收到回答片段后立即显示。流式输出需要问题改写；开启流式会开启改写，关闭改写会同时关闭流式。\n\n'
          '每日 200 次额度。基础生成每次消耗 1 次；仅问题改写消耗 2 次；同时开启改写和流式，每次消耗 1+1+1=3 次额度，是基础生成的 3 倍。当前每次消耗 ${options.quotaCost} 次。\n\n'
          '额度是 App 的使用限制，不代表 Google 的收费倍数。回答模型和检索比例均在下一次提问生效。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Widget _value(String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .3,
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: .4),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final canSave = prefs != null && !saving;
    final label =
        catalog?.models
            .where((m) => m.id == selectedModel)
            .firstOrNull
            ?.label ??
        '已保存的模型';
    void rephrase(bool value) => _saveOptions(
      options.copyWith(rephrase: value, streaming: value && options.streaming),
    );
    void streaming(bool value) => _saveOptions(
      options.copyWith(rephrase: value || options.rephrase, streaming: value),
    );
    return InfoCard(
      children: [
        IconTile(
          icon: Icons.auto_awesome_outlined,
          label: '回答模型',
          trailing: _value(
            selectedModel == 'stable'
                ? '稳定版'
                : label.replaceFirst('Gemini ', ''),
          ),
          onTap: catalog == null ? null : _models,
        ),
        IconTile(
          icon: Icons.psychology_outlined,
          label: '问题改写',
          onTap: canSave ? () => rephrase(!options.rephrase) : null,
          trailing: Switch(
            value: options.rephrase,
            onChanged: canSave ? rephrase : null,
          ),
        ),
        IconTile(
          icon: Icons.notes_rounded,
          label: '流式输出',
          onTap: canSave ? () => streaming(!options.streaming) : null,
          trailing: Switch(
            value: options.streaming,
            onChanged: canSave ? streaming : null,
          ),
        ),
        IconTile(
          icon: Icons.manage_search_rounded,
          label: '检索条目数',
          trailing: _value('${options.resultCount} 条'),
          onTap: canSave ? _resultCount : null,
        ),
        IconTile(
          icon: Icons.balance_rounded,
          label: '教材与题目比例',
          trailing: _value(options.ratioLabel),
          onTap: canSave ? _ratio : null,
        ),
        IconTile(
          icon: Icons.info_outline_rounded,
          label: '使用说明',
          trailing: _value('每次 ${options.quotaCost} 次额度'),
          onTap: _help,
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (widget.gateway == null) (gateway as AiSearchClient).dispose();
    changes.dispose();
    super.dispose();
  }
}
