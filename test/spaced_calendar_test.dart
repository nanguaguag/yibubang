import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/services/spaced_repetition_engine.dart';

void main() {
  test('回拨日23:30仍计入今日，预测窗口按日历分桶不遗漏下一日', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(inMemoryDatabasePath);
    try {
      await UserDBHelper().createSpacedRepetitionTablesForTesting(db);
      await db.execute(
        'CREATE TABLE Activities(id TEXT PRIMARY KEY,title TEXT,timestamp INTEGER,duration INTEGER,is_right TEXT)',
      );
      await db.execute(
        'CREATE TABLE Question(id TEXT PRIMARY KEY,status INTEGER,collection INTEGER,cut_question TEXT)',
      );
      await db.execute(
        'CREATE TABLE Notes(id TEXT PRIMARY KEY,question_id TEXT)',
      );
      final late = DateTime(2026, 11, 1, 23, 30);
      await db.insert('ReviewEvents', {
        'id': 'e',
        'item_id': 'q',
        'plan_id': 'p',
        'kind': 'ReviewAnswer',
        'was_new': 1,
        'duration_ms': 0,
        'timestamp': late.millisecondsSinceEpoch,
      });
      final service = DailyReviewService(bankPathsResolver: (_) async => {});
      final summary = await service.getTodaySummary(
        customPlan: const ReviewPlan(id: 'p', name: 'p', dailyReviewLimit: 0),
        now: late,
        executor: db,
      );
      expect(summary.completedNewToday, 1);
      final repo = SpacedReviewRepository();
      await repo.saveItem(
        SpacedReviewItem(
          itemId: 'q',
          planId: 'p',
          state: ReviewState.review,
          dueDate: DateTime(2026, 11, 2, 0, 30).millisecondsSinceEpoch,
        ),
        db,
      );
      final forecast = await repo.getDueForecast(
        planId: 'p',
        days: 3,
        now: late,
        executor: db,
      );
      expect(forecast.keys, ['2026-11-01', '2026-11-02', '2026-11-03']);
      expect(forecast['2026-11-02'], 1);
    } finally {
      await db.close();
    }
  });
  test('春秋DST与23:59评分均落在下一日零点，非固定24小时', () {
    for (final base in [
      DateTime(2026, 3, 8, 23, 59),
      DateTime(2026, 11, 1, 23, 59),
    ]) {
      final due = DateTime.fromMillisecondsSinceEpoch(
        SpacedRepetitionEngine.calculateDueDate(base, 0),
      );
      expect(due, DateTime(base.year, base.month, base.day + 1));
      expect(due.isAfter(base), true);
      if (Platform.environment['TZ'] == 'America/Los_Angeles') {
        final sod = SpacedRepetitionEngine.startOfDay(base);
        expect(due.difference(sod).inHours, base.month == 3 ? 23 : 25);
      }
    }
  });
  test('UTC和本地输入表示同一瞬间，日历跨年及负间隔保持至少次日', () {
    final local = DateTime(2026, 12, 31, 23, 59);
    for (final days in [-5, 0, 1, 6]) {
      expect(
        SpacedRepetitionEngine.calculateDueDate(local, days),
        SpacedRepetitionEngine.calculateDueDate(local.toUtc(), days),
      );
    }
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        SpacedRepetitionEngine.calculateDueDate(local, -5),
      ),
      DateTime(2027, 1, 1),
    );
  });
  test('EF下限连续Good仍增长，Easy回升，不新增经验补偿参数', () {
    const engine = SpacedRepetitionEngine();
    var item = const SpacedReviewItem(itemId: 'hard');
    final now = DateTime(2026, 11, 1, 23, 59);
    for (var i = 0; i < 20; i++) {
      item = engine.evaluateRating(
        item: item,
        rating: ReviewRating.again,
        now: now,
      );
    }
    expect(item.easeFactor, 1.3);
    final intervals = <int>[];
    for (var i = 0; i < 6; i++) {
      item = engine.evaluateRating(
        item: item,
        rating: ReviewRating.good,
        now: now,
      );
      intervals.add(item.interval);
    }
    expect(intervals, [1, 6, 8, 10, 13, 17]);
    item = engine.evaluateRating(
      item: item,
      rating: ReviewRating.easy,
      now: now,
    );
    expect(item.easeFactor, 1.45);
    expect(item.interval, greaterThan(17));
  });
}
