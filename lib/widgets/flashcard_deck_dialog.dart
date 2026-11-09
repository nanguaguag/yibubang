import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../common/app_shapes.dart';
import '../models/spaced_review_item.dart';
import '../repositories/spaced_review_repository.dart';
import 'flashcard_edit_dialog.dart';

/// 闪卡卡包管理对话框（支持全局搜索、标签筛选、正背面编辑、删除与斩卡）
class FlashcardDeckDialog extends StatefulWidget {
  const FlashcardDeckDialog({super.key});

  /// 唤起卡包管理
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const FlashcardDeckDialog(),
    );
  }

  @override
  State<FlashcardDeckDialog> createState() => _FlashcardDeckDialogState();
}

class _FlashcardDeckDialogState extends State<FlashcardDeckDialog> {
  final _spacedRepo = SpacedReviewRepository();
  final _searchController = TextEditingController();

  bool _loading = true;
  List<CustomFlashcard> _allCards = [];
  List<CustomFlashcard> _filteredCards = [];
  Map<String, SpacedReviewItem> _reviewItemMap = {};

  String _selectedTag = '全部';
  Set<String> _availableTags = {'全部'};
  bool _hasModified = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);

    try {
      final cards = await _spacedRepo.getAllFlashcards();
      final itemIds = cards.map((c) => c.id).toList();

      final itemMap = <String, SpacedReviewItem>{};
      for (final id in itemIds) {
        final it = await _spacedRepo.getItem(id);
        if (it != null) itemMap[id] = it;
      }

      // 提取动态标签列表
      final tagsSet = <String>{'全部'};
      for (final c in cards) {
        if (c.tags != null && c.tags!.trim().isNotEmpty) {
          final splits = c.tags!.split(RegExp(r'[,，、\s]+'));
          for (final s in splits) {
            if (s.trim().isNotEmpty) tagsSet.add(s.trim());
          }
        }
      }

      if (mounted) {
        setState(() {
          _allCards = cards;
          _reviewItemMap = itemMap;
          _availableTags = tagsSet;
          _loading = false;
        });
        _applyFilter();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载闪卡失败: $e')),
        );
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    final tag = _selectedTag;

    final filtered = _allCards.where((card) {
      final matchesQuery = query.isEmpty ||
          card.front.toLowerCase().contains(query) ||
          card.back.toLowerCase().contains(query) ||
          card.title.toLowerCase().contains(query) ||
          (card.tags?.toLowerCase().contains(query) ?? false);

      final matchesTag = tag == '全部' ||
          (card.tags != null && card.tags!.contains(tag));

      return matchesQuery && matchesTag;
    }).toList();

    setState(() {
      _filteredCards = filtered;
    });
  }

  Future<void> _createCard() async {
    final result = await FlashcardEditDialog.show(
      context,
      dialogTitle: '新建独立闪卡',
    );
    if (result != null) {
      _hasModified = true;
      _loadCards();
    }
  }

  Future<void> _editCard(CustomFlashcard card) async {
    final result = await FlashcardEditDialog.show(
      context,
      existingCard: card,
      dialogTitle: '编辑闪卡',
    );
    if (result != null) {
      _hasModified = true;
      _loadCards();
    }
  }

  Future<void> _toggleMastered(CustomFlashcard card) async {
    final item = _reviewItemMap[card.id];
    final isMastered = item?.state == ReviewState.mastered;

    await _spacedRepo.toggleFlashcardMastered(card.id);
    _hasModified = true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMastered ? '已恢复该闪卡至复习计划' : '已斩卡！该卡片将不再出现在每日复习中'),
          duration: const Duration(seconds: 1),
        ),
      );
      _loadCards();
    }
  }

  Future<void> _deleteCard(CustomFlashcard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除闪卡'),
        content: Text('确定删除闪卡「${card.title.isNotEmpty ? card.title : card.front}」吗？\n删除后该卡片及其记忆复习进度将被彻底清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _spacedRepo.deleteFlashcard(card.id);
      _hasModified = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('闪卡已成功删除')),
        );
        _loadCards();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    final dialogWidth = math.min(width - 32, 720.0);
    final dialogHeight = math.min(height - 48, 800.0);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          children: [
            // 1. 顶部标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.style_rounded, color: scheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '闪卡卡包管理',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_allCards.length} 张',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '支持知识点正反面记忆、标签归纳与随时斩卡',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建闪卡'),
                    onPressed: _createCard,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(_hasModified),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索正面问题、背面答案、知识点或标签...',
                  hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShapes.large),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),

            // 3. 标签筛选横向滑动栏
            if (_availableTags.length > 1)
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _availableTags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tag = _availableTags.elementAt(index);
                    final isSelected = _selectedTag == tag;
                    return FilterChip(
                      selected: isSelected,
                      label: Text(tag),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? scheme.onPrimary : scheme.onSurface,
                      ),
                      selectedColor: scheme.primary,
                      backgroundColor: scheme.surfaceContainerLow,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _selectedTag = tag;
                        });
                        _applyFilter();
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 6),

            // 4. 闪卡列表主视图
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCards.isEmpty
                      ? _buildEmptyState(context, theme, scheme)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _filteredCards.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final card = _filteredCards[index];
                            final reviewItem = _reviewItemMap[card.id];
                            return _buildFlashcardItem(context, card, reviewItem, theme, scheme);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.style_outlined,
              size: 54,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              _allCards.isEmpty ? '卡包暂无闪卡' : '未找到符合条件的闪卡',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _allCards.isEmpty
                  ? '可在做题时将笔记一键转为闪卡，或直接新建自制卡片'
                  : '尝试更换搜索词或筛选标签',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (_allCards.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('制作第一张闪卡'),
                onPressed: _createCard,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcardItem(
    BuildContext context,
    CustomFlashcard card,
    SpacedReviewItem? reviewItem,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final isMastered = reviewItem?.state == ReviewState.mastered;
    final isNew = reviewItem == null || reviewItem.state == ReviewState.new_;
    final interval = reviewItem?.interval ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(
          color: isMastered
              ? Colors.teal.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      color: isMastered
          ? Colors.teal.withValues(alpha: 0.04)
          : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态徽章与关联原题标记
            Row(
              children: [
                // 记忆状态徽章
                if (isMastered)
                  _buildBadge('已斩卡 · 熟练掌握', Colors.teal, scheme)
                else if (isNew)
                  _buildBadge('待学新卡', Colors.blue, scheme)
                else
                  _buildBadge('复习中 (间隔 $interval天)', Colors.orange.shade800, scheme),

                if (card.questionId != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_rounded, size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text(
                          '题库关联',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // 快捷操作：斩卡 / 恢复
                IconButton(
                  tooltip: isMastered ? '恢复进入每日复习' : '斩卡（移出复习队列）',
                  icon: Icon(
                    isMastered ? Icons.undo_rounded : Icons.content_cut_rounded,
                    size: 18,
                    color: isMastered ? Colors.teal : scheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleMastered(card),
                ),
                // 编辑
                IconButton(
                  tooltip: '编辑闪卡',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editCard(card),
                ),
                // 删除
                IconButton(
                  tooltip: '删除闪卡',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteCard(card),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 正面内容 (Front)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '正面',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    card.front,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 背面内容 (Back)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppShapes.medium),
                border: Border.all(
                  color: scheme.secondary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '背面',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      card.back,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 底部标签
            if (card.tags != null && card.tags!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: card.tags!
                    .split(RegExp(r'[,，、\s]+'))
                    .where((s) => s.trim().isNotEmpty)
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
