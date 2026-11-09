import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../common/adaptive_route.dart';
import '../common/app_shapes.dart';
import '../models/chapter.dart';
import '../models/daily_review_session.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../models/spaced_review_item.dart';
import '../screens/question_detail_page.dart';
import '../screens/question_detail/question_detail_controller.dart';
import '../screens/settings_page.dart';
import '../services/daily_review_service.dart';
import '../services/note_service.dart';
import '../services/spaced_repetition_engine.dart';
import '../widgets/common/app_network_image.dart';
import '../widgets/daily_review_celebration_dialog.dart';
import '../widgets/daily_review_plan_dialog.dart';
import '../widgets/flashcard_flip_card.dart';
import '../widgets/image_view.dart';

/// 百词斩风格：每日抽题与记忆曲线刷题页面
class DailyReviewPage extends StatefulWidget {
  final ReviewPlan? plan;
  final DailyReviewService? service;
  final DailyReviewSession? initialSession;
  final bool isExtraSession;

  const DailyReviewPage({
    super.key,
    this.plan,
    this.service,
    this.initialSession,
    this.isExtraSession = false,
  });

  @override
  State<DailyReviewPage> createState() => _DailyReviewPageState();
}

class _DailyReviewPageState extends State<DailyReviewPage> {
  late final DailyReviewService _service;
  SpacedRepetitionEngine _engine = const SpacedRepetitionEngine();

  bool _loading = true;
  String? _errorMessage;

  final List<DailyReviewQueueItem> _queue = [];
  int _currentIndex = 0;
  int _initialTotalCount = 0;

  // 当前题目作答交互状态
  String? _selectedOption;
  final Set<String> _selectedOptions = {};
  bool _isAnswerSubmitted = false;
  bool _isAnswerRevealed = false;
  DateTime _questionStartTime = DateTime.now();
  List<QuestionNote> _currentNotes = [];
  bool _isCramMode = false;
  bool _reviewNoteWithQuestion = false;

