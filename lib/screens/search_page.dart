import 'package:flutter/material.dart';

import '../common/adaptive_route.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../repositories/question_search_repository.dart';
import 'question_detail_page.dart';

class QuestionSearchPage extends StatefulWidget {
  const QuestionSearchPage({super.key});

  @override
  State<QuestionSearchPage> createState() => _QuestionSearchPageState();
}

class _QuestionSearchPageState extends State<QuestionSearchPage> {
  final QuestionSearchRepository _repository = QuestionSearchRepository();
  final TextEditingController _controller = TextEditingController();

  String _keyword = '';
  final List<QuestionSearchResult> _allResults = <QuestionSearchResult>[];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<String> _history = <String>[];

  // 分页状态：每个题库当前已加载条数，及是否已加载完。
  final Map<String, int> _offsets = <String, int>{};
  final Set<String> _exhaustedBanks = <String>{};
  final ScrollController _scrollController = ScrollController();

  // 筛选条件
  String? _filterType;
  String? _filterSubject;
  String? _filterYear;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore => _offsets.keys.isNotEmpty &&
      (_exhaustedBanks.length < _offsets.length);

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadHistory() async {
    final history = await _repository.loadHistory();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _search(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _keyword = term;
      _loading = true;
      _error = null;
      _allResults.clear();
      _offsets.clear();
      _exhaustedBanks.clear();
      _filterType = null;
      _filterSubject = null;
      _filterYear = null;
    });
    _repository.addHistory(term).then((history) {
      if (mounted) setState(() => _history = history);
    });
    try {
      // 初始化各题库偏移，避免多轮并发导致重复/丢失。
      final banks = await _repository.listSearchBanks();
      if (mounted) {
        setState(() {
          for (final bank in banks) {
            _offsets[bank.bankId] = 0;
          }
        });
      }
      await _loadPage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadPage() async {
    if (_offsets.isEmpty) return;
    final keyword = _keyword;
    // 取尚未加载完的题库。
    final pending = _offsets.keys
        .where((bankId) => !_exhaustedBanks.contains(bankId))
        .toList();
    if (pending.isEmpty) return;

    if (_allResults.isEmpty) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final offsets = {
        for (final bankId in pending) bankId: _offsets[bankId] ?? 0,
      };
      final page = await _repository.loadPage(keyword, offsets);
      if (!mounted) return;
      setState(() {
        int added = 0;
        pending.forEach((bankId) {
          final results = page[bankId];
          if (results == null) {
            _exhaustedBanks.add(bankId);
            return;
          }
          _offsets[bankId] = (_offsets[bankId] ?? 0) + results.length;
          added += results.length;
          _allResults.addAll(results);
          if (results.length < QuestionSearchRepository.pageSize) {
            _exhaustedBanks.add(bankId);
          }
        });
        _loading = false;
        _loadingMore = false;
        if (added == 0) {
          // 没有任何新增结果，视为全部加载完。
          pending.forEach(_exhaustedBanks.add);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = _allResults.isEmpty ? '搜索失败：$e' : null;
      });
      if (_allResults.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败：$e')),
        );
      }
    }
  }

  Future<void> _loadMore() => _loadPage();

  void _onHistoryTap(String term) {
    _controller.text = term;
    _search(term);
  }

