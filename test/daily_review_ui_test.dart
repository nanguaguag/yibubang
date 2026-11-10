import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/models/daily_review_session.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/screens/daily_plan_page.dart';
import 'package:yibubang/screens/daily_review_page.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:yibubang/widgets/daily_review_card.dart';
import 'package:yibubang/widgets/daily_review_celebration_dialog.dart';
import 'package:yibubang/widgets/daily_review_plan_dialog.dart';

void main() {
  group('DailyReviewPlanDialog Widget Tests', () {
    testWidgets('renders initial plan and allows selecting new targets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const initialPlan = ReviewPlan(
        id: 'plan_test',
        name: '考研二战计划',
        dailyNewTarget: 20,
        dailyReviewLimit: 50,
      );

      final fakeRepo = _FakeSpacedReviewRepository();
      ReviewPlan? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  DailyReviewPlanDialog.show(
                    context,
                    initialPlan: initialPlan,
                    repository: fakeRepo,
                    availableSubjects: const [],
                    onSaved: (p) => savedResult = p,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('计划与抽题范围'), findsOneWidget);
      expect(find.text('考研二战计划'), findsOneWidget);
      expect(find.text('30 题'), findsOneWidget); // new target preset

      // 选择新题量 30 题
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '30 题'));
      await tester.tap(find.widgetWithText(ChoiceChip, '30 题'));
      await tester.pumpAndSettle();

      // 点击保存
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.name, '考研二战计划');
      expect(savedResult!.dailyNewTarget, 30);
    });
  });

  group('DailyReviewCelebrationDialog Widget Tests', () {
    testWidgets('displays celebration statistics, streak and buttons', (
      tester,
    ) async {
      bool moreSessionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyReviewCelebrationDialog(
              newCount: 15,
              reviewCount: 35,
              streakDays: 7,
              onMoreSession: () => moreSessionTapped = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('今日计划打卡成功！'), findsOneWidget);
      expect(find.text('已连续打卡 7 天'), findsOneWidget);
      expect(find.text('15 题'), findsOneWidget);
      expect(find.text('35 题'), findsOneWidget);
      expect(find.text('50 题'), findsOneWidget); // total

      expect(find.text('再学一组'), findsOneWidget);
      expect(find.text('完成打卡'), findsOneWidget);

      await tester.tap(find.text('再学一组'));
      await tester.pumpAndSettle();

      expect(moreSessionTapped, isTrue);
    });
  });

  group('DailyReviewCard Widget Tests', () {
    testWidgets(
      'renders daily progress and triggers review action when not completed',
      (tester) async {
        const summary = DailyReviewSummary(
          planId: 'plan_1',
          planName: '口腔每日计划',
          dailyNewTarget: 20,
          dailyReviewLimit: 50,
          completedNewToday: 5,
          completedReviewToday: 5,
          remainingDueCount: 10,
          remainingNewCount: 15,
          streakDays: 3,
        );

        final fakeService = _FakeDailyReviewService(summary: summary);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DailyReviewCard(service: fakeService)),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('口腔每日计划'), findsOneWidget);
        expect(find.text('已连续打卡 3 天'), findsOneWidget);
        expect(find.text('待学新题: 15 题'), findsOneWidget);
        expect(find.text('待到期复习: 10 题'), findsOneWidget);
        expect(find.text('开始今日打卡'), findsOneWidget);
      },
    );

    testWidgets('renders achieved state when daily plan is completed', (
      tester,
    ) async {
      const completedSummary = DailyReviewSummary(
        planId: 'plan_1',
        planName: '执业医师打卡计划',
        dailyNewTarget: 20,
        dailyReviewLimit: 50,
        completedNewToday: 20,
        completedReviewToday: 50,
        remainingDueCount: 0,
        remainingNewCount: 0,
        streakDays: 12,
      );

      final fakeService = _FakeDailyReviewService(summary: completedSummary);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DailyReviewCard(service: fakeService)),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('执业医师打卡计划'), findsOneWidget);
      expect(find.text('已连续打卡 12 天'), findsOneWidget);
      expect(find.text('今日计划已圆满打卡！'), findsOneWidget);
      expect(find.text('再学一组 / 继续巩固'), findsOneWidget);
    });
  });

  group('DailyReviewPage Interactive Flow Tests', () {
    testWidgets(
      'answers multiple-choice question, displays feedback, rating bar and celebrates',
      (tester) async {
        final sampleQuestion = Question(
          id: 'q_mock_001',
          title: '牙周炎最主要的始动因子是？',
          answer: 'B',
          userAnswer: '',
          type: '1', // 单选题
          explain: '牙菌斑生物膜是牙周病发生发展的始动因子。',
          option:
              '[{"key":"A","title":"不良修复体"},{"key":"B","title":"牙菌斑生物膜"},{"key":"C","title":"咬合创伤"}]',
        );

        final queueItem = DailyReviewQueueItem(
          questionId: sampleQuestion.id,
          isNew: true,
          question: sampleQuestion,
          bankId: 'dental_final',
          reviewItem: SpacedReviewItem(itemId: sampleQuestion.id),
        );

        const plan = ReviewPlan(id: 'plan_mock', name: '模拟计划');
        final session = DailyReviewSession(
          plan: plan,
          date: DateTime.now(),
          dueQueue: [],
          newQueue: [queueItem],
        );

        final fakeService = _FakeDailyReviewService(session: session);

        await tester.pumpWidget(
          MaterialApp(
            home: DailyReviewPage(
              plan: plan,
              service: fakeService,
              initialSession: session,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. 验证题干与选项已渲染
        expect(find.text('牙周炎最主要的始动因子是？'), findsOneWidget);
        expect(find.text('今日新学'), findsOneWidget);
        expect(find.text('1 / 1'), findsOneWidget);
        expect(find.text('牙菌斑生物膜'), findsOneWidget);

        // 评分条此时未作答不展示
        expect(find.text('重来'), findsNothing);

        // 2. 点击正确答案 B
        await tester.tap(find.text('牙菌斑生物膜'));
        await tester.pumpAndSettle();

        // 3. 验证选项反馈高亮、解析展开以及 4 档评级栏出现
        expect(find.text('题目解析'), findsOneWidget);
        expect(find.text('牙菌斑生物膜是牙周病发生发展的始动因子。'), findsOneWidget);
        expect(find.text('重来'), findsOneWidget);
        expect(find.text('困难'), findsOneWidget);
        expect(find.text('良好'), findsOneWidget);
        expect(find.text('简单'), findsOneWidget);

        // 写入未完成时双击评分只能提交一次，不能提前推进或结算。
        fakeService.submissionGate = Completer<void>();
        await tester.tap(find.text('良好'));
        await tester.pump();
        await tester.tap(find.text('良好'));
        await tester.pump();
        expect(fakeService.submissionCount, 1);
        expect(find.text('今日计划打卡成功！'), findsNothing);
        fakeService.submissionGate!.complete();
        await tester.pumpAndSettle();

        // 5. 校验 Service 提交结果
        expect(fakeService.lastSubmittedQuestionId, 'q_mock_001');
        expect(fakeService.lastSubmittedRating, ReviewRating.good);

        // 6. 验证打卡成功结算弹窗展示
        expect(find.text('今日计划打卡成功！'), findsOneWidget);
        expect(find.text('完成打卡'), findsOneWidget);
      },
    );
  });

  testWidgets('斩卡移除当前及尾部Again副本，不再流转已斩卡', (tester) async {
    const card = CustomFlashcard(id: 'cut_card', front: 'front', back: 'back');
    const item = DailyReviewQueueItem(
      questionId: 'cut_card',
      itemType: ReviewItemType.flashcard,
      isNew: false,
      customFlashcard: card,
    );
    final session = DailyReviewSession(
      plan: const ReviewPlan(id: 'p', name: 'p'),
      date: DateTime.now(),
      dueQueue: [item, item],
      newQueue: [],
    );
    final service = _FakeDailyReviewService(session: session);
    await tester.pumpWidget(
      MaterialApp(
        home: DailyReviewPage(service: service, initialSession: session),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('熟练斩卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('斩掉此卡'));
    await tester.pumpAndSettle();
    expect(service.lastCutQuestionId, 'cut_card');
    expect(find.text('今日计划打卡成功！'), findsOneWidget);
  });

  group('DailyPlanPage Tab Widget Tests', () {
    testWidgets(
      'renders daily plan tab with scope summary, insights and forecast',
      (tester) async {
        const summary = DailyReviewSummary(
          planId: 'plan_tab',
          planName: 'Anki浓缩错题计划',
          dailyNewTarget: 15,
          dailyReviewLimit: 30,
          completedNewToday: 0,
          completedReviewToday: 0,
          remainingDueCount: 8,
          remainingNewCount: 15,
          streakDays: 4,
          sourceTypes: ['wrong', 'collected', 'note'],
          coveredSubjects: ['101', '102'],
          poolWrongCount: 42,
          poolCollectedCount: 19,
          poolNoteCount: 7,
          poolMasteredCount: 88,
        );

        final fakeService = _FakeDailyReviewService(summary: summary);
        final fakeRepo = _FakeSpacedReviewRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: DailyPlanPage(service: fakeService, repository: fakeRepo),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('每日复习计划'), findsOneWidget);
        expect(find.text('Anki浓缩错题计划'), findsOneWidget);
        expect(find.text('已连续打卡 4 天'), findsOneWidget);
        expect(find.text('抽题范围: 错题 · 收藏 · 笔记 | 覆盖 2 门课程'), findsOneWidget);
        expect(find.text('卡片池'), findsOneWidget);
        expect(find.text('闪卡卡包'), findsOneWidget);
        expect(find.text('自制闪卡'), findsOneWidget);
        expect(find.text('42'), findsOneWidget); // 错题攻克
        expect(find.text('19'), findsOneWidget); // 星标收藏
        expect(find.text('未来 7 天到期预测'), findsOneWidget);
        expect(find.text('开始今日打卡'), findsOneWidget);
      },
    );

    testWidgets(
      'reviews flashcard with 3D flip card and self-eval rating bar',
      (tester) async {
        const plan = ReviewPlan(
          id: 'plan_flashcard',
          name: '闪卡自测计划',
          targetType: 'all',
          dailyNewTarget: 10,
          dailyReviewLimit: 20,
        );

        final flashcard = const CustomFlashcard(
          id: 'fc_pharmacology_1',
          title: '利多卡因抗心律失常机制',
          front: '简述利多卡因治疗室性心律失常的作用靶点与机制。',
          back: '抑制钠通道，降低自律性，缩短动作电位时程(APD)及有效不应期(ERP)。',
          tags: '药理学,心血管',
        );

        final queueItem = DailyReviewQueueItem(
          questionId: flashcard.id,
          itemType: ReviewItemType.flashcard,
          isNew: true,
          customFlashcard: flashcard,
        );

        final session = DailyReviewSession(
          plan: plan,
          date: DateTime.now(),
          dueQueue: [],
          newQueue: [queueItem],
        );

        final fakeService = _FakeDailyReviewService(session: session);

        await tester.pumpWidget(
          MaterialApp(
            home: DailyReviewPage(
              plan: plan,
              service: fakeService,
              initialSession: session,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. 验证闪卡卡片正面渲染
        expect(find.text('今日闪卡记忆'), findsOneWidget);
        expect(find.text('闪卡 · 正面'), findsOneWidget);
        expect(find.text('自制闪卡'), findsOneWidget);
        expect(find.text(flashcard.front), findsOneWidget);
        expect(find.text('轻触卡片 3D 翻转至背面查看解析 ✨'), findsOneWidget);

        // 自评按钮在未翻转前不应出现
        expect(find.text('良好'), findsNothing);

        // 2. 点击卡片进行 3D 物理翻转
        await tester.tap(find.text(flashcard.front));
        await tester.pumpAndSettle();

        // 3. 翻转至背面：展示背面答案及滑出自评按钮
        expect(find.text('闪卡 · 背面 (答案与解析)'), findsOneWidget);
        expect(find.text(flashcard.back), findsOneWidget);

        expect(find.text('重来'), findsOneWidget);
        expect(find.text('困难'), findsOneWidget);
        expect(find.text('良好'), findsOneWidget);
        expect(find.text('简单'), findsOneWidget);

        // 4. 用户点击 "良好" 自评评级
        await tester.tap(find.text('良好'));
        await tester.pumpAndSettle();

        // 5. 校验 Service 提交结果
        expect(fakeService.lastSubmittedQuestionId, 'fc_pharmacology_1');
        expect(fakeService.lastSubmittedRating, ReviewRating.good);

        // 6. 验证完成打卡弹窗
        expect(find.text('今日计划打卡成功！'), findsOneWidget);
      },
    );

    testWidgets(
      'reviews note directly without flipping and evaluates immediately',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'review_note_with_question': false,
        });

        const plan = ReviewPlan(
          id: 'plan_note',
          name: '笔记复习计划',
          targetType: 'all',
          dailyNewTarget: 10,
          dailyReviewLimit: 20,
        );

        final question = Question(
          id: 'q_note_001',
          title: '下列生理活动中，属于负反馈调节的是什么？',
          type: '1',
          typeStr: '单选题',
          answer: 'A',
          option:
              '[{"key":"A","title":"降压反射调节血压"},{"key":"B","title":"排尿反射"},{"key":"C","title":"血液凝固"},{"key":"D","title":"分娩过程"}]',
          userAnswer: 'A',
        );

        final queueItem = DailyReviewQueueItem(
          questionId: question.id,
          itemType: ReviewItemType.question,
          isNew: false,
          isFromNote: true,
          question: question,
        );

        final session = DailyReviewSession(
          plan: plan,
          date: DateTime.now(),
          dueQueue: [queueItem],
          newQueue: [],
        );

        final fakeService = _FakeDailyReviewService(session: session);

        await tester.pumpWidget(
          MaterialApp(
            home: DailyReviewPage(
              plan: plan,
              service: fakeService,
              initialSession: session,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. 无需翻转，直接展示题目题干与选项
        expect(find.text('下列生理活动中，属于负反馈调节的是什么？'), findsOneWidget);
        expect(find.text('降压反射调节血压'), findsOneWidget);

        // 2. 评级栏直接可见，无需任何翻转卡片步骤
        expect(find.text('良好'), findsOneWidget);
        expect(find.text('困难'), findsOneWidget);
        expect(find.text('简单'), findsOneWidget);

        // 3. 直接自评打分切题
        await tester.tap(find.text('良好'));
        await tester.pumpAndSettle();

        expect(fakeService.lastSubmittedQuestionId, 'q_note_001');
        expect(fakeService.lastSubmittedRating, ReviewRating.good);
      },
    );

    testWidgets(
      'reviews flashcard without 3D animation when setting disabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({'flashcard_3d_flip': false});

        const plan = ReviewPlan(
          id: 'plan_flashcard_flat',
          name: '平面闪卡计划',
          targetType: 'all',
          dailyNewTarget: 10,
          dailyReviewLimit: 20,
        );

        final flashcard = const CustomFlashcard(
          id: 'fc_physio_2',
          title: '动作电位去极化离子基础',
          front: '动作电位上升支（去极化）是由哪种离子流产生的？',
          back: 'Na+快速大量内流。',
        );

        final queueItem = DailyReviewQueueItem(
          questionId: flashcard.id,
          itemType: ReviewItemType.flashcard,
          isNew: true,
          customFlashcard: flashcard,
        );

        final session = DailyReviewSession(
          plan: plan,
          date: DateTime.now(),
          dueQueue: [],
          newQueue: [queueItem],
        );

        final fakeService = _FakeDailyReviewService(session: session);

        await tester.pumpWidget(
          MaterialApp(
            home: DailyReviewPage(
              plan: plan,
              service: fakeService,
              initialSession: session,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 验证提示文案为平面切换提示
        expect(find.text('轻触卡片查看背面解析 ✨'), findsOneWidget);
        expect(find.text('动作电位上升支（去极化）是由哪种离子流产生的？'), findsOneWidget);

        // 点击直接切换到背面
        await tester.tap(find.text('动作电位上升支（去极化）是由哪种离子流产生的？'));
        await tester.pumpAndSettle();

        expect(find.text('Na+快速大量内流。'), findsOneWidget);
        expect(find.text('良好'), findsOneWidget);
      },
    );
  });
}

class _FakeDailyReviewService extends DailyReviewService {
  final DailyReviewSummary? summary;
  final DailyReviewSession? session;

  Completer<void>? submissionGate;
  int submissionCount = 0;
  String? lastCutQuestionId;
  String? lastSubmittedQuestionId;
  ReviewRating? lastSubmittedRating;

  _FakeDailyReviewService({this.summary, this.session});

  @override
  Future<DailyReviewSummary> getTodaySummary({
    ReviewPlan? customPlan,
    DateTime? now,
    dynamic executor,
  }) async {
    if (summary != null) return summary!;
    return const DailyReviewSummary(
      planId: 'plan_test',
      planName: '测试计划',
      dailyNewTarget: 20,
      dailyReviewLimit: 50,
      completedNewToday: 0,
      completedReviewToday: 0,
      remainingDueCount: 5,
      remainingNewCount: 10,
    );
  }

  @override
  Future<DailyReviewSession> buildDailySession({
    ReviewPlan? customPlan,
    DateTime? now,
    dynamic executor,
    bool isExtraSession = false,
  }) async {
    if (session != null) return session!;
    return DailyReviewSession(
      plan: customPlan ?? const ReviewPlan(id: 'p', name: 'n'),
      date: now ?? DateTime.now(),
      dueQueue: [],
      newQueue: [],
    );
  }

  @override
  Future<void> cutQuestion({
    required String questionId,
    required String bankId,
    String? planId,
    DateTime? now,
    dynamic executor,
  }) async {
    lastCutQuestionId = questionId;
  }

  @override
  Future<SpacedReviewItem> submitReviewResult({
    required String questionId,
    required ReviewRating rating,
    int durationSeconds = 0,
    String? userAnswer,
    String? bankId,
    DateTime? now,
    dynamic executor,
    String? eventId,
    String? planId,
    ReviewItemType? expectedItemType,
  }) async {
    submissionCount++;
    if (submissionGate != null) await submissionGate!.future;
    lastSubmittedQuestionId = questionId;
    lastSubmittedRating = rating;
    return SpacedReviewItem(itemId: questionId, lastRating: rating);
  }
}

class _FakeSpacedReviewRepository extends SpacedReviewRepository {
  ReviewPlan? savedPlan;

  @override
  Future<void> savePlan(ReviewPlan plan, [dynamic executor]) async {
    savedPlan = plan;
  }

  @override
  Future<ReviewPlan> getOrCreateActivePlan([dynamic executor]) async {
    return savedPlan ?? const ReviewPlan(id: 'active', name: '默认计划');
  }

  @override
  Future<Map<String, int>> getDueForecast({
    String? planId,
    int days = 7,
    DateTime? now,
    dynamic executor,
  }) async {
    return {};
  }
}
