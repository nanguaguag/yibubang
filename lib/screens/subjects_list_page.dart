import 'package:flutter/material.dart';

import '../common/app_strings.dart';
import '../models/subject.dart';

class SubjectsListPage extends StatefulWidget {
  @override
  _SubjectsListPageState createState() => _SubjectsListPageState();
}

class _SubjectsListPageState extends State<SubjectsListPage>
    with SingleTickerProviderStateMixin {
  Future<List<Subject>> subjectsFuture = fetchAllSubjects();
  List<Subject> _allSubjects = []; // 完整数据列表
  List<Subject> filteredSubjects = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  AnimationController? _animationController;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    // 获取数据后保存到_allSubjects和filteredSubjects中
    subjectsFuture.then((data) {
      setState(() {
        _allSubjects = data;
        filteredSubjects = data;
      });
    });
    // 初始化动画控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: const Offset(0, 0),
    ).animate(
      CurvedAnimation(
        parent: _animationController!,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 根据输入内容过滤数据
  void _filterSearchResults(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredSubjects = _allSubjects;
      } else {
        filteredSubjects = _allSubjects
            .where((item) => item.name.toLowerCase().contains(
                  query.toLowerCase(),
                ))
            .toList();
      }
    });
  }

  // 构建带高亮效果的文本组件
  Widget _buildHighlightedText(Subject subject, String query) {
    String text = subject.name;
    // 定义基本样式和高亮样式
    TextStyle normalStyle = TextStyle(
      fontSize: 15,
      decoration: TextDecoration.none,
    );
    TextStyle highlightStyle = TextStyle(
      fontSize: 15,
      color: Colors.red,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.none,
    );

    if (query.isEmpty) {
      return Text(text, style: normalStyle);
    }
    String lowerText = text.toLowerCase();
    String lowerQuery = query.toLowerCase();
    List<TextSpan> spans = [];
    int start = 0;
    int index = lowerText.indexOf(lowerQuery);
    while (index != -1) {
      // 添加匹配之前的文本
      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: normalStyle,
          ),
        );
      }
      // 添加匹配的文本，并进行高亮显示
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: highlightStyle,
        ),
      );
      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }
    // 添加剩余文本
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: normalStyle,
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Stack(
          children: [
            // 默认标题，当不处于搜索状态时显示
            Visibility(
              visible: !_isSearching,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(AppStrings.subjectsListTitle),
              ),
            ),
            // 搜索框，使用SlideTransition实现从右侧滑入效果
            Visibility(
              visible: _isSearching,
              child: SlideTransition(
                position: _slideAnimation!,
                child: TextField(
                  controller: _searchController,
                  autofocus: true, // 自动聚焦
                  onChanged: _filterSearchResults,
                  decoration: const InputDecoration(
                    hintText: '搜索课程...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            // 使用AnimatedSwitcher对图标进行动画切换
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _isSearching
                  ? const Icon(Icons.close, key: ValueKey('closeIcon'))
                  : const Icon(Icons.search, key: ValueKey('searchIcon')),
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  // 隐藏搜索框，反向动画
                  _animationController!.reverse();
                  _searchController.clear();
                  _filterSearchResults('');
                } else {
                  // 显示搜索框，执行正向动画
                  _animationController!.forward();
                }
                _isSearching = !_isSearching;
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Subject>>(
        future: subjectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 正在加载时显示进度条
            return const Center(child: LinearProgressIndicator());
          } else if (snapshot.hasError) {
            // 加载错误时显示错误信息
            return Center(child: Text('加载失败: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // 没有数据时显示提示
            return const Center(child: Text('没有数据'));
          } else {
            // 数据加载完成，使用filteredSubjects进行显示
            return ListView.builder(
              itemCount: filteredSubjects.length,
              itemBuilder: (context, index) {
                Subject subject = filteredSubjects[index];
                return ListTile(
                  // 使用_highlightedText来显示匹配字符的高亮效果
                  title: _buildHighlightedText(
                    subject,
                    _searchController.text,
                  ),
                  tileColor:
                      subject.selected == 1 ? Colors.blue.shade100 : null,
                  onTap: () {
                    setState(() {
                      toggleSubjectSelected(subject.id); // 更新数据库状态
                      subject.selected = subject.selected == 1 ? 0 : 1;
                    });
                  },
                  trailing: subject.selected == 1
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.check_circle_outline),
                );
              },
            );
          }
        },
      ),
    );
  }
}