  Future<void> _deleteHistory(String term) async {
    final history = await _repository.removeHistory(term);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _clearHistory() async {
    final history = await _repository.clearHistory();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _toggleCollection(QuestionSearchResult result) async {
    final target = !result.collection;
    setState(() => result.collection = target);
    try {
      await _repository.setCollection(result.questionId, target);
    } catch (e) {
      if (!mounted) return;
      setState(() => result.collection = !target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏操作失败：$e')),
      );
    }
  }

  Future<void> _openResult(QuestionSearchResult result) async {
    try {
      final question = await _repository.getQuestionById(
        result.bankId,
        result.questionId,
      );
      if (question == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('题目不存在或题库已变更')),
          );
        }
        return;
      }
      final fetchedUserQuestion = await _repository.getUserQuestionById(
        result.questionId,
      );
      final UserQuestion userQuestion =
          fetchedUserQuestion ??
          UserQuestion(
            id: result.questionId,
            chapterId: question.chapterId ?? '',
            chapterParentId: question.chapterParentId ?? '',
            cutQuestion: '',
            userAnswer: '',
            status: 0,
            collection: result.collection ? 1 : 0,
          );
      if (!mounted) return;
      final chapter = Chapter(
        id: question.chapterId ?? '',
        name: result.subjectName ?? result.bankName,
        subjectId: question.chapterParentId ?? '',
        correct: 0,
        incorrect: 0,
        total: 1,
        identityId: question.identityId,
      );
      await Navigator.push(
        context,
        adaptivePageRoute(
          builder: (_) => QuestionDetailPage(
            chapter: chapter,
            questions: [question],
            userQuestions: [userQuestion],
            questionIndex: 0,
            bankId: result.bankId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开题目失败：$e')),
        );
      }
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

  String _contextSnippet(String text, String term, {int radius = 24}) {
    final lowerText = text.toLowerCase();
    final index = lowerText.indexOf(term.toLowerCase());
    if (index < 0) {
      return text.length > 60 ? '${text.substring(0, 60)}…' : text;
    }
    final start = index - radius < 0 ? 0 : index - radius;
    final end = (index + term.length + radius) > text.length
        ? text.length
        : index + term.length + radius;
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  void _buildBottomSpans(
    QuestionSearchResult result,
    String term,
    TextStyle base,
    TextStyle highlight,
    TextStyle label,
    List<InlineSpan> out,
  ) {
    final fields = <MapEntry<String, String>>[
      MapEntry('选项', result.optionText),
      if (result.restore != null && result.restore!.isNotEmpty)
        MapEntry('考点还原', result.restore!),
      if (result.explain != null && result.explain!.isNotEmpty)
        MapEntry('解析', result.explain!),
    ];

    final lowerTerm = term.toLowerCase();
    var first = true;
    for (final field in fields) {
      final value = field.value;
      if (value.trim().isEmpty) continue;
      if (!value.toLowerCase().contains(lowerTerm)) continue;
      if (!first) out.add(TextSpan(text: '\n'));
      first = false;
      out.add(TextSpan(text: '${field.key} ', style: label));
      out.addAll(
        _highlightSpans(_contextSnippet(value, term), term, base, highlight),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        _history.isEmpty ? '输入关键词搜索所有题库中的题目' : '搜索历史',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) return _buildEmptyState();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '搜索历史',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        for (final term in _history)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(term),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '删除',
              onPressed: () => _deleteHistory(term),
            ),
            onTap: () => _onHistoryTap(term),
          ),
      ],
    );
  }

  List<String> get _typeOptions =>
      _allResults.map((r) => r.typeLabel).toSet().toList()..sort();

  List<String> get _subjectOptions => _allResults
      .map((r) => r.subjectName)
      .where((s) => s != null && s.isNotEmpty)
      .map((s) => s!)
      .toSet()
      .toList()
    ..sort();

  List<String> get _yearOptions => _allResults
      .map((r) => r.year)
      .where((s) => s != null && s.isNotEmpty)
      .map((s) => s!)
      .toSet()
      .toList()
    ..sort();

  List<QuestionSearchResult> get _filteredResults =>
      _allResults.where((r) {
        if (_filterType != null && r.typeLabel != _filterType) return false;
        if (_filterSubject != null &&
            (r.subjectName ?? '') != _filterSubject) {
          return false;
        }
        if (_filterYear != null && (r.year ?? '') != _filterYear) return false;
        return true;
      }).toList();

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                                '筛选结果',
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

  Widget _buildResultCard(QuestionSearchResult result) {
    final theme = Theme.of(context);
    final term = _keyword;
    final titleStyle =
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    final highlightStyle = TextStyle(
      fontWeight: FontWeight.bold,
      backgroundColor: Colors.yellow.withValues(alpha: 0.55),
      color: Colors.black87,
    );
    final snippetBase = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final labelStyle = TextStyle(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );

    final bottomSpans = <InlineSpan>[];
    _buildBottomSpans(
      result,
      term,
      snippetBase,
      highlightStyle,
      labelStyle,
      bottomSpans,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openResult(result),
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
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: result.collection ? '取消收藏' : '收藏',
                    icon: Icon(
                      result.collection
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 18,
                      color: result.collection
                          ? Colors.redAccent
                          : theme.disabledColor,
                    ),
                    onPressed: () => _toggleCollection(result),
                  ),
                ],
              ),
              if (bottomSpans.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: bottomSpans),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final results = _filteredResults;
    if (results.isEmpty) {
      return Center(
        child: Text(
          _allResults.isEmpty
              ? '未找到与“$_keyword”相关的题目'
              : '没有符合筛选条件的题目',
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        return _buildResultCard(results[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜索题干、选项、考点、解析',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _keyword = '';
                  _allResults.clear();
                  _offsets.clear();
                  _exhaustedBanks.clear();
                  _error = null;
                });
              },
            ),
          ),
        ),
        actions: [
          if (_keyword.isNotEmpty && _allResults.isNotEmpty)
            IconButton(
              tooltip: '筛选',
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterSheet,
            ),
        ],
      ),
      body: _keyword.isEmpty
          ? _buildHistory()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _buildResults(),
    );
  }
}
