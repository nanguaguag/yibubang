import 'package:flutter/material.dart';

import '../common/app_strings.dart';
import '../models/subject.dart';

class SubjectsListPage extends StatefulWidget {
  const SubjectsListPage({super.key});

  @override
  State<SubjectsListPage> createState() => _SubjectsListPageState();
}

class _SubjectsListPageState extends State<SubjectsListPage>
    with SingleTickerProviderStateMixin {
  late Future<List<SubjectTreeNode>> subjectsFuture;
  List<SubjectTreeNode> _allNodes = [];
  List<SubjectTreeNode> _filteredNodes = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    subjectsFuture = getSubjectTreeByIdentity();
    subjectsFuture.then((data) {
      if (!mounted) return;
      setState(() {
        _allNodes = data;
        _filteredNodes = data;
      });
    });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: const Offset(0, 0),
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<SubjectTreeNode> _filterTree(
    List<SubjectTreeNode> nodes,
    String query,
  ) {
    if (query.isEmpty) return nodes;
    final lowerQuery = query.toLowerCase();
    final filtered = <SubjectTreeNode>[];

    for (final node in nodes) {
      final matchingSubjects = node.subjects
          .where((subject) => subject.name.toLowerCase().contains(lowerQuery))
          .toList();
      final matchingChildren = _filterTree(node.children, query);
      if (matchingSubjects.isNotEmpty || matchingChildren.isNotEmpty) {
        filtered.add(
          node.copyWith(
            subjects: matchingSubjects,
            children: matchingChildren,
          ),
        );
      }
    }
    return filtered;
  }

  // 根据输入内容过滤数据，同时保留匹配课程所在的 Identity 路径。
  void _filterSearchResults(String query) {
    if (!mounted) return;
    setState(() {
      _filteredNodes = _filterTree(_allNodes, query.trim());
    });
  }

  // 构建带高亮效果的课程名称。
  Widget _buildHighlightedText(Subject subject, String query) {
    final text = subject.name;
    const normalStyle = TextStyle(
      fontSize: 15,
      decoration: TextDecoration.none,
    );
    const highlightStyle = TextStyle(
      fontSize: 15,
      color: Colors.red,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.none,
    );

    if (query.isEmpty) {
      return Text(text, style: normalStyle);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    var index = lowerText.indexOf(lowerQuery);
    while (index != -1) {
      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: normalStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: highlightStyle,
        ),
      );
      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }
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

  Future<void> _toggleSubject(Subject subject) async {
    final previousValue = subject.selected;
    setState(() {
      subject.selected = previousValue == 1 ? 0 : 1;
    });

    try {
      await toggleSubjectSelected(subject);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        subject.selected = previousValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存课程选择失败: $error')),
      );
    }
  }

  Widget _buildSubjectTile(Subject subject) {
    return ListTile(
      title: _buildHighlightedText(subject, _searchController.text.trim()),
      tileColor: subject.selected == 1
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
          : null,
      onTap: () => _toggleSubject(subject),
      trailing: subject.selected == 1
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.check_circle_outline),
    );
  }

  Widget _buildIdentityNode(SubjectTreeNode node) {
    final query = _searchController.text.trim();
    final children = <Widget>[
      ...node.subjects.map(_buildSubjectTile),
      ...node.children.map(_buildIdentityNode),
    ];

    return ExpansionTile(
      key: ValueKey('${node.identity.id}-${query.isNotEmpty}'),
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        node.identity.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle:
          node.subjects.isEmpty ? null : Text('${node.subjects.length} 门课程'),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Stack(
          children: [
            Visibility(
              visible: !_isSearching,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(AppStrings.subjectsListTitle),
              ),
            ),
            Visibility(
              visible: _isSearching,
              child: SlideTransition(
                position: _slideAnimation,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
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
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _isSearching
                  ? const Icon(Icons.close, key: ValueKey('closeIcon'))
                  : const Icon(Icons.search, key: ValueKey('searchIcon')),
            ),
            onPressed: () {
              if (_isSearching) {
                _animationController.reverse();
                _searchController.clear();
                _filterSearchResults('');
              } else {
                _animationController.forward();
              }
              setState(() {
                _isSearching = !_isSearching;
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<SubjectTreeNode>>(
        future: subjectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: LinearProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('没有数据'));
          }
          if (_filteredNodes.isEmpty) {
            return const Center(child: Text('没有匹配的课程'));
          }
          return ListView(
            children: _filteredNodes.map(_buildIdentityNode).toList(),
          );
        },
      ),
    );
  }
}
