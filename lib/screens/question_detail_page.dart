import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_strings.dart';
import '../common/shortcut_config.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import 'question_detail/chapter_cross_indicator.dart';
import 'question_detail/question_detail_controller.dart';
import 'question_detail/question_page_item.dart';
import 'question_detail/question_test_bar.dart';

/// 支持鼠标与触控板拖动、统一使用 Bouncing 弹性回弹的自定义滚动行为
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

/// 跨章节边缘滑动状态别名
typedef _OverscrollState = ChapterCrossOverscrollState;

/// 题目详情页面（刷题核心主页面）
///
/// 架构重构后作为纯粹的顶层协调容器，业务状态与计时逻辑
/// 委托给 [QuestionDetailController]，并解耦为各独立子组件，彻底终结全树 setState()。
///
/// 原生支持跨章节顺滑翻页（首题/末题滑动阻尼动效 + 释放进入上/下一章节）。
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
  late Chapter _currentChapter;
  late List<Question> _questions;
  late List<UserQuestion> _userQuestions;
  late QuestionDetailController _controller;

  /// 同一学科下的所有章节列表
  List<Chapter> _siblingChapters = [];
  Chapter? _prevChapter;
  Chapter? _nextChapter;
  bool _isSwitchingChapter = false;
  bool _isLeaving = false;
  double _transitionDirection = 1.0;
  Key _chapterKey = UniqueKey();

  /// 预加载相邻章节题目缓存，杜绝切换时的网络/磁盘卡顿
  final Map<String, List<Question>> _prefetchedQuestions = {};

  /// 边缘持续滑动状态 Notifier（仅驱动微指示器局部渲染，不触发整页重绘）
  final ValueNotifier<_OverscrollState> _overscrollNotifier =
      ValueNotifier<_OverscrollState>(const _OverscrollState());

  /// 章节切换顶部浮现 Badge 提示
  final ValueNotifier<String?> _switchBannerNotifier = ValueNotifier<String?>(
    null,
  );
  Timer? _switchBannerTimer;

  bool _hasTriggeredHaptic = false;
  static const double _overscrollThreshold = 85.0;

  /// 松手时准备触发切章的目标状态
  Chapter? _targetChapterToTrigger;
  bool _isTriggeringNext = false;
  bool _canTriggerChapter = false;

  /// 捕获刷题页快捷键的焦点节点（页面打开时自动获得焦点）
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'question-shortcuts',
  );

  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapter;
    _questions = widget.questions;
    _userQuestions = widget.userQuestions;

    _controller = QuestionDetailController(
      chapter: _currentChapter,
      questions: _questions,
      userQuestions: _userQuestions,
      initialIndex: widget.questionIndex,
      bankId: widget.bankId,
      defaultShowCutContent: widget.defaultShowCutContent,
    );
    _controller.init();
    _loadSiblingChapters();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _switchBannerTimer?.cancel();
    _overscrollNotifier.dispose();
    _switchBannerNotifier.dispose();
    _shortcutFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 异步加载当前学科下所有章节并计算上一章与下一章
  Future<void> _loadSiblingChapters() async {
    try {
      final siblings = await getSiblingChapters(_currentChapter);
      if (!mounted) return;
      setState(() {
        _siblingChapters = siblings;
        _updatePrevNextChapters();
      });
      _prefetchAdjacentChapters();
    } catch (e) {
      debugPrint('[QuestionDetailPage] 加载同级章节失败：$e');
    }
  }

  void _updatePrevNextChapters() {
    if (_siblingChapters.isEmpty) {
      _prevChapter = null;
      _nextChapter = null;
      return;
    }
    final index = _siblingChapters.indexWhere(
      (c) => c.id == _currentChapter.id,
    );
    if (index == -1) {
      _prevChapter = null;
      _nextChapter = null;
      return;
    }
    _prevChapter = index > 0 ? _siblingChapters[index - 1] : null;
    _nextChapter = index < _siblingChapters.length - 1
        ? _siblingChapters[index + 1]
        : null;
  }

  /// 后台极速静默预取相邻章节题目，切换时 0 延迟
  Future<void> _prefetchAdjacentChapters() async {
    final toFetch = [_prevChapter, _nextChapter].whereType<Chapter>();
    for (final ch in toFetch) {
      if (_prefetchedQuestions.containsKey(ch.id)) continue;
      try {
        final qs = await getQuestionsFromChapter(ch);
        _prefetchedQuestions[ch.id] = qs;
      } catch (_) {}
    }
  }

  /// 监听屏幕抬手或触控板释放事件（在松手的瞬间立即触发切章）
  void _handleTriggerRelease() {
    if (_canTriggerChapter &&
        _targetChapterToTrigger != null &&
        !_isSwitchingChapter) {
      final target = _targetChapterToTrigger!;
      final toFirst = _isTriggeringNext;
      _canTriggerChapter = false;
      _targetChapterToTrigger = null;
      _overscrollNotifier.value = const _OverscrollState();
      _hasTriggeredHaptic = false;
      _switchToChapter(target, toFirstQuestion: toFirst);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _canTriggerChapter = false;
    _targetChapterToTrigger = null;
    _overscrollNotifier.value = const _OverscrollState();
    _hasTriggeredHaptic = false;
  }

  /// 监听 PageView 边缘滑动手势（支持首题右滑进上一章、末题左滑进下一章）
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (_isSwitchingChapter) return false;

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _handleTriggerRelease();
    }

    if (notification is ScrollUpdateNotification) {
      final currentPage = _controller.currentPage;
      final pixels = notification.metrics.pixels;
      final maxExtent = notification.metrics.maxScrollExtent;

      // 处于第一题且向右拖动（超出左侧边界）
      if (currentPage == 0 && pixels < 0) {
        final dist = -pixels;
        _overscrollNotifier.value = _OverscrollState(
          isNext: false,
          distance: dist,
          targetChapter: _prevChapter,
        );
        _targetChapterToTrigger = _prevChapter;
        _isTriggeringNext = false;
        if (dist >= _overscrollThreshold && _prevChapter != null) {
          _canTriggerChapter = true;
          if (!_hasTriggeredHaptic) {
            _hasTriggeredHaptic = true;
            HapticFeedback.mediumImpact();
          }
        }
      }
      // 处于最后一题且向左拖动（超出右侧边界）
      else if (currentPage >= _questions.length - 1 && pixels > maxExtent) {
        final dist = pixels - maxExtent;
        _overscrollNotifier.value = _OverscrollState(
          isNext: true,
          distance: dist,
          targetChapter: _nextChapter,
        );
        _targetChapterToTrigger = _nextChapter;
        _isTriggeringNext = true;
        if (dist >= _overscrollThreshold && _nextChapter != null) {
          _canTriggerChapter = true;
          if (!_hasTriggeredHaptic) {
            _hasTriggeredHaptic = true;
            HapticFeedback.mediumImpact();
          }
        }
      }
      // 在正常范围内
      else if (_overscrollNotifier.value.distance > 0) {
        _overscrollNotifier.value = const _OverscrollState();
      }
    } else if (notification is ScrollEndNotification) {
      _handleTriggerRelease();
    }
    return false;
  }

  /// 跨章节平滑切入
  Future<void> _switchToChapter(
    Chapter targetChapter, {
    required bool toFirstQuestion,
  }) async {
    if (_isSwitchingChapter || _isLeaving) return;
    _isSwitchingChapter = true;
    final oldController = _controller;
    QuestionDetailController? next;
    var installed = false;
    try {
      if (oldController.mode == 2) {
        final confirmed = await oldController.confirmLeaveTest(context);
        if (confirmed != true || !mounted || _isLeaving) return;
      }
      await oldController.finishTestAndFlush();
      if (!mounted || _isLeaving) return;
      final newQuestions =
          _prefetchedQuestions[targetChapter.id] ??
          await getQuestionsFromChapter(targetChapter);
      if (newQuestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('《${targetChapter.name}》暂无可做题目')),
          );
        }
        return;
      }
      final newUserQuestions = await getUserQuestions(
        Future.value(newQuestions),
      );
      if (!mounted || _isLeaving) return;
      final index = toFirstQuestion ? 0 : newQuestions.length - 1;
      next = QuestionDetailController(
        chapter: targetChapter,
        questions: newQuestions,
        userQuestions: newUserQuestions,
        initialIndex: index,
        bankId: widget.bankId,
        defaultShowCutContent: widget.defaultShowCutContent,
      );
      await next.init(persistPosition: false);
      if (!mounted || _isLeaving) return;
      setState(() {
        _currentChapter = targetChapter;
        _questions = newQuestions;
        _userQuestions = newUserQuestions;
        _controller = next!;
        _transitionDirection = toFirstQuestion ? 1 : -1;
        _chapterKey = UniqueKey();
        _updatePrevNextChapters();
      });
      installed = true;
      oldController.dispose();
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        await prefs.setString('lastChapterId', targetChapter.id);
        await prefs.setString('lastSubjectId', targetChapter.subjectId);
        await prefs.setInt('lastQIndex', index);
        _prefetchAdjacentChapters();
        _showChapterSwitchBadge(targetChapter, index + 1, newQuestions.length);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换章节失败：$e')));
      }
    } finally {
      if (!installed) next?.dispose();
      _isSwitchingChapter = false;
    }
  }

  void _showChapterSwitchBadge(Chapter chapter, int currentIndex, int total) {
    _switchBannerTimer?.cancel();
    _switchBannerNotifier.value =
        '已进入：${chapter.name}（第 $currentIndex / $total 题）';
    _switchBannerTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _switchBannerNotifier.value = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isLeaving) return;
        _isLeaving = true;
        final controller = _controller;
        var popped = false;
        try {
          if (controller.mode == 2) {
            final confirmed = await controller.confirmLeaveTest(context);
            if (confirmed != true || !context.mounted) return;
          }
          await controller.finishTestAndFlush();
          if (context.mounted) {
            Navigator.of(context).pop(_currentChapter);
            popped = true;
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('保存或交卷失败：$e')));
          }
        } finally {
          if (!popped) _isLeaving = false;
        }
      },
      child: ValueListenableBuilder<double>(
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
              title: Text(
                _currentChapter.name,
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
                        Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerUp: (_) => _handleTriggerRelease(),
                          onPointerPanZoomEnd: (_) => _handleTriggerRelease(),
                          onPointerCancel: _handlePointerCancel,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleScrollNotification,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final inOffset = Tween<Offset>(
                                  begin: Offset(_transitionDirection, 0.0),
                                  end: Offset.zero,
                                ).animate(animation);
                                return SlideTransition(
                                  position: inOffset,
                                  child: child,
                                );
                              },
                              child: KeyedSubtree(
                                key: _chapterKey,
                                child: PageView.builder(
                                  controller: _controller.pageController,
                                  onPageChanged: _controller.onPageChanged,
                                  itemCount: _questions.length,
                                  itemBuilder: (context, index) {
                                    return QuestionPageItem(
                                      key: ValueKey(_questions[index].id),
                                      question: _questions[index],
                                      userQuestion: _userQuestions[index],
                                      index: index,
                                      controller: _controller,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 跨章节滑动边缘指示器
                        ValueListenableBuilder<_OverscrollState>(
                          valueListenable: _overscrollNotifier,
                          builder: (context, state, _) {
                            return ChapterCrossIndicator(
                              isNext: state.isNext,
                              overscrollDistance: state.distance,
                              threshold: _overscrollThreshold,
                              targetChapter: state.targetChapter,
                            );
                          },
                        ),

                        // 章节切换成功顶部悬浮通知
                        _buildFloatingSwitchBanner(),

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
      ),
    );
  }

  /// 章节切换顶部浮现小徽章
  Widget _buildFloatingSwitchBanner() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Positioned(
      top: 16,
      left: 20,
      right: 20,
      child: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: _switchBannerNotifier,
          builder: (context, bannerText, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0.0, -0.4),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                  child: child,
                ),
              ),
              child: bannerText == null
                  ? const SizedBox.shrink()
                  : Material(
                      elevation: 4,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      color: scheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_stories_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                bannerText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            );
          },
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

    final int index = _controller.currentPage;
    if (index < 0 || index >= _questions.length) return null;
    final Question question = _questions[index];
    final UserQuestion userQuestion = _userQuestions[index];

    // 已作答客观题禁止通过快捷键再次改选
    if (question.type == '3') {
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
        if (_controller.currentPage < _questions.length - 1) {
          _controller.nextPage();
        } else if (_nextChapter != null) {
          _switchToChapter(_nextChapter!, toFirstQuestion: true);
        }
        break;
      case ShortcutAction.previousQuestion:
        if (_controller.currentPage > 0) {
          _controller.previousPage();
        } else if (_prevChapter != null) {
          _switchToChapter(_prevChapter!, toFirstQuestion: false);
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
            final bool isAtFirst = currentPage == 0;
            final bool isAtLast = currentPage >= _questions.length - 1;
            final bool canPrev = !isAtFirst || _prevChapter != null;
            final bool canNext = !isAtLast || _nextChapter != null;

            return Stack(
              children: [
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: Tooltip(
                    message: isAtFirst && _prevChapter != null
                        ? '返回上一章：${_prevChapter!.name}'
                        : '上一题',
                    child: ElevatedButton(
                      onPressed: !canPrev
                          ? null
                          : () {
                              if (!isAtFirst) {
                                _controller.previousPage();
                              } else if (_prevChapter != null) {
                                _switchToChapter(
                                  _prevChapter!,
                                  toFirstQuestion: false,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(15),
                        elevation: 3,
                        backgroundColor: isAtFirst && _prevChapter != null
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      child: Icon(
                        isAtFirst && _prevChapter != null
                            ? Icons.keyboard_double_arrow_left_rounded
                            : Icons.arrow_left,
                        size: 50,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Tooltip(
                    message: isAtLast && _nextChapter != null
                        ? '进入下一章：${_nextChapter!.name}'
                        : '下一题',
                    child: ElevatedButton(
                      onPressed: !canNext
                          ? null
                          : () {
                              if (!isAtLast) {
                                _controller.nextPage();
                              } else if (_nextChapter != null) {
                                _switchToChapter(
                                  _nextChapter!,
                                  toFirstQuestion: true,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(15),
                        elevation: 3,
                        backgroundColor: isAtLast && _nextChapter != null
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      child: Icon(
                        isAtLast && _nextChapter != null
                            ? Icons.keyboard_double_arrow_right_rounded
                            : Icons.arrow_right,
                        size: 50,
                      ),
                    ),
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
