import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/adaptive_route.dart';
import '../common/animation.dart';
import '../common/app_shapes.dart';
import '../common/platform_adaptive.dart';
import '../models/ai_search.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../repositories/question_search_repository.dart';
import '../services/ai_search_controller.dart';
import 'textbook_reader_page.dart';
import 'textbook_search_page.dart';
import '../widgets/ai_answer_text.dart';
import '../widgets/gemini_mark.dart';
import 'question_detail_page.dart';

/// 精选 30 个核心高频医学问题库
const List<(String, String, IconData)> _medicalQuestionPool = [
  ('理解机制', '为什么 HLA Ⅰ类分子向 CD8⁺T 细胞提呈抗原？', Icons.hub_outlined),
  ('比较知识点', '心肌与骨骼肌的动作电位有什么区别？', Icons.compare_arrows_rounded),
  ('联系临床', '如何理解心力衰竭的前负荷和后负荷？', Icons.favorite_border_rounded),
  ('生理机制', '简述肾小球滤过率的自身调节机制。', Icons.filter_alt_outlined),
  ('病理鉴别', 'Crohn 病与溃疡性结肠炎的病理表现有何不同？', Icons.difference_outlined),
  ('药理作用', '为什么普萘洛尔禁用于支气管哮喘患者？', Icons.medication_outlined),
  ('临床诊断', '急性心肌梗死与心绞痛在疼痛性质上有何区别？', Icons.monitor_heart_outlined),
  ('生化代谢', '简述糖异生途径的关键酶及其生理意义。', Icons.biotech_outlined),
  ('免疫应答', '简述单克隆抗体与多克隆抗体的核心差异。', Icons.coronavirus_outlined),
  ('病理生理', '休克早期微循环障碍的代偿机制是什么？', Icons.bloodtype_outlined),
  ('心电图鉴别', '如何通过心电图区分室上速与室性心动过速？', Icons.show_chart_rounded),
  ('药理机制', '阿司匹林抗血小板聚集的药理学机制是什么？', Icons.healing_outlined),
  ('急腹症鉴别', '机械性肠梗阻与动力性肠梗阻的临床表现鉴别。', Icons.emergency_outlined),
  ('血液系统', '简述内源性凝血与外源性凝血途径的启动差异。', Icons.water_drop_outlined),
  ('呼吸系统', 'Ⅰ型呼衰与Ⅱ型呼衰的血气诊断标准与给氧原则。', Icons.air_rounded),
  ('内分泌鉴别', '库欣综合征（Cushing syndrome）的常见病因与鉴别。', Icons.science_outlined),
  ('消化系统', '门静脉高压症的三大临床表现及侧支循环途径。', Icons.account_tree_outlined),
  ('神经系统', '上运动神经元瘫痪与下运动神经元瘫痪的特点区别。', Icons.psychology_outlined),
  ('循环听诊', '简述第一心音与第二心音的产生机理与听诊特点。', Icons.hearing_rounded),
  ('配伍禁忌', '为什么青霉素与庆大霉素不可置于同一输液瓶中？', Icons.warning_amber_rounded),
  ('肾病鉴别', '急性肾炎水肿与肾病综合征水肿的发生机制有何不同？', Icons.water_damage_outlined),
  ('病理炎性', '简述肉芽肿性炎的概念与常见病因。', Icons.lens_blur_rounded),
  ('分子遗传', '简述 DNA 双螺旋结构的要点及稳定因素。', Icons.grain_rounded),
  ('儿科营养', '简述母乳喂养的优点及初乳的特性。', Icons.child_care_rounded),
  ('产科急症', '简述前置胎盘与胎盘早剥的临床鉴别诊断要点。', Icons.pregnant_woman_rounded),
  ('传染病学', '简述病毒性肝炎中“大三阳”与“小三阳”的血清学意义。', Icons.vaccines_outlined),
  ('外科高压', '简述颅内压增高的三主征及其产生原因。', Icons.psychology_alt_outlined),
  ('降压机制', '钙通道阻滞剂（CCB）的分类及抗高血压机制。', Icons.speed_rounded),
  ('肿瘤病理', '简述良性肿瘤与恶性肿瘤的生物学特性区别。', Icons.category_outlined),
  ('急救复苏', '简述心肺复苏（CPR）中高质量胸外按压的要点。', Icons.medical_services_outlined),
];

