import 'package:flutter/material.dart';
import '../common/app_shapes.dart';
import '../common/platform_adaptive.dart';
import '../models/ai_search.dart';
import '../services/textbook_client.dart';
import 'textbook_reader_page.dart';
import '../widgets/textbook_thumbnail.dart';

/// 教材检索页面，遵循医不帮统一的 Material 3 规范与课程选择 UI，支持单选/多选教材。
class TextbookSearchPage extends StatefulWidget {
  final TextbookGateway? gateway;
  final Future<void> Function(BuildContext, AiCitation)? openPage;
  const TextbookSearchPage({super.key, this.gateway, this.openPage});

  @override
  State<TextbookSearchPage> createState() => _TextbookSearchPageState();
}

class _TextbookSearchPageState extends State<TextbookSearchPage>
    with SingleTickerProviderStateMixin {
  late final TextbookGateway gateway;
  final input = TextEditingController();
  List<Map<String, dynamic>> books = [];
  List<TextbookHit> hits = [];
  Set<String> selectedBookIds = {};
  String next = '';
  String query = '';
  String? error;
  bool busy = false;
  bool searched = false;
  bool opening = false;
  AiQuota? quota;

  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? TextbookClient();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    try {
      final data = await gateway.books();
      if (mounted) {
        setState(
          () => books = {for (final b in data) b['book_id']: b}.values.toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  String get _primaryBookId {
    if (selectedBookIds.length == 1) return selectedBookIds.first;
    return '';
  }

  Future<void> _search({bool more = false}) async {
    final text = more ? query : input.text.trim();
    if (busy || text.isEmpty) return;
    if (text.length > 2000) {
      setState(() => error = '搜索内容最多 2000 字');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // 若单选则向后端传递指定教材 ID，若多选/全选则全库检索后客户端匹配
      final data = await gateway.search(
        text,
        bookId: _primaryBookId,
        pageToken: more ? next : '',
      );
      if (!mounted) return;

      var newItems = data.items;
      if (selectedBookIds.length > 1) {
        newItems = newItems
            .where((hit) => selectedBookIds.contains(hit.citation.bookId))
            .toList();
      }

      setState(() {
        query = text;
        hits = more ? [...hits, ...newItems] : newItems;
        next = data.nextPageToken;
        quota = data.quota;
        searched = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open(AiCitation citation) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      if (widget.openPage != null) {
        await widget.openPage!(context, citation);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextbookReaderPage(citation: citation),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  /// 唤起「直接查页」弹窗，允许用户指定任意教材与页码一键调阅原版 PDF 扫描件
  Future<void> _showDirectPageDialog() async {
    if (books.isEmpty) {
      await _loadBooks();
      if (!mounted) return;
      if (books.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在加载教材列表，请稍后重试')),
        );
        return;
      }
    }
    if (!mounted) return;

    final initialBookId = selectedBookIds.isNotEmpty
        ? selectedBookIds.first
        : (books.first['book_id'] as String);

    Map<String, dynamic> selectedBook = books.firstWhere(
      (b) => b['book_id'] == initialBookId,
      orElse: () => books.first,
    );

    final pageController = TextEditingController();
    String? inputError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final pageCount = (selectedBook['page_count'] as num?)?.toInt() ?? 0;

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.find_in_page_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('直接查阅教材原页'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '选择指定课本并输入页码，可直接调阅高清扫描原页。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '目标教材',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(AppShapes.medium),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedBook['book_id'] as String,
                          items: books.map((b) {
                            final title = b['title'] as String;
                            final count = b['page_count'];
                            return DropdownMenuItem<String>(
                              value: b['book_id'] as String,
                              child: Text(
                                '《$title》${count != null ? ' (共 $count 页)' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (newId) {
                            if (newId != null) {
                              setDialogState(() {
                                selectedBook = books.firstWhere(
                                  (b) => b['book_id'] == newId,
                                );
                                inputError = null;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PDF 页码',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: pageController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: pageCount > 0 ? '1 ~ $pageCount' : '请输入数字页码',
                        suffixText: pageCount > 0 ? '/ $pageCount 页' : null,
                        errorText: inputError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppShapes.medium),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) {
                        if (inputError != null) {
                          setDialogState(() => inputError = null);
                        }
                      },
                      onSubmitted: (_) {
                        _submitDirectPage(
                          dialogContext,
                          selectedBook,
                          pageController.text,
                          (err) => setDialogState(() => inputError = err),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    _submitDirectPage(
                      dialogContext,
                      selectedBook,
                      pageController.text,
                      (err) => setDialogState(() => inputError = err),
                    );
                  },
                  child: const Text('立即查阅'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _submitDirectPage(
    BuildContext dialogContext,
    Map<String, dynamic> book,
    String rawPage,
    void Function(String) onError,
  ) {
    final page = int.tryParse(rawPage.trim());
    final pageCount = (book['page_count'] as num?)?.toInt() ?? 0;

    if (page == null) {
      onError('请输入有效的数字页码');
      return;
    }
    if (page < 1 || (pageCount > 0 && page > pageCount)) {
      onError('页码超出范围 (有效: 1 ~ ${pageCount > 0 ? pageCount : 1})');
      return;
    }

    Navigator.of(dialogContext).pop();

    final citation = AiCitation(
      number: 1,
      questionId: '',
      title: '${book['title']} · PDF 第 $page 页',
      kind: 'textbook',
      bookId: book['book_id'] as String,
      bookTitle: book['title'] as String,
      sourceVersion: book['source_version'] as String? ?? '',
      edition: book['edition'] as String? ?? '',
      pdfPage: page,
      pageCount: pageCount,
      printedPage: '',
    );

    _open(citation);
  }

  /// 唤起直接多选教材的自适应模态框
  Future<void> _showBookSelector() async {
    final selected = await showAdaptiveModalSheet<Set<String>>(
      context: context,
      title: '选择检索教材',
      builder: (sheetContext) {
        String filterText = '';
        Set<String> tempSelected = Set.from(selectedBookIds);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final filteredBooks = books.where((b) {
              if (filterText.isEmpty) return true;
              final title = (b['title'] as String? ?? '').toLowerCase();
              return title.contains(filterText.toLowerCase());
            }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isDesktopLayout(sheetContext))
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tempSelected.isEmpty
                                ? '检索全部教材 (${books.length} 本)'
                                : '已选 ${tempSelected.length} 本教材',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (tempSelected.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setModalState(() => tempSelected.clear()),
                            child: const Text('全部'),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  // 搜索过滤栏
                  Container(
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppShapes.large),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search_rounded, size: 20),
                        hintText: '搜索教材名称...',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) =>
                          setModalState(() => filterText = val.trim()),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 全部教材选项（点击即全选/清空特定单项）
                  Material(
                    color: tempSelected.isEmpty
                        ? scheme.primaryContainer.withValues(alpha: 0.35)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppShapes.medium),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppShapes.medium),
                      ),
                      title: const Text(
                        '全部教材',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('在知识库全部 ${books.length} 本课本中深度检索'),
                      trailing: Checkbox(
                        value: tempSelected.isEmpty,
                        onChanged: (_) {
                          setModalState(() => tempSelected.clear());
                        },
                      ),
                      onTap: () {
                        setModalState(() => tempSelected.clear());
                      },
                    ),
                  ),
                  const Divider(height: 14),

                  Expanded(
                    child: filteredBooks.isEmpty
                        ? const Center(child: Text('没有找到匹配的教材'))
                        : ListView.builder(
                            itemCount: filteredBooks.length,
                            itemBuilder: (context, index) {
                              final b = filteredBooks[index];
                              final id = b['book_id'] as String;
                              final title = b['title'] as String;
                              final count = b['page_count'];
                              final isSelected = tempSelected.contains(id);

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Material(
                                  color: isSelected
                                      ? scheme.primaryContainer
                                          .withValues(alpha: 0.35)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.medium),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppShapes.medium),
                                    ),
                                    title: Text(
                                      title,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: count != null
                                        ? Text('共 $count 页')
                                        : null,
                                    trailing: Checkbox(
                                      value: isSelected,
                                      onChanged: (val) {
                                        setModalState(() {
                                          if (val == true) {
                                            tempSelected.add(id);
                                          } else {
                                            tempSelected.remove(id);
                                          }
                                        });
                                      },
                                    ),
                                    onTap: () {
                                      setModalState(() {
                                        if (isSelected) {
                                          tempSelected.remove(id);
                                        } else {
                                          tempSelected.add(id);
                                        }
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          setModalState(() => tempSelected.clear());
                        },
                        child: const Text('重置为全部'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, tempSelected),
                        child: Text(tempSelected.isEmpty
                            ? '检索全部'
                            : '确定 (${tempSelected.length} 本)'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        selectedBookIds = selected;
        hits = [];
        next = '';
        searched = false;
      });
    }
  }

  Widget _snippet(String text) {
    final terms = RegExp(
      r'[A-Za-z0-9+-]{2,}|[\u4e00-\u9fff]{2,}',
    ).allMatches(query).map((m) => m.group(0)!).take(20).toList();
    final spans = <TextSpan>[];
    var position = 0;
    if (terms.isNotEmpty) {
      final pattern = RegExp(
        terms.map(RegExp.escape).join('|'),
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(text)) {
        if (match.start > position) {
          spans.add(TextSpan(text: text.substring(position, match.start)));
        }
        spans.add(
          TextSpan(
            text: match.group(0),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            ),
          ),
        );
        position = match.end;
      }
    }
    spans.add(TextSpan(text: text.substring(position)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
    );
  }

  String _bookTitle(String id) {
    return books
            .where((b) => b['book_id'] == id)
            .firstOrNull?['title'] as String? ??
        '教材';
  }

  String get _currentScopeLabel {
    if (selectedBookIds.isEmpty) return '全部教材';
    if (selectedBookIds.length == 1) return _bookTitle(selectedBookIds.first);
    return '已选 ${selectedBookIds.length} 本教材';
  }

  @override
  void dispose() {
    input.dispose();
    if (widget.gateway == null) gateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('教材检索'),
        actions: [
          TextButton.icon(
            onPressed: _showDirectPageDialog,
            icon: const Icon(Icons.find_in_page_outlined, size: 18),
            label: const Text('直接查页'),
          ),
          Tooltip(
            message: '教材检索与 AI 共用每日 200 次额度；直接查页每次消耗 1 次',
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppShapes.full),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        quota == null ? '每日 200 次' : '今日剩余 ${quota!.remaining}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              // 1. 顶部现代 Material 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppShapes.extraLarge),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: scheme.onSurfaceVariant, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: input,
                          onSubmitted: (_) => _search(),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: '搜索知识点，找到教材原页...',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (input.text.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            input.clear();
                            setState(() {});
                          },
                        ),
                      IconButton.filled(
                        tooltip: '检索教材',
                        onPressed: busy ? null : () => _search(),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. 检索范围选择条（支持多选教材标签与清空）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppShapes.medium),
                  ),
                  child: Row(
                    children: [
                      //Icon(Icons.tune_rounded, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '检索范围：',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: Text(_currentScopeLabel),
                                selected: selectedBookIds.isNotEmpty,
                                onSelected: (_) => _showBookSelector(),
                              ),
                              if (selectedBookIds.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                ActionChip(
                                  avatar: const Icon(Icons.close_rounded, size: 14),
                                  label: const Text('重置全部'),
                                  onPressed: () => setState(() {
                                    selectedBookIds.clear();
                                    hits = [];
                                    next = '';
                                    searched = false;
                                  }),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showBookSelector,
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(
                          selectedBookIds.length > 1 ? '修改范围' : '切换',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. 搜索加载动画
              if (busy)
                LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),

              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppShapes.medium),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 18, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. 检索结果与空状态
              Expanded(
                child: !searched && hits.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer
                                      .withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  size: 40,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '从知识点回到教材',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${books.length} 本权威医学教科书 · 毫秒全文检索 · 原页直达',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.medium),
                                  border: Border.all(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  '输入疾病、解剖结构、药物机制等医学概念，直接定位对应教材原版书页与插图。支持多选课本联合检索。',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : hits.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.find_in_page_outlined,
                                  size: 56,
                                  color: scheme.outline,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '未找到相关教材页',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '试试更具体的专业术语，或切换至「全部教材」检索',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                            itemCount: hits.length + (next.isNotEmpty ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == hits.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: FilledButton.tonalIcon(
                                      onPressed: busy
                                          ? null
                                          : () => _search(more: true),
                                      icon: const Icon(Icons.expand_more_rounded),
                                      label: const Text('查看更多教材页'),
                                    ),
                                  ),
                                );
                              }
                              final hit = hits[i];
                              final c = hit.citation;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.large),
                                  side: BorderSide(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                color: scheme.surfaceContainerLow,
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _open(c),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.menu_book_rounded,
                                                    color: scheme.primary,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      c.bookTitle.isEmpty
                                                          ? c.title
                                                          : '《${c.bookTitle}》',
                                                      style: theme
                                                          .textTheme.titleMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right_rounded,
                                                    size: 20,
                                                    color: scheme.onSurfaceVariant,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: scheme.primaryContainer
                                                          .withValues(alpha: 0.6),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              AppShapes.xs),
                                                    ),
                                                    child: Text(
                                                      'PDF 第 ${c.pdfPage} 页',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: scheme
                                                            .onPrimaryContainer,
                                                      ),
                                                    ),
                                                  ),
                                                  if (c.printedPage.isNotEmpty)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: scheme
                                                            .surfaceContainerHighest,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                AppShapes.xs),
                                                      ),
                                                      child: Text(
                                                        '书页 ${c.printedPage}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                  if (c.edition.isNotEmpty)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: scheme
                                                            .surfaceContainerHighest,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                AppShapes.xs),
                                                      ),
                                                      child: Text(
                                                        c.edition,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              if (c.needsReview)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                      bottom: 8),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: scheme.errorContainer
                                                          .withValues(alpha: 0.4),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              AppShapes.xs),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            Icons.info_outline_rounded,
                                                            size: 13,
                                                            color: scheme.error),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '符号、公式请核对原页',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: scheme.error,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              _snippet(hit.snippet),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              AppShapes.small),
                                          child: TextbookThumbnail(
                                            key: ValueKey(
                                              '${c.bookId}:${c.sourceVersion}:${c.pdfPage}',
                                            ),
                                            citation: c,
                                            gateway: gateway,
                                            width: MediaQuery.sizeOf(context)
                                                        .width <
                                                    400
                                                ? 68
                                                : 96,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
