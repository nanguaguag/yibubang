import 'package:shared_preferences/shared_preferences.dart';
import '../common/request.dart';
import 'question.dart';

class QuestionLabel {
  final String id;
  final String label;
  final String color;
  final int count;
  final bool userLabel;

  const QuestionLabel({
    required this.id,
    required this.label,
    required this.color,
    required this.count,
    required this.userLabel,
  });

  factory QuestionLabel.fromJson(Map<String, dynamic> json) {
    return QuestionLabel(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      color: json['color']?.toString() ?? '#000000',
      count: int.tryParse(json['count']?.toString() ?? '0') ?? 0,
      userLabel: (json['user_label']?.toString() ?? '0') != '0',
    );
  }
}

final Map<String, List<QuestionLabel>> _labelCache = {};

/// 从医考帮获取题目标签
Future<List<QuestionLabel>> fetchQuestionLabels(Question question) async {
  if (_labelCache.containsKey(question.id)) {
    return _labelCache[question.id]!;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final identityId = question.identityId?.isNotEmpty == true
        ? question.identityId!
        : (prefs.getString('identityId') ?? '');
    final subjectId = question.chapterParentId ?? '';
    final appId = question.appId?.isNotEmpty == true ? question.appId! : '1';

    final params = <String, dynamic>{
      'question_id': question.id,
      'subject_id': subjectId,
      'identity_id': identityId,
      'app_id': appId,
      'is_vip': '0',
      'is_svip': '0',
    };

    final resp = await basicReq(
      '/allquestion/main/label',
      params,
      method: 'GET',
    );

    if (resp['code'] == '200' && resp['data'] is List) {
      final list = (resp['data'] as List)
          .map((e) => QuestionLabel.fromJson(e as Map<String, dynamic>))
          .toList();
      _labelCache[question.id] = list;
      return list;
    }
  } catch (e) {
    // 忽略异常，降级返回空列表
  }
  return [];
}
