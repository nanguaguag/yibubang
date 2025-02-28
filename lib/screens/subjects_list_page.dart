import 'package:flutter/material.dart';
import '../common/app_strings.dart';
import '../db/subject.dart';

class SubjectsListPage extends StatefulWidget {
  @override
  _SubjectsListPageState createState() => _SubjectsListPageState();
}

class _SubjectsListPageState extends State<SubjectsListPage> {
  Future<List<Subject>> subjectsFuture = fetchAllSubjects();
  List<Subject> _allSubjects = []; // 保存完整数据
  List<Subject> filteredSubjects = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 动态筛选函数，直接使用_allSubjects作为数据源
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

  @override
  void initState() {
    super.initState();
    subjectsFuture.then((data) {
      setState(() {
        _allSubjects = data;
        filteredSubjects = data;
      });
    });
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
        // 使用AnimatedSwitcher在标题与搜索框之间切换
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _isSearching
              ? TextField(
                  key: const ValueKey('searchField'),
                  controller: _searchController,
                  onChanged: _filterSearchResults,
                  style: const TextStyle(color: Colors.black54),
                  decoration: const InputDecoration(
                    hintText: '搜索课程...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                )
              : Text(
                  AppStrings.subjectsListTitle,
                  key: const ValueKey('title'),
                ),
        ),
        actions: [
          IconButton(
            // 使用AnimatedSwitcher对图标进行动画切换
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 100),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return RotationTransition(turns: animation, child: child);
              },
              child: _isSearching
                  ? const Icon(Icons.close, key: ValueKey('closeIcon'))
                  : const Icon(Icons.search, key: ValueKey('searchIcon')),
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _filterSearchResults('');
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
                  title: Text(subject.name),
                  tileColor: subject.selected == 1 ? Colors.blue.shade50 : null,
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
