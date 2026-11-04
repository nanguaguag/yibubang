import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/question.dart';
import '../../models/question_section_config.dart';
import '../../widgets/reading_layout.dart';
import '../comment_page.dart';
import 'analysis_text_with_images.dart';
import 'question_detail_controller.dart';
import 'question_header_view.dart';
import 'question_label_view.dart';
import 'question_note_view.dart';
import 'question_options_view.dart';
import 'question_stat_view.dart';

/// 题目详情解析视图（已作答、背题模式）
///
/// 聚合了题目头部、选项高亮、对错答案栏、难度统计、考点还原富文本解析以及评论列表
class QuestionExplainView extends StatelessWidget {
  final Question question;
  final UserQuestion userQuestion;
  final int index;
  final QuestionDetailController controller;
  final VoidCallback onStateChanged;

  const QuestionExplainView({
    super.key,
    required this.question,
    required this.userQuestion,
    required this.index,
    required this.controller,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String userAnswer = getLastAnswer(userQuestion.userAnswer);
    final String answer = question.answer ?? '';
    final scrollController = controller.controllerFor(index);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ValueListenableBuilder<List<QuestionSectionItem>>(
        valueListenable: QuestionSectionConfig.configNotifier,
        builder: (context, sections, _) {
          final List<Widget> sectionWidgets = [];

          for (final section in sections) {
            if (!section.enabled) continue;
            switch (section.id) {
              case 'answer_stat':
                sectionWidgets.add(
                  ReadingContent(
                    child: Column(
                      key: const ValueKey('section_answer_stat'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (question.isSubjective)
                          Row(
                            children: [
                              const Text(
                                '自评：',
                                style: TextStyle(fontSize: 14),
                              ),
                              Flexible(
                                child: Text(
                                  userQuestion.status == 1
                                      ? '已掌握 (正确)'
                                      : (userQuestion.status == 2
                                          ? '未掌握 (待复习)'
                                          : (userAnswer.isNotEmpty ? userAnswer : '背题浏览')),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: userQuestion.status == 1
                                        ? Colors.green
                                        : (userQuestion.status == 2 ? Colors.red : Colors.grey),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Text.rich(
                            TextSpan(
                              text: '答案：正确答案 $answer, 你的答案 ',
                              children: [
                                TextSpan(
                                  text: userAnswer,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: userQuestion.status == 1
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        const SizedBox(height: 6),
                        QuestionStatView(
                          question: question,
                          userQuestion: userQuestion,
                        ),
                        if (question.source != null &&
                            question.source!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '来源：${question.source}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        const SizedBox(height: 10),
                        const Divider(color: Color(0x22888888)),
                      ],
                    ),
                  ),
                );
                break;
              case 'restore':
                if ((question.restore?.isNotEmpty ?? false) ||
                    (question.restoreImg?.isNotEmpty ?? false)) {
                  sectionWidgets.add(
                    _buildAnalysisSection(
                      context,
                      '考点还原',
                      Icons.location_on_outlined,
                      question.restore ?? '',
                      question.restoreImg,
                    ),
                  );
                }
                break;
              case 'explain':
                if ((question.explain?.isNotEmpty ?? false) ||
                    (question.explainImg?.isNotEmpty ?? false)) {
                  sectionWidgets.add(
                    _buildAnalysisSection(
                      context,
                      '答案解析',
                      Icons.lightbulb_outlined,
                      question.explain ?? '',
                      question.explainImg,
                    ),
                  );
                }
                break;
              case 'label':
                sectionWidgets.add(
                  QuestionLabelView(
                    key: const ValueKey('section_label'),
                    question: question,
                  ),
                );
                break;
              case 'note':
                sectionWidgets.add(
                  QuestionNoteView(
                    key: const ValueKey('section_note'),
                    question: question,
                  ),
                );
                break;
              case 'comment':
                sectionWidgets.add(
                  CommentPage(
                    key: ValueKey('comment_$index'),
                    question: question,
                    scrollController: scrollController,
                  ),
                );
                break;
            }
          }

          return ListView(
            controller: scrollController,
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            children: [
              ReadingContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    QuestionHeaderView(
                      question: question,
                      index: index,
                      totalCount: controller.questions.length,
                    ),
                    const SizedBox(height: 12),
                    QuestionOptionsView(
                      question: question,
                      userQuestion: userQuestion,
                      index: index,
                      controller: controller,
                      onStateChanged: onStateChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ...sectionWidgets,
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnalysisSection(
    BuildContext context,
    String title,
    IconData icon,
    String analysisText,
    String? storedImages,
  ) {
    const Color orangeAccent = Color(0xFFB39D6B);
    void copySection() {
      Clipboard.setData(ClipboardData(text: analysisText));
    }

    return ReadingContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: orangeAccent, size: 24),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: orangeAccent,
              ),
            ),
            const Spacer(),
            _CopyFeedbackButton(
              text: analysisText,
              tooltip: '复制$title',
              color: orangeAccent,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SelectionArea(
          contextMenuBuilder: (context, selectableRegionState) {
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: selectableRegionState.contextMenuAnchors,
              buttonItems: [
                ...selectableRegionState.contextMenuButtonItems,
                ContextMenuButtonItem(
                  label: '复制全部',
                  onPressed: () {
                    selectableRegionState.hideToolbar();
                    copySection();
                  },
                ),
              ],
            );
          },
          child: AnalysisTextWithImages(
            text: analysisText,
            storedImages: storedImages,
            legacyBaseUrl: _legacyImageBaseUrl,
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: Color(0x22888888)),
        ],
      ),
    );
  }

  String get _legacyImageBaseUrl {
    final nativeAppId = question.nativeAppId?.trim();
    final appId = nativeAppId != null && nativeAppId.isNotEmpty
        ? nativeAppId
        : question.appId?.trim();
    final number = question.number?.trim();
    if (appId == null || appId.isEmpty || number == null || number.isEmpty) {
      return '';
    }
    return 'https://ykb-app-files.yikaobang.com.cn/question/restore/$appId/$number';
  }
}

/// 复制成功后原地切换为绿色勾选图标，并在 1.5 秒后自动复原
class _CopyFeedbackButton extends StatefulWidget {
  final String text;
  final String tooltip;
  final Color color;

  const _CopyFeedbackButton({
    required this.text,
    required this.tooltip,
    required this.color,
  });

  @override
  State<_CopyFeedbackButton> createState() => _CopyFeedbackButtonState();
}

class _CopyFeedbackButtonState extends State<_CopyFeedbackButton> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleCopy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _copied
            ? const Icon(
                Icons.check_rounded,
                key: ValueKey('check'),
                size: 18,
                color: Colors.green,
              )
            : Icon(
                Icons.copy_rounded,
                key: const ValueKey('copy'),
                size: 18,
                color: widget.color,
              ),
      ),
      tooltip: _copied ? '已复制' : widget.tooltip,
      onPressed: _handleCopy,
    );
  }
}

