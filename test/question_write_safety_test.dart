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
