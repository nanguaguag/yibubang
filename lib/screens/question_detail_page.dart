import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../common/app_strings.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import 'question_detail/question_detail_controller.dart';
import 'question_detail/question_page_item.dart';
import 'question_detail/question_test_bar.dart';

/// 支持鼠标与触控板拖动的自定义滚动行为
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

/// 题目详情页面（刷题核心主页面）
///
/// 架构重构后作为纯粹的顶层协调容器，业务状态与计时逻辑
/// 委托给 [QuestionDetailController]，并解耦为各独立子组件，彻底终结全树 setState()。
class QuestionDetailPage extends StatefulWidget {
  final Chapter chapter;
  final List<Question> questions;
  final List<UserQuestion> userQuestions;
  final int questionIndex;
  final String? bankId;

  const QuestionDetailPage({
    super.key,
    required this.chapter,
    required this.questions,
    required this.userQuestions,
    required this.questionIndex,
    this.bankId,
  });

  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  late final QuestionDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuestionDetailController(
      chapter: widget.chapter,
      questions: widget.questions,
      userQuestions: widget.userQuestions,
      initialIndex: widget.questionIndex,
      bankId: widget.bankId,
    );
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _controller.fontScaleNotifier,
      builder: (context, fontScale, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child!,
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.chapter.name,
            overflow: TextOverflow.ellipsis,
          ),
          centerTitle: true,
          actions: <Widget>[
            _buildCutQuestionBtn(),
            _buildCopyBtn(),
            _buildCollectionBtn(),
            _buildModeMenu(),
          ],
        ),
        body: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _controller.modeNotifier,
              builder: (context, mode, _) {
                if (mode == 2) {
                  return QuestionTestInfoBar(controller: _controller);
                }
                return const SizedBox.shrink();
              },
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: MyCustomScrollBehavior(),
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _controller.pageController,
                      onPageChanged: _controller.onPageChanged,
                      itemCount: _controller.questions.length,
                      itemBuilder: (context, index) {
                        return QuestionPageItem(
                          question: _controller.questions[index],
                          userQuestion: _controller.userQuestions[index],
                          index: index,
                          controller: _controller,
                        );
                      },
                    ),
                    _buildDesktopNavigation(),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _controller.modeNotifier,
              builder: (context, mode, _) {
                if (mode == 2) {
                  return QuestionTestSubmitBar(
                    onSubmit: () => _controller.submitTest(context),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCutQuestionBtn() {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_controller, _controller.currentPageNotifier]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        return IconButton(
          icon: !uq.isCut
              ? const Icon(Icons.block)
              : const Icon(Icons.block_outlined, color: Colors.redAccent),
          onPressed: () => _controller.toggleCut(context),
        );
      },
    );
  }

  Widget _buildCopyBtn() {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_controller, _controller.currentPageNotifier]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        if (uq.status == 0 || uq.status == 3) {
          return const SizedBox.shrink();
        }
        return IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () => _controller.copyQuestion(context),
        );
      },
    );
  }

  Widget _buildCollectionBtn() {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_controller, _controller.currentPageNotifier]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        return IconButton(
          icon: uq.collection == 0
              ? const Icon(Icons.favorite_outline)
              : const Icon(Icons.favorite, color: Colors.redAccent),
          onPressed: () => _controller.toggleCollection(context),
        );
      },
    );
  }

  Widget _buildModeMenu() {
    return ValueListenableBuilder<int>(
      valueListenable: _controller.modeNotifier,
      builder: (context, currentMode, _) {
        return PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert),
          onSelected: (val) => _controller.onModeChanged(val, context),
          itemBuilder: (context) {
            return List.generate(AppStrings.modesList.length, (index) {
              return PopupMenuItem<int>(
                value: index,
                child: Row(
                  children: [
                    Text(AppStrings.modesList[index]),
                    const SizedBox(width: 8),
                    if (currentMode == index) const Icon(Icons.check, size: 20),
                  ],
                ),
              );
            });
          },
        );
      },
    );
  }

  Widget _buildDesktopNavigation() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return ValueListenableBuilder<int>(
          valueListenable: _controller.currentPageNotifier,
          builder: (context, currentPage, _) {
            return Stack(
              children: [
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: ElevatedButton(
                    onPressed: currentPage == 0 ? null : _controller.previousPage,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(15),
                      elevation: 3,
                    ),
                    child: const Icon(Icons.arrow_left, size: 50),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: ElevatedButton(
                    onPressed: currentPage == _controller.questions.length - 1
                        ? null
                        : _controller.nextPage,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(15),
                      elevation: 3,
                    ),
                    child: const Icon(Icons.arrow_right, size: 50),
                  ),
                ),
              ],
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
