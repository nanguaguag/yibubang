import 'package:flutter/material.dart';
import '../common/app_shapes.dart';
import '../models/spaced_review_item.dart';
import '../models/subject.dart';
import '../repositories/spaced_review_repository.dart';

/// 每日记忆曲线计划设置与创建对话框（支持自定义抽题来源与覆盖课程）
class DailyReviewPlanDialog extends StatefulWidget {
  final ReviewPlan? initialPlan;
  final ValueChanged<ReviewPlan>? onSaved;
  final SpacedReviewRepository? repository;
  final List<Subject>? availableSubjects;

  const DailyReviewPlanDialog({
    super.key,
    this.initialPlan,
    this.onSaved,
    this.repository,
    this.availableSubjects,
  });

  static Future<ReviewPlan?> show(
    BuildContext context, {
    ReviewPlan? initialPlan,
    ValueChanged<ReviewPlan>? onSaved,
    SpacedReviewRepository? repository,
    List<Subject>? availableSubjects,
  }) {
    return showDialog<ReviewPlan>(
      context: context,
      builder: (context) => DailyReviewPlanDialog(
        initialPlan: initialPlan,
        onSaved: onSaved,
        repository: repository,
        availableSubjects: availableSubjects,
      ),
    );
  }

  @override
  State<DailyReviewPlanDialog> createState() => _DailyReviewPlanDialogState();
}

class _DailyReviewPlanDialogState extends State<DailyReviewPlanDialog> {
  late final SpacedReviewRepository _repo;
  late TextEditingController _nameController;
  late int _dailyNewTarget;
  late int _dailyReviewLimit;
  late Set<String> _sourceTypes;
  late Set<String> _coveredSubjects;

  List<Subject> _allAvailableSubjects = [];
  bool _loading = false;
  ReviewPlan? _currentPlan;

  static const List<int> _newTargetPresets = [10, 20, 30, 50];
  static const List<int> _reviewLimitPresets = [20, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SpacedReviewRepository();
    _currentPlan = widget.initialPlan;
    _nameController = TextEditingController(
      text: widget.initialPlan?.name ?? '每日记忆计划',
    );
    _dailyNewTarget = widget.initialPlan?.dailyNewTarget ?? 20;
    _dailyReviewLimit = widget.initialPlan?.dailyReviewLimit ?? 50;
    _sourceTypes = Set<String>.from(
      widget.initialPlan?.sourceTypes ?? const ['wrong', 'collected', 'note'],
    );
    _coveredSubjects = Set<String>.from(
      widget.initialPlan?.coveredSubjects ?? const [],
    );

    _initData();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    try {
      if (_currentPlan == null) {
        final plan = await _repo.getOrCreateActivePlan();
        _currentPlan = plan;
        _nameController.text = plan.name;
        _dailyNewTarget = plan.dailyNewTarget;
        _dailyReviewLimit = plan.dailyReviewLimit;
        _sourceTypes = Set<String>.from(plan.sourceTypes);
        _coveredSubjects = Set<String>.from(plan.coveredSubjects);
      }

      // 加载题库全部课程供勾选
      if (widget.availableSubjects != null) {
        _allAvailableSubjects = widget.availableSubjects!;
      } else {
        try {
          final tree = await getSubjectTreeByIdentity();
          final subjects = <Subject>[];
          void walk(SubjectTreeNode n) {
            subjects.addAll(n.subjects);
            for (final c in n.children) {
              walk(c);
            }
          }
          for (final r in tree) {
            walk(r);
          }
          _allAvailableSubjects = subjects;
        } catch (_) {}
      }

      // 若未设置过覆盖课程，默认自动勾选首页已选课程
      if (_coveredSubjects.isEmpty && _allAvailableSubjects.isNotEmpty) {
        try {
          final selected = await getSelectedSubjects();
          if (selected.isNotEmpty) {
            _coveredSubjects = selected.map((s) => s.id.toString()).toSet();
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _syncWithHomeCourses() async {
    try {
      final selected = await getSelectedSubjects();
      if (mounted) {
        setState(() {
          _coveredSubjects = selected.map((s) => s.id.toString()).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_sourceTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个抽题来源（如错题、收藏或笔记）')),
      );
      return;
    }

    final base = _currentPlan ??
        ReviewPlan(
          id: 'plan_default',
          name: name,
        );

    final updated = base.copyWith(
      name: name,
      dailyNewTarget: _dailyNewTarget,
      dailyReviewLimit: _dailyReviewLimit,
      sourceTypes: _sourceTypes.toList(),
      coveredSubjects: _coveredSubjects.toList(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await _repo.savePlan(updated);
      widget.onSaved?.call(updated);
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } catch (e) {
      debugPrint('[DailyReviewPlanDialog] 保存计划失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存计划失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.psychology_outlined, color: scheme.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            widget.initialPlan == null ? '设置记忆计划' : '计划与抽题范围',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: '计划名称',
                        prefixIcon: const Icon(Icons.edit_note_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 1. 抽题来源配置（Anki 核心浓缩理念：重点攻克错题、收藏与笔记）
                    Text(
                      '自定义抽题来源',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '优先循环强化精华高频卡片，避免重复刷无意义的简单题。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildSourceChip('错题 (重点攻克)', 'wrong', Icons.error_outline),
                        _buildSourceChip('我的收藏 (强化难点)', 'collected', Icons.star_border),
                        _buildSourceChip('笔记卡片 (核心速记)', 'note', Icons.edit_note_rounded),
                        _buildSourceChip('包含未做新题', 'all', Icons.auto_awesome_outlined),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 2. 覆盖的课程配置
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '选择覆盖的课程 (${_coveredSubjects.isEmpty ? "全部" : "已选 ${_coveredSubjects.length} 门"})',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurface,
                                ),
                              ),
                              Text(
                                '已学完或无需复习的课程可取消勾选，其错题不再出现。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _syncWithHomeCourses,
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('一键选首页课程', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_allAvailableSubjects.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _allAvailableSubjects.map((subject) {
                              final idStr = subject.id.toString();
                              final isSelected = _coveredSubjects.contains(idStr);
                              return FilterChip(
                                label: Text(subject.name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _coveredSubjects.add(idStr);
                                    } else {
                                      _coveredSubjects.remove(idStr);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),

                    // 3. 每日目标设置
                    Text(
                      '每日新学题量 ($_dailyNewTarget 题)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _newTargetPresets.map((count) {
                        final isSelected = _dailyNewTarget == count;
                        return ChoiceChip(
                          label: Text('$count 题'),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _dailyNewTarget = count);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '每日复习上限 ($_dailyReviewLimit 题)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _reviewLimitPresets.map((count) {
                        final isSelected = _dailyReviewLimit == count;
                        return ChoiceChip(
                          label: Text('$count 题'),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _dailyReviewLimit = count);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          onPressed: _loading ? null : _handleSave,
          child: const Text('保存计划'),
        ),
      ],
    );
  }

  Widget _buildSourceChip(String label, String key, IconData icon) {
    final isSelected = _sourceTypes.contains(key);
    return FilterChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _sourceTypes.add(key);
          } else {
            _sourceTypes.remove(key);
          }
        });
      },
    );
  }
}