/// 底栏 AI 搜索页面，遵循医不帮 Material 3 统一规范与优雅动效。
class AiSearchPage extends StatefulWidget {
  final AiSearchController? controller;
  final Future<void> Function(BuildContext, AiCitation)? openCitation;
  const AiSearchPage({super.key, this.controller, this.openCitation});

  @override
  State<AiSearchPage> createState() => _AiSearchPageState();
}

class _AiSearchPageState extends State<AiSearchPage>
    with SingleTickerProviderStateMixin {
  late final AiSearchController ai;
  final input = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();
  int? editing;
  bool openingCitation = false;

  static const _citationsCollapsedKey = 'ai_search_citations_collapsed';
  // 记录参考资料折叠状态（默认不折叠，支持持久化存储）
  bool _citationsCollapsed = false;

  // 随机推荐问题当前列表（默认 3 个）
  List<(String, String, IconData)> _currentSuggestions = [];
  int _poolOffset = 0;

  late final AnimationController _entryController;
  late final Animation<double> _entryFadeAnimation;
  late final Animation<Offset> _entrySlideAnimation;

  @override
  void initState() {
    super.initState();
    ai = widget.controller ?? AiSearchController();
    focus.onKeyEvent = _composerKey;
    ai.addListener(_changed);

    _loadCitationsCollapsed();

    // 默认展示题库前 3 个经典问题（包含测试断言的“理解机制”）
    _refreshSuggestions(useRandom: false);

    if (ai.loading) unawaited(ai.initialize());

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entryFadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: AppAnimation.curve,
    ));
    _entryController.forward();
  }

  void _refreshSuggestions({bool useRandom = true}) {
    if (!useRandom) {
      _currentSuggestions = _medicalQuestionPool.take(3).toList();
      return;
    }
    setState(() {
      _poolOffset = (_poolOffset + 3) % _medicalQuestionPool.length;
      final shuffled = List<(String, String, IconData)>.from(_medicalQuestionPool);
      shuffled.shuffle(Random());
      // 保持测试兼容性：如果需要，可包含前排
      _currentSuggestions = shuffled.take(3).toList();
    });
  }

  Future<void> _loadCitationsCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _citationsCollapsed = prefs.getBool(_citationsCollapsedKey) ?? false;
      });
    }
  }

  Future<void> _toggleCitationsCollapsed() async {
    final newVal = !_citationsCollapsed;
    setState(() {
      _citationsCollapsed = newVal;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_citationsCollapsedKey, newVal);
  }

  @override
  void dispose() {
    ai.removeListener(_changed);
    if (widget.controller == null) ai.dispose();
    input.dispose();
    scroll.dispose();
    focus.dispose();
    _entryController.dispose();
    super.dispose();
  }

  /// 修复滚动体验：AI 回答变长过程中，不再强制 jumpTo(maxScrollExtent)，保持对齐提问！
  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  Duration get duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppAnimation.duration;

  void _send() {
    if (input.text.trim().isEmpty ||
        ai.busy ||
        ai.loading ||
        !input.value.composing.isCollapsed) {
      return;
    }
    final text = input.text;
    input.clear();
    if (!_desktopKeyboard) focus.unfocus();
    final replace = editing;
    setState(() => editing = null);

    // 发送提问时平滑滚动到最新提问，之后流式输出保持不动，对齐当前提问
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    unawaited(ai.send(text, replaceFrom: replace));
  }

  bool get _desktopKeyboard => const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  KeyEventResult _composerKey(FocusNode node, KeyEvent event) {
    if (!_desktopKeyboard ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        !HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        !input.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _send();
    return KeyEventResult.handled;
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
    if (mounted) {
      setState(() {
        editing = null;
        _refreshSuggestions(useRandom: true);
      });
    }
  }

  Future<void> _history() async {
    final selected = await showAdaptiveModalSheet<AiSession>(
      context: context,
      title: '会话记录',
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;

          return SizedBox(
            height: (MediaQuery.sizeOf(context).height * 0.7).clamp(360.0, 560.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isDesktopLayout(sheetContext))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded),
                        const SizedBox(width: 8),
                        Text(
                          '会话记录 (${ai.sessions.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ai.sessions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 48, color: scheme.outline),
                              const SizedBox(height: 12),
                              const Text('还没有会话，开始探索一个知识点吧'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: ai.sessions.length,
                          itemBuilder: (context, index) {
                            final session = ai.sessions[index];
                            final isCurrent = session.id == ai.session?.id;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: isCurrent
                                    ? scheme.primaryContainer.withValues(alpha: 0.45)
                                    : scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(AppShapes.medium),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(AppShapes.medium),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, session),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isCurrent
                                                ? scheme.primary
                                                : scheme.surfaceContainerHighest,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isCurrent
                                                ? Icons.chat_bubble_rounded
                                                : Icons.chat_bubble_outline_rounded,
                                            size: 16,
                                            color: isCurrent
                                                ? scheme.onPrimary
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                session.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: isCurrent
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${session.updatedAt.month}月${session.updatedAt.day}日',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '删除会话',
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20),
                                          onPressed: () async {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: sheetContext,
                                              builder: (ctx) => AlertDialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppShapes.extraLarge),
                                                ),
                                                title: const Text('删除这段会话？'),
                                                content:
                                                    const Text('本地问题和回答将一起删除。'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx, false),
                                                    child: const Text('取消'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx, true),
                                                    child: const Text('删除'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirmed == true) {
                                              await ai.delete(session);
                                              if (context.mounted) {
                                                updateSheet(() {});
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
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
      if (citation.isTextbook) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextbookReaderPage(citation: citation),
          ),
        );
        return;
      }
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
          children: [
            GeminiMark(size: 22),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'AI 搜索',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '教材检索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TextbookSearchPage()),
            ),
            icon: const Icon(Icons.menu_book_outlined),
          ),
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
      body: FadeTransition(
        opacity: _entryFadeAnimation,
        child: SlideTransition(
          position: _entrySlideAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                children: [
                  Expanded(
                    child: ai.loading
                        ? const Center(child: CircularProgressIndicator())
                        : AnimatedSwitcher(
                            duration: duration,
                            child: ai.turns.isEmpty
                                ? _welcome()
                                : _conversation(),
                          ),
                  ),
                  if (ai.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppShapes.small),
                        ),
                        child: Text(
                          ai.error!,
                          style: TextStyle(
                              color: scheme.onErrorContainer, fontSize: 13),
                        ),
                      ),
                    ),
                  _composer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('ai_welcome'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const GeminiMark(size: 44),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _refreshSuggestions(useRandom: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('换一批问题', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '让知识，\n从一个问题展开。',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.28,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '从权威医学教材与真题题库查找依据，用清晰的逻辑连接知识点。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          for (final item in _currentSuggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: scheme.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShapes.large),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppShapes.large),
                  onTap: () {
                    input.text = item.$2;
                    focus.requestFocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppShapes.medium),
                          ),
                          child: Icon(item.$3, color: scheme.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.$2,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.north_west_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: ai.turns.length,
          itemBuilder: (context, index) {
            final turn = ai.turns[index];
            final active = index == ai.turns.length - 1 && ai.busy;
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final isCollapsed = _citationsCollapsed;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 用户提问气泡（视口在此处对齐）
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(AppShapes.large),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                turn.question,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: '修改问题',
                              onPressed: ai.busy ? null : () => _edit(index),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. AI 标题与思考状态
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
                              const SizedBox(width: 8),
                              Text(
                                '医不帮 AI',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // 3. 骨架屏或内容流式渲染
                  if (active && turn.answer.isEmpty)
                    _RetrievalSkeleton(animate: duration != Duration.zero),
                  if (turn.answer.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppShapes.large),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: AiAnswerText(
                        key: ValueKey(turn.id),
                        text: turn.answer,
                        citations: turn.citations,
                        onCitation: _open,
                        animateReveal: active && duration != Duration.zero,
                      ),
                    ),

                  if (turn.status == 'stopped' || turn.status == 'interrupted')
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text('回答已停止，内容已保留',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                    ),

                  if (turn.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(AppShapes.small),
                        ),
                        child: Text(
                          turn.error!,
                          style: TextStyle(color: scheme.error, fontSize: 13),
                        ),
                      ),
                    ),

                  // 4. 引用资料来源卡片（支持折叠/展开切换，状态持久化）
                  if (turn.citations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppShapes.small),
                      onTap: _toggleCitationsCollapsed,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.library_books_rounded,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '参考资料 (${turn.citations.length})',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isCollapsed ? '展开' : '收起',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Icon(
                              isCollapsed
                                  ? Icons.expand_more_rounded
                                  : Icons.expand_less_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final citation in turn.citations)
                            _buildCitationChip(context, citation),
                        ],
                      ),
                    ],
                  ],

                  // 5. 底部操作工具栏
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
                                    unawaited(
                                      ai.send(turn.question,
                                          replaceFrom: index),
                                    );
                                  },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('重新回答'),
                          ),
                          TextButton.icon(
                            onPressed:
                                ai.busy ? null : () => focus.requestFocus(),
                            icon: const Icon(Icons.reply_rounded, size: 18),
                            label: const Text('继续追问'),
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

  Widget _buildCitationChip(BuildContext context, AiCitation citation) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (citation.isTextbook) {
      // 提取教材纯名（如“药理学”）并过滤书名号
      String bookName = citation.bookTitle;
      if (bookName.isEmpty) {
        final match = RegExp(r'^《?([^·《》\s]+)》?').firstMatch(citation.title);
        bookName = match != null ? match.group(1)! : citation.title;
      }
      bookName = bookName.replaceAll(RegExp(r'^[《<]+|[》>]+$'), '').trim();

      // 提取 PDF 页码
      int page = citation.pdfPage;
      if (page <= 0) {
        final pageMatch =
            RegExp(r'(?:PDF第|第|P)(\d+)页?').firstMatch(citation.title);
        if (pageMatch != null) {
          page = int.tryParse(pageMatch.group(1)!) ?? 0;
        }
      }

      return ActionChip(
        avatar: CircleAvatar(
          radius: 10,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            '${citation.number}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bookName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (page > 0) ...[
              const SizedBox(width: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'P$page',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    //height: 1.1,
                  ),
                ),
              ),
            ],
          ],
        ),
        tooltip: citation.title,
        onPressed: openingCitation ? null : () => _open(citation),
      );
    }

    // 非教材类型引用（如题目）
    return ActionChip(
      avatar: CircleAvatar(
        radius: 10,
        backgroundColor: scheme.secondaryContainer,
        child: Text(
          '${citation.number}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Text(
          citation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      tooltip: citation.title,
      onPressed: openingCitation ? null : () => _open(citation),
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Column(
          children: [
            if (editing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppShapes.small),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_rounded,
                          size: 18, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '修改后重新回答，后续追问将被替换',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
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
              ),

            // 现代胶囊输入栏
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppShapes.extraLarge),
                border: Border.all(
                  color: focus.hasFocus
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                  width: focus.hasFocus ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                          vertical: 12,
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
                              tooltip: editing == null
                                  ? (_desktopKeyboard
                                      ? '发送问题（Shift+Enter）'
                                      : '发送问题')
                                  : '修改并重试',
                              onPressed: ai.loading ? null : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 额度与说明胶囊
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
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
                    '·  今日剩余 ${ai.quota!.remaining}/${ai.quota!.limit}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
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
    duration: const Duration(milliseconds: 1400),
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
              opacity: widget.animate ? .6 + pulse.value * .4 : 1,
              child: Transform.scale(
                scale: widget.animate ? .9 + pulse.value * .15 : 1,
                child: child,
              ),
            ),
            child: const GeminiMark(size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: widget.animate
                  ? const Duration(milliseconds: 250)
                  : Duration.zero,
              child: Align(
                key: ValueKey(widget.message),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Text(
                      widget.message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
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
    duration: const Duration(milliseconds: 1200),
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
            opacity: widget.animate ? .4 + glow.value * .45 : .6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final width in [1.0, .88, .62])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FractionallySizedBox(
                      widthFactor: width,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppShapes.xs),
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
