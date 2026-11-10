import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/shortcut_config.dart';
import '../../models/chapter.dart';
import '../../db/database_helper.dart';
import '../../models/question.dart';
import '../../services/ykb_sync_service.dart';

/// 题目详情页状态管理控制器
///
/// 采用精准订阅模式（基于 ValueNotifier/ChangeNotifier），
/// 将高频的 1 秒定时器、单题作答刷新、页码切换与全局组件解耦，
/// 彻底避免每秒全树 setState() 重绘。
class QuestionDetailController extends ChangeNotifier
    with WidgetsBindingObserver {
  final Set<Future<void>> _pendingWrites = {};
  bool _disposed = false;
  final Stopwatch _answerWatch = Stopwatch()..start();
  bool _foreground = true;
  Object? lastSaveError;
  Future<MapEntry<int, int>>? _finishing;
  bool _changingMode = false;
  bool get isSaving =>
      _pendingWrites.isNotEmpty || _finishing != null || _changingMode;
  final Map<String, int> _unsavedTestTime = {};
  final Map<String, UserQuestion> _pendingTestSelections = {};
  Future<void> _persistTestTime(String id, int ms) async {
    final db = await UserDBHelper().database;
    await db.transaction((tx) async {
      await tx.rawInsert(
        'INSERT OR IGNORE INTO QuestionTestTime(question_id,duration_ms) VALUES (?,0)',
        [id],
      );
      await tx.rawUpdate(
        'UPDATE QuestionTestTime SET duration_ms=duration_ms+? WHERE question_id=?',
        [ms, id],
      );
    });
    final remaining = (_unsavedTestTime[id] ?? 0) - ms;
    if (remaining <= 0) {
      _unsavedTestTime.remove(id);
    } else {
      _unsavedTestTime[id] = remaining;
    }
  }

  void _captureTestTime(int index) {
    if (_mode != 2 ||
        _finishing != null ||
        index < 0 ||
        index >= questions.length) {
      return;
    }
    final ms = _answerWatch.elapsedMilliseconds;
    _answerWatch.reset();
    if (ms == 0) return;
    final id = questions[index].id;
    _unsavedTestTime[id] = (_unsavedTestTime[id] ?? 0) + ms;
    trackLocalWrite(_persistTestTime(id, ms));
  }

  Future<MapEntry<int, int>> finishTestAndFlush() {
    if (_finishing != null) return _finishing!;
    final work = _finishTestAndFlush();
    _finishing = work;
    return work.whenComplete(() => _finishing = null);
  }

  Future<MapEntry<int, int>> _finishTestAndFlush() async {
    _captureTestTime(_currentPage);
    if (_mode == 2) {
      _stopTestTimer();
      _answerWatch.stop();
    }
    try {
      await flushPendingWrites();
      // 弱盘/锁冲突时选答可能尚未落库；交卷先重试保存，再判分。
      for (final entry in Map<String, UserQuestion>.from(
        _pendingTestSelections,
      ).entries) {
        final q = questions.firstWhere((q) => q.id == entry.key);
        await updateQuestionSimple(
          entry.value,
          q,
          fields: const {'status', 'user_answer'},
        );
        if (identical(_pendingTestSelections[entry.key], entry.value)) {
          _pendingTestSelections.remove(entry.key);
        }
      }
      for (final entry in Map<String, int>.from(_unsavedTestTime).entries) {
        await _persistTestTime(entry.key, entry.value);
      }
      if (_mode != 2) return const MapEntry(0, 0);
      final result = await gradePendingQuestions(
        questions,
        userQuestions,
        bankId: bankId,
      );
      _mode = 0;
      _testBaseMs = 0;
      _answerWatch.reset();
      if (_foreground) _answerWatch.start();
      if (!_disposed) {
        modeNotifier.value = 0;
        _updateAnsweredCount();
        notifyListeners();
      }
      await _saveSettings();
      await _saveTestElapsed(0);
      return result;
    } catch (_) {
      if (!_disposed && _mode == 2) {
        if (_foreground) {
          _testStopwatch.start();
          _answerWatch.start();
        }
        _testTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          elapsedNotifier.value = testElapsed;
        });
      }
      rethrow;
    }
  }

  void trackLocalWrite(
    Future<void> write, {
    BuildContext? context,
    VoidCallback? rollback,
    VoidCallback? onSaved,
  }) {
    late Future<void> pending;
    pending = write
        .then((_) {
          lastSaveError = null;
          onSaved?.call();
        })
        .catchError((Object error) {
          lastSaveError = error;
          if (!_disposed) {
            rollback?.call();
            if (context?.mounted == true) {
              ScaffoldMessenger.of(
                context!,
              ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
            }
            notifyListeners();
          }
        })
        .whenComplete(() => _pendingWrites.remove(pending));
    _pendingWrites.add(pending);
  }

  Future<void> flushPendingWrites() async {
    while (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList());
    }
  }

  void savePendingSelection(
    Question q,
    UserQuestion uq, {
    BuildContext? context,
  }) {
    final snapshot = UserQuestion.fromMap(uq.toMap());
    _pendingTestSelections[q.id] = snapshot;
    trackLocalWrite(
      updateQuestionSimple(
        snapshot,
        q,
        fields: const {'status', 'user_answer'},
      ),
      context: context,
      onSaved: () {
        if (identical(_pendingTestSelections[q.id], snapshot)) {
          _pendingTestSelections.remove(q.id);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _captureTestTime(_currentPage);
      if (_mode == 2) {
        _testStopwatch.stop();
        trackLocalWrite(_saveTestElapsed(testElapsed.inMilliseconds));
      }
    } else if (_mode == 2) {
      _testStopwatch.start();
    }
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _answerWatch.start();
    } else {
      _answerWatch.stop();
    }
  }

  final Chapter chapter;
  final List<Question> questions;
  final List<UserQuestion> userQuestions;
  final String? bankId;
  final bool defaultShowCutContent;

  late final PageController pageController;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  int _mode = 0;
  int get mode => _mode;

  // 记录当前题目页的打开时间，用于计算单题作答时长（毫秒）
  late int pageOpenedAt;

  // 测试模式正计时：Stopwatch 记录当前段用时，仅通过 elapsedNotifier 驱动计时栏组件
  final Stopwatch _testStopwatch = Stopwatch();
  Timer? _testTicker;
  int _testBaseMs = 0;

  // 每个题目页独立的滚动控制器，供评论区无限滚动监听
  final Map<int, ScrollController> _scrollControllers = {};

  // 已斩题目临时显示内容的页码集合；未记录时使用 defaultShowCutContent
  final Map<int, bool> _cutContentReveal = {};

  // 局部精准刷新 Notifier
  final ValueNotifier<Duration> elapsedNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<int> answeredCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> currentPageNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> modeNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> fontScaleNotifier = ValueNotifier<double>(1.0);

  QuestionDetailController({
    required this.chapter,
    required this.questions,
    required this.userQuestions,
    required int initialIndex,
    this.bankId,
    this.defaultShowCutContent = false,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _currentPage = initialIndex;
    currentPageNotifier.value = initialIndex;
    pageController = PageController(initialPage: initialIndex);
    pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
    _updateAnsweredCount();
  }

  Future<void> init({bool persistPosition = true}) async {
    await ShortcutConfig.load();
    if (_disposed) return;
    await _loadSettings();
    if (persistPosition && !_disposed) await _saveLastQIndex();
  }

  ScrollController controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, ScrollController.new);

  Duration get testElapsed =>
      Duration(milliseconds: _testBaseMs) + _testStopwatch.elapsed;

  void _updateAnsweredCount() {
    answeredCountNotifier.value = userQuestions
        .where((uq) => uq.status == 4)
        .length;
  }

  void _startTestTimer() {
    _testStopwatch
      ..reset()
      ..start();
    _testTicker?.cancel();
    elapsedNotifier.value = testElapsed;
    _testTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedNotifier.value = testElapsed;
    });
  }

  void _stopTestTimer() {
    _testTicker?.cancel();
    _testTicker = null;
    _testStopwatch.stop();
  }

  Future<void> _saveTestElapsed(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('testElapsedMs', ms);
  }

  String formatElapsed() {
    final Duration d = testElapsed;
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _mode = prefs.getInt('mode') ?? 0;
    modeNotifier.value = _mode;
    _testBaseMs = prefs.getInt('testElapsedMs') ?? 0;
    fontScaleNotifier.value = prefs.getDouble('fontScale') ?? 1.0;
    notifyListeners();

    if (_mode == 2) {
      _startTestTimer();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', _mode);
  }

  Future<void> _saveLastQIndex() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('lastQIndex')) {
      await prefs.setInt('lastQIndex', _currentPage);
    }
    debugPrint('保存上次做题记录: $_currentPage');
  }

  void nextPage() {
    pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void previousPage() {
    pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void onPageChanged(int page) {
    _captureTestTime(_currentPage);
    _currentPage = page;
    currentPageNotifier.value = page;
    pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
    _answerWatch.reset();
    if (_foreground) _answerWatch.start();
    _saveLastQIndex();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 快捷键交互
  // ------------------------------------------------------------------

  /// 是否临时显示已斩题目的内容（供斩题占位视图使用）。
  bool isCutContentRevealed(int index) {
    return _cutContentReveal[index] ?? defaultShowCutContent;
  }

  /// 切换当前题目已斩内容的显示状态。
  void toggleCutContentReveal(int index) {
    if (index < 0 || index >= userQuestions.length) return;
    final UserQuestion userQuestion = userQuestions[index];
    if (!userQuestion.isCut && userQuestion.status != 3) return;
    _cutContentReveal[index] = !isCutContentRevealed(index);
    notifyListeners();
  }

  /// 通过键盘选择第 [optionIndex] 个选项（从 0 开始）。
  ///
  /// 单选题选择后立即判题（与点击选项一致）；
  /// 多选题切换勾选状态，由「提交答案」快捷键提交。
  bool selectOptionByShortcut(int optionIndex, BuildContext context) {
    if (isSaving) return false;
    final int index = _currentPage;
    final Question question = questions[index];
    final UserQuestion userQuestion = userQuestions[index];

    if (_mode == 3) return false;
    if (userQuestion.isCut && !isCutContentRevealed(index)) return false;
    if (userQuestion.status == 1 ||
        userQuestion.status == 2 ||
        userQuestion.status == 3) {
      return false;
    }

    if (question.isSubjective) {
      if (optionIndex == 0) {
        submitSubjectiveAnswer(
          question,
          userQuestion,
          index,
          context,
          isCorrect: true,
        );
        return true;
      } else if (optionIndex == 1) {
        submitSubjectiveAnswer(
          question,
          userQuestion,
          index,
          context,
          isCorrect: false,
        );
        return true;
      }
      return false;
    }

    if (question.type != '1' && question.type != '2') return false;

    final List<dynamic> options = getOptionJson(question);
    if (optionIndex < 0 || optionIndex >= options.length) return false;
    final Object? option = options[optionIndex];
    final String optionKey = option is Map
        ? (option['key']?.toString() ?? '')
        : '';
    if (optionKey.isEmpty) return false;

    if (question.type == '1') {
      userQuestion.userAnswer = changeLastAnswer(
        userQuestion.userAnswer,
        optionKey,
      );
      submitAnswer(question, userQuestion, index, context);
    } else {
      final String currentAnswer = getLastAnswer(userQuestion.userAnswer);
      final String nextAnswer = currentAnswer.contains(optionKey)
          ? currentAnswer.replaceAll(optionKey, '')
          : '$currentAnswer$optionKey';
      userQuestion.userAnswer = changeLastAnswer(
        userQuestion.userAnswer,
        nextAnswer,
      );
      if (_mode == 2) {
        userQuestion.status = 4;
        userQuestions[index].status = 4;
        savePendingSelection(question, userQuestion, context: context);
      }
    }
    notifyListeners();
    return true;
  }

  /// 通过快捷键提交当前多选题答案（对应页面上的「提交」按钮）。
  bool submitCurrentAnswer(BuildContext context) {
    final int index = _currentPage;
    final Question question = questions[index];
    final UserQuestion userQuestion = userQuestions[index];

    if (_mode == 2 || _mode == 3) return false;
    if (question.type != '2') return false;
    if (userQuestion.isCut && !isCutContentRevealed(index)) return false;
    if (userQuestion.status == 1 ||
        userQuestion.status == 2 ||
        userQuestion.status == 3) {
      return false;
    }
    if (getLastAnswer(userQuestion.userAnswer).isEmpty) return false;

    submitAnswer(question, userQuestion, index, context);
    notifyListeners();
    return true;
  }

  /// 在当前题目内容中滚动。[direction] 为 1 向下、-1 向上。
  ///
  /// [byPage] 为 true 时按「翻页步长」滚动，否则按「连续滚动步长」滚动。
  void scrollCurrentPage(int direction, {bool byPage = true}) {
    final ScrollController scrollController = controllerFor(_currentPage);
    if (!scrollController.hasClients) return;
    final ScrollPosition position = scrollController.position;
    if (!position.hasContentDimensions) return;

    final double distance = byPage
        ? position.viewportDimension * ShortcutConfig.pageScrollPercent / 100
        : ShortcutConfig.lineScrollPixels.toDouble();
    final double target = (position.pixels + distance * direction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return;
    scrollController.animateTo(
      target,
      duration: Duration(milliseconds: byPage ? 180 : 80),
      curve: byPage ? Curves.easeOutCubic : Curves.easeOut,
    );
  }

  void submitAnswer(
    Question question,
    UserQuestion userQuestion,
    int index,
    BuildContext context, {
    VoidCallback? onStateChanged,
  }) {
    if (isSaving) return;
    final previousStatus = userQuestion.status;
    final int elapsedMs = _answerWatch.elapsedMilliseconds;
    final String userAnswer = getLastAnswer(userQuestion.userAnswer);

    if (question.type == '1' && userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('不能不填答案哦~'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    } else if (question.type == '2' && userAnswer.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('多选题要选择多个选项哦~'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    if (_mode == 2) {
      _captureTestTime(index);
      userQuestion.status = 4; // 测试模式 - 待提交
      savePendingSelection(question, userQuestion, context: context);
      userQuestions[index].status = 4;
      _updateAnsweredCount();
      onStateChanged?.call();
      nextPage();
    } else {
      final String correctAns = question.answer ?? '';
      if (correctAns.isNotEmpty &&
          sortString(userAnswer) == sortString(correctAns)) {
        userQuestion.status = 1; // 回答正确
      } else {
        userQuestion.status = 2; // 回答错误
      }
      final expectedStatus = userQuestion.status;
      trackLocalWrite(
        updateQuestion(
          userQuestion,
          question,
          durationMs: elapsedMs,
          bankId: bankId,
          chapter: chapter,
        ),
        context: context,
        rollback: () {
          if (userQuestion.status == expectedStatus) {
            userQuestion.status = previousStatus;
          }
          onStateChanged?.call();
        },
      );
      userQuestions[index].status = userQuestion.status;
      onStateChanged?.call();
      if (userQuestion.status == 1 && _mode == 1) {
        // 快刷模式自动翻页
        nextPage();
      }
    }
  }

  /// 主观题（填空/名词解释/简答/论述/病例分析等）自评作答提交
  void submitSubjectiveAnswer(
    Question question,
    UserQuestion userQuestion,
    int index,
    BuildContext context, {
    required bool isCorrect,
    VoidCallback? onStateChanged,
  }) {
    if (isSaving) return;
    final previousStatus = userQuestion.status;
    final int elapsedMs = _answerWatch.elapsedMilliseconds;

    userQuestion.userAnswer = isCorrect ? '已掌握' : '未掌握';

    if (_mode == 2) {
      _captureTestTime(index);
      userQuestion.status = 4; // 测试模式 - 待提交
      savePendingSelection(question, userQuestion, context: context);
      userQuestions[index].status = 4;
      _updateAnsweredCount();
      onStateChanged?.call();
      nextPage();
    } else {
      userQuestion.status = isCorrect ? 1 : 2;
      final expectedStatus = userQuestion.status;
      trackLocalWrite(
        updateQuestion(
          userQuestion,
          question,
          durationMs: elapsedMs,
          bankId: bankId,
          chapter: chapter,
        ),
        context: context,
        rollback: () {
          if (userQuestion.status == expectedStatus) {
            userQuestion.status = previousStatus;
          }
          onStateChanged?.call();
        },
      );
      userQuestions[index].status = userQuestion.status;
      onStateChanged?.call();
      if (userQuestion.status == 1 && _mode == 1) {
        // 快刷模式自动翻页
        nextPage();
      }
    }
    notifyListeners();
  }

  /// 修改主观题已作答状态（重新标记已掌握/未掌握）
  void updateSubjectiveStatus(
    Question question,
    UserQuestion userQuestion,
    int index, {
    required bool isCorrect,
    VoidCallback? onStateChanged,
  }) {
    userQuestion.userAnswer = isCorrect ? '已掌握' : '未掌握';
    userQuestion.status = isCorrect ? 1 : 2;
    trackLocalWrite(
      updateQuestion(
        userQuestion,
        question,
        durationMs: 0,
        bankId: bankId,
        chapter: chapter,
      ),
    );
    userQuestions[index].status = userQuestion.status;
    onStateChanged?.call();
    notifyListeners();
  }

  void toggleCollection(BuildContext context, {VoidCallback? onStateChanged}) {
    final UserQuestion userQuestion = userQuestions[_currentPage];
    final Question question = questions[_currentPage];
    final previous = userQuestion.collection;
    userQuestion.collection = previous == 0 ? 1 : 0;
    final sent = userQuestion.collection;
    trackLocalWrite(
      updateQuestionSimple(
        userQuestion,
        question,
        fields: const {'collection'},
      ),
      context: context,
      rollback: () {
        if (userQuestion.collection == sent) userQuestion.collection = previous;
        onStateChanged?.call();
      },
    );
    userQuestions[_currentPage].collection = userQuestion.collection;
    onStateChanged?.call();
    notifyListeners();
  }

  void toggleCut(BuildContext context, {VoidCallback? onStateChanged}) {
    final UserQuestion userQuestion = userQuestions[_currentPage];
    final Question question = questions[_currentPage];
    // 斩题状态变化后，重新收起临时显示的题目内容
    _cutContentReveal.remove(_currentPage);
    final previous = userQuestion.cutQuestion;
    userQuestion.isCut = !userQuestion.isCut;
    final cut = userQuestion.isCut;
    if (!cut && userQuestion.status == 3) userQuestion.status = 0;
    trackLocalWrite(
      updateQuestionSimple(
        userQuestion,
        question,
        fields: const {'cut_question'},
      ),
      context: context,
      rollback: () {
        if (userQuestion.isCut == cut) userQuestion.cutQuestion = previous;
        onStateChanged?.call();
      },
      onSaved: () => unawaited(
        YkbSyncService.instance.syncCutQuestion(
          question: question,
          isCut: cut,
          chapter: chapter,
        ),
      ),
    );
    userQuestions[_currentPage].cutQuestion = userQuestion.cutQuestion;
    onStateChanged?.call();
    notifyListeners();

    // 斩题后自动切到下一题
    if (userQuestion.isCut) {
      nextPage();
    }
  }

  void copyQuestion(BuildContext context) {
    final UserQuestion userQuestion = userQuestions[_currentPage];
    final Question question = questions[_currentPage];
    if (userQuestion.status == 0 || userQuestion.status == 3) {
      return;
    }

    final String userAnswer = getLastAnswer(userQuestion.userAnswer);
    final String answer = question.answer ?? '';
    final List<dynamic> optionJson = getOptionJson(question);
    String optionText = "";
    for (final option in optionJson) {
      final String key = option['key'];
      final String title = option['title'];
      optionText += '\n$key. $title';
    }
    final String copyText =
        '## 题目\n\n'
        '${question.publicTitle ?? ''}'
        '${question.title ?? ''}$optionText\n\n'
        '## 正确答案：$answer\n\n'
        '## 我的答案：$userAnswer\n\n'
        '## 参考解析\n\n${question.explain ?? ''}';
    Clipboard.setData(ClipboardData(text: copyText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('题目、答案、解析已复制，去问AI吧～'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> onModeChanged(int newMode, BuildContext context) async {
    if (newMode == _mode || _changingMode) return;
    _changingMode = true;
    try {
      final entering = newMode == 2;
      if (_mode == 2) {
        if (await confirmLeaveTest(context) != true ||
            !context.mounted ||
            _disposed) {
          return;
        }
        await finishTestAndFlush();
      }
      if (entering) {
        final db = await UserDBHelper().database;
        await db.transaction((tx) async {
          final ids = questions.map((q) => q.id).toList();
          for (var i = 0; i < ids.length; i += 500) {
            final chunk = ids.sublist(
              i,
              i + 500 < ids.length ? i + 500 : ids.length,
            );
            await tx.rawDelete(
              'DELETE FROM QuestionTestTime WHERE question_id IN (${List.filled(chunk.length, '?').join(',')})',
              chunk,
            );
          }
        });
      }
      if (_disposed) return;
      _mode = newMode;
      modeNotifier.value = newMode;
      notifyListeners();
      await _saveSettings();
      if (entering) {
        _answerWatch.reset();
        _startTestTimer();
      }
    } catch (e) {
      lastSaveError = e;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换模式失败：$e')));
      }
    } finally {
      _changingMode = false;
    }
  }

  Future<bool?> confirmLeaveTest(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出测试模式'),
          content: const Text('退出测试将自动交卷并判分已作答内容，确定继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
  }

  Future<void> submitTest(BuildContext context) async {
    if (_mode != 2) return;
    final bool? confirmed = await confirmSubmit(context);
    if (confirmed != true) return;

    if (!context.mounted || _disposed) return;
    final String used = formatElapsed();
    MapEntry<int, int> result;
    try {
      result = await finishTestAndFlush();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('交卷失败，请重试：$e')));
      }
      return;
    }

    final int answered = result.key;
    final int correct = result.value;
    final int unanswered = questions.length - answered;
    if (context.mounted) {
      showResultDialog(context, answered, correct, unanswered, used);
    }
  }

  Future<bool?> confirmSubmit(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('交卷确认'),
          content: const Text('确定要交卷吗？交卷后将公布成绩。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('交卷'),
            ),
          ],
        );
      },
    );
  }

  void showResultDialog(
    BuildContext context,
    int answered,
    int correct,
    int unanswered,
    String used,
  ) {
    final double accuracy = answered == 0 ? 0.0 : correct / answered * 100;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('测试结果'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _resultLine('已作答', '$answered 题'),
              _resultLine('答对', '$correct 题'),
              _resultLine('答错', '${answered - correct} 题'),
              _resultLine('正确率', '${accuracy.toStringAsFixed(1)}%'),
              _resultLine('未作答', '$unanswered 题'),
              _resultLine('用时', used),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  static Widget _resultLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static List<dynamic> getOptionJson(Question question) {
    const defaultOptionString = '''[{
        "title": "A选项加载失败",
        "img": "",
        "key": "A",
        "img_height": "0",
        "img_width": "0"
      },
      {
        "title": "B选项加载失败",
        "img": "",
        "key": "B",
        "img_height": "0",
        "img_width": "0"
      },
      {
        "title": "C选项加载失败",
        "img": "",
        "key": "C",
        "img_height": "0",
        "img_width": "0"
      }
    ]''';

    try {
      return json.decode(question.option ?? defaultOptionString);
    } catch (_) {
      return json.decode(defaultOptionString);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _captureTestTime(_currentPage);
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _answerWatch.stop();
    if (_mode == 2) {
      _testStopwatch.stop();
      _testTicker?.cancel();
      trackLocalWrite(_saveTestElapsed(testElapsed.inMilliseconds));
    } else {
      _testTicker?.cancel();
    }
    for (final ScrollController c in _scrollControllers.values) {
      c.dispose();
    }
    elapsedNotifier.dispose();
    answeredCountNotifier.dispose();
    currentPageNotifier.dispose();
    modeNotifier.dispose();
    fontScaleNotifier.dispose();
    pageController.dispose();
    super.dispose();
  }
}
