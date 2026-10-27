import 'package:flutter/material.dart';

import '../common/platform_adaptive.dart';
import '../common/question_navigation.dart';
import '../repositories/question_search_repository.dart';

class UserQuestionsListPage extends StatefulWidget {
  final UserQuestionsType type;

  const UserQuestionsListPage({
    super.key,
    required this.type,
  });

  @override
  State<UserQuestionsListPage> createState() => _UserQuestionsListPageState();
}

class _UserQuestionsListPageState extends State<UserQuestionsListPage> {
  final QuestionSearchRepository _repository = QuestionSearchRepository();
  final TextEditingController _searchController = TextEditingController();

  List<QuestionSearchResult> _allQuestions = [];
  bool _loading = true;
  String? _error;

  bool _isSearching = false;
  String _keyword = '';

  // 筛选条件
  String? _filterType;
  String? _filterSubject;
  String? _filterYear;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.type) {
      case UserQuestionsType.collection:
        return '我的收藏';
      case UserQuestionsType.mistake:
        return '我的错题';
      case UserQuestionsType.cut:
        return '已斩的题';
    }
  }

  String get _emptyMessage {
    switch (widget.type) {
      case UserQuestionsType.collection:
        return '暂无收藏的题目';
      case UserQuestionsType.mistake:
        return '暂无错题记录，继续保持！';
      case UserQuestionsType.cut:
        return '暂无已斩的题目';
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _repository.loadUserQuestions(widget.type);
      if (!mounted) return;
      setState(() {
        _allQuestions = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载题目失败：$e';
        _loading = false;
      });
    }
  }

  List<String> get _typeOptions =>
      _allQuestions.map((r) => r.typeLabel).toSet().toList()..sort();

  List<String> get _subjectOptions => _allQuestions
      .map((r) => r.subjectName)
      .where((s) => s != null && s.isNotEmpty)
      .map((s) => s!)
      .toSet()
      .toList()
    ..sort();

  List<String> get _yearOptions => _allQuestions
      .map((r) => r.year)
      .where((s) => s != null && s.isNotEmpty)
      .map((s) => s!)
      .toSet()
      .toList()
    ..sort();

  bool get _hasActiveFilters =>
      _filterType != null || _filterSubject != null || _filterYear != null;

  List<QuestionSearchResult> get _filteredQuestions {
    final term = _keyword.trim().toLowerCase();
    return _allQuestions.where((r) {
      if (_filterType != null && r.typeLabel != _filterType) return false;
      if (_filterSubject != null && (r.subjectName ?? '') != _filterSubject) {
        return false;
      }
      if (_filterYear != null && (r.year ?? '') != _filterYear) return false;
      if (term.isNotEmpty) {
        final inStem = r.stem.toLowerCase().contains(term);
        final inOption = r.optionText.toLowerCase().contains(term);
        final inRestore = (r.restore ?? '').toLowerCase().contains(term);
        final inExplain = (r.explain ?? '').toLowerCase().contains(term);
        if (!inStem && !inOption && !inRestore && !inExplain) return false;
      }
      return true;
    }).toList();
  }

  void _showFilterSheet() {
    showAdaptiveModalSheet(
      context: context,
      title: '筛选题目',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget section(
              String title,
              List<String> options,
              String? selected,
              void Function(String?) onSelect,
            ) {
              if (options.isEmpty) return const SizedBox.shrink();
              final all = <String>['全部', ...options];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final opt in all)
                          ChoiceChip(
                            label: Text(opt),
                            selected: (opt == '全部' && selected == null) ||
                                opt == selected,
                            onSelected: (_) {
                              onSelect(opt == '全部' ? null : opt);
                              setModalState(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '筛选题目',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _filterType = null;
                                  _filterSubject = null;
                                  _filterYear = null;
                                });
                                setModalState(() {});
                              },
                              child: const Text('重置'),
                            ),
                          ],
                        ),
                      ),
                      section('题型', _typeOptions, _filterType,
                          (v) => setState(() => _filterType = v)),
                      section('所在课程', _subjectOptions, _filterSubject,
                          (v) => setState(() => _filterSubject = v)),
                      section('时间', _yearOptions, _filterYear,
                          (v) => setState(() => _filterYear = v)),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleCollection(QuestionSearchResult result) async {
    final next = !result.collection;
    await _repository.setCollection(result.questionId, next);
    setState(() {
      result.collection = next;
      if (widget.type == UserQuestionsType.collection && !next) {
        _allQuestions.removeWhere((r) => r.questionId == result.questionId);
      }
    });
  }

  Future<void> _toggleCut(QuestionSearchResult result) async {
    final next = !result.isCut;
    await _repository.setCutQuestion(result.questionId, next);
    setState(() {
      result.isCut = next;
      if (widget.type == UserQuestionsType.cut && !next) {
        _allQuestions.removeWhere((r) => r.questionId == result.questionId);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? '已加入已斩题目' : '已取消斩题并放回题库'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  List<InlineSpan> _highlightSpans(
    String text,
    String term,
    TextStyle base,
    TextStyle highlight,
  ) {
    if (term.isEmpty) return [TextSpan(text: text, style: base)];
    final spans = <InlineSpan>[];
    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();
    var start = 0;
    var index = lowerText.indexOf(lowerTerm);
    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: base));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + term.length),
          style: highlight,
        ),
      );
      start = index + term.length;
      index = lowerText.indexOf(lowerTerm, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
    return spans;
  }

  Widget _buildQuestionCard(QuestionSearchResult result) {
    final theme = Theme.of(context);
    final term = _keyword.trim();
    final titleStyle =
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    final highlightStyle = TextStyle(
      fontWeight: FontWeight.bold,
      backgroundColor: Colors.yellow.withValues(alpha: 0.55),
      color: Colors.black87,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await openQuestionDetailPage(
            context,
            result,
            defaultShowCutContent: widget.type == UserQuestionsType.cut,
          );
          if (mounted) {
            _loadQuestions();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                result.typeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          const WidgetSpan(child: SizedBox(width: 6)),
                          ..._highlightSpans(
                            result.stem,
                            term,
                            titleStyle,
                            highlightStyle,
                          ),
                        ],
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (widget.type == UserQuestionsType.collection)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: result.collection ? '取消收藏' : '收藏',
                      icon: Icon(
                        result.collection
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 20,
                        color: result.collection
                            ? Colors.redAccent
                            : theme.disabledColor,
                      ),
                      onPressed: () => _toggleCollection(result),
                    )
                  else if (widget.type == UserQuestionsType.cut)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '放回题库 (取消已斩)',
                      icon: const Icon(
                        Icons.content_cut,
                        size: 20,
                        color: Colors.deepPurple,
                      ),
                      onPressed: () => _toggleCut(result),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.only(top: 4, right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '错题',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (result.subjectName != null &&
                      result.subjectName!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        result.subjectName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (result.year != null && result.year!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${result.year}年',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredQuestions;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索题目内容/解析...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _keyword = v),
              )
            : Text('$_title (${_allQuestions.length})'),
        actions: [
          IconButton(
            tooltip: _isSearching ? '取消搜索' : '搜索题目',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _keyword = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: '筛选',
            icon: Badge(
              isLabelVisible: _hasActiveFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _allQuestions.isEmpty
                  ? Center(
                      child: Text(
                        _emptyMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            '没有符合筛选条件的题目',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 6, bottom: 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildQuestionCard(filtered[index]);
                          },
                        ),
    );
  }
}
