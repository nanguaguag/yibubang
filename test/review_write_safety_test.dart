import 'package:yibubang/models/question.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/db/review_events.dart';
import 'package:yibubang/models/answer_statistics.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:yibubang/services/spaced_repetition_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String originalPath;
  late Database db;
  final repo = SpacedReviewRepository();
  final service = DailyReviewService();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalPath = await getDatabasesPath();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('review_write_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await UserDBHelper().database;
    await repo.saveItem(const SpacedReviewItem(itemId: 'q', planId: 'p'));
  });
  tearDown(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(originalPath);
  });
  test('配置实验算法的预测与实际落库一致，参数切换不会当EF使用', () async {
    SharedPreferences.setMockInitialValues({'spaced_algorithm': 'fsrs_lite'});
    final engine = await SpacedRepetitionEngine.loadConfigured();
    final configured = DailyReviewService(engine: engine);
    final before = (await repo.getItem('q'))!;
    final prediction = configured.engine.previewNextIntervals(
      before,
    )[ReviewRating.good];
    var saved = await configured.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
    );
    expect(prediction, 3);
    expect(saved.interval, prediction);
    expect(saved.easeFactor, 2.5);
    expect(saved.extra?['fsrs_difficulty'], 5);
    saved = await configured.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.again,
    );
    expect(saved.extra?['fsrs_difficulty'], 6.2);
    saved = await service.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
    );
    expect(saved.interval, 1);
    expect(saved.easeFactor, 2.5);
    expect(saved.extra?['algorithm'], 'sm2_v1');
    expect(saved.extra?['fsrs_difficulty'], 6.2);
    saved = await configured.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
    );
    expect(saved.interval, 3);
    expect(saved.easeFactor, 2.5);
  });
  test('斩题和斩卡拒绝旧评分，显式恢复后才可继续学习', () async {
    await service.cutQuestion(questionId: 'q', bankId: '');
    await expectLater(
      service.submitReviewResult(questionId: 'q', rating: ReviewRating.again),
      throwsA(isA<ReviewUnavailableException>()),
    );
    expect((await repo.getItem('q'))!.state, ReviewState.mastered);
    final question = Question(id: 'q', userAnswer: '');
    final user = UserQuestion.fromMap((await db.query('Question')).single)
      ..isCut = false;
    await updateQuestionSimple(user, question, fields: {'cut_question'});
    await service.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
    );
    const card = CustomFlashcard(id: 'fc', front: 'f', back: 'b');
    await repo.saveFlashcard(card);
    await service.cutQuestion(questionId: 'fc', bankId: '');
    await expectLater(
      service.submitReviewResult(questionId: 'fc', rating: ReviewRating.again),
      throwsA(isA<ReviewUnavailableException>()),
    );
    expect(await repo.toggleFlashcardMastered('fc'), false);
    await service.submitReviewResult(
      questionId: 'fc',
      rating: ReviewRating.good,
    );
    expect(await db.query('Question', where: "id='fc'"), isEmpty);
  });
  test('删除后未知旧会话提交不创建孤儿，显式重新建卡移除墓碑', () async {
    const card = CustomFlashcard(id: 'deleted', front: 'f', back: 'b');
    await repo.saveFlashcard(card);
    await repo.deleteFlashcard(card.id);
    await expectLater(
      service.submitReviewResult(
        questionId: card.id,
        rating: ReviewRating.good,
      ),
      throwsA(isA<ReviewUnavailableException>()),
    );
    expect(await repo.getItem(card.id), isNull);
    expect(
      await db.query('Question', where: 'id=?', whereArgs: [card.id]),
      isEmpty,
    );
    await repo.saveFlashcard(card);
    await service.submitReviewResult(
      questionId: card.id,
      rating: ReviewRating.good,
      expectedItemType: ReviewItemType.flashcard,
    );
    expect((await repo.getItem(card.id))!.itemType, ReviewItemType.flashcard);
  });
  test('复习8秒进入答题统计且按权威关系原子维护章节计数', () async {
    final file = p.join(dir.path, 'fixture.sqlite');
    final fixture = await openDatabase(file);
    await fixture.execute(
      'CREATE TABLE IdentityQuestion(question_id TEXT,identity_id TEXT,subject_id TEXT,chapter_id TEXT)',
    );
    await fixture.insert('IdentityQuestion', {
      'question_id': 'q',
      'identity_id': 'i',
      'subject_id': 's',
      'chapter_id': 'c',
    });
    await fixture.execute(
      'CREATE TABLE Question(id TEXT PRIMARY KEY,title TEXT,chapter_id TEXT,chapter_parent_id TEXT)',
    );
    await fixture.insert('Question', {
      'id': 'q',
      'title': 'q',
      'chapter_id': 'c',
      'chapter_parent_id': 's',
    });
    await fixture.close();
    await QuestionBankDatabaseManager().openBank(
      'b',
      filePath: file,
      validate: false,
    );
    final now = DateTime(2026, 11, 11, 12);
    await service.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
      userAnswer: 'A',
      durationSeconds: 8,
      bankId: 'b',
      now: now,
      eventId: 'e',
    );
    final activity = (await db.query('Activities')).single;
    expect(activity['duration'], 8000);
    expect(activity['bank_id'], 'b');
    expect(activity['subject_id'], 's');
    expect(activity['chapter_id'], 'c');
    expect((await db.query('IdentityChapter')).single['correct'], 1);
    final stats = await getPeriodStats(
      startMs: now.millisecondsSinceEpoch - 1,
      endMs: now.millisecondsSinceEpoch + 1,
      bankId: 'b',
    );
    final records = await getAnsweredRecordsInRange(
      startMs: now.millisecondsSinceEpoch - 1,
      endMs: now.millisecondsSinceEpoch + 1,
      bankId: 'b',
    );
    expect(records.length, 1);
    expect(stats.answeredCount, 1);
    expect(stats.totalDuration.inMilliseconds, 8000);
    await db.insert('Activities', {
      'id': 'cut',
      'title': '熟练斩卡',
      'description': '',
      'timestamp': now.millisecondsSinceEpoch,
      'is_right': '1',
      'duration': 0,
    });
    expect(
      (await getPeriodStats(
        startMs: now.millisecondsSinceEpoch - 1,
        endMs: now.millisecondsSinceEpoch + 1,
      )).answeredCount,
      1,
    );
  });
  test('Again后Good与Cram不改变当天首次事件的新学复习归类', () async {
    final now = DateTime(2026, 11, 11, 12);
    await repo.saveItem(
      SpacedReviewItem(
        itemId: 'old',
        planId: 'p',
        state: ReviewState.review,
        reps: 3,
        lastReviewAt: now
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      ),
    );
    for (final id in ['q', 'old']) {
      await service.submitReviewResult(
        questionId: id,
        rating: ReviewRating.again,
        now: now,
        eventId: '${id}1',
      );
      await service.submitReviewResult(
        questionId: id,
        rating: ReviewRating.good,
        now: now,
        eventId: '${id}2',
      );
      await service.submitReviewResult(
        questionId: id,
        rating: ReviewRating.easy,
        now: now,
        eventId: '${id}3',
      );
    }
    final summary = await service.getTodaySummary(
      customPlan: const ReviewPlan(id: 'p', name: 'p'),
      now: now,
    );
    expect(summary.completedNewToday, 1);
    expect(summary.completedReviewToday, 1);
  });
  test('旧复习秒记录转换幂等，普通答题毫秒保持原值', () async {
    for (final entry in {'legacy': '记忆曲线复习', 'normal': 'NewAnswer'}.entries) {
      await db.insert('Activities', {
        'id': entry.key,
        'title': entry.value,
        'description': '',
        'timestamp': 1,
        'duration': 8,
        'is_right': '1',
      });
    }
    await db.transaction(ReviewEvents.migrateLegacyActivities);
    await db.transaction(ReviewEvents.migrateLegacyActivities);
    final rows = {
      for (final row in await db.query('Activities')) row['id']: row,
    };
    expect(rows['legacy']!['duration'], 8000);
    expect(rows['normal']!['duration'], 8);
    expect(
      ReviewEvents.normalizeActivity({
        'title': '闪卡复习',
        'duration': 8,
      })['duration'],
      8000,
    );
    expect(
      ReviewEvents.normalizeActivity({
        'title': 'FlashcardReview',
        'duration': 8000,
      })['duration'],
      8000,
    );
  });
  test('流水失败回滚调度答案及outbox，原请求可重试且只记一次', () async {
    await db.execute(
      "CREATE TRIGGER fail_review BEFORE INSERT ON Activities BEGIN SELECT RAISE(ABORT,'disk'); END",
    );
    await expectLater(
      service.submitReviewResult(
        questionId: 'q',
        rating: ReviewRating.good,
        userAnswer: 'A',
        eventId: 'e',
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.getItem('q'))!.reps, 0);
    expect(await db.query('Question'), isEmpty);
    expect(await db.query('CloudOutbox'), isEmpty);
    await db.execute('DROP TRIGGER fail_review');
    await Future.wait(
      List.generate(
        2,
        (_) => service.submitReviewResult(
          questionId: 'q',
          rating: ReviewRating.good,
          userAnswer: 'A',
          eventId: 'e',
        ),
      ),
    );
    expect((await repo.getItem('q'))!.reps, 1);
    expect((await db.query('Activities')).length, 1);
    await UserDBHelper().close();
    db = await UserDBHelper().database;
    await service.submitReviewResult(
      questionId: 'q',
      rating: ReviewRating.good,
      eventId: 'e',
    );
    expect((await repo.getItem('q'))!.reps, 1);
  });
  test('同毫秒不同请求串行累进而非丢失一次复习', () async {
    final now = DateTime(2026, 11, 11, 12);
    await Future.wait(
      ['e1', 'e2'].map(
        (id) => service.submitReviewResult(
          questionId: 'q',
          rating: ReviewRating.good,
          now: now,
          eventId: id,
        ),
      ),
    );
    expect((await repo.getItem('q'))!.reps, 2);
    expect((await db.query('Activities')).length, 2);
  });
  test('斩题流水失败原子回滚归档与题目状态', () async {
    await db.execute(
      "CREATE TRIGGER fail_cut BEFORE INSERT ON Activities BEGIN SELECT RAISE(ABORT,'disk'); END",
    );
    await expectLater(
      service.cutQuestion(questionId: 'q', bankId: 'b'),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.getItem('q'))!.state, ReviewState.new_);
    expect(await db.query('Question'), isEmpty);
  });
}
