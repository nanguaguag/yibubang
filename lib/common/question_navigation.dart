import 'package:flutter/material.dart';

import 'adaptive_route.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../repositories/question_search_repository.dart';
import '../screens/question_detail_page.dart';

/// 统一跳转到题目详情页的通用路由方法
Future<bool> openQuestionDetailPage(
  BuildContext context,
  QuestionSearchResult result,
) async {
  final repository = QuestionSearchRepository();
  try {
    final question = await repository.getQuestionById(
      result.bankId,
      result.questionId,
    );
    if (question == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未在题库中找到题目详情')),
        );
      }
      return false;
    }
    final userQuestion =
        await repository.getUserQuestionById(result.questionId) ??
            UserQuestion(
              id: question.id,
              chapterId: question.chapterId ?? '',
              chapterParentId: question.chapterParentId ?? '',
              cutQuestion: '0',
              userAnswer: '',
              status: 0,
              collection: 0,
              updatedAt: 0,
            );
    if (!context.mounted) return false;
    final chapter = Chapter(
      id: question.chapterId ?? '',
      name: result.subjectName ?? result.bankName,
      subjectId: question.chapterParentId ?? '',
      correct: 0,
      incorrect: 0,
      total: 1,
      identityId: question.identityId,
    );
    await Navigator.push(
      context,
      adaptivePageRoute(
        builder: (_) => QuestionDetailPage(
          chapter: chapter,
          questions: [question],
          userQuestions: [userQuestion],
          questionIndex: 0,
          bankId: result.bankId,
        ),
      ),
    );
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开题目失败：$e')),
      );
    }
    return false;
  }
}
