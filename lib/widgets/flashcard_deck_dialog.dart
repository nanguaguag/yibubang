import 'package:flutter/material.dart';

import '../common/app_shapes.dart';
import '../common/platform_adaptive.dart';
import '../common/question_navigation.dart';
import '../models/spaced_review_item.dart';
import '../repositories/question_search_repository.dart';
import '../repositories/spaced_review_repository.dart';
import 'flashcard_edit_dialog.dart';

/// 闪卡卡包管理页面与控制器（移动端作为全屏页面，桌面端自适应居中模态卡片）
class FlashcardDeckPage extends StatefulWidget {
  const FlashcardDeckPage({super.key});

  /// 唤起卡包管理（移动端新页面跳转，桌面端自适应模态卡片）
  static Future<bool?> open(BuildContext context) {
    if (isDesktopLayout(context)) {
      return pushAdaptiveModalPage<bool>(
        context,
        desktopConstraints: const BoxConstraints(maxWidth: 840, maxHeight: 820),
        builder: (_) => const FlashcardDeckPage(),
      );
    } else {
      return Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const FlashcardDeckPage()),
      );
    }
  }

  /// 保持旧命名兼容调用
  static Future<bool?> show(BuildContext context) => open(context);

  @override
  State<FlashcardDeckPage> createState() => _FlashcardDeckPageState();
}

/// 兼容旧引用别名
typedef FlashcardDeckDialog = FlashcardDeckPage;

class _FlashcardDeckPageState extends State<FlashcardDeckPage> {
  final _spacedRepo = SpacedReviewRepository();
  final _searchController = TextEditingController();

  bool _loading = true;
  List<CustomFlashcard> _allCards = [];
  List<CustomFlashcard> _filteredCards = [];
  Map<String, SpacedReviewItem> _reviewItemMap = {};

  final Set<String> _selectedTags = {'全部'};
  List<String> _availableTags = ['全部'];
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

      // 提取动态标签列表（去重、排序）
      final tagsSet = <String>{};
      for (final c in cards) {
        if (c.tags != null && c.tags!.trim().isNotEmpty) {
          final splits = c.tags!.split(RegExp(r'[,，、\s]+'));
          for (final s in splits) {
            if (s.trim().isNotEmpty) tagsSet.add(s.trim());
          }
        }
      }
      final sortedTags = ['全部', ...tagsSet.toList()..sort()];

