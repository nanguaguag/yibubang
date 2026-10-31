import 'package:flutter/material.dart';

import '../../common/request.dart';
import '../../models/question.dart';
import '../../models/question_stat.dart';

/// 题目统计视图：展示难度星级、全网作答情况及用户个人历史作答正确率
class QuestionStatView extends StatelessWidget {
  final Question question;
  final UserQuestion userQuestion;

  const QuestionStatView({
    super.key,
    required this.question,
    required this.userQuestion,
  });

  Future<QuestionStat?> _fetchQuestionStat() async {
    final resolvedAppId = question.nativeAppId?.isNotEmpty == true
        ? question.nativeAppId!
        : (question.appId?.isNotEmpty == true ? question.appId! : '1');

    final response = await basicReq('/allquestion/main/stat', method: 'GET', {
      'module_type': '1',
      'question_id': question.id,
      'app_id': resolvedAppId,
    });
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return QuestionStat.fromMap(data);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuestionStat?>(
      future: _fetchQuestionStat(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            !snapshot.hasData) {
          return _buildStatLayout(null);
        }
        return _buildStatLayout(snapshot.data);
      },
    );
  }

  Widget _buildStatLayout(QuestionStat? stat) {
    int fullStars = 0;
    bool hasHalfStar = false;
    int emptyStars = 5;

    if (stat != null) {
      final int rightCount = int.tryParse(stat.rightCount) ?? 0;
      final int wrongCount = int.tryParse(stat.wrongCount) ?? 0;
      final int totalCount = rightCount + wrongCount;
      final double errorRate = totalCount == 0 ? 0.0 : wrongCount / totalCount;
      final int n = (errorRate * 10).ceil();
      fullStars = n ~/ 2;
      hasHalfStar = n % 2 == 1;
      emptyStars = (5 - fullStars - (hasHalfStar ? 1 : 0)).clamp(0, 5);
    }

    final List<String> myAnswers = userQuestion.userAnswer
        .split(';')
        .where((ans) => ans.isNotEmpty)
        .toList();
    final int totalAnsCnt = myAnswers.length;
    final String correctAns = question.answer ?? '';

    int myCorrectAnsCnt = 0;
    for (final String ans in myAnswers) {
      if (correctAns.isNotEmpty && sortString(ans) == sortString(correctAns)) {
        myCorrectAnsCnt += 1;
      }
    }

    final Color textColor = (totalAnsCnt == 0 || myCorrectAnsCnt < totalAnsCnt / 2)
        ? Colors.red
        : Colors.green;
    final String myAccuracy = totalAnsCnt == 0
        ? '0.00'
        : (myCorrectAnsCnt / totalAnsCnt * 100).toStringAsFixed(2);

    final String statInfo = stat != null
        ? '${stat.statInfo}共${stat.commentCount}条评论。'
        : '本题???人收藏，全部考生作答???次，对???次，正确率???%，共???条评论。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 5),
        Row(
          children: [
            const Text('难度：'),
            ...List.generate(
              fullStars,
              (_) => const Icon(Icons.star, color: Colors.orange, size: 20),
            ),
            if (hasHalfStar)
              const Icon(Icons.star_half, color: Colors.orange, size: 20),
            ...List.generate(
              emptyStars,
              (_) => const Icon(Icons.star_border, color: Colors.grey, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('统计：'),
            Expanded(
              child: RichText(
                text: TextSpan(
                  text: statInfo,
                  style: const TextStyle(color: Colors.grey),
                  children: <TextSpan>[
                    const TextSpan(text: '本人作答'),
                    TextSpan(
                      text: '$totalAnsCnt',
                      style: TextStyle(color: textColor),
                    ),
                    const TextSpan(text: '次，对'),
                    TextSpan(
                      text: '$myCorrectAnsCnt',
                      style: TextStyle(color: textColor),
                    ),
                    const TextSpan(text: '次，正确率'),
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
        const SizedBox(height: 5),
      ],
    );
  }
}
