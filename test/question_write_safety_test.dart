import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/models/chapter.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/screens/question_detail/question_detail_controller.dart';
import 'package:yibubang/screens/question_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database db;
  late String previous;
  final q = Question(
    id: '1',
    chapterId: 'c',
    chapterParentId: 's',
    identityId: 'i',
    type: '1',
    answer: 'A',
    userAnswer: '',
  );
  UserQuestion uq() => UserQuestion(
    id: '1',
    chapterId: 'c',
    chapterParentId: 's',
    userAnswer: '',
    status: 0,
    collection: 0,
  );
  QuestionDetailController controller(UserQuestion u) =>
      QuestionDetailController(
        chapter: Chapter(
          id: 'c',
          name: 'c',
          subjectId: 's',
          correct: 0,
          incorrect: 0,
          total: 1,
        ),
        questions: [q],
        userQuestions: [u],
        initialIndex: 0,
        bankId: 'b',
      );
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('question_write_');
    await databaseFactory.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({
      'sync_answers_to_ykb': false,
      'sync_cut_to_ykb': false,
    });
    db = await UserDBHelper().database;
  });
  tearDown(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  Future<void> bank() async {
    final path = p.join(dir.path, 'fixture.sqlite');
    final fixture = await openDatabase(path);
    await fixture.execute(
      'CREATE TABLE IdentityQuestion(question_id TEXT,identity_id TEXT,subject_id TEXT,chapter_id TEXT)',
    );
    await fixture.insert('IdentityQuestion', {
      'question_id': '1',
      'identity_id': 'i',
      'subject_id': 's',
      'chapter_id': 'c',
    });
    await fixture.close();
    await QuestionBankDatabaseManager().openBank(
      'b',
      filePath: path,
      validate: false,
    );
  }

  test('旧页面收藏/斩题意图不会覆盖云端的新答案', () async {
    await db.insert('Question', {
      'id': '1',
      'status': 1,
      'user_answer': 'A',
      'collection': 0,
      'cut_question': '0',
    });
    final stale = uq()..collection = 1;
    await updateQuestionSimple(stale, q, fields: {'collection'});
    stale.cutQuestion = '1';
    await updateQuestionSimple(stale, q, fields: {'cut_question'});
    final saved = (await db.query('Question')).single;
    expect(saved['user_answer'], 'A');
    expect(saved['status'], 1);
    expect(saved['collection'], 1);
    expect(saved['cut_question'], '1');
  });
  test('放回历史斩题只条件重置状态3，不能清除已同步的新答案', () async {
    await db.insert('Question', {
      'id': '1',
      'status': 1,
      'user_answer': 'A',
      'cut_question': '1',
    });
    final stale = uq()
      ..status = 3
      ..cutQuestion = '0';
    await updateQuestionSimple(stale, q, fields: {'cut_question'});
    expect((await db.query('Question')).single['status'], 1);
    await db.update('Question', {'status': 3}, where: "id='1'");
    await updateQuestionSimple(stale, q, fields: {'cut_question'});
    expect((await db.query('Question')).single['status'], 0);
  });
  test('提交快照在首个await前固定，作答也不覆盖收藏和斩题', () async {
    await bank();
    await db.insert('Question', {
      'id': '1',
      'status': 2,
      'user_answer': 'B',
      'collection': 1,
      'cut_question': '1',
    });
    final answer = uq()
      ..userAnswer = 'A'
      ..status = 1;
    final saving = updateQuestion(answer, q, bankId: 'b', durationMs: 123);
    answer.userAnswer = 'B';
    answer.status = 2;
    await saving;
    final saved = (await db.query('Question')).single;
    expect(saved['user_answer'], 'A');
    expect(saved['status'], 1);
    expect(saved['collection'], 1);
    expect(saved['cut_question'], '1');
    expect((await db.query('Activities')).single['duration'], 123);
  });
  test('等待所有本地保存，控制器销毁后晚到失败不会通知失活页面', () async {
    final c = controller(uq());
    final pending = Completer<void>();
    var flushed = false;
    c.trackLocalWrite(pending.future);
    final flushing = c.flushPendingWrites().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, false);
    c.dispose();
    pending.completeError(StateError('disk failure'));
    await flushing;
    expect(flushed, true);
    expect(c.lastSaveError, isA<StateError>());
  });
  test('测试交卷保存恢复用时并同时退出模式，重复调用不重复记账', () async {
    await bank();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', 2);
    await db.insert('Question', {'id': '1', 'status': 4, 'user_answer': 'A'});
    await db.insert('QuestionTestTime', {
      'question_id': '1',
      'duration_ms': 1234,
    });
    final user = uq()
      ..userAnswer = 'A'
      ..status = 4;
    final c = controller(user);
    await c.init();
    final results = await Future.wait([
      c.finishTestAndFlush(),
      c.finishTestAndFlush(),
    ]);
    expect(results.first.key, 1);
    expect(results.last.key, 1);
    expect(c.mode, 0);
    expect(prefs.getInt('mode'), 0);
    expect(
      (await db.query('Activities')).single['duration'] as int,
      greaterThanOrEqualTo(1234),
    );
    expect((await db.query('Question')).single['status'], 1);
    expect(await db.query('QuestionTestTime'), isEmpty);
    c.dispose();
    await c.flushPendingWrites();
  });
  test('交卷失败保留待提交状态和用时，重试成功后才退出', () async {
    await bank();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', 2);
    await db.insert('Question', {'id': '1', 'status': 4, 'user_answer': 'A'});
    await db.insert('QuestionTestTime', {
      'question_id': '1',
      'duration_ms': 4321,
    });
    await db.execute(
      "CREATE TRIGGER fail_grade BEFORE INSERT ON Activities BEGIN SELECT RAISE(ABORT,'fail'); END",
    );
    final user = uq()
      ..userAnswer = 'A'
      ..status = 4;
    final c = controller(user);
    await c.init();
    await expectLater(
      c.finishTestAndFlush(),
      throwsA(isA<DatabaseException>()),
    );
    expect(c.mode, 2);
    expect(user.status, 4);
    expect((await db.query('Question')).single['status'], 4);
    expect(
      (await db.query('QuestionTestTime')).single['duration_ms'] as int,
      greaterThanOrEqualTo(4321),
    );
    await db.execute('DROP TRIGGER fail_grade');
    await c.finishTestAndFlush();
    expect(c.mode, 0);
    expect((await db.query('Activities')).length, 1);
    c.dispose();
    await c.flushPendingWrites();
  });
  test('初始化期间销毁控制器不会使用已释放的notifier', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', 2);
    final c = controller(uq());
    final init = c.init(persistPosition: false);
    c.dispose();
    await init;
    expect(c.mode, 0);
  });
  test('待交选答保存失败时不提前退出，恢复磁盘后交卷可重试', () async {
    await bank();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', 2);
    final user = uq()
      ..userAnswer = 'A'
      ..status = 4;
    final c = controller(user);
    await c.init();
    await db.execute(
      "CREATE TRIGGER fail_selection BEFORE UPDATE ON Question BEGIN SELECT RAISE(ABORT,'disk'); END",
    );
    c.savePendingSelection(q, user);
    await expectLater(
      c.finishTestAndFlush(),
      throwsA(isA<DatabaseException>()),
    );
    expect(c.mode, 2);
    expect(await db.query('Activities'), isEmpty);
    await db.execute('DROP TRIGGER fail_selection');
    await c.finishTestAndFlush();
    expect(c.mode, 0);
    expect((await db.query('Activities')).single['is_right'], '1');
    c.dispose();
    await c.flushPendingWrites();
  });
  testWidgets('返回取消保留测试，确认后交卷并冒泡当前章节结果', (tester) async {
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      await bank();
      prefs = await SharedPreferences.getInstance();
      await prefs.setInt('mode', 2);
      await db.insert('Question', {'id': '1', 'status': 4, 'user_answer': 'A'});
      await db.insert('QuestionTestTime', {
        'question_id': '1',
        'duration_ms': 500,
      });
    });
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('home')),
      ),
    );
    final chapter = Chapter(
      id: 'c',
      name: 'chapter',
      subjectId: 's',
      correct: 0,
      incorrect: 0,
      total: 1,
    );
    Object? returned;
    nav.currentState!
        .push(
          MaterialPageRoute<Object?>(
            builder: (_) => QuestionDetailPage(
              chapter: chapter,
              questions: [q],
              userQuestions: [
                uq()
                  ..status = 4
                  ..userAnswer = 'A',
              ],
              questionIndex: 0,
              bankId: 'b',
            ),
          ),
        )
        .then((value) => returned = value);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.byType(BackButton)));
    await tester.pumpAndSettle();
    expect(find.text('退出测试模式'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('取消')));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(prefs.getInt('mode'), 2);
    await tester.runAsync(() => tester.tap(find.byType(BackButton)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('继续')));
    for (var i = 0; i < 250 && returned == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(returned, isA<Chapter>());
    expect((returned as Chapter).id, 'c');
    expect(prefs.getInt('mode'), 0);
    final rows = await tester.runAsync(() => db.query('Activities'));
    expect(rows!.single['duration'] as int, greaterThanOrEqualTo(500));
    await tester.pumpAndSettle();
  });
  testWidgets('后台停留与系统时钟跳变不会污染毫秒时长', (tester) async {
    await tester.runAsync(() async {
      await bank();
      await db.insert('Question', {'id': '1'});
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const Scaffold();
          },
        ),
      ),
    );
    final user = uq()..userAnswer = 'A';
    final c = controller(user);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    c.pageOpenedAt = -999999999;
    await tester.runAsync(() async {
      c.submitAnswer(q, user, 0, context);
      await c.flushPendingWrites();
    });
    final rows = await tester.runAsync(() => db.query('Activities'));
    expect(rows!.single['duration'] as int, lessThan(50));
    c.dispose();
  });
  testWidgets('收藏保存失败回滚界面字段并展示错误', (tester) async {
    await tester.runAsync(() async {
      await db.insert('Question', {'id': '1', 'status': 1, 'user_answer': 'A'});
      await db.execute(
        "CREATE TRIGGER fail_collection BEFORE UPDATE ON Question WHEN NEW.collection!=OLD.collection BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const Scaffold();
          },
        ),
      ),
    );
    final user = uq();
    final c = controller(user);
    await tester.runAsync(() async {
      c.toggleCollection(context);
      await c.flushPendingWrites();
    });
    await tester.pump();
    expect(user.collection, 0);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    c.dispose();
  });
}
