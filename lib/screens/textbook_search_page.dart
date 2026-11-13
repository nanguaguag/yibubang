import 'package:flutter/material.dart';
import '../models/ai_search.dart';
import '../services/textbook_client.dart';
import 'textbook_reader_page.dart';
import '../widgets/textbook_thumbnail.dart';

class TextbookSearchPage extends StatefulWidget {
  final TextbookGateway? gateway;
  final Future<void> Function(BuildContext, AiCitation)? openPage;
  const TextbookSearchPage({super.key, this.gateway, this.openPage});
  @override
  State<TextbookSearchPage> createState() => _TextbookSearchPageState();
}

class _TextbookSearchPageState extends State<TextbookSearchPage> {
  late final TextbookGateway gateway;
  final input = TextEditingController();
  List<Map<String, dynamic>> books = [];
  List<TextbookHit> hits = [];
  String bookId = '';
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
      final data = await gateway.search(
        text,
        bookId: bookId,
        pageToken: more ? next : '',
      );
      if (!mounted) return;
      setState(() {
        query = text;
        hits = more ? [...hits, ...data.items] : data.items;
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

  @override
  void dispose() {
    input.dispose();
    if (widget.gateway == null) gateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('教材检索')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: TextField(
                  controller: input,
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索知识点，找到教材原页',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      tooltip: '检索教材',
                      onPressed: busy ? null : () => _search(),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: bookId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '检索范围',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('全部教材'),
                          ),
                          for (final b in books)
                            DropdownMenuItem(
                              value: b['book_id'] as String,
                              child: Text(
                                b['title'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                bookId = value ?? '';
                                hits = [];
                                next = '';
                                searched = false;
                              }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: '教材检索与 AI 共用每日 200 次额度；直接查页每次消耗 1 次',
                      child: Text(
                        quota == null ? '直接查页' : '今日剩余 ${quota!.remaining}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy) const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: !searched && hits.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 64,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '从知识点回到教材',
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${books.length} 本教材 · 文字搜索 · 原页阅读',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                '输入疾病、症状或概念，查看对应教材页。',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : hits.isEmpty
                    ? const Center(child: Text('未找到相关页，试试更具体的医学术语'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: hits.length + (next.isNotEmpty ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == hits.length) {
                            return TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _search(more: true),
                              child: const Text('查看更多教材页'),
                            );
                          }
                          final hit = hits[i];
                          final c = hit.citation;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _open(c),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.menu_book_outlined,
                                                color:
                                                    theme.colorScheme.primary,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  c.bookTitle.isEmpty
                                                      ? c.title
                                                      : '《${c.bookTitle}》',
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'PDF 第 ${c.pdfPage} 页${c.printedPage.isEmpty ? '' : ' · 书页 ${c.printedPage}'}${c.edition.isEmpty ? '' : ' · ${c.edition}'}',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          if (c.needsReview)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Text('符号、公式请核对原页'),
                                            ),
                                          _snippet(hit.snippet),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TextbookThumbnail(
                                      key: ValueKey(
                                        '${c.bookId}:${c.sourceVersion}:${c.pdfPage}',
                                      ),
                                      citation: c,
                                      gateway: gateway,
                                      width:
                                          MediaQuery.sizeOf(context).width < 400
                                          ? 64
                                          : 90,
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
