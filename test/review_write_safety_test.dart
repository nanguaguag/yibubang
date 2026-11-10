import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/services/daily_review_service.dart';

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
    dir = await Directory.systemTemp.createTemp('review_write_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await UserDBHelper().database;
    await repo.saveItem(const SpacedReviewItem(itemId: 'q', planId: 'p'));
  });
  tearDown(() async {
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(originalPath);
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
