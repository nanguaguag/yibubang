import 'package:flutter/material.dart';
import '../constants/app_strings.dart';

// 我的页面，展示用户的收藏/评论/笔记

class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.myPageTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(
        child: Text('用户相关信息', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
