import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../common/app_shapes.dart';
import '../common/platform_adaptive.dart';
import '../models/spaced_review_item.dart';
import '../repositories/spaced_review_repository.dart';

/// 闪卡创建与编辑组件（支持常规弹窗与下弹抽屉 BottomSheet 两种形态）
class FlashcardEditDialog extends StatefulWidget {
  final CustomFlashcard? existingCard;
  final String? initialFront;
  final String? initialBack;
  final String? questionId;
  final List<String>? initialTags;
  final List<String>? availableTags;
  final String? defaultTag;
  final String? restoreText;
  final String? explainText;
  final String dialogTitle;
  final bool isBottomSheet;

  const FlashcardEditDialog({
    super.key,
    this.existingCard,
    this.initialFront,
    this.initialBack,
    this.questionId,
    this.initialTags,
    this.availableTags,
    this.defaultTag,
    this.restoreText,
    this.explainText,
    this.dialogTitle = '制作闪卡',
    this.isBottomSheet = false,
  });

  /// 唤起自适应闪卡创建与编辑（移动端新页面，桌面端居中模态卡片）
  static Future<CustomFlashcard?> show(
    BuildContext context, {
    CustomFlashcard? existingCard,
    String? initialFront,
    String? initialBack,
    String? questionId,
    List<String>? initialTags,
    List<String>? availableTags,
    String? defaultTag,
    String? restoreText,
    String? explainText,
    String dialogTitle = '制作闪卡',
  }) {
    final page = FlashcardEditDialog(
      existingCard: existingCard,
      initialFront: initialFront,
      initialBack: initialBack,
      questionId: questionId,
      initialTags: initialTags,
      availableTags: availableTags,
      defaultTag: defaultTag,
      restoreText: restoreText,
      explainText: explainText,
      dialogTitle: dialogTitle,
      isBottomSheet: false,
    );

    if (isDesktopLayout(context)) {
      return pushAdaptiveModalPage<CustomFlashcard>(
        context,
        desktopConstraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        builder: (_) => page,
      );
    } else {
      return Navigator.of(context).push<CustomFlashcard>(
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }

  /// 唤起下弹抽屉（BottomSheet 模式，与写笔记交互完全一致）
  static Future<CustomFlashcard?> showAsBottomSheet(
    BuildContext context, {
    CustomFlashcard? existingCard,
    String? initialFront,
    String? initialBack,
    String? questionId,
    List<String>? initialTags,
    List<String>? availableTags,
    String? defaultTag,
    String? restoreText,
    String? explainText,
    String dialogTitle = '制作闪卡',
  }) {
    return showModalBottomSheet<CustomFlashcard>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FlashcardEditDialog(
        existingCard: existingCard,
        initialFront: initialFront,
        initialBack: initialBack,
        questionId: questionId,
        initialTags: initialTags,
        availableTags: availableTags,
        defaultTag: defaultTag,
        restoreText: restoreText,
        explainText: explainText,
        dialogTitle: dialogTitle,
        isBottomSheet: true,
      ),
    );
  }

  @override
  State<FlashcardEditDialog> createState() => _FlashcardEditDialogState();
}

class _FlashcardEditDialogState extends State<FlashcardEditDialog> {
  late final TextEditingController _frontController;
  late final TextEditingController _backController;
  late final TextEditingController _tagInputController;
  final _spacedRepo = SpacedReviewRepository();

  final List<String> _selectedTags = [];
  List<String> _availableTags = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _frontController = TextEditingController(
      text: widget.existingCard?.front ?? widget.initialFront ?? '',
    );
    _backController = TextEditingController(
      text: widget.existingCard?.back ?? widget.initialBack ?? '',
    );
    _tagInputController = TextEditingController();

    _initTags();
    if (widget.availableTags != null) {
      _availableTags = List.from(widget.availableTags!);
    } else {
      _loadAvailableTags();
    }
  }

  void _initTags() {
    final tagsFromCard = widget.existingCard?.tags;
    if (tagsFromCard != null && tagsFromCard.trim().isNotEmpty) {
      _addTagsFromString(tagsFromCard);
    } else if (widget.initialTags != null && widget.initialTags!.isNotEmpty) {
      for (final t in widget.initialTags!) {
        _addTagsFromString(t);
      }
    } else if (widget.defaultTag != null && widget.defaultTag!.trim().isNotEmpty) {
      _addTagsFromString(widget.defaultTag!);
    }
  }

