import 'package:shared_preferences/shared_preferences.dart';

// 存储数据
Future<void> initSettings() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('isDarkMode') == null) {
    await prefs.setBool('isDarkMode', false); // 默认关闭暗黑模式
  }
  if (prefs.getInt('cutType') == null) {
    await prefs.setInt('cutType', 0); // 斩题: 全部
  }
  if (prefs.getInt('questionType') == null) {
    await prefs.setInt('questionType', 0); // 题型: 全部
  }
  if (prefs.getInt('category') == null) {
    await prefs.setInt('category', 0); // 分类: 全部
  }
  if (prefs.getInt('mode') == null) {
    await prefs.setInt('mode', 0); // 模式: 练习模式
  }
}
