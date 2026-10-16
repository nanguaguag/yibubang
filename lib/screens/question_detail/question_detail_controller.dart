import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chapter.dart';
import '../../models/question.dart';

/// 题目详情页状态管理控制器
///
/// 采用精准订阅模式（基于 ValueNotifier/ChangeNotifier），
/// 将高频的 1 秒定时器、单题作答刷新、页码切换与全局组件解耦，
/// 彻底避免每秒全树 setState() 重绘。
class QuestionDetailController extends ChangeNotifier {
  final Chapter chapter;
  final List<Question> questions;
  final List<UserQuestion> userQuestions;
  final String? bankId;

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

  // 局部精准刷新 Notifier
  final ValueNotifier<Duration> elapsedNotifier = ValueNotifier<Duration>(Duration.zero);
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
  }) {
    _currentPage = initialIndex;
    currentPageNotifier.value = initialIndex;
    pageController = PageController(initialPage: initialIndex);
    pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
    _updateAnsweredCount();
  }

  Future<void> init() async {
    await _loadSettings();
    await _saveLastQIndex();
  }

  ScrollController controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, ScrollController.new);

  Duration get testElapsed =>
      Duration(milliseconds: _testBaseMs) + _testStopwatch.elapsed;

  void _updateAnsweredCount() {
    answeredCountNotifier.value =
        userQuestions.where((uq) => uq.status == 4).length;
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
    _currentPage = page;
    currentPageNotifier.value = page;
    pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
    _saveLastQIndex();
  }

  void submitAnswer(
    Question question,
    UserQuestion userQuestion,
    int index,
    BuildContext context, {
    VoidCallback? onStateChanged,
  }) {
    final int elapsedMs = (DateTime.now().millisecondsSinceEpoch - pageOpenedAt)
        .clamp(0, 1 << 62);
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
      userQuestion.status = 4; // 测试模式 - 待提交
      updateQuestionSimple(userQuestion, question);
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
      updateQuestion(userQuestion, question, durationMs: elapsedMs, bankId: bankId);
      userQuestions[index].status = userQuestion.status;
      onStateChanged?.call();
      if (userQuestion.status == 1 && _mode == 1) {
        // 快刷模式自动翻页
        nextPage();
      }
    }
  }

  void toggleCollection(BuildContext context, {VoidCallback? onStateChanged}) {
    final UserQuestion userQuestion = userQuestions[_currentPage];
    final Question question = questions[_currentPage];
    userQuestion.collection = userQuestion.collection == 0 ? 1 : 0;
    updateQuestionSimple(userQuestion, question);
    userQuestions[_currentPage].collection = userQuestion.collection;
    onStateChanged?.call();
    notifyListeners();
  }

  void toggleCut(BuildContext context, {VoidCallback? onStateChanged}) {
    final UserQuestion userQuestion = userQuestions[_currentPage];
    final Question question = questions[_currentPage];
    userQuestion.isCut = !userQuestion.isCut;
    updateQuestionSimple(userQuestion, question);
    userQuestions[_currentPage].cutQuestion = userQuestion.cutQuestion;
    onStateChanged?.call();
    notifyListeners();
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
    final String copyText = '## 题目\n\n'
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
    if (newMode == _mode) return;

    final bool enteringTest = newMode == 2;
    final bool leavingTest = _mode == 2;

    if (leavingTest) {
      final bool? confirmed = await confirmLeaveTest(context);
      if (confirmed != true) {
        return;
      }
      _stopTestTimer();
      _testBaseMs = 0;
      await _saveTestElapsed(0);
      await gradePendingQuestions(
        questions,
        userQuestions,
        bankId: bankId,
      );
      _updateAnsweredCount();
    }

    _mode = newMode;
    modeNotifier.value = newMode;
    notifyListeners();
    await _saveSettings();

    if (enteringTest) {
      _startTestTimer();
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

    _stopTestTimer();
    final String used = formatElapsed();
    final MapEntry<int, int> result = await gradePendingQuestions(
      questions,
      userQuestions,
      bankId: bankId,
    );

    _mode = 0;
    modeNotifier.value = 0;
    _testBaseMs = 0;
    _updateAnsweredCount();
    notifyListeners();

    await _saveSettings();
    await _saveTestElapsed(0);

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
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
    if (_mode == 2) {
      _testStopwatch.stop();
      _testTicker?.cancel();
      _saveTestElapsed(testElapsed.inMilliseconds);
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
