import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/question.dart';
import '../../models/question_section_config.dart';
import '../comment_page.dart';
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
                  Column(
                    key: const ValueKey('section_answer_stat'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '答案：正确答案 $answer, 你的答案 ',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            userAnswer,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: userQuestion.status == 1
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
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
                );
                break;
              case 'restore':
                if (question.restore != null && question.restore!.isNotEmpty) {
                  sectionWidgets.add(
                    _buildAnalysisSection(
                      context,
                      '考点还原',
                      Icons.location_on_outlined,
                      question.restore!,
                    ),
                  );
                }
                break;
              case 'explain':
                if (question.explain != null && question.explain!.isNotEmpty) {
                  sectionWidgets.add(
                    _buildAnalysisSection(
                      context,
                      '答案解析',
                      Icons.lightbulb_outlined,
                      question.explain!,
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
  ) {
    const Color orangeAccent = Color(0xFFB39D6B);
    void copySection() {
      Clipboard.setData(ClipboardData(text: analysisText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title已复制'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    return Column(
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
            IconButton(
              icon:
                  const Icon(Icons.copy_rounded, size: 18, color: orangeAccent),
              tooltip: '复制$title',
              onPressed: copySection,
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
          child: _buildTextWithImage(
            context,
            analysisText,
            'https://ykb-app-files.yikaobang.com.cn/question/restore/${question.nativeAppId}/${question.number}',
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: Color(0x22888888)),
      ],
    );
  }

  Widget _buildTextWithImage(BuildContext context, String text, String imgUrl) {
    final RegExp regex = RegExp(r'(?:[0-9\u4e00-\u9fa5]+)?P\d+(?:-P\d+)?');
    final List<String> parts = text.split(regex);
    final List<String> imageUrls = [];
    final List<String> matches =
        regex.allMatches(text).map((match) => match.group(0)!).toList();

    for (int i = 0; i < matches.length; i++) {
      parts.insert(2 * i + 1, matches[i]);
      imageUrls.insert(
        i,
        "$imgUrl${matches[i]}-${i + 1}.jpg?x-oss-process=style/water_mark",
      );
    }

    return Text.rich(
      TextSpan(
        children: List.generate(parts.length, (index) {
          if (index.isEven) {
            return _buildTextWithBold(parts[index]);
          } else {
            return WidgetSpan(
              child: ElevatedButton(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(EdgeInsets.zero),
                  minimumSize: WidgetStateProperty.all(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  elevation: WidgetStateProperty.all(0),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      parts[index],
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const Icon(
                      Icons.photo,
                      size: 18,
                      color: Colors.deepOrange,
                    )
                  ],
                ),
                onPressed: () {
                  showFullScreenImage(
                    context,
                    imageUrls,
                    index ~/ 2,
                  );
                },
              ),
            );
          }
        }),
      ),
    );
  }

  TextSpan _buildTextWithBold(String text) {
    final RegExp regex = RegExp(r'（[A-Z](对|错)(，为本题正确答案)?）');
    final List<String> parts = text.split(regex);
    final List<String> matches =
        regex.allMatches(text).map((match) => match.group(0)!).toList();

    for (int i = 0; i < matches.length; i++) {
      parts.insert(2 * i + 1, matches[i]);
    }

    return TextSpan(
      children: List.generate(parts.length, (index) {
        if (index.isEven) {
          return TextSpan(
            text: parts[index],
            style: const TextStyle(
              fontSize: 16,
              height: 1.8,
            ),
          );
        } else {
          return TextSpan(
            text: parts[index],
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              height: 1.8,
            ),
          );
        }
      }),
    );
  }
}
