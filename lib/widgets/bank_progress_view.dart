import 'package:flutter/material.dart';

import '../models/bank_progress.dart';

class BankProgressView extends StatelessWidget {
  const BankProgressView({super.key, required this.progress});
  final BankProgress progress;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(value: progress.fraction),
      const SizedBox(height: 12),
      Text(progress.stage),
      if (progress.chapter.isNotEmpty) Text(progress.chapter),
      if (progress.total > 0) Text('章节 ${progress.completed}/${progress.total}'),
      if (progress.expectedQuestions > 0)
        Text('题目 ${progress.questions}/${progress.expectedQuestions}（含跨章重复）')
      else if (progress.questions > 0) Text('已抓取 ${progress.questions} 题'),
    ],
  );
}
