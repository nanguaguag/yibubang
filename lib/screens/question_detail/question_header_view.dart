import 'package:flutter/material.dart';

import '../../common/adaptive_route.dart';
import '../../models/question.dart';
import '../../widgets/common/app_network_image.dart';
import '../../widgets/image_view.dart';

/// 全屏看图路由辅助函数
void showFullScreenImage(
  BuildContext context,
  List<String> imageUrls,
  int initialIndex,
) {
  Navigator.push(
    context,
    adaptivePageRoute(
      builder: (context) => FullScreenImageView(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// 题目头部信息组件：题型、题号、公用题干、题目题干及配图
class QuestionHeaderView extends StatelessWidget {
  final Question question;
  final int index;
  final int totalCount;

  const QuestionHeaderView({
    super.key,
    required this.question,
    required this.index,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final titleImg = question.titleImg;
    final publicTitle = question.publicTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              question.typeLabel,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 5, 3),
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontSize: 22),
              ),
            ),
            Text(
              '/ $totalCount',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (publicTitle != null && publicTitle.isNotEmpty) ...[
          Text(
            publicTitle,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 10),
        ],
        _buildTitleWidget(context),
        if (titleImg != null && titleImg.isNotEmpty)
          InkWell(
            onTap: () {
              showFullScreenImage(
                context,
                [titleImg],
                0,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AppNetworkImage(
                imageUrl: titleImg,
                height: 200,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitleWidget(BuildContext context) {
    final rawTitle = question.title ?? '';
    if (!rawTitle.contains('#@')) {
      return Text(
        rawTitle,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final regex = RegExp(r'#@(.*?)(?:@#|$)');
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    int blankIndex = 1;

    final theme = Theme.of(context);
    for (final match in regex.allMatches(rawTitle)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: rawTitle.substring(lastEnd, match.start),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            '【空 $blankIndex】',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ));
      blankIndex++;
      lastEnd = match.end;
    }

    if (lastEnd < rawTitle.length) {
      spans.add(TextSpan(
        text: rawTitle.substring(lastEnd),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
