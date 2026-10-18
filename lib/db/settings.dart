import 'package:shared_preferences/shared_preferences.dart';
import '../models/question_section_config.dart';

// 存储数据
Future<void> initSettings() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('themeMode')) {
    await prefs.setString('themeMode', 'system'); // 默认暗黑模式为自动(系统)
  }
  if (!prefs.containsKey('cutType')) {
    await prefs.setInt('cutType', 0); // 斩题: 全部
  }
  if (!prefs.containsKey('questionType')) {
    await prefs.setInt('questionType', 0); // 题型: 全部
  }
  if (!prefs.containsKey('category')) {
    await prefs.setInt('category', 0); // 分类: 全部
  }
  if (!prefs.containsKey('mode')) {
    await prefs.setInt('mode', 0); // 模式: 练习模式
  }
  final existingIdentityId = prefs.getString('identityId') ?? '30401';
  if (!prefs.containsKey('activeBankId')) {
    final legacyBank = switch (existingIdentityId) {
      '20101' => 'clinical_final',
      '11070' => 'nursing_final',
      _ => 'dental_final',
    };
    await prefs.setString('activeBankId', legacyBank); // 默认题库
  }
  if (!prefs.containsKey('identityId')) {
    await prefs.setString('identityId', existingIdentityId); // 默认identity: 口腔题库
  }
  if (!prefs.containsKey('lastProgressBankId')) {
    await prefs.setString(
      'lastProgressBankId',
      prefs.getString('activeBankId') ?? 'dental_final',
    );
  }
  if (!prefs.containsKey('lastSubjectId')) {
    await prefs.setString('lastSubjectId', ''); // 上次做到的的课程ID
  }
  if (!prefs.containsKey('lastChapterId')) {
    await prefs.setString('lastChapterId', ''); // 上次做到的的章节ID
  }
  if (!prefs.containsKey('lastQIndex')) {
    await prefs.setInt('lastQIndex', -1); // 上次做到的的题目ID
  }
  if (!prefs.containsKey('questionUpload')) {
    await prefs.setBool('questionUpload', true); // 打开后启用做题上传功能
  }
  if (!prefs.containsKey('needToRebuildQuestionCount')) {
    await prefs.setBool('needToRebuildQuestionCount', true); // 新版本强制重建题目计数
  }

  /// Settings ///
  if (!prefs.containsKey('accept_update')) {
    await prefs.setBool('accept_update', true);
  }
  if (!prefs.containsKey('sync_question_bank')) {
    await prefs.setBool('sync_question_bank', false);
  }
  if (!prefs.containsKey('fontScale')) {
    await prefs.setDouble('fontScale', 1.0); // 刷题字号缩放比例
  }
  if (!prefs.containsKey('autoResume')) {
    await prefs.setBool('autoResume', false); // 启动自动继续上次进度
  }
  if (!prefs.containsKey('sync_notes_to_ykb')) {
    await prefs.setBool('sync_notes_to_ykb', true); // 同步笔记到医考帮默认开启
  }
  if (!prefs.containsKey('sync_cut_to_ykb')) {
    await prefs.setBool('sync_cut_to_ykb', true); // 同步斩题到医考帮默认开启
  }
  if (!prefs.containsKey('sync_answers_to_ykb')) {
    final legacy = prefs.getBool('questionUpload') ?? prefs.getBool('sync_question_bank') ?? true;
    await prefs.setBool('sync_answers_to_ykb', legacy); // 做题同步到医考帮默认开启
  }
  if (!prefs.containsKey('sync_redo_to_ykb')) {
    await prefs.setBool('sync_redo_to_ykb', true); // 章节重做同步到医考帮默认开启
  }
  await QuestionSectionConfig.loadConfig();
}

Future<void> clearUserInfo() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setBool('loggedin', false);
  await prefs.remove('user_id');
  await prefs.remove('mobile');
  await prefs.remove('is_logout');
  await prefs.remove('email');
  await prefs.remove('avatar');
  await prefs.remove('nickname');
  await prefs.remove('user_uuid');
  await prefs.remove('sex');
  await prefs.remove('str_sex');
  await prefs.remove('token');
  await prefs.remove('secret');
  await prefs.remove('user_type');
  await prefs.remove('now_id');
  await prefs.remove('now_name');
  await prefs.remove('now_major_id');
  await prefs.remove('now_major_name');
  await prefs.remove('education_id');
  await prefs.remove('education_name');
  await prefs.remove('entrance_time');
}
