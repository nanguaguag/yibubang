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
  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.controller.mode;
    final uq = widget.userQuestion;
    final q = widget.question;

    // 背题模式：直接展示答案与解析
    if (mode == 3) {
      return QuestionExplainView(
        question: q,
        userQuestion: uq,
        index: widget.index,
        controller: widget.controller,
        onStateChanged: _onStateChanged,
      );
    }

    // 斩题状态
    if (uq.status == 3 || uq.isCut) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '该题目已斩',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      );
    }

    switch (uq.status) {
      case 0: // 未作答
      case 4: // 测试模式 - 待提交
        return _buildUnansweredView(context);
      case 1: // 正确
      case 2: // 错误
        return QuestionExplainView(
          question: q,
          userQuestion: uq,
          index: widget.index,
          controller: widget.controller,
          onStateChanged: _onStateChanged,
        );
      default:
        return const Center(child: Text('未知的题目状态'));
    }
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
