import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/cloud_outbox.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/comment.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/question_search_repository.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/screens/about_page.dart';
import 'package:yibubang/screens/comment_page.dart';
import 'package:yibubang/screens/my_notes_page.dart';
import 'package:yibubang/screens/user_questions_list_page.dart';
import 'package:yibubang/services/comment_service.dart';
import 'package:yibubang/widgets/flashcard_deck_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String testDir;
  late Database testDb;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'user_id': '3734063',
      'token': 'test_token',
      'secret': 'test_secret',
      'subjectId': '11070',
      'identityId': '11070',
    });
    testDir = Directory.systemTemp.createTempSync('comment_feat_test_').path;
    testDb = await openDatabase('$testDir/user_data.sqlite');
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
    await testDb.execute('''
      CREATE TABLE IF NOT EXISTS Notes (
        id TEXT PRIMARY KEY,
        remote_id TEXT,
        question_id TEXT NOT NULL,
        content TEXT NOT NULL,
        imgs TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await UserDBHelper().createSpacedRepetitionTablesForTesting(testDb);
    await CloudOutbox.install(testDb);
    await CloudOutbox.bind(testDb, 'user_d1_1');
    UserDBHelper.setDatabaseForTesting(testDb);
    DatabaseHelper.setDatabaseForTesting(testDb);
  });

  tearDownAll(() async {
    UserDBHelper.setDatabaseForTesting(null);
    DatabaseHelper.setDatabaseForTesting(null);
    await testDb.close();
    try {
      Directory(testDir).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('医考帮我的点赞、我的评论与评论四维排序测试', () {
    test('syncCommentsForQuestion 拉取 mypraise 与 mycomment 并持久化及进入 CloudOutbox', () async {
      final capturedFuncs = <String>[];
      final q = Question(
        id: '1676022',
        chapterId: '11001',
        chapterParentId: '11',
        appId: '35',
        userAnswer: '',
      );

      await http.runWithClient(
        () async {
          await CommentService.instance.syncCommentsForQuestion(q);
        },
        () => MockClient((req) async {
          expect(req.url.path, contains('/Comment/Main/list'));
          final bodyParams = Uri.splitQueryString(req.body);
          final func = bodyParams['func'] ?? '';
          capturedFuncs.add(func);

          if (func == 'mypraise') {
            final payload = {
              'code': '200',
              'message': 'ok',
              'data': {
                'hot': [],
                'time_line': [
                  {
                    'id': '23910002',
                    'obj_id': '1676022',
                    'user_id': '5113574',
                    'content': '1.内环境理化因素保持相对稳定的状态称为稳态',
                    'praise_num': '72',
                    'oppose_num': '0',
                    'floor_num': '1',
                    'ctime': '2025-01-27',
                    'ctime_timestamp': '1737945975',
                    'nickname': 'BaiYuesen',
                    'school': '杭州医学院',
                    'is_praise': '1',
                    'c_imgs': {},
                    'reply': [],
                  },
                ],
              },
            };
            return http.Response.bytes(
              utf8.encode(jsonEncode(payload)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          } else if (func == 'mycomment') {
            final payload = {
              'code': '200',
              'message': 'ok',
              'data': {
                'hot': [],
                'time_line': [
                  {
                    'id': '31206886',
                    'obj_id': '1676022',
                    'user_id': '3734063',
                    'content': '前馈调节的作用是防止负反馈调节的矫枉过正。',
                    'praise_num': '0',
                    'oppose_num': '0',
                    'floor_num': '1',
                    'ctime': '5秒前',
                    'ctime_timestamp': '1795424645',
                    'nickname': '冬瓜瓜瓜（我）',
                    'school': '四川大学',
                    'is_author': '1',
                    'c_imgs': {},
                    'reply': [],
                  },
                ],
              },
            };
            return http.Response.bytes(
              utf8.encode(jsonEncode(payload)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            '{"code":"200","data":{"hot":[],"time_line":[]}}',
            200,
          );
        }),
      );

      expect(capturedFuncs, containsAll(['mypraise', 'mycomment']));

      final praised = await CommentService.instance.getAllSavedComments(
        category: SavedCommentCategory.praise,
      );
      expect(praised.length, 1);
      expect(praised.first.commentId, '23910002');
      expect(praised.first.praiseNum, 72);
      expect(praised.first.nickname, 'BaiYuesen');

      final myComments = await CommentService.instance.getAllSavedComments(
        category: SavedCommentCategory.myComment,
      );
      expect(myComments.length, 1);
      expect(myComments.first.commentId, '31206886');
      expect(myComments.first.content, contains('前馈调节'));

      // 验证 CloudOutbox 触发器已记录 saved_comment
      final outbox = await CloudOutbox.snapshot(testDb, 'user_d1_1');
      final savedOutbox =
          outbox.where((r) => r['kind'] == 'saved_comment').toList();
      expect(savedOutbox.length, 2);

      // 删除一条点赞评论，验证 tombstone 防复活
      await CommentService.instance.deleteSavedComment(praised.first.id);
      await http.runWithClient(
        () async {
          await CommentService.instance.syncCommentsForQuestion(q);
        },
        () => MockClient((req) async {
          final payload = {
            'code': '200',
            'data': {
              'hot': [],
              'time_line': [
                {
                  'id': '23910002',
                  'obj_id': '1676022',
                  'content': '1.内环境理化因素保持相对稳定的状态称为稳态',
                },
              ],
            },
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode(payload)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final afterDelete = await CommentService.instance.getAllSavedComments(
        category: SavedCommentCategory.praise,
      );
      expect(afterDelete, isEmpty);
    });

    test('fetchSortedComments 支持四维排序 type 参数 (空/recommend/replies/newst)', () async {
      final requestedTypes = <String>[];
      final q = Question(id: '1637909', appId: '40', userAnswer: '');

      await http.runWithClient(
        () async {
          for (final sort in CommentSortType.values) {
            final data = await CommentService.instance.fetchSortedComments(
              question: q,
              sortType: sort,
              page: 1,
            );
            expect(data.timeLine.length, 1);
            expect(data.timeLine.first.praiseNum, '10596');
          }
        },
        () => MockClient((req) async {
          expect(req.url.path, contains('/comment/main/hot'));
          final bodyParams = Uri.splitQueryString(req.body);
          requestedTypes.add(bodyParams['type'] ?? '<missing>');
          final payload = {
            'code': '200',
            'data': {
              'hot': [],
              'time_line': [
                {
                  'id': '14971085',
                  'obj_id': '1637909',
                  'content': '酮体包括乙丙丁：乙酰乙酸，丙酮，β-羟丁酸。',
                  'praise_num': '10596',
                  'replies': '29',
                  'c_imgs': {},
                },
              ],
            },
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode(payload)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(requestedTypes, ['', 'recommend', 'replies', 'newst']);
    });

    testWidgets('闪卡详情 -> 编辑闪卡返回时仅返回一级回到闪卡详情页，不直接退回卡包页', (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = SpacedReviewRepository();
      const card = CustomFlashcard(
        id: 'fc_nav_level_test',
        front: '洋地黄中毒最早出现的心外表现',
        back: '胃肠道反应（厌食、恶心、呕吐）',
        tags: '内科学',
      );
      await tester.runAsync(() => repo.saveFlashcard(card));

      await tester.pumpWidget(
        const MaterialApp(
          home: FlashcardDeckPage(),
        ),
      );

      for (int i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text(card.front).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();

      // 1. 点击闪卡进入「闪卡详情」
      await tester.tap(find.text(card.front));
      await tester.pumpAndSettle();
      expect(find.text('闪卡详情'), findsOneWidget);

      // 2. 在「闪卡详情」点击「编辑闪卡」
      await tester.tap(find.text('编辑闪卡'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsOneWidget);

      // 3. 在编辑弹窗点击「取消」返回，应当停留在「闪卡详情」而不是直接退回卡包列表
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('闪卡详情'), findsOneWidget);
    });

    testWidgets('关于页面包含 Telegram 交流群 (t.me/yibubang) 入口', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Telegram 交流群'), findsOneWidget);
      expect(find.text('t.me/yibubang'), findsOneWidget);
    });

    test('getTouchedQuestionIds 正确提取已做、收藏、笔记与评论去重题目 ID', () async {
      await testDb.execute('DELETE FROM Question');
      await testDb.execute('DELETE FROM Notes');
      await testDb.execute('DELETE FROM SavedComments');

      await testDb.insert('Question', {
        'id': 'q_done_1',
        'status': 1,
        'collection': 0,
      });
      await testDb.insert('Question', {
        'id': 'q_collected_1',
        'status': 0,
        'collection': 1,
      });
      await testDb.insert('Notes', {
        'id': 'n_1',
        'question_id': 'q_note_1',
        'content': 'test note',
        'timestamp': 1000,
      });
      await testDb.insert('SavedComments', {
        'id': 'sc_1',
        'category': 'praise',
        'comment_id': 'c_1',
        'question_id': 'q_comment_1',
        'content': 'test',
        'timestamp': 1000,
        'updated_at': 1000,
      });

      final ids = await CommentService.instance.getTouchedQuestionIds();
      expect(ids, containsAll(['q_done_1', 'q_collected_1', 'q_note_1', 'q_comment_1']));
      expect(ids.length, 4);
    });

    testWidgets('UserQuestionsListPage 在 scopedQuestionIds 模式下展示计划筛选提示与切换按钮',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UserQuestionsListPage(
            type: UserQuestionsType.mistake,
            scopedQuestionIds: ['q_fake_1'],
            scopeTitle: '每日计划范围',
          ),
        ),
      );
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.textContaining('已按每日计划范围筛选').evaluate().isNotEmpty) break;
      }

      expect(find.textContaining('已按每日计划范围筛选'), findsOneWidget);
      expect(find.text('查看全部'), findsOneWidget);

      await tester.tap(find.text('查看全部'));
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.textContaining('正在查看全部我的错题').evaluate().isNotEmpty) break;
      }

      expect(find.textContaining('正在查看全部我的错题'), findsOneWidget);
      expect(find.text('切回计划范围'), findsOneWidget);
    });

    testWidgets('MyNotesPage 在 scopedQuestionIds 模式下展示计划筛选提示与切换按钮',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MyNotesPage(
            scopedQuestionIds: ['q_note_1'],
            scopeTitle: '每日计划范围',
          ),
        ),
      );
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.textContaining('已按每日计划范围筛选').evaluate().isNotEmpty) break;
      }

      expect(find.textContaining('已按每日计划范围筛选'), findsOneWidget);
      expect(find.text('查看全部'), findsOneWidget);

      await tester.tap(find.text('查看全部'));
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.textContaining('正在查看全部笔记').evaluate().isNotEmpty) break;
      }

      expect(find.textContaining('正在查看全部笔记'), findsOneWidget);
      expect(find.text('切回计划范围'), findsOneWidget);
    });

    test('syncFromTouchedQuestions 支持通过 isCancelled 随时终止同步循环', () async {
      int progressCallCount = 0;
      bool cancelled = false;

      final count = await CommentService.instance.syncFromTouchedQuestions(
        category: SavedCommentCategory.praise,
        targetQuestionIds: ['q_cancel_1', 'q_cancel_2', 'q_cancel_3', 'q_cancel_4'],
        isCancelled: () => cancelled,
        onProgress: (curr, total) {
          progressCallCount++;
          if (curr >= 2) {
            cancelled = true;
          }
        },
      );

      // 仅执行了前 2 题，后续 2 题被成功终止
      expect(progressCallCount, 2);
      expect(count, greaterThanOrEqualTo(0));
    });

    test('全局批量同步互斥防护与 cancelBatchSync 状态流转', () async {
      final completer = Completer<void>();

      // 启动一个长耗时的后台模拟同步
      final syncFuture = CommentService.instance.syncFromTouchedQuestions(
        category: SavedCommentCategory.praise,
        targetQuestionIds: ['q_block_1', 'q_block_2', 'q_block_3'],
        onProgress: (curr, total) async {
          if (curr == 1 && !completer.isCompleted) {
            completer.complete();
          }
        },
      );

      // 等待任务进入运行状态
      await completer.future;
      expect(CommentService.instance.isBatchSyncing, isTrue);
      expect(CommentService.instance.batchSyncNotifier.value.isRunning, isTrue);

      // 再次尝试发起另一个并发同步，必须被抛出 StateError 严格拦截
      expect(
        () => CommentService.instance.syncFromTouchedQuestions(
          category: SavedCommentCategory.myComment,
          targetQuestionIds: ['q_concurrent_1'],
        ),
        throwsA(isA<StateError>()),
      );

      // 通过全局 cancelBatchSync 终止正在运行的同步
      CommentService.instance.cancelBatchSync();
      expect(CommentService.instance.batchSyncNotifier.value.isCancelled, isTrue);

      await syncFuture;

      // 结束后全局状态自动恢复为 false
      expect(CommentService.instance.isBatchSyncing, isFalse);
    });

    testWidgets('未登录时评论区隐藏最热/最新/我的点赞/我的评论标签并展示登录引导', (tester) async {
      SharedPreferences.setMockInitialValues({'loggedin': false});
      final q = Question(id: '1236056', appId: '40', userAnswer: '');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommentPage(question: q),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0;
          i < 100 &&
              find.text('您还没登录，无法在线加载医考帮评论哦～').evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(find.text('您还没登录，无法在线加载医考帮评论哦～'), findsOneWidget);
      expect(find.text('最热'), findsNothing);
      expect(find.text('最新'), findsNothing);
      expect(find.textContaining('我的点赞'), findsNothing);
      expect(find.textContaining('我的评论'), findsNothing);
    });
  });
}