      if (mounted) {
        setState(() {
          _allCards = cards;
          _reviewItemMap = itemMap;
          _availableTags = sortedTags;
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

    final filtered = _allCards.where((card) {
      final matchesQuery = query.isEmpty ||
          card.front.toLowerCase().contains(query) ||
          card.back.toLowerCase().contains(query) ||
          card.title.toLowerCase().contains(query) ||
          (card.tags?.toLowerCase().contains(query) ?? false);

      final cardTagList = (card.tags ?? '')
          .split(RegExp(r'[,，、\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      final matchesTag = _selectedTags.contains('全部') ||
          _selectedTags.any((t) => cardTagList.contains(t));

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
        title: const Text('删除闪卡确认'),
        content: Text('确定要删除闪卡「${card.title}」吗？\n删除后复习进度与自制内容将无法找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          const SnackBar(content: Text('闪卡已删除'), duration: Duration(seconds: 1)),
        );
        _loadCards();
      }
    }
  }

  void _viewCardDetails(CustomFlashcard card) {
    pushAdaptiveModalPage(
      context,
      desktopConstraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
      builder: (ctx) => _FlashcardDetailView(
        card: card,
        reviewItem: _reviewItemMap[card.id],
        onEdit: () {
          Navigator.of(ctx).pop();
          _editCard(card);
        },
        onToggleMastered: () {
          Navigator.of(ctx).pop();
          _toggleMastered(card);
        },
        onDelete: () {
          Navigator.of(ctx).pop();
          _deleteCard(card);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDesktop = isDesktopLayout(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('闪卡卡包管理'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_filteredCards.length}/${_allCards.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(isDesktop ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(_hasModified),
        ),
        actions: [
          IconButton(
            tooltip: '新建自制闪卡',
            icon: const Icon(Icons.add_rounded),
            onPressed: _createCard,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 搜索框
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

          // 2. 标签多选筛选横向滑动栏 (反馈 5)
          if (_availableTags.length > 1)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _availableTags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tag = _availableTags[index];
                  final isSelected = _selectedTags.contains(tag);
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
                    showCheckmark: tag != '全部',
                    checkmarkColor: scheme.onPrimary,
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
                        if (tag == '全部') {
                          _selectedTags.clear();
                          _selectedTags.add('全部');
                        } else {
                          _selectedTags.remove('全部');
                          if (val) {
                            _selectedTags.add(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                          if (_selectedTags.isEmpty) {
                            _selectedTags.add('全部');
                          }
                        }
                      });
                      _applyFilter();
                    },
                  );
                },
              ),
            ),

          const SizedBox(height: 6),

          // 3. 闪卡列表主视图
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCards.isEmpty
                    ? _buildEmptyState(context, theme, scheme)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

  /// 列表项预览（正面/背面最多显示4行，卡片可点击查看详情）(反馈 4)
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
      clipBehavior: Clip.antiAlias,
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
      child: InkWell(
        onTap: () => _viewCardDetails(card),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 状态徽章与快捷操作
              Row(
                children: [
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
                  IconButton(
                    tooltip: '编辑闪卡',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editCard(card),
                  ),
                  IconButton(
                    tooltip: '删除闪卡',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteCard(card),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 正面内容 (Front - 最多4行)
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
                    child: Text(
                      card.front,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
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

              // 背面内容 (Back - 最多4行)
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
                      child: Text(
                        card.back,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
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

/// 点击闪卡卡片打开的详情视图（支持全文无截断阅读、状态管理与编辑/斩卡/删除操作）(反馈 4)
class _FlashcardDetailView extends StatelessWidget {
  final CustomFlashcard card;
  final SpacedReviewItem? reviewItem;
  final VoidCallback onEdit;
  final VoidCallback onToggleMastered;
  final VoidCallback onDelete;

  const _FlashcardDetailView({
    required this.card,
    required this.reviewItem,
    required this.onEdit,
    required this.onToggleMastered,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMastered = reviewItem?.state == ReviewState.mastered;
    final isNew = reviewItem == null || reviewItem?.state == ReviewState.new_;
    final interval = reviewItem?.interval ?? 0;
    final reps = reviewItem?.reps ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('闪卡详情'),
        leading: IconButton(
          icon: Icon(isDesktopLayout(context) ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: isMastered ? '恢复进入复习' : '斩卡',
            icon: Icon(isMastered ? Icons.undo_rounded : Icons.content_cut_rounded),
            onPressed: onToggleMastered,
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: onDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态指示条
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isMastered ? Colors.teal : (isNew ? Colors.blue : Colors.orange))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isMastered ? '已斩卡 · 熟练掌握' : (isNew ? '待学新卡' : '复习中 · 间隔 $interval 天'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isMastered ? Colors.teal : (isNew ? Colors.blue : Colors.orange.shade800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '已复习 $reps 次',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (card.questionId != null && card.questionId!.isNotEmpty) ...[
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppShapes.small),
                    onTap: () async {
                      final qId = card.questionId!;
                      final searchRepo = QuestionSearchRepository();
                      final result = await searchRepo.findQuestion(qId);
                      if (!context.mounted) return;
                      if (result == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('未在已安装题库中找到该原题 (ID: $qId)')),
                        );
                        return;
                      }
                      await openQuestionDetailPage(context, result);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '原题: ${card.questionId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.open_in_new_rounded, size: 12, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // 正面全文 (Front)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppShapes.medium),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.crop_portrait_rounded, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        //'正面 (Front · 问题 / 概念)',
                        '正面',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    card.front,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 背面全文 (Back)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppShapes.medium),
                border: Border.all(color: scheme.secondary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flip_to_back_rounded, size: 18, color: scheme.secondary),
                      const SizedBox(width: 6),
                      Text(
                        //'背面 (Back · 答案 / 解析)',
                        '背面',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    card.back,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 标签列表
            if (card.tags != null && card.tags!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: card.tags!
                    .split(RegExp(r'[,，、\s]+'))
                    .where((s) => s.trim().isNotEmpty)
                    .map((tag) => Chip(
                          label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 32),

            // 底部操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: Icon(isMastered ? Icons.undo_rounded : Icons.content_cut_rounded, size: 18),
                    label: Text(isMastered ? '恢复进入复习' : '熟练斩卡'),
                    onPressed: onToggleMastered,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑闪卡'),
                    onPressed: onEdit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
