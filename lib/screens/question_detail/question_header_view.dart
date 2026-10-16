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
              question.typeStr ?? '未知题型',
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
        Text(
          question.title ?? '',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
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
}
