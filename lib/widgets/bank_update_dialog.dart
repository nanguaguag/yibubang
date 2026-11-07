import 'package:flutter/material.dart';
import '../models/bank_source.dart';
import '../models/question_bank.dart';
import '../services/question_bank_file_service.dart';

Future<BankImportMode?> showBankUpdateDialog(
  BuildContext context,
  QuestionBank bank,
  BankUpdateInfo info,
  BankContentDiff diff,
) => showDialog<BankImportMode>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text('更新「${bank.name}」'),
    content: SingleChildScrollView(
      child: Text(
        '${info.label}\n'
        '新包新增 ${diff.added} 道题、${diff.changed} 道内容不同，本地独有 ${diff.localExtras} 道题。\n\n'
        '合并保留本地独有题目和课程关系；同一道题采用订阅内容。替换使用完整订阅版本。个人作答、收藏和笔记会保留。',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('暂不更新'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(ctx, BankImportMode.replace),
        child: const Text('使用订阅版本'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, BankImportMode.merge),
        child: const Text('保留本地补充'),
      ),
    ],
  ),
);