  void _addTagsFromString(String raw) {
    final parts = raw.split(RegExp(r'[,，\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    for (final tag in parts) {
      if (!_selectedTags.contains(tag)) {
        _selectedTags.add(tag);
      }
    }
  }

  Future<void> _loadAvailableTags() async {
    final tags = await _spacedRepo.getAllFlashcardTags();
    if (mounted) {
      setState(() {
        _availableTags = tags;
      });
    }
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _commitCurrentTagInput() {
    final text = _tagInputController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _addTagsFromString(text);
        _tagInputController.clear();
      });
    }
  }

  void _appendOrSetBack(String title, String content) {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) return;

    final current = _backController.text.trim();
    setState(() {
      if (current.isEmpty) {
        _backController.text = cleanContent;
      } else {
        _backController.text = '$current\n\n【$title】\n$cleanContent';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已成功引用$title到闪卡背面'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleSave() async {
    _commitCurrentTagInput();

    final frontText = _frontController.text.trim();
    final backText = _backController.text.trim();

    if (frontText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入闪卡正面内容（提问/概念）')),
      );
      return;
    }
    if (backText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入闪卡背面内容（答案/解析）')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final cardId = widget.existingCard?.id ??
          'fc_${nowMs}_${math.Random().nextInt(9999).toString().padLeft(4, '0')}';

      final title = frontText.length > 30
          ? '${frontText.substring(0, 30)}...'
          : frontText;

      final tagsString = _selectedTags.isNotEmpty ? _selectedTags.join(', ') : null;

      final card = CustomFlashcard(
        id: cardId,
        title: title,
        front: frontText,
        back: backText,
        questionId: widget.existingCard?.questionId ?? widget.questionId,
        tags: tagsString,
        createdAt: widget.existingCard?.createdAt ?? nowMs,
        updatedAt: nowMs,
      );

      await _spacedRepo.saveFlashcard(card);

      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop(card);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存闪卡失败: $e')),
        );
      }
    }
  }

  Widget _buildBody(BuildContext context, {bool showHeader = true, bool showBottomActions = true}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 未选中的已有标签候选（排除已选）
    final candidateTags = _availableTags.where((t) => !_selectedTags.contains(t)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          // 头部标题与关闭
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.style_outlined, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.dialogTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        // 正面（提问/题干）
        Row(
          children: [
            Icon(Icons.crop_portrait_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '正面 (Front · 问题 / 概念)',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _frontController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '写下正面需要回忆或测试的知识点、题干或概念...',
            hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 背面（答案/解析）及一键引用工具栏
        Row(
          children: [
            Icon(Icons.flip_to_back_rounded, size: 16, color: scheme.secondary),
            const SizedBox(width: 6),
            Text(
              '背面 (Back · 答案 / 解析 / 重点总结)',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.secondary,
              ),
            ),
          ],
        ),
        if ((widget.restoreText != null && widget.restoreText!.trim().isNotEmpty) ||
            (widget.explainText != null && widget.explainText!.trim().isNotEmpty)) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (widget.restoreText != null && widget.restoreText!.trim().isNotEmpty) ...[
                  ActionChip(
                    avatar: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
                    label: const Text('引用考点还原', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _appendOrSetBack('考点还原', widget.restoreText!),
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.explainText != null && widget.explainText!.trim().isNotEmpty) ...[
                  ActionChip(
                    avatar: Icon(Icons.lightbulb_outline, size: 14, color: scheme.secondary),
                    label: const Text('引用答案解析', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _appendOrSetBack('答案解析', widget.explainText!),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        TextField(
          controller: _backController,
          minLines: 6,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: '写下背面参考答案、核心记忆秘诀、精炼总结...',
            hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              borderSide: BorderSide(color: scheme.secondary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 标签管理（已选标签 Chips + 快速选取已有标签 + 自定义输入）
        Row(
          children: [
            Icon(Icons.label_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '标签分类 (点击可删除或添加)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 已选标签 Chips（支持一键删除默认的课程名、章节名或自定义标签）
        if (_selectedTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _selectedTags.map((tag) {
              return InputChip(
                label: Text(tag, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                onDeleted: () {
                  setState(() {
                    _selectedTags.remove(tag);
                  });
                },
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.4),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // 快捷选择已有标签池
        if (candidateTags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    '常用标签: ',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 4),
                  ...candidateTags.take(8).map((tag) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 13),
                        label: Text(tag, style: const TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        //padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: () {
                          setState(() {
                            _selectedTags.add(tag);
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],

        // 自定义输入标签输入框（符合 Material 3 规范：带前后缀图标与舒适内边距）
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: TextField(
            controller: _tagInputController,
            decoration: InputDecoration(
              hintText: '输入新标签，多个用逗号隔开',
              hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.style_outlined, size: 20, color: scheme.primary),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                tooltip: '添加标签',
                color: scheme.primary,
                onPressed: _commitCurrentTagInput,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShapes.medium),
                borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppShapes.medium),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _commitCurrentTagInput(),
          ),
        ),

        if (widget.questionId != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.link_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Text(
                '已自动关联原题 (ID: ${widget.questionId})，复习时可一键回溯原题',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ],
          ),
        ],

        if (showBottomActions) ...[
          const SizedBox(height: 18),

          // 底部动作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppShapes.medium),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _saving ? '正在保存...' : (widget.existingCard == null ? '保存并入库' : '保存修改'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _saving ? null : _handleSave,
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isBottomSheet) {
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: bottomInset + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖拽手柄
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _buildBody(context, showHeader: true),
              ],
            ),
          ),
        ),
      );
    }

    final isDesktop = isDesktopLayout(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dialogTitle),
        leading: IconButton(
          icon: Icon(isDesktop ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _handleSave,
            child: Text(
              _saving ? '正在保存...' : '保存',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _buildBody(context, showHeader: false, showBottomActions: false),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppShapes.medium),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _saving ? '正在保存...' : (widget.existingCard == null ? '保存并入库' : '保存修改'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _saving ? null : _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
