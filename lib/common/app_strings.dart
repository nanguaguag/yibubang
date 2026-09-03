import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class AppStrings {
  static const Map<String, IconData> identityIconMap = {
    '20101': Symbols.health_metrics,
    '30401': Symbols.dentistry_rounded,
    '11070': Symbols.bloodtype_rounded,
    '2': Symbols.health_metrics,
    '3': Symbols.dentistry_rounded,
    '4': Symbols.health_and_safety_rounded,
    '5': Symbols.cannabis,
    '6': Symbols.pediatrics,
    '7': Symbols.pill_rounded,
    '8': Symbols.cannabis,
    '10': Symbols.biotech_sharp,
    '11': Symbols.bloodtype_rounded,
    '12': Symbols.medical_services,
  };
  static const String appTitle = '医不帮';
  static const String selectedSubjectsTitle = '我的课程';
  static const String statisticsTitle = '统计';
  static const String myPageTitle = '我的';
  static const String subjectsListTitle = '选择课程';
  static const List<String> cutTypes = ['全部', '已斩', '未斩'];
  static const List<String> questionTypes = ['全部', '单选题', '多选题'];
  static const List<String> categories = ['全部', '做错的', '收藏的', '未做的'];
  static const List<String> modesList = ['练习', '快刷', '测试', '背题'];
  static const bool needTransfer = true;
}
