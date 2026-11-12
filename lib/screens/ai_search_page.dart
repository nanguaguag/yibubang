import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/adaptive_route.dart';
import '../common/animation.dart';
import '../common/platform_adaptive.dart';
import '../models/ai_search.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../repositories/question_search_repository.dart';
import '../services/ai_search_controller.dart';
import '../widgets/ai_answer_text.dart';
import '../widgets/gemini_mark.dart';
import 'question_detail_page.dart';

class AiSearchPage extends StatefulWidget {
  final AiSearchController? controller;
  final Future<void> Function(BuildContext, AiCitation)? openCitation;
  const AiSearchPage({super.key, this.controller, this.openCitation});
  @override
  State<AiSearchPage> createState() => _AiSearchPageState();
}

class _AiSearchPageState extends State<AiSearchPage> {
  late final AiSearchController ai;
  final input = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();
  int? editing;
  bool followBottom = true;
  bool openingCitation = false;
  @override
  void initState() {
    super.initState();
    ai = widget.controller ?? AiSearchController();
    ai.addListener(_changed);
    scroll.addListener(() {
      if (scroll.hasClients) followBottom = scroll.position.extentAfter < 160;
    });
    if (ai.loading) unawaited(ai.initialize());
  }

  @override
  void dispose() {
    ai.removeListener(_changed);
    if (widget.controller == null) ai.dispose();
    input.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (followBottom && ai.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients && followBottom) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Duration get duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppAnimation.duration;
  void _send() {
    if (input.text.trim().isEmpty || ai.busy) return;
    final text = input.text;
    input.clear();
    focus.unfocus();
    followBottom = true;
    final replace = editing;
    setState(() => editing = null);
    unawaited(ai.send(text, replaceFrom: replace));
  }

  void _edit(int index) {
    setState(() => editing = index);
    input.text = ai.turns[index].question;
    input.selection = TextSelection.collapsed(offset: input.text.length);
    focus.requestFocus();
  }

  Future<void> _new() async {
    await ai.newSession();
    input.clear();
    if (mounted) setState(() => editing = null);
  }

  Future<void> _history() async {
    final selected = await showAdaptiveModalSheet<AiSession>(
      context: context,
      title: '会话记录',
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) {
          return SizedBox(
            height: 480,
            child: ai.sessions.isEmpty
                ? const Center(child: Text('还没有会话，开始探索一个知识点吧'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    itemCount: ai.sessions.length,
                    itemBuilder: (context, index) {
                      final session = ai.sessions[index];
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text(
                          session.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${session.updatedAt.month}月${session.updatedAt.day}日',
                        ),
                        selected: session.id == ai.session?.id,
                        onTap: () => Navigator.pop(sheetContext, session),
                        trailing: IconButton(
                          tooltip: '删除会话',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: sheetContext,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除这段会话？'),
                                content: const Text('本地问题和回答将一起删除。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ai.delete(session);
                              if (context.mounted) updateSheet(() {});
                            }
                          },
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
    if (selected != null && mounted) {
      await ai.select(selected);
      input.clear();
      if (mounted) setState(() => editing = null);
    }
  }

  Future<void> _open(AiCitation citation) async {
    if (openingCitation) return;
    if (widget.openCitation != null) {
      await widget.openCitation!(context, citation);
      return;
    }
    setState(() => openingCitation = true);
    try {
      final repository = QuestionSearchRepository();
      final result = await repository.findQuestion(citation.questionId);
      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('原题所在题库尚未安装或未启用，请在题库管理中下载并启用')),
          );
        }
        return;
      }
      final question = await repository.getQuestionById(
        result.bankId,
        citation.questionId,
      );
      if (question == null) return;
      final user =
          await repository.getUserQuestionById(citation.questionId) ??
          UserQuestion(
            id: citation.questionId,
            chapterId: question.chapterId ?? '',
            chapterParentId: question.chapterParentId ?? '',
            cutQuestion: '0',
            userAnswer: '',
            status: 0,
            collection: 0,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        adaptivePageRoute(
          builder: (_) => QuestionDetailPage(
            chapter: Chapter(
              id: question.chapterId ?? '',
              name: result.subjectName ?? result.bankName,
              subjectId: question.chapterParentId ?? '',
              correct: 0,
              incorrect: 0,
              total: 1,
              identityId: question.identityId,
            ),
            questions: [question],
            userQuestions: [user],
            questionIndex: 0,
            bankId: result.bankId,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法打开原题，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => openingCitation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [GeminiMark(size: 22), SizedBox(width: 10), Text('AI 搜索')],
        ),
        actions: [
          IconButton(
            tooltip: '会话记录',
            onPressed: ai.busy || ai.loading ? null : _history,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: '新会话',
            onPressed: ai.busy || ai.loading ? null : _new,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Expanded(
                child: ai.loading
                    ? const Center(child: CircularProgressIndicator())
                    : AnimatedSwitcher(
                        duration: duration,
                        child: ai.turns.isEmpty ? _welcome() : _conversation(),
                      ),
              ),
              if (ai.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Text(ai.error!, style: TextStyle(color: scheme.error)),
                ),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('ai_welcome'),
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GeminiMark(size: 52),
          const SizedBox(height: 24),
          Text(
            '让知识，\n从一个问题展开。',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '从医学题库查找依据，用清晰的解释连接知识点。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 30),
          for (final item in [
            ('理解机制', '为什么 HLA Ⅰ类分子向 CD8⁺T 细胞提呈抗原？', Icons.hub_outlined),
            ('比较知识点', '心肌与骨骼肌的动作电位有什么区别？', Icons.compare_arrows_rounded),
            ('联系临床', '如何理解心力衰竭的前负荷和后负荷？', Icons.favorite_border_rounded),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    input.text = item.$2;
                    focus.requestFocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(item.$3, color: theme.colorScheme.primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$1, style: theme.textTheme.labelLarge),
                              const SizedBox(height: 4),
                              Text(item.$2, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.north_west_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _conversation() => SelectionArea(
    child: ListView.builder(
      key: const ValueKey('ai_conversation'),
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: ai.turns.length,
      itemBuilder: (context, index) {
        final turn = ai.turns[index];
        final active = index == ai.turns.length - 1 && ai.busy;
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        turn.question,
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '修改问题',
                      onPressed: ai.busy ? null : () => _edit(index),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: duration,
                child: active
                    ? _ThinkingIndicator(
                        key: const ValueKey('ai_progress'),
                        message: ai.phase,
                        animate: duration != Duration.zero,
                      )
                    : Row(
                        key: const ValueKey('ai_answer_header'),
                        children: [
                          const GeminiMark(size: 20),
                          const SizedBox(width: 10),
                          Text('医不帮 AI', style: theme.textTheme.labelLarge),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              if (active && turn.answer.isEmpty)
                _RetrievalSkeleton(animate: duration != Duration.zero),
              if (turn.answer.isNotEmpty)
                AiAnswerText(
                  text: turn.answer,
                  citations: turn.citations,
                  onCitation: _open,
                ),
              if (turn.status == 'stopped' || turn.status == 'interrupted')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('回答已停止，内容已保留', style: theme.textTheme.bodySmall),
                ),
              if (turn.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    turn.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (turn.citations.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('参考题目', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final citation in turn.citations)
                      ActionChip(
                        avatar: Text(
                          '${citation.number}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: Text(
                            citation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onPressed: openingCitation
                            ? null
                            : () => _open(citation),
                      ),
                  ],
                ),
              ],
              if (!active)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '复制回答',
                        onPressed: turn.answer.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: turn.answer),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('回答已复制')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.content_copy_rounded, size: 18),
                      ),
                      TextButton.icon(
                        onPressed: ai.busy
                            ? null
                            : () {
                                followBottom = true;
                                unawaited(
                                  ai.send(turn.question, replaceFrom: index),
                                );
                              },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('重新回答'),
                      ),
                      TextButton(
                        onPressed: ai.busy ? null : () => focus.requestFocus(),
                        child: const Text('继续追问'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            if (editing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '修改后重新回答，后续追问将被替换',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消修改',
                      onPressed: () {
                        input.clear();
                        setState(() => editing = null);
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ai_input'),
                      controller: input,
                      focusNode: focus,
                      enabled: !ai.loading,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: ai.turns.isEmpty ? '想了解哪个医学知识点？' : '继续追问…',
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: AnimatedSwitcher(
                      duration: duration,
                      child: ai.busy
                          ? IconButton.filled(
                              key: const ValueKey('ai_stop'),
                              tooltip: '停止回答',
                              onPressed: ai.stop,
                              icon: const Icon(Icons.stop_rounded),
                            )
                          : IconButton.filled(
                              key: const ValueKey('ai_send'),
                              tooltip: editing == null ? '发送问题' : '修改并重试',
                              onPressed: ai.loading ? null : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'AI 可能出错，请结合原题与教材核对',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (ai.quota != null) ...[
                  Text(
                    '今日剩余 ${ai.quota!.remaining}/100',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  final String message;
  final bool animate;
  const _ThinkingIndicator({
    super.key,
    required this.message,
    required this.animate,
  });
  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ThinkingIndicator old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) {
      if (widget.animate) {
        pulse.repeat(reverse: true);
      } else {
        pulse.stop();
      }
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AnimatedBuilder(
        animation: pulse,
        builder: (context, child) => Opacity(
          opacity: widget.animate ? .55 + pulse.value * .45 : 1,
          child: Transform.scale(
            scale: widget.animate ? .88 + pulse.value * .12 : 1,
            child: child,
          ),
        ),
        child: const GeminiMark(size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AnimatedSwitcher(
          duration: widget.animate
              ? const Duration(milliseconds: 250)
              : Duration.zero,
          child: Align(
            key: ValueKey(widget.message),
            alignment: Alignment.centerLeft,
            child: Text(
              widget.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _RetrievalSkeleton extends StatefulWidget {
  final bool animate;
  const _RetrievalSkeleton({required this.animate});
  @override
  State<_RetrievalSkeleton> createState() => _RetrievalSkeletonState();
}

class _RetrievalSkeletonState extends State<_RetrievalSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) glow.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RetrievalSkeleton old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) {
      if (widget.animate) {
        glow.repeat(reverse: true);
      } else {
        glow.stop();
      }
    }
  }

  @override
  void dispose() {
    glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: glow,
      builder: (context, _) => Opacity(
        opacity: widget.animate ? .4 + glow.value * .4 : .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final width in [1.0, .9, .62])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
