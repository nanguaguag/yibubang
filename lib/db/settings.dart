import 'package:shared_preferences/shared_preferences.dart';

// 存储数据
Future<void> initSettings() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('isDarkMode')) {
    await prefs.setBool('isDarkMode', false); // 默认关闭暗黑模式
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
  if (!prefs.containsKey('identityId')) {
    await prefs.setString('identityId', '110701'); // 默认identity: 临床题库
  }
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