  int _sessionNewCount = 0;
  int _sessionReviewCount = 0;
  int _streakDays = 1;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DailyReviewService();
    SpacedRepetitionEngine.loadConfigured().then((eng) {
      if (mounted) setState(() => _engine = eng);
    });
    SettingsPage.getReviewNoteWithQuestion().then((val) {
      if (mounted) setState(() => _reviewNoteWithQuestion = val);
    });
    if (widget.initialSession != null) {
      _applySession(widget.initialSession!);
    } else {
      _loadDailySession();
    }
  }

  Future<void> _loadDailySession({bool extra = false}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final summary = await _service.getTodaySummary(customPlan: widget.plan);
      _streakDays = summary.streakDays;

      final session = await _service.buildDailySession(
        customPlan: widget.plan,
        isExtraSession: extra || widget.isExtraSession,
      );
      if (mounted) {
        _applySession(session);
      }
    } on Object catch (e, st) {
      debugPrint('[DailyReviewPage] Error loading daily session: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = '加载今日刷题计划失败: $e';
        });
      }
    }
  }

  /// 额外再学一组新题
  void _loadExtraSession() {
    _loadDailySession(extra: true);
  }

  void _applySession(DailyReviewSession session) {
    debugPrint(
      '[DailyReviewPage] _applySession: ${session.allItems.length} items '
      '(due: ${session.dueQueue.length}, new: ${session.newQueue.length}, cram: ${session.isCramMode})',
    );
    _isCramMode = session.isCramMode;

    void updateState() {
      _queue.clear();
      _queue.addAll(session.allItems);
      _initialTotalCount = _queue.length;
      _currentIndex = 0;
      _loading = false;
      _resetQuestionState();
    }

    if (mounted) {
      setState(updateState);
    } else {
      updateState();
    }
  }

  void _resetQuestionState() {
    _selectedOption = null;
    _selectedOptions.clear();
    _isAnswerSubmitted = false;
    _isAnswerRevealed = false;
    _currentNotes = [];
    _questionStartTime = DateTime.now();
    _loadCurrentNotes();
  }

  Future<void> _loadCurrentNotes() async {
    final item = _currentItem;
    if (item == null) return;
    try {
      final notes = await NoteService.instance.getLocalNotes(item.questionId);
      if (mounted && _currentItem?.questionId == item.questionId) {
        setState(() {
          _currentNotes = notes;
        });
      }
    } catch (_) {}
  }

  bool _isMultiChoice(Question question) {
    if (question.type == '2' || question.typeLabel == '多选题') return true;
    final ans = question.answer?.trim();
    return ans != null && ans.length > 1;
  }

  DailyReviewQueueItem? get _currentItem {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  /// 跳转至原题目详情页面（查看完整题干、解析、全科评论与全部历史记录）
  void _openOriginalQuestion(DailyReviewQueueItem item) {
    final q = item.question;
    if (q == null) return;
    final uq = item.userQuestion ??
        UserQuestion(
          id: q.id,
          chapterId: q.chapterId ?? '',
          chapterParentId: q.chapterParentId ?? '',
          cutQuestion: '0',
          userAnswer: '',
          status: 0,
          collection: 0,
          updatedAt: 0,
        );
    final chapter = Chapter(
      id: q.chapterId ?? '',
      name: '记忆曲线原题',
      subjectId: q.chapterParentId ?? '',
      correct: 0,
      incorrect: 0,
      total: 1,
      identityId: q.identityId,
    );
    Navigator.push(
      context,
      adaptivePageRoute(
        builder: (_) => QuestionDetailPage(
          chapter: chapter,
          questions: [q],
          userQuestions: [uq],
          questionIndex: 0,
          bankId: item.bankId,
        ),
      ),
    );
  }

  /// 提交并进入下一题
  Future<void> _onRatingSelected(ReviewRating rating) async {
    final item = _currentItem;
    if (item == null) return;

    final elapsed = DateTime.now().difference(_questionStartTime).inSeconds;

    // 1. 调用 Service 记录算法演进与流水
    await _service.submitReviewResult(
      questionId: item.questionId,
      rating: rating,
      durationSeconds: elapsed,
      userAnswer: _selectedOption,
      bankId: item.bankId,
    );

    // 2. 统计本次会话新学/复习完成数
    if (item.isNew) {
      _sessionNewCount++;
    } else {
      _sessionReviewCount++;
    }

    // 3. 百词斩/Anki 精髓：选择 Again（重来）的题目，加入当前轮次末尾再次复习，直至彻底巩固
    if (rating == ReviewRating.again) {
      _queue.add(item.copyWith(isNew: false));
    }

    // 4. 步进到下一题或结题
    if (_currentIndex + 1 < _queue.length) {
      setState(() {
        _currentIndex++;
        _resetQuestionState();
      });
    } else {
      // 今日全部刷完：弹出成就结算弹窗
      _onSessionCompleted();
    }
  }

  Future<void> _onSessionCompleted() async {
    final completed = await DailyReviewCelebrationDialog.show(
      context,
      newCount: _sessionNewCount,
      reviewCount: _sessionReviewCount,
      streakDays: math.max(1, _streakDays),
      onMoreSession: () {
        // 用户希望再来一组：重新拉取
        _loadDailySession();
      },
    );

    if (mounted && (completed ?? true)) {
      Navigator.of(context).pop(true);
    }
  }

  /// 斩题/斩卡处理：直接标记为已斩且已完全掌握，跳过后续复习
  Future<void> _handleCutQuestion() async {
    final item = _currentItem;
    if (item == null) return;
    final isFlashcard = item.itemType == ReviewItemType.flashcard;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFlashcard ? '熟练斩卡' : '熟练斩题'),
        content: Text(isFlashcard
            ? '确定将本闪卡标记为已斩吗？\n斩卡后该闪卡将自动归档为完全掌握，移出每日复习计划。'
            : '确定将本题标记为已斩吗？\n斩题后该题将自动归档为完全掌握，移出每日复习计划。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isFlashcard ? '斩掉此卡' : '斩掉此题'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 标记为斩题并直接归档为 mastered
    await _service.cutQuestion(
      questionId: item.questionId,
      bankId: item.bankId ?? '',
      planId: item.reviewItem?.planId,
    );

    if (item.isNew) {
      _sessionNewCount++;
    } else {
      _sessionReviewCount++;
    }

    if (_currentIndex + 1 < _queue.length) {
      setState(() {
        _currentIndex++;
        _resetQuestionState();
      });
    } else {
      _onSessionCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFlashcard = _currentItem?.itemType == ReviewItemType.flashcard;

    return Scaffold(
      appBar: AppBar(
        title: Text(isFlashcard ? '今日闪卡记忆' : '今日记忆卡片'),
        actions: [
          if (_currentItem != null)
            IconButton(
              tooltip: isFlashcard ? '熟练斩卡' : '熟练斩题',
              icon: const Icon(Icons.content_cut_rounded),
              onPressed: _handleCutQuestion,
            ),
        ],
      ),
      body: _buildBody(context, theme, scheme),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadDailySession,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_queue.isEmpty || _currentIndex >= _queue.length) {
      return _buildEmptyState(context, theme, scheme);
    }

    final item = _currentItem!;
    final question = item.question;

    return Column(
      children: [
        // 顶部进度指示条与状态统计
        _buildHeaderProgress(context, theme, scheme),

        // 题目主展示区
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.itemType == ReviewItemType.flashcard) ...[
                  // 专属 3D 物理翻牌动效卡片
                  FlashcardFlipCard(
                    queueItem: item,
                    onFlipped: (isBack) {
                      setState(() {
                        _isAnswerRevealed = isBack;
                      });
                    },
                    onOpenOriginalQuestion: question != null
                        ? () => _openOriginalQuestion(item)
                        : null,
                  ),
                ] else ...[
                  _buildQuestionCard(context, item, question, theme, scheme),
                  const SizedBox(height: 16),

                  // 选项或主观题/纯笔记卡片直背区
                  if (question != null &&
                      !question.isSubjective &&
                      question.option != null &&
                      (!item.isFromNote || _reviewNoteWithQuestion))
                    _buildChoiceOptions(question, theme, scheme)
                  else
                    _buildSubjectiveOrFlashcardContent(item, question, theme, scheme),

                  // 个人速记笔记展开区（作答后或翻转后优先呈现，唤醒浓缩知识点）
                  if ((_isAnswerSubmitted || _isAnswerRevealed) && _currentNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildNotesCard(context, theme, scheme),
                  ],

                  // 解析展开区
                  if (_isAnswerSubmitted || _isAnswerRevealed) ...[
                    const SizedBox(height: 16),
                    _buildExplanationCard(item, question, theme, scheme),
                  ],
                ],
              ],
            ),
          ),
        ),

        // 底部 Material 3 自适应 4 档评级栏（作答或揭晓答案后滑出）
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: (_isAnswerSubmitted || _isAnswerRevealed)
              ? _buildRatingBar(item, theme, scheme)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 顶部百词斩进度条与徽章
  Widget _buildHeaderProgress(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final progress = _initialTotalCount > 0
        ? math.min(1.0, (_currentIndex) / _initialTotalCount)
        : 1.0;

    final item = _currentItem;
    final isNew = item?.isNew ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isCramMode
                      ? Colors.deepOrange.withValues(alpha: 0.15)
                      : (isNew
                          ? Colors.teal.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(AppShapes.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isCramMode
                          ? Icons.local_fire_department_rounded
                          : (isNew ? Icons.auto_awesome : Icons.repeat_rounded),
                      size: 14,
                      color: _isCramMode
                          ? Colors.deepOrange.shade700
                          : (isNew ? Colors.teal.shade700 : Colors.amber.shade900),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isCramMode
                          ? '提前巩固'
                          : (isNew ? '今日新学' : '艾宾浩斯复习'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _isCramMode
                            ? Colors.deepOrange.shade700
                            : (isNew ? Colors.teal.shade700 : Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              if (item?.itemType == ReviewItemType.flashcard) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppShapes.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.style_rounded, size: 14, color: Colors.purple.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '自制闪卡',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (item?.isFromNote == true || _currentNotes.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppShapes.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '笔记精选',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${_currentIndex + 1} / ${_queue.length}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.full),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 题干卡片
  Widget _buildQuestionCard(
    BuildContext context,
    DailyReviewQueueItem item,
    Question? question,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final title = question?.title ??
        item.customFlashcard?.front ??
        '（无题干内容）';
    final publicTitle = question?.publicTitle;
    final titleImg = question?.titleImg;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (question?.typeLabel != null)
                  Text(
                    question!.typeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const Spacer(),
                if (question != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppShapes.full),
                    onTap: () => _openOriginalQuestion(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new_rounded, size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '原题详情',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (publicTitle != null && publicTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  publicTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                height: 1.5,
              ),
            ),
            if (titleImg != null && titleImg.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    adaptivePageRoute(
                      builder: (context) => FullScreenImageView(
                        imageUrls: [titleImg],
                        initialIndex: 0,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppShapes.medium),
                  child: AppNetworkImage(
                    imageUrl: titleImg,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 选择题选项渲染
  Widget _buildChoiceOptions(
    Question question,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final options = QuestionDetailController.getOptionJson(question);
    final standardAnswer = question.answer ?? '';
    final isMulti = _isMultiChoice(question);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...options.map<Widget>((opt) {
          final key = opt['key']?.toString() ?? '';
          final text = opt['title']?.toString() ?? '';
          final isSelected = isMulti
              ? _selectedOptions.contains(key)
              : _selectedOption == key;
          final isCorrectAnswer = standardAnswer.contains(key);

          Color? tileColor;
          BorderSide borderSide = BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          );
          Color badgeColor = scheme.surfaceContainerHighest;
          Color badgeTextColor = scheme.onSurface;
          Widget? statusTrailing;

          if (_isAnswerSubmitted) {
            if (isCorrectAnswer && isSelected) {
              // 1. 选对：标准绿色
              tileColor = Colors.green.withValues(alpha: 0.12);
              borderSide = const BorderSide(color: Colors.green, width: 1.5);
              badgeColor = Colors.green;
              badgeTextColor = Colors.white;
              statusTrailing = const Icon(Icons.check_circle, color: Colors.green, size: 20);
            } else if (isCorrectAnswer && !isSelected) {
              // 2. 漏选：红框警示，标注“漏选”
              tileColor = Colors.red.withValues(alpha: 0.08);
              borderSide = BorderSide(color: Colors.red.shade400, width: 1.5);
              badgeColor = Colors.red.shade400;
              badgeTextColor = Colors.white;
              statusTrailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '漏选',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle_outline, color: Colors.red.shade700, size: 20),
                ],
              );
            } else if (!isCorrectAnswer && isSelected) {
              // 3. 错选：红色背景与叉号
              tileColor = Colors.red.withValues(alpha: 0.12);
              borderSide = const BorderSide(color: Colors.red, width: 1.5);
              badgeColor = Colors.red;
              badgeTextColor = Colors.white;
              statusTrailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '错选',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.cancel, color: Colors.red, size: 20),
                ],
              );
            }
          } else if (isMulti && isSelected) {
            tileColor = scheme.primaryContainer.withValues(alpha: 0.35);
            borderSide = BorderSide(color: scheme.primary, width: 1.5);
            badgeColor = scheme.primary;
            badgeTextColor = scheme.onPrimary;
            statusTrailing = Icon(Icons.check_box_rounded, color: scheme.primary, size: 20);
          } else if (isMulti && !isSelected) {
            statusTrailing = Icon(
              Icons.check_box_outline_blank_rounded,
              color: scheme.outlineVariant,
              size: 20,
            );
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: tileColor ?? scheme.surface,
              borderRadius: BorderRadius.circular(AppShapes.medium),
              border: Border.fromBorderSide(borderSide),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              onTap: _isAnswerSubmitted
                  ? null
                  : () {
                      if (isMulti) {
                        setState(() {
                          if (_selectedOptions.contains(key)) {
                            _selectedOptions.remove(key);
                          } else {
                            _selectedOptions.add(key);
                          }
                        });
                      } else {
                        setState(() {
                          _selectedOption = key;
                          _isAnswerSubmitted = true;
                        });
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: isMulti ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: isMulti ? BorderRadius.circular(6) : null,
                        color: badgeColor,
                      ),
                      child: Text(
                        key,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: badgeTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (statusTrailing != null) statusTrailing,
                  ],
                ),
              ),
            ),
          );
        }),

        // 多选题专属提交按钮（作答前展示）
        if (isMulti && !_isAnswerSubmitted && !_isAnswerRevealed) ...[
          const SizedBox(height: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShapes.medium),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _selectedOptions.isEmpty
                ? null
                : () {
                    final sorted = _selectedOptions.toList()..sort();
                    setState(() {
                      _selectedOption = sorted.join('');
                      _isAnswerSubmitted = true;
                    });
                  },
            child: Text(
              _selectedOptions.isEmpty
                  ? '请勾选选项（多选题）'
                  : '提交答案 (已选 ${_selectedOptions.length} 项)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  /// 主观题或闪卡内容渲染
  Widget _buildSubjectiveOrFlashcardContent(
    DailyReviewQueueItem item,
    Question? question,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    if (!_isAnswerRevealed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShapes.large),
              ),
            ),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('查看参考答案 / 翻转卡片', style: TextStyle(fontSize: 16)),
            onPressed: () {
              setState(() {
                _isAnswerRevealed = true;
              });
            },
          ),
        ),
      );
    }

    final answerText = question?.answer ??
        item.customFlashcard?.back ??
        '（暂无参考答案）';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppShapes.large),
        border: Border.all(
          color: scheme.secondary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: scheme.secondary, size: 20),
              const SizedBox(width: 8),
              Text(
                '参考答案',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            answerText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 题目解析展示卡片
  Widget _buildExplanationCard(
    DailyReviewQueueItem item,
    Question? question,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final explain = question?.explain;
    final explainImg = question?.explainImg;

    if ((explain == null || explain.trim().isEmpty) &&
        (explainImg == null || explainImg.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppShapes.large),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              Text(
                '题目解析',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          if (explain != null && explain.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explain,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.5,
              ),
            ),
          ],
          if (explainImg != null && explainImg.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  adaptivePageRoute(
                    builder: (context) => FullScreenImageView(
                      imageUrls: [explainImg],
                      initialIndex: 0,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppShapes.medium),
                child: AppNetworkImage(
                  imageUrl: explainImg,
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
          if (question != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _openOriginalQuestion(item),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('进入原题详情（查看考点与考友笔记）'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部自适应 4 档评级操作栏（Material 3 间隔重复按钮）
  Widget _buildRatingBar(
    DailyReviewQueueItem item,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final reviewItem = item.reviewItem ??
        SpacedReviewItem(itemId: item.questionId);
    final intervals = _engine.previewNextIntervals(reviewItem);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, -4),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _buildRatingButton(
              title: '重来',
              interval: '${intervals[ReviewRating.again] ?? 1}天',
              color: Colors.red.shade700,
              bgColor: Colors.red.withValues(alpha: 0.1),
              rating: ReviewRating.again,
            ),
            const SizedBox(width: 8),
            _buildRatingButton(
              title: '困难',
              interval: '${intervals[ReviewRating.hard] ?? 2}天',
              color: Colors.orange.shade800,
              bgColor: Colors.orange.withValues(alpha: 0.1),
              rating: ReviewRating.hard,
            ),
            const SizedBox(width: 8),
            _buildRatingButton(
              title: '良好',
              interval: '${intervals[ReviewRating.good] ?? 6}天',
              color: scheme.primary,
              bgColor: scheme.primaryContainer.withValues(alpha: 0.5),
              rating: ReviewRating.good,
              isProminent: true,
            ),
            const SizedBox(width: 8),
            _buildRatingButton(
              title: '简单',
              interval: '${intervals[ReviewRating.easy] ?? 10}天',
              color: Colors.green.shade700,
              bgColor: Colors.green.withValues(alpha: 0.1),
              rating: ReviewRating.easy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButton({
    required String title,
    required String interval,
    required Color color,
    required Color bgColor,
    required ReviewRating rating,
    bool isProminent = false,
  }) {
    return Expanded(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppShapes.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppShapes.medium),
          onTap: () => _onRatingSelected(rating),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppShapes.medium),
              border: Border.all(
                color: isProminent ? color : color.withValues(alpha: 0.35),
                width: isProminent ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  interval,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 专属笔记展示卡片（作答后展示用户记录的知识点精华）
  Widget _buildNotesCard(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppShapes.large),
        border: Border.all(
          color: Colors.amber.shade700.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.amber.shade900, size: 22),
              const SizedBox(width: 8),
              Text(
                '我的精粹笔记 (${_currentNotes.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._currentNotes.map((note) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppShapes.medium),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.45,
                    ),
                  ),
                  if (note.images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final imageUrls = note.images.map((e) => e.bImg).where((e) => e.isNotEmpty).toList();
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: note.images.map((img) {
                          final thumb = img.sImg.isNotEmpty ? img.sImg : img.bImg;
                          return GestureDetector(
                            onTap: () {
                              if (imageUrls.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  adaptivePageRoute(
                                    builder: (_) => FullScreenImageView(
                                      imageUrls: imageUrls,
                                      initialIndex: imageUrls.indexOf(img.bImg).clamp(0, imageUrls.length - 1),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppShapes.small),
                              child: AppNetworkImage(
                                imageUrl: thumb,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 队列为空或已学完提示
  Widget _buildEmptyState(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.done_all_rounded, size: 56, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              '今日暂无待刷题目！',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '今日计划指标已完成，或当前范围题目已到期复习完毕。随时可以再刷一组！',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final updated = await DailyReviewPlanDialog.show(context);
                    if (updated != null) {
                      _loadDailySession();
                    }
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('调整抽题范围'),
                ),
                FilledButton.icon(
                  onPressed: _loadExtraSession,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('再学一组新题'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
