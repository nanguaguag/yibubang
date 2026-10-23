import 'package:flutter/material.dart';

import '../../models/question.dart';
import 'question_detail_controller.dart';
import 'question_explain_view.dart';
import 'question_header_view.dart';
import 'question_options_view.dart';

/// 单道题目的独立渲染容器
///
/// 具备独立局部状态刷新能力。当本道题目作答、斩题或切换选项时，
/// 仅限当前卡片自身局部重建，彻底终结跨题全树重绘。
class QuestionPageItem extends StatefulWidget {
  final Question question;
  final UserQuestion userQuestion;
  final int index;
  final QuestionDetailController controller;

  const QuestionPageItem({
    super.key,
    required this.question,
    required this.userQuestion,
    required this.index,
    required this.controller,
  });

  @override
  State<QuestionPageItem> createState() => _QuestionPageItemState();
}

class _QuestionPageItemState extends State<QuestionPageItem> {
  bool _showContentAnyway = false;
  bool _lastIsCut = false;

  @override
  void initState() {
    super.initState();
    final uq = widget.controller.userQuestions[widget.index];
    _lastIsCut = uq.isCut || uq.status == 3;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(QuestionPageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    final uq = widget.controller.userQuestions[widget.index];
    final currentIsCut = uq.isCut || uq.status == 3;
    if (currentIsCut != _lastIsCut) {
      _lastIsCut = currentIsCut;
      _showContentAnyway = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final uq = widget.controller.userQuestions[widget.index];
    final currentIsCut = uq.isCut || uq.status == 3;
    if (currentIsCut != _lastIsCut) {
      _lastIsCut = currentIsCut;
      // 斩题状态发生改变时（如斩题或取消斩题），重置临时显示标记
      _showContentAnyway = false;
    }
    setState(() {});
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.controller.mode;
    final uq = widget.controller.userQuestions[widget.index];
    final q = widget.controller.questions[widget.index];
    final isCut = uq.isCut || uq.status == 3;

    // 斩题状态且未点击“显示题目内容”：100% 展示斩题占位并提供查看内容按钮
    if (isCut && !_showContentAnyway) {
      return _buildCutView(context);
    }

    // 正常题目展示（包含已斩但用户主动点击“显示题目内容”时）
    Widget content;
    // 背题模式：直接展示答案与解析
    if (mode == 3) {
      content = QuestionExplainView(
        question: q,
        userQuestion: uq,
        index: widget.index,
        controller: widget.controller,
        onStateChanged: _onStateChanged,
      );
    } else {
      switch (uq.status) {
        case 0: // 未作答
        case 4: // 测试模式 - 待提交
          content = _buildUnansweredView(context);
          break;
        case 1: // 正确
        case 2: // 错误
        case 3: // 历史已斩状态
          content = (uq.userAnswer.isNotEmpty || (q.answer != null && q.answer!.isNotEmpty))
              ? QuestionExplainView(
                  question: q,
                  userQuestion: uq,
                  index: widget.index,
                  controller: widget.controller,
                  onStateChanged: _onStateChanged,
                )
              : _buildUnansweredView(context);
          break;
        default:
          content = const Center(child: Text('未知的题目状态'));
      }
    }

    if (isCut && _showContentAnyway) {
      return _buildRevealedView(context, content);
    }

    return content;
  }

  /// 构建已斩题目的占位卡片
  Widget _buildCutView(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.content_cut_rounded,
                size: 36,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '该题目已斩',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '已在当前题库中标记为斩题',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('显示题目内容'),
              onPressed: () {
                setState(() {
                  _showContentAnyway = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 临时查看已斩题目时的包裹层（带顶部轻量提示条，可收起）
  Widget _buildRevealedView(BuildContext context, Widget child) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.28),
          child: Row(
            children: [
              Icon(
                Icons.content_cut_rounded,
                size: 15,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '该题目已斩',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.visibility_off_outlined, size: 15),
                label: const Text('隐藏题目内容', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() {
                    _showContentAnyway = false;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildUnansweredView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        controller: widget.controller.controllerFor(widget.index),
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: [
          QuestionHeaderView(
            question: widget.question,
            index: widget.index,
            totalCount: widget.controller.questions.length,
          ),
          const SizedBox(height: 12),
          QuestionOptionsView(
            question: widget.question,
            userQuestion: widget.userQuestion,
            index: widget.index,
            controller: widget.controller,
            onStateChanged: _onStateChanged,
          ),
        ],
      ),
    );
  }
}
