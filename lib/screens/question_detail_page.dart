import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_strings.dart';
import '../widgets/image_view.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../models/question_stat.dart';
import '../common/request.dart';
import 'comment_page.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse, // 支持触控板/鼠标拖动
        PointerDeviceKind.trackpad, // 一些 Flutter 版本不需要加这个
      };
}

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
  _QuestionDetailPageState createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  int mode = 0; // 初始化刷题模式
  int _currentPage = 0; // 当前页面
  // 记录当前题目页的打开时间，用于计算单题作答时长（毫秒）
  late int _pageOpenedAt;
  // 创建 PageController
  PageController _pageController = PageController();
  // 测试模式正计时：Stopwatch 记录当前段用时，Timer 每秒刷新界面
  final Stopwatch _testStopwatch = Stopwatch();
  Timer? _testTicker;
  // 返回页面时落盘的累计基准（毫秒），再次进入测验从该值继续，避免归零
  int _testBaseMs = 0;
  // 每个题目页独立的滚动控制器，供评论区无限滚动监听
  final Map<int, ScrollController> _scrollControllers = {};
  // 刷题字号缩放比例（来自设置页「刷题字号」）
  double _fontScale = 1.0;

  @override
  void initState() {
    _loadSettings();
    _saveLastQIndex();
    super.initState();
    _currentPage = widget.questionIndex;
    _pageController = PageController(initialPage: _currentPage);
    _pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    if (mode == 2) {
      // 未交卷就离开页面：暂停计时并把累计时长落盘，下次进入继续
      _testStopwatch.stop();
      _testTicker?.cancel();
      _saveTestElapsed(_testElapsed.inMilliseconds);
    } else {
      _testTicker?.cancel();
    }
    for (final ScrollController c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // 获取指定题目页的滚动控制器（懒创建）
  ScrollController _controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, ScrollController.new);

  // 累计总用时 = 落盘基准 + 当前段
  Duration get _testElapsed =>
      Duration(milliseconds: _testBaseMs) + _testStopwatch.elapsed;

  // 启动测试模式正计时（当前段从 0 开始，累计基准已恢复）
  void _startTestTimer() {
    _testStopwatch..reset()..start();
    _testTicker?.cancel();
    _testTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // 停止测试模式正计时
  void _stopTestTimer() {
    _testTicker?.cancel();
    _testTicker = null;
    _testStopwatch.stop();
  }

  // 累计用时落盘
  Future<void> _saveTestElapsed(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('testElapsedMs', ms);
  }

  // 将累计用时格式化为 mm:ss 或 hh:mm:ss
  String _formatElapsed() {
    final Duration d = _testElapsed;
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // 请求接口数据
  Future<QuestionStat> _fetchQuestionStat(Question question) async {
    final response = await basicReq('/allquestion/main/stat', method: 'GET', {
      'module_type': '1',
      'question_id': question.id,
      'app_id': question.appId,
    });
    return QuestionStat.fromMap(response['data']);
  }

  Future<void> _saveLastQIndex() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('lastQIndex')) {
      await prefs.setInt('lastQIndex', _currentPage);
    }
    debugPrint('保存上次做题记录: $_currentPage');
  }

  // 控制翻到下一页的方法
  void _nextPage() {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 翻到上一页
  void _previousPage() {
    _pageController.previousPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 获取数据
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      mode = prefs.getInt('mode') ?? 0;
      _testBaseMs = prefs.getInt('testElapsedMs') ?? 0;
      _fontScale = prefs.getDouble('fontScale') ?? 1.0;
    });
    if (mode == 2) {
      _startTestTimer();
    }
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', mode);
  }

  Widget _submitButton(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    // 测试模式下不显示「提交」按钮（交卷统一在底部）；快刷模式单选自动提交也不显示
    if (mode == 2 || (mode == 1 && question.type == '1')) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 200,
        height: 70,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
            elevation: 3,
          ),
          onPressed: () {
            submitAnswer(question, userQuestion, index);
          },
          child: const Text(
            '提交',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }

  Widget _checkableOptionsList(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    final List<dynamic> optionJson = _getOptionJson(question);
    return Expanded(
      child: ListView.builder(
        itemCount: optionJson.length,
        itemBuilder: (context, i) {
          final Map<String, dynamic> option = optionJson[i];
          switch (question.type) {
            case '1': // 单选题
              return RadioListTile<String>(
                title: Text("${option['key']}. ${option['title']}"),
                value: option['key'],
                groupValue: getLastAnswer(userQuestion.userAnswer),
                onChanged: (String? value) {
                  setState(() {
                    userQuestion.userAnswer = changeLastAnswer(
                      userQuestion.userAnswer,
                      value ?? '',
                    );
                  });
                  if (mode == 1 || mode == 2) {
                    // 快刷模式 && 测试模式, 单选题自动提交
                    submitAnswer(question, userQuestion, index);
                  }
                },
              );
            case '2': // 多选题
              return CheckboxListTile(
                title: Text("${option['key']}. ${option['title']}"),
                value: getLastAnswer(userQuestion.userAnswer)
                    .contains(option['key']),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) {
                  setState(() {
                    bool checked = getLastAnswer(userQuestion.userAnswer)
                        .contains(option['key']);
                    if (value == true && !checked) {
                      userQuestion.userAnswer = changeLastAnswer(
                        userQuestion.userAnswer,
                        getLastAnswer(userQuestion.userAnswer) + option['key'],
                      );
                    } else if (value == false && checked) {
                      userQuestion.userAnswer = changeLastAnswer(
                        userQuestion.userAnswer,
                        getLastAnswer(userQuestion.userAnswer).replaceAll(
                          option['key'],
                          '',
                        ),
                      );
                    }
                    // 测试模式多选无「提交」按钮：边选边标记待提交，交卷时统一判分
                    if (mode == 2) {
                      userQuestion.status = 4;
                      widget.userQuestions[index].status = 4;
                    }
                  });
                  if (mode == 2) {
                    updateQuestionSimple(userQuestion, question);
                  }
                },
              );
            default:
              return const Text('未知的题目类型');
          }
        },
      ),
    );
  }

  Widget _questionHeaders(Question question, int index) {
    final titleImg = question.titleImg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              question.typeStr ?? '未知题型',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            Spacer(),
            Padding(
              // 3: (22-16)/2
              padding: EdgeInsets.fromLTRB(5, 0, 5, 3),
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 22),
              ),
            ),
            Text(
              '/ ${widget.questions.length}',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        question.publicTitle != ''
            ? Text(
                question.publicTitle ?? '',
                style: const TextStyle(
                  fontSize: 18,
                ),
              )
            : const SizedBox.shrink(),
        const SizedBox(height: 10),
        Text(
          question.title ?? '',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        titleImg != null && titleImg.isNotEmpty
            ? InkWell(
                onTap: () {
                  _showFullScreenImage(
                    context,
                    [titleImg],
                    0,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.network(
                    titleImg,
                    height: 200,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _unansweredQuestion(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionHeaders(question, index),
          _checkableOptionsList(question, userQuestion, index),
          _submitButton(question, userQuestion, index),
        ],
      ),
    );
  }

  Widget _buildOptions(Question question, UserQuestion userQuestion) {
    final List<dynamic> optionJson = _getOptionJson(question);
    for (Map<String, dynamic> option in optionJson) {
      final String key = option['key'];
      final bool answerContains = question.answer!.contains(key);
      final bool userAnswerContains =
          getLastAnswer(userQuestion.userAnswer).contains(key);
      if ((mode == 3 && userQuestion.status == 0) || userQuestion.status == 4) {
        if (answerContains) {
          option['color'] = null;
          option['icon'] = Icons.check_circle;
        } else {
          option['color'] = Colors.grey;
          option['icon'] = Icons.circle_outlined;
        }
      } else if (answerContains && userAnswerContains) {
        option['color'] = Colors.green;
        option['icon'] = Icons.check_circle;
      } else if (answerContains && !userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.check_circle;
      } else if (!answerContains && userAnswerContains) {
        option['color'] = Colors.red;
        option['icon'] = Icons.cancel;
      } else {
        option['color'] = Colors.grey;
        option['icon'] = Icons.circle_outlined;
      }
    }
    return Column(
      children: List.generate(optionJson.length, (index) {
        final Map<String, dynamic> option = optionJson[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                option['icon'],
                color: option['color'],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "${option['key']}. ${option['title']}",
                    style: TextStyle(
                      fontSize: 16.5,
                      color: option['color'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => FullScreenImageView(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  TextSpan _buildTextWithBold(String text) {
    final RegExp regex = RegExp(r'（[A-Z](对|错)(，为本题正确答案)?）');
    final List<String> parts = text.split(regex);
    List<String> matches =
        regex.allMatches(text).map((match) => match.group(0)!).toList();
    // merge parts and matches
    for (int i = 0; i < matches.length; i++) {
      parts.insert(2 * i + 1, matches[i]);
    }
    return TextSpan(
      children: List.generate(parts.length, (index) {
        if (index.isEven) {
          return TextSpan(
            text: parts[index],
            style: TextStyle(
              fontSize: 16,
              height: 1.8,
            ),
          );
        } else {
          return TextSpan(
            text: parts[index],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              height: 1.8,
            ),
          );
        }
      }),
    );
  }

  Widget _buildTextWithImage(String text, String imgUrl) {
    // split text with regex: (?:[\u4e00-\u9fa5]+)?P\d+(?:-P\d+)?
    // 1. (?:[\u4e00-\u9fa5]+)? : optional chinese characters
    // 2. P\d+ : P + digits
    // 3. (?:-P\d+)? : optional -P + digits
    final RegExp regex = RegExp(r'(?:[0-9\u4e00-\u9fa5]+)?P\d+(?:-P\d+)?');
    final List<String> parts = text.split(regex);
    final List<String> imageUrls = [];
    List<String> matches =
        regex.allMatches(text).map((match) => match.group(0)!).toList();
    // merge parts and matches
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
                  padding: WidgetStateProperty.all<EdgeInsets>(
                    EdgeInsets.zero,
                  ),
                  minimumSize: WidgetStateProperty.all(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                  elevation: WidgetStateProperty.all(0), // 去掉阴影
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      parts[index],
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.deepOrange,
                      ),
                    ),
                    Icon(
                      Icons.photo,
                      size: 18,
                      color: Colors.deepOrange,
                    )
                  ],
                ),
                onPressed: () {
                  _showFullScreenImage(
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

  Widget _buildAnalysisText(
    String title,
    IconData icon,
    String analysisText,
    Question q,
  ) {
    Color orangeAccent = Color(0xFFB39D6B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: orangeAccent, size: 24),
            SizedBox(width: 6), // 图标与文字间距
            Text(
              title, // 标题文字
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: orangeAccent, // 标题颜色
              ),
            ),
          ],
        ),
        SizedBox(height: 10), // 标题与内容间距
        _buildTextWithImage(
          analysisText,
          'https://ykb-app-files.yikaobang.com.cn/question/restore/${q.nativeAppId}/${q.number}',
        ),
        SizedBox(height: 10),
        Divider(color: Color(0x22888888)),
      ],
    );
  }

  Widget _createStat(
    QuestionStat stat,
    Question question,
    UserQuestion userQuestion,
  ) {
    int rightCount = int.parse(stat.rightCount);
    int wrongCount = int.parse(stat.wrongCount);
    final int totalCount = rightCount + wrongCount;
    // 无人作答时 totalCount 为 0，直接除会得到 NaN，进而 ceil() 抛异常。
    double errorRate = totalCount == 0 ? 0.0 : wrongCount / totalCount;
    int n = (errorRate * 10).ceil(); // 难度
    int fullStars = n ~/ 2; // 整星的数量
    bool hasHalfStar = n % 2 == 1; // 是否有半颗星
    int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0); // 空星数量

    int myCorrectAnsCnt = 0;
    final List<String> myAnswers = userQuestion.userAnswer.split(';');
    final int totalAnsCnt = myAnswers.length;
    for (String ans in myAnswers) {
      if (sortString(ans) == sortString(question.answer!)) {
        myCorrectAnsCnt += 1;
      }
    }
    Color textColor =
        myCorrectAnsCnt < totalAnsCnt / 2 ? Colors.red : Colors.green;
    final String myAccuracy =
        (myCorrectAnsCnt / totalAnsCnt * 100).toStringAsFixed(2);

    return Column(children: [
      SizedBox(height: 5),
      Row(
        children: [
          Text('难度：'),
          ...List.generate(
            fullStars,
            (index) => Icon(
              Icons.star,
              color: Colors.orange,
            ),
          ), // 整星
          if (hasHalfStar)
            Icon(
              Icons.star_half,
              color: Colors.orange,
            ), // 半颗星
          ...List.generate(
            emptyStars,
            (index) => Icon(
              Icons.star_border,
              color: Colors.grey,
            ),
          ), // 空星
        ],
      ),
      SizedBox(height: 5),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('统计：'),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: '${stat.statInfo}共${stat.commentCount}条评论。',
                style: TextStyle(color: Colors.grey),
                children: <TextSpan>[
                  TextSpan(text: '本人作答'),
                  TextSpan(
                    text: '${myAnswers.length}',
                    style: TextStyle(color: textColor),
                  ),
                  TextSpan(text: '次，对'),
                  TextSpan(
                    text: '$myCorrectAnsCnt',
                    style: TextStyle(color: textColor),
                  ),
                  TextSpan(text: '次，正确率'),
                  TextSpan(
                    text: '$myAccuracy%',
                    style: TextStyle(color: textColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: 5),
    ]);
  }

  Widget _createEmptyStat(
    Question question,
    UserQuestion userQuestion,
  ) {
    int n = 0;
    int fullStars = n ~/ 2; // 整星的数量
    bool hasHalfStar = n % 2 == 1; // 是否有半颗星
    int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0); // 空星数量

    int myCorrectAnsCnt = 0;
    final List<String> myAnswers = userQuestion.userAnswer.split(';');
    final int totalAnsCnt = myAnswers.length;
    for (String ans in myAnswers) {
      if (sortString(ans) == sortString(question.answer!)) {
        myCorrectAnsCnt += 1;
      }
    }
    Color textColor =
        myCorrectAnsCnt < totalAnsCnt / 2 ? Colors.red : Colors.green;
    final String myAccuracy =
        (myCorrectAnsCnt / totalAnsCnt * 100).toStringAsFixed(2);

    return Column(children: [
      SizedBox(height: 5),
      Row(
        children: [
          Text('难度：'),
          ...List.generate(
            fullStars,
            (index) => Icon(
              Icons.star,
              color: Colors.orange,
            ),
          ), // 整星
          if (hasHalfStar)
            Icon(
              Icons.star_half,
              color: Colors.orange,
            ), // 半颗星
          ...List.generate(
            emptyStars,
            (index) => Icon(
              Icons.star_border,
              color: Colors.grey,
            ),
          ), // 空星
        ],
      ),
      SizedBox(height: 5),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('统计：'),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: '本题???人收藏，全部考生作答???次，对???次，正确率???%，共???条评论。',
                style: TextStyle(color: Colors.grey),
                children: <TextSpan>[
                  TextSpan(text: '本人作答'),
                  TextSpan(
                    text: '${myAnswers.length}',
                    style: TextStyle(color: textColor),
                  ),
                  TextSpan(text: '次，对'),
                  TextSpan(
                    text: '$myCorrectAnsCnt',
                    style: TextStyle(color: textColor),
                  ),
                  TextSpan(text: '次，正确率'),
                  TextSpan(
                    text: '$myAccuracy%',
                    style: TextStyle(color: textColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: 5),
    ]);
  }

  Widget _answeredQuestion(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    final String userAnswer = getLastAnswer(userQuestion.userAnswer);
    final String answer = question.answer ?? '';
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            controller: _controllerFor(index),
            shrinkWrap: true, // 让外层 ListView 适应内容
            physics: ClampingScrollPhysics(), // 正常滚动
            children: [
              _questionHeaders(question, index),
              _buildOptions(question, userQuestion),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '答案：正确答案 $answer, 你的答案 ',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    userAnswer,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          userQuestion.status == 1 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              FutureBuilder<QuestionStat>(
                future: _fetchQuestionStat(question),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _createEmptyStat(question, userQuestion);
                  } else if (snapshot.hasError) {
                    return _createEmptyStat(question, userQuestion);
                  } else if (snapshot.hasData) {
                    return _createStat(snapshot.data!, question, userQuestion);
                  } else {
                    return Container();
                  }
                },
              ),
              if (question.source != '')
                Text(
                  '来源：${question.source ?? ''}',
                  style: TextStyle(fontSize: 14),
                ),
              SizedBox(height: 10),
              Divider(color: Color(0x22888888)),
              if (question.restore != '')
                _buildAnalysisText(
                  '考点还原',
                  Icons.location_on_outlined,
                  question.restore ?? '',
                  question,
                ),
              if (question.explain != '')
                _buildAnalysisText(
                  '答案解析',
                  Icons.lightbulb_outlined,
                  question.explain ?? '',
                  question,
                ),
              CommentPage(
                question: question,
                scrollController: _controllerFor(index),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cuttedQuestion(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text("该题目已斩"),
    );
  }

  Widget _buildQuestion(
    Question question,
    UserQuestion userQuestion,
    int index,
  ) {
    if (mode == 3) {
      // 背题模式, 直接显示正确答案
      return _answeredQuestion(question, userQuestion, index);
    }
    switch (userQuestion.status) {
      case 0: // 未作答
        return _unansweredQuestion(question, userQuestion, index);
      case 1: // 正确作答
        return _answeredQuestion(question, userQuestion, index);
      case 2: // 错误回答
        return _answeredQuestion(question, userQuestion, index);
      case 3: // 已斩题
        return _cuttedQuestion(question, userQuestion, index);
      case 4: // 测试模式 - 已作答
        return _unansweredQuestion(question, userQuestion, index);
      default:
        return const Text('未知的题目状态');
    }
  }

  _copyBtn() {
    UserQuestion userQuestion = widget.userQuestions[_currentPage];
    Question question = widget.questions[_currentPage];
    if (userQuestion.status == 0 || userQuestion.status == 3) {
      return Container();
    }
    return IconButton(
      icon: Icon(Icons.copy),
      onPressed: () {
        final String userAnswer = getLastAnswer(userQuestion.userAnswer);
        final String answer = question.answer ?? '';
        final List<dynamic> optionJson = _getOptionJson(question);
        String optionText = "";
        for (Map<String, dynamic> option in optionJson) {
          final String key = option['key'];
          final String title = option['title'];
          optionText += '\n$key. $title';
        }
        String copyText = '## 题目\n\n'
            '${question.publicTitle ?? ''}'
            '${question.title ?? ''}$optionText\n\n'
            '## 正确答案：$answer\n\n'
            '## 我的答案：$userAnswer\n\n'
            '## 参考解析\n\n${question.explain}';
        Clipboard.setData(ClipboardData(text: copyText));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('题目、答案、解析已复制，去问AI吧～'),
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _collectionBtn() {
    UserQuestion userQuestion = widget.userQuestions[_currentPage];
    Question question = widget.questions[_currentPage];
    return IconButton(
      icon: userQuestion.collection == 0
          ? Icon(Icons.favorite_outline)
          : Icon(Icons.favorite, color: Colors.redAccent),
      onPressed: () {
        if (userQuestion.collection == 0) {
          userQuestion.collection = 1;
        } else {
          userQuestion.collection = 0;
        }
        updateQuestionSimple(userQuestion, question);
        setState(() {
          widget.userQuestions[_currentPage].collection =
              userQuestion.collection;
        });
      },
    );
  }

  Widget _cutQuestionBtn() {
    UserQuestion userQuestion = widget.userQuestions[_currentPage];
    Question question = widget.questions[_currentPage];
    return IconButton(
      icon: userQuestion.cutQuestion == ""
          ? Icon(Icons.block)
          : Icon(Icons.block_outlined, color: Colors.redAccent),
      onPressed: () {
        if (userQuestion.cutQuestion == "cutted") {
          userQuestion.cutQuestion = "";
        } else {
          userQuestion.cutQuestion = "cutted";
        }
        updateQuestionSimple(userQuestion, question);
        setState(() {
          widget.userQuestions[_currentPage].cutQuestion =
              userQuestion.cutQuestion;
        });
      },
    );
    //return ElevatedButton(
    //  onPressed: _onQuestionCutted,
    //  style: ElevatedButton.styleFrom(
    //    shape: CircleBorder(), // 圆形
    //    backgroundColor: Colors.transparent, // 设置透明背景
    //    shadowColor: Colors.transparent, // 去掉阴影
    //    elevation: 3, // 按钮阴影
    //    padding: EdgeInsets.all(0), // 去掉内边距
    //  ),
    //  child: Padding(
    //    padding: EdgeInsets.all(7),
    //    child: Text(
    //      "斩",
    //      style: TextStyle(
    //        fontSize: 18,
    //        fontWeight: FontWeight.bold,
    //      ),
    //    ),
    //  ),
    //);
  }

  Widget _backForwardBtm() {
    return Stack(
      children: [
        // 左下角按钮
        Positioned(
          bottom: 20,
          left: 20,
          child: ElevatedButton(
            onPressed: _currentPage == 0 ? null : () => _previousPage(),
            style: ElevatedButton.styleFrom(
              shape: CircleBorder(),
              padding: EdgeInsets.all(15), // 控制按钮大小
              elevation: 3,
            ),
            child: Icon(
              Icons.arrow_left,
              size: 50, // 图标更大
            ),
          ),
        ),
        // 右下角按钮
        Positioned(
          bottom: 20,
          right: 20,
          child: ElevatedButton(
            onPressed: _currentPage == widget.questions.length - 1
                ? null
                : () => _nextPage(),
            style: ElevatedButton.styleFrom(
              shape: CircleBorder(),
              padding: EdgeInsets.all(15),
              elevation: 3,
            ),
            child: Icon(
              Icons.arrow_right,
              size: 50,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtom() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        break;
      case TargetPlatform.iOS:
        break;
      case TargetPlatform.macOS:
        return _backForwardBtm();
      case TargetPlatform.windows:
        return _backForwardBtm();
      case TargetPlatform.linux:
        return _backForwardBtm();
      default:
        break;
    }
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_fontScale),
      ),
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.chapter.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          _cutQuestionBtn(),
          _copyBtn(),
          _collectionBtn(),
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) => _onModeChanged(value),
            itemBuilder: (context) {
              return List.generate(AppStrings.modesList.length, (index) {
                return PopupMenuItem<int>(
                  value: index,
                  child: Row(
                    children: [
                      Text(AppStrings.modesList[index]),
                      SizedBox(width: 8),
                      if (mode == index) Icon(Icons.check, size: 20),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (mode == 2) _buildTestInfoBar(),
          Expanded(
            child: ScrollConfiguration(
              behavior: MyCustomScrollBehavior(),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (int page) {
                      setState(() {
                        _currentPage = page; // 更新当前页索引
                      });
                      // 翻页后重设计时，保证每题时长是从浏览当前题开始计算
                      _pageOpenedAt = DateTime.now().millisecondsSinceEpoch;
                      _saveLastQIndex(); // 更新上次做到的题目
                    },
                    itemCount: widget.questions.length,
                    itemBuilder: (context, index) {
                      return _buildQuestion(
                        widget.questions[index],
                        widget.userQuestions[index],
                        index,
                      );
                    },
                  ),
                  _buildButtom(),
                ],
              ),
            ),
          ),
          if (mode == 2) _buildSubmitBar(),
        ],
      ),
      ),
    );
  }

  // 测试模式顶部信息栏：显示已用时与已作答进度
  Widget _buildTestInfoBar() {
    final int answered =
        widget.userQuestions.where((uq) => uq.status == 4).length;
    final int total = widget.questions.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '已用时 ${_formatElapsed()}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            '已作答 $answered/$total',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // 测试模式底部交卷按钮
  Widget _buildSubmitBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: ElevatedButton(
            onPressed: _submitTest,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text('交卷', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }

  List<dynamic> _getOptionJson(Question question) {
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

    return json.decode(
      question.option ?? defaultOptionString,
    );
  }

  String sortString(String str) {
    // 将字符串转换为字符列表并排序
    List<String> chars = str.split('')..sort();
    // 将字符列表转换回字符串
    String sortedStr = chars.join();
    return sortedStr;
  }

  void submitAnswer(Question question, UserQuestion userQuestion, int index) {
    // 计算当前题目作答时长（毫秒），避免出现负数
    final int elapsedMs = (DateTime.now().millisecondsSinceEpoch - _pageOpenedAt)
        .clamp(0, 1 << 62);
    final String userAnswer = getLastAnswer(userQuestion.userAnswer);
    if (question.type == '1' && userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('不能不填答案哦~'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (question.type == '2' && userAnswer.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('多选题要选择多个选项哦~'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (mode == 2) {
      userQuestion.status = 4; // 测试模式 - 待提交
      // 测试模式下仅标记「待提交」，不判分、不写统计与流水，交卷时统一判分
      updateQuestionSimple(userQuestion, question);
      setState(() {
        widget.userQuestions[index].status = userQuestion.status;
      });
      _nextPage();
    } else {
      if (sortString(userAnswer) == sortString(question.answer!)) {
        userQuestion.status = 1; // 回答正确
      } else {
        userQuestion.status = 2; // 回答错误
      }
      updateQuestion(userQuestion, question, durationMs: elapsedMs, bankId: widget.bankId);
      setState(() {
        widget.userQuestions[index].status = userQuestion.status;
      });
      if (userQuestion.status == 1 && mode == 1) {
        // 快刷模式自动翻页 || 测试模式自动翻页
        _nextPage();
      }
    }
  }

  // 切换刷题模式：处理测试模式的正计时启停，并判分离开测试模式时的待提交题
  Future<void> _onModeChanged(int newMode) async {
    if (newMode == mode) {
      setState(() {});
      return;
    }
    final bool enteringTest = newMode == 2;
    final bool leavingTest = mode == 2;
    if (leavingTest) {
      final bool? confirmed = await _confirmLeaveTest();
      if (confirmed != true || !mounted) {
        return; // 用户取消，保持测试模式
      }
      _stopTestTimer();
      _testBaseMs = 0; // 放弃本次测试，累计归零
      await _saveTestElapsed(0);
      // 用户边缘情况：测试模式做了题但没交卷就切走，自动判分，灰格变绿/红
      await gradePendingQuestions(
        widget.questions,
        widget.userQuestions,
        bankId: widget.bankId,
      );
      if (!mounted) return;
    }
    setState(() {
      mode = newMode;
    });
    await _saveSettings();
    if (enteringTest) {
      _startTestTimer();
    }
  }

  // 切换离开测试模式前的确认弹窗
  Future<bool?> _confirmLeaveTest() {
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

  // 交卷：确认后停止计时、判分、弹窗显示成绩并回到练习模式
  Future<void> _submitTest() async {
    if (mode != 2) return;
    final bool? confirmed = await _confirmSubmit();
    if (confirmed != true || !mounted) return;
    _stopTestTimer();
    final String used = _formatElapsed(); // 先记录本次用时
    final MapEntry<int, int> result = await gradePendingQuestions(
      widget.questions,
      widget.userQuestions,
      bankId: widget.bankId,
    );
    if (!mounted) return;
    setState(() {
      mode = 0; // 交卷后回到练习模式，方便查看已判分的解析
      _testBaseMs = 0;
    });
    await _saveSettings();
    await _saveTestElapsed(0); // 本次测试结束，累计清零
    if (!mounted) return;
    final int answered = result.key;
    final int correct = result.value;
    final int unanswered = widget.questions.length - answered;
    _showResultDialog(answered, correct, unanswered, used);
  }

  // 交卷前的确认弹窗
  Future<bool?> _confirmSubmit() {
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

  // 测试结果弹窗
  void _showResultDialog(int answered, int correct, int unanswered, String used) {
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

  Widget _resultLine(String label, String value) {
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
}
