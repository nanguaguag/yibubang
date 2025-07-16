import 'dart:ui';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_strings.dart';
import '../widgets/image_view.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../models/questionStat.dart';
import '../common/request.dart';
import 'commet_page.dart';

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

  const QuestionDetailPage({
    super.key,
    required this.chapter,
    required this.questions,
    required this.userQuestions,
    required this.questionIndex,
  });

  @override
  _QuestionDetailPageState createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  int mode = 0; // 初始化刷题模式
  int _currentPage = 0; // 当前页面
  // 创建 PageController
  PageController _pageController = PageController();

  @override
  void initState() {
    _loadSettings();
    super.initState();
    _currentPage = widget.questionIndex;
    _pageController = PageController(initialPage: _currentPage);
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

  String _getLastAnswer(String userAnswer) {
    /// userAnswer 格式：
    /// - 最后一次答案是DC：AB;ABC;DC
    /// - 还没做：AB;ABC;
    List<String> answers = userAnswer.split(';');
    return answers.last;
  }

  String _changeLastAnswer(String userAnswer, String lastAnswer) {
    List<String> answers = userAnswer.split(';');
    answers.last = lastAnswer;
    return answers.join(';');
  }

  // 获取数据
  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      mode = prefs.getInt('mode') ?? 0;
    });
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
    // 如果是快刷/测试模式且为单选题，不显示提交按钮
    if ((mode == 1 || mode == 2) && question.type == '1') {
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
                groupValue: _getLastAnswer(userQuestion.userAnswer),
                onChanged: (String? value) {
                  setState(() {
                    userQuestion.userAnswer = _changeLastAnswer(
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
                value: _getLastAnswer(userQuestion.userAnswer)
                    .contains(option['key']),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) {
                  setState(() {
                    bool checked = _getLastAnswer(userQuestion.userAnswer)
                        .contains(option['key']);
                    if (value == true && !checked) {
                      userQuestion.userAnswer = _changeLastAnswer(
                        userQuestion.userAnswer,
                        _getLastAnswer(userQuestion.userAnswer) + option['key'],
                      );
                    } else if (value == false && checked) {
                      userQuestion.userAnswer = _changeLastAnswer(
                        userQuestion.userAnswer,
                        _getLastAnswer(userQuestion.userAnswer).replaceAll(
                          option['key'],
                          '',
                        ),
                      );
                    }
                  });
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
        const SizedBox(height: 10),
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
          _getLastAnswer(userQuestion.userAnswer).contains(key);
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
    double errorRate = wrongCount / (rightCount + wrongCount);
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
    final String userAnswer = _getLastAnswer(userQuestion.userAnswer);
    final String answer = question.answer ?? '';
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
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
              CommentPage(question: question),
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

  // 额外的图标按钮功能
  void _onQuestionCutted() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('该功能仍在开发中，敬请期待！'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _collectionBtn() {
    UserQuestion userQuestion = widget.userQuestions[_currentPage];
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
        updateQuestion(userQuestion); // 在数据库中 update
        setState(() {
          widget.userQuestions[_currentPage].collection =
              userQuestion.collection;
        });
      },
    );
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
      case TargetPlatform.linux:
        return _backForwardBtm();
      default:
        break;
    }
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.chapter.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          ElevatedButton(
            onPressed: _onQuestionCutted,
            style: ElevatedButton.styleFrom(
              shape: CircleBorder(), // 圆形
              backgroundColor: Colors.transparent, // 设置透明背景
              shadowColor: Colors.transparent, // 去掉阴影
              elevation: 3, // 按钮阴影
              padding: EdgeInsets.all(0), // 去掉内边距
            ),
            child: Padding(
              padding: EdgeInsets.all(7),
              child: Text(
                "斩",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          _collectionBtn(),
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              setState(() {
                mode = value;
              });
              _saveSettings();
            },
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
      body: ScrollConfiguration(
        behavior: MyCustomScrollBehavior(),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (int page) {
                setState(() {
                  _currentPage = page; // 更新当前页索引
                });
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
    final String userAnswer = _getLastAnswer(userQuestion.userAnswer);
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
      userQuestion.status = 4; // 测试模式 - 已作答
      updateQuestion(userQuestion);
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
      updateQuestion(userQuestion);
      setState(() {
        widget.userQuestions[index].status = userQuestion.status;
      });
      if (userQuestion.status == 1 && mode == 1) {
        // 快刷模式自动翻页 || 测试模式自动翻页
        _nextPage();
      }
    }
  }
}
