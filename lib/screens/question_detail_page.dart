import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/app_strings.dart';
import '../common/shortcut_config.dart';
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
  final bool defaultShowCutContent;

  const QuestionDetailPage({
    super.key,
    required this.chapter,
    required this.questions,
    required this.userQuestions,
    required this.questionIndex,
    this.bankId,
    this.defaultShowCutContent = false,
  });

  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  late final QuestionDetailController _controller;

  /// 捕获刷题页快捷键的焦点节点（页面打开时自动获得焦点）
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'question-shortcuts',
  );

  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _controller = QuestionDetailController(
      chapter: widget.chapter,
      questions: widget.questions,
      userQuestions: widget.userQuestions,
      initialIndex: widget.questionIndex,
      bankId: widget.bankId,
      defaultShowCutContent: widget.defaultShowCutContent,
    );
    _controller.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _controller.fontScaleNotifier,
      builder: (context, fontScale, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child!,
        );
      },
      child: Focus(
        focusNode: _shortcutFocusNode,
        autofocus: true,
        onKeyEvent: _handleShortcutKeyEvent,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.chapter.name, overflow: TextOverflow.ellipsis),
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
                            key: ValueKey(_controller.questions[index].id),
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
      ),
    );
  }

  // ------------------------------------------------------------------
  // 键盘快捷键
  // ------------------------------------------------------------------

  KeyEventResult _handleShortcutKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 弹窗、底部面板等覆盖路由打开时不响应，避免误触底层题目
    if (_route != null && !_route!.isCurrent) {
      return KeyEventResult.ignored;
    }
    // 文本输入框获得焦点时，按键交给输入框处理
    if (_isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final bool isRepeat = event is KeyRepeatEvent;

    // 选项键（数字 / 字母）优先于功能快捷键；长按不重复切换选项
    if (!isRepeat) {
      final int? optionIndex = _resolveOptionIndex(event.logicalKey);
      if (optionIndex != null) {
        _controller.selectOptionByShortcut(optionIndex, context);
        return KeyEventResult.handled;
      }
    }

    for (final ShortcutAction action in ShortcutAction.values) {
      if (action == ShortcutAction.toggleFullscreen) continue;
      if (isRepeat && !action.allowsRepeat) continue;
      for (final KeyBinding binding in ShortcutConfig.bindingsFor(action)) {
        if (!binding.matches(event.logicalKey)) continue;
        _runShortcutAction(action);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _isTextInputFocused() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// 将按下的键解析为当前题目的选项序号（0 起），未命中返回 null。
  int? _resolveOptionIndex(LogicalKeyboardKey key) {
    // 带 Ctrl / Alt / Meta 的组合键不应误触发选项选择
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return null;
    }

    final int page = _controller.currentPage;
    final Question question = _controller.questions[page];
    if (question.type != '1' && question.type != '2') return null;
    final UserQuestion userQuestion = _controller.userQuestions[page];
    if (userQuestion.isCut && !_controller.isCutContentRevealed(page)) {
      return null;
    }
    if (_controller.mode == 3 ||
        userQuestion.status == 1 ||
        userQuestion.status == 2 ||
        userQuestion.status == 3) {
      return null;
    }

    final List<dynamic> options = QuestionDetailController.getOptionJson(
      question,
    );
    if (options.isEmpty) return null;

    final OptionKeyMode mode = ShortcutConfig.optionKeyMode;
    if (mode != OptionKeyMode.letter) {
      final int? index = ShortcutConfig.numberOptionIndex(key);
      if (index != null && index < options.length) return index;
    }

    if (mode != OptionKeyMode.number) {
      final String? letter = ShortcutConfig.letterOptionKey(key);
      if (letter != null) {
        for (int i = 0; i < options.length; i++) {
          final Object? item = options[i];
          final String optionKey = item is Map
              ? (item['key']?.toString().toUpperCase() ?? '')
              : '';
          if (optionKey == letter) return i;
        }
        // 选项未使用字母作为 key 时，按顺序退化映射
        final int fallback = letter.codeUnitAt(0) - 65;
        if (fallback >= 0 && fallback < options.length) return fallback;
      }
    }
    return null;
  }

  void _runShortcutAction(ShortcutAction action) {
    switch (action) {
      case ShortcutAction.toggleFullscreen:
        break; // 由应用级快捷键处理。
      case ShortcutAction.nextQuestion:
        if (_controller.currentPage < _controller.questions.length - 1) {
          _controller.nextPage();
        }
        break;
      case ShortcutAction.previousQuestion:
        if (_controller.currentPage > 0) {
          _controller.previousPage();
        }
        break;
      case ShortcutAction.submitAnswer:
        _controller.submitCurrentAnswer(context);
        break;
      case ShortcutAction.scrollPageDown:
        _controller.scrollCurrentPage(1);
        break;
      case ShortcutAction.scrollPageUp:
        _controller.scrollCurrentPage(-1);
        break;
      case ShortcutAction.scrollLineDown:
        _controller.scrollCurrentPage(1, byPage: false);
        break;
      case ShortcutAction.scrollLineUp:
        _controller.scrollCurrentPage(-1, byPage: false);
        break;
      case ShortcutAction.toggleCut:
        _controller.toggleCut(context);
        break;
      case ShortcutAction.toggleCollection:
        _controller.toggleCollection(context);
        break;
      case ShortcutAction.copyQuestion:
        _controller.copyQuestion(context);
        break;
      case ShortcutAction.toggleCutContent:
        _controller.toggleCutContentReveal(_controller.currentPage);
        break;
      case ShortcutAction.submitTest:
        _controller.submitTest(context);
        break;
    }
  }

  /// tooltip 中附带当前快捷键，便于发现键位。
  String _shortcutHint(ShortcutAction action) {
    final List<KeyBinding> bindings = ShortcutConfig.bindingsFor(action);
    if (bindings.isEmpty) return '';
    return '（${bindings.map((KeyBinding binding) => binding.label).join(' / ')}）';
  }

  Widget _buildCutQuestionBtn() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        _controller.currentPageNotifier,
      ]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        return IconButton(
          tooltip:
              '${uq.isCut ? '取消斩题' : '斩题'}${_shortcutHint(ShortcutAction.toggleCut)}',
          icon: !uq.isCut
              ? const Icon(Icons.content_cut)
              : const Icon(Icons.content_cut, color: Colors.redAccent),
          onPressed: () => _controller.toggleCut(context),
        );
      },
    );
  }

  Widget _buildCopyBtn() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        _controller.currentPageNotifier,
      ]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        if (uq.status == 0 || uq.status == 3) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: '复制题目${_shortcutHint(ShortcutAction.copyQuestion)}',
          icon: const Icon(Icons.copy),
          onPressed: () => _controller.copyQuestion(context),
        );
      },
    );
  }

  Widget _buildCollectionBtn() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        _controller.currentPageNotifier,
      ]),
      builder: (context, _) {
        final uq = _controller.userQuestions[_controller.currentPage];
        return IconButton(
          tooltip:
              '${uq.collection == 0 ? '收藏' : '取消收藏'}${_shortcutHint(ShortcutAction.toggleCollection)}',
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
                    onPressed: currentPage == 0
                        ? null
                        : _controller.previousPage,
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
