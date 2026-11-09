import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/screens/question_detail/question_note_view.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:yibubang/widgets/flashcard_deck_dialog.dart';
import 'package:yibubang/widgets/flashcard_edit_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String testDir;
  late String dbPath;
  late Database testDb;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'sync_notes_to_ykb': false});
    testDir = Directory.systemTemp.createTempSync('flashcard_test_').path;
    dbPath = '$testDir/user_data.sqlite';
    testDb = await openDatabase(dbPath);
    await testDb.execute('''
      CREATE TABLE IF NOT EXISTS Question (
        id TEXT PRIMARY KEY,
        chapter_id TEXT,
        chapter_parent_id TEXT,
        cut_question TEXT DEFAULT '0',
        user_answer TEXT DEFAULT '',
        status INTEGER DEFAULT 0,
        collection INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0
      )
    ''');
    await testDb.execute('''
      CREATE TABLE IF NOT EXISTS Notes (
        id TEXT PRIMARY KEY,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await testDb.execute('''
      CREATE TABLE IF NOT EXISTS Activities (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        bank_id TEXT,
        question_id TEXT,
        identity_id TEXT,
        subject_id TEXT,
        chapter_id TEXT,
        is_right TEXT,
        duration INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await UserDBHelper().createSpacedRepetitionTablesForTesting(testDb);
    UserDBHelper.setDatabaseForTesting(testDb);
  });

  tearDownAll(() async {
    UserDBHelper.setDatabaseForTesting(null);
    await testDb.close();
    try {
      Directory(testDir).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Flashcard System & Touchpoint Tests', () {
    testWidgets('Touchpoint 1: QuestionNoteView renders make flashcard and one-click convert buttons', (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final question = Question(
        id: 'q_cardiology_888',
        title: '心衰患者使用洋地黄中毒最具特异性的心电图表现是什么？',
        type: '1',
        typeStr: '单选题',
        userAnswer: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuestionNoteView(question: question),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证标题栏中的「制作闪卡」与「写笔记」按钮
      expect(find.text('我的笔记'), findsOneWidget);
      expect(find.text('制作闪卡'), findsOneWidget);
      expect(find.text('写笔记'), findsOneWidget);

      // 点击「制作闪卡」唤起 FlashcardEditDialog
      await tester.tap(find.text('制作闪卡'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('制作自制闪卡'), findsOneWidget);
      expect(find.text('正面 (Front · 问题 / 概念)'), findsOneWidget);
      expect(find.text('背面 (Back · 答案 / 解析 / 重点总结)'), findsOneWidget);
      expect(find.textContaining('已自动关联原题 (ID: q_cardiology_888)'), findsOneWidget);

      // 关闭弹窗
      await tester.tap(find.text('取消'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    });

    testWidgets('Touchpoint 1: FlashcardEditDialog creates and saves flashcard', (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      CustomFlashcard? savedCard;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  savedCard = await FlashcardEditDialog.show(
                    ctx,
                    initialFront: '急性左心衰竭抢救体位',
                    initialBack: '端坐位，双腿下垂，减少静脉回流。',
                    questionId: 'q_hf_001',
                    defaultTag: '急危重症,心血管',
                    dialogTitle: '为本题制作自制闪卡',
                  );
                },
                child: const Text('打开编辑弹窗'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('打开编辑弹窗'));
      await tester.pumpAndSettle();

      expect(find.text('为本题制作自制闪卡'), findsOneWidget);
      expect(find.text('急性左心衰竭抢救体位'), findsOneWidget);
      expect(find.text('端坐位，双腿下垂，减少静脉回流。'), findsOneWidget);

      // 点击保存入库
      final filledBtn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledBtn.onPressed, isNotNull);
      await tester.runAsync(() async {
        filledBtn.onPressed!();
        for (int i = 0; i < 50; i++) {
          if (savedCard != null) break;
          await Future.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(savedCard, isNotNull);
      expect(savedCard?.front, '急性左心衰竭抢救体位');
      expect(savedCard?.questionId, 'q_hf_001');
      expect(savedCard?.tags, contains('急危重症'));

      // 验证仓库已保存
      final repo = SpacedReviewRepository();
      CustomFlashcard? loaded;
      await tester.runAsync(() async {
        loaded = await repo.getFlashcard(savedCard!.id);
        await repo.deleteFlashcard(savedCard!.id);
      });
      expect(loaded, isNotNull);
      expect(loaded?.back, contains('端坐位'));
    });

    testWidgets('Touchpoint 2: FlashcardDeckDialog displays list, search and tag filter', (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = SpacedReviewRepository();
      final card1 = const CustomFlashcard(
        id: 'fc_test_deck_1',
        front: '硝酸甘油舒张血管主要机制',
        back: '在血管平滑肌细胞内释放NO，激活鸟苷酸环化酶，增加cGMP。',
        tags: '药理学,心绞痛',
      );
      final card2 = const CustomFlashcard(
        id: 'fc_test_deck_2',
        front: '法洛四联症四种畸形',
        back: '肺动脉狭窄、室间隔缺损、主动脉骑跨、右心室肥厚。',
        tags: '儿科学,先心病',
      );

      await tester.runAsync(() async {
        await repo.saveFlashcard(card1);
        await repo.saveFlashcard(card2);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlashcardDeckDialog(),
          ),
        ),
      );

      for (int i = 0; i < 50; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.text(card1.front).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();

      // 验证卡包头部与列表项
      expect(find.text('闪卡卡包管理'), findsOneWidget);
      expect(find.text(card1.front), findsOneWidget);
      expect(find.text(card2.front), findsOneWidget);

      // 验证标签 FilterChip
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('儿科学'), findsOneWidget);

      // 切换标签筛选
      await tester.tap(find.text('儿科学'));
      await tester.pumpAndSettle();

      expect(find.text(card2.front), findsOneWidget);
      expect(find.text(card1.front), findsNothing);

      // 搜索框筛选
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '硝酸甘油');
      await tester.pumpAndSettle();

      expect(find.text(card1.front), findsOneWidget);
      expect(find.text(card2.front), findsNothing);

      // 清理
      await tester.runAsync(() async {
        await repo.deleteFlashcard(card1.id);
        await repo.deleteFlashcard(card2.id);
      });
    });

    test('Touchpoint 3: DailyReviewService draws flashcards and processes SM-2 self-evaluation', () async {
      final repo = SpacedReviewRepository();
      final card = const CustomFlashcard(
        id: 'fc_draw_test_1',
        front: '阿司匹林三联征(Aspirin triad)',
        back: '阿司匹林不耐受、哮喘、鼻息肉。',
        tags: '内科学,呼吸系统',
      );
      await repo.saveFlashcard(card);

      final service = DailyReviewService();
      final plan = const ReviewPlan(
        id: 'plan_flashcard_draw',
        name: '闪卡自测',
        targetType: 'all',
        sourceTypes: ['flashcard'],
        dailyNewTarget: 5,
        dailyReviewLimit: 10,
      );

      // 1. 抽取新题队列包含自制闪卡
      final session = await service.buildDailySession(customPlan: plan);
      expect(session.newQueue.any((item) => item.questionId == 'fc_draw_test_1'), isTrue);

      final flashcardItem = session.newQueue.firstWhere((item) => item.questionId == 'fc_draw_test_1');
      expect(flashcardItem.itemType, ReviewItemType.flashcard);
      expect(flashcardItem.customFlashcard?.front, contains('阿司匹林三联征'));

      // 2. 模拟自评提交 "Good"
      final updatedItem = await service.submitReviewResult(
        questionId: 'fc_draw_test_1',
        rating: ReviewRating.good,
        durationSeconds: 8,
      );

      expect(updatedItem.reps, 1);
      expect(updatedItem.interval, greaterThanOrEqualTo(1));
      expect(updatedItem.itemType, ReviewItemType.flashcard);

      // 3. 验证斩卡
      await service.cutQuestion(
        questionId: 'fc_draw_test_1',
        bankId: '',
        planId: plan.id,
      );

      final masteredItem = await repo.getItem('fc_draw_test_1');
      expect(masteredItem?.state, ReviewState.mastered);

      // 清理
      await repo.deleteFlashcard('fc_draw_test_1');
    });

    test('SQLite self-healing: repairs CustomFlashcards missing question_id and Notes foreign key', () async {
      final healDir = Directory.systemTemp.createTempSync('heal_test_').path;
      final healDbPath = '$healDir/user_data.sqlite';
      final healDb = await openDatabase(
        healDbPath,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA foreign_keys = ON');
        },
      );

      // 模拟老版本有缺陷的表结构
      await healDb.execute('''
        CREATE TABLE Question (
          id TEXT PRIMARY KEY,
          chapter_id TEXT,
          chapter_parent_id TEXT,
          updated_at INTEGER DEFAULT 0
        )
      ''');
      // 老旧的 CustomFlashcards 没有 question_id 列
      await healDb.execute('''
        CREATE TABLE CustomFlashcards (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          front TEXT NOT NULL,
          back TEXT NOT NULL,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      // 老旧的 Notes 误指向 questions(id)
      await healDb.execute('''
        CREATE TABLE Notes (
          id TEXT PRIMARY KEY,
          question_id TEXT NOT NULL,
          content TEXT NOT NULL,
          imgs TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id)
        )
      ''');

      // 插入一条历史笔记
      await healDb.execute('PRAGMA foreign_keys = OFF');
      await healDb.insert('Notes', {
        'id': 'note_old_1',
        'question_id': 'q_old_100',
        'content': '老数据内容',
        'imgs': '[]',
        'timestamp': 1234567,
      });
      await healDb.execute('PRAGMA foreign_keys = ON');

      // 执行自愈
      await UserDBHelper().repairDatabaseForTesting(healDb);

      // 1. 验证 CustomFlashcards 补上了 question_id
      final flashcardCols = (await healDb.rawQuery('PRAGMA table_info(CustomFlashcards)'))
          .map((r) => r['name'] as String)
          .toList();
      expect(flashcardCols.contains('question_id'), isTrue);

      // 测试插入带 question_id 的新闪卡无异常
      await healDb.insert('CustomFlashcards', {
        'id': 'fc_new_1',
        'title': '测试标题',
        'front': '问题',
        'back': '答案',
        'question_id': 'q_old_100',
        'tags': '标签1',
        'created_at': 1234567,
        'updated_at': 1234567,
      });

      // 2. 验证 Notes 表外键指向了 Question(id) 并且老数据完整保留
      final notesSql = (await healDb.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='Notes'",
      )).first['sql'] as String;
      expect(notesSql, contains('REFERENCES Question(id)'));
      expect(notesSql.contains('questions('), isFalse);

      final preservedRows = await healDb.query('Notes', where: 'id = ?', whereArgs: ['note_old_1']);
      expect(preservedRows.length, 1);
      expect(preservedRows.first['content'], '老数据内容');

      // 测试在 foreign_keys = ON 下正常保存笔记
      await healDb.insert('Question', {
        'id': 'q_test_200',
        'chapter_id': 'c1',
        'chapter_parent_id': 's1',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await healDb.insert('Notes', {
        'id': 'note_new_2',
        'question_id': 'q_test_200',
        'content': '新笔记',
        'imgs': '[]',
        'timestamp': 7654321,
      });

      await healDb.close();
      try {
        Directory(healDir).deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('FlashcardEditDialog quotes restore/explain and manages tags', (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  FlashcardEditDialog.showAsBottomSheet(
                    ctx,
                    initialFront: '简述成釉细胞瘤的病理特征',
                    restoreText: '成釉细胞瘤是颌骨最常见的牙源性肿瘤',
                    explainText: '滤泡型成釉细胞瘤周边为单层柱状细胞，中央为星网状细胞',
                    initialTags: ['口腔组织病理学', '牙源性肿瘤'],
                    availableTags: ['常考点', '药理学'],
                  );
                },
                child: const Text('打开底部抽屉闪卡'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('打开底部抽屉闪卡'));
      await tester.pumpAndSettle();

      // 验证默认标签已渲染为 Chips
      expect(find.text('口腔组织病理学'), findsOneWidget);
      expect(find.text('牙源性肿瘤'), findsOneWidget);

      // 删除其中一个标签（点击删除图标）
      final closeIcons = find.byIcon(Icons.close_rounded);
      expect(closeIcons, findsWidgets);
      // 点击其中一个标签的删除图标（第一个closeIcon是右上角关闭按钮，后面的则是InputChip的deleteIcon）
      await tester.tap(closeIcons.at(1));
      await tester.pumpAndSettle();

      // 验证引用考点还原
      expect(find.text('✨ 引用考点还原'), findsOneWidget);
      await tester.tap(find.text('✨ 引用考点还原'));
      await tester.pumpAndSettle();

      // 验证引用答案解析
      expect(find.text('💡 引用答案解析'), findsOneWidget);
      await tester.tap(find.text('💡 引用答案解析'));
      await tester.pumpAndSettle();

      // 验证快捷选择常用标签
      expect(find.text('常考点'), findsOneWidget);
      await tester.tap(find.text('常考点'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // 验证常用标签已被添加到已选列表中
      expect(find.text('常考点'), findsOneWidget);

      // 关闭抽屉
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  });
}
