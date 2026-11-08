import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/services/spaced_repetition_engine.dart';

void main() {
  group('SpacedRepetitionEngine SM-2 Algorithm Tests', () {
    const engine = SpacedRepetitionEngine(
      startingEaseFactor: 2.5,
      minEaseFactor: 1.3,
      easyBonus: 1.3,
      hardIntervalMultiplier: 1.2,
      quickAnswerDurationThreshold: 5,
      masteryRepThreshold: 5,
    );

    final fixedNow = DateTime(2026, 11, 8, 10, 0, 0);

    test('new item evaluated with Good progresses to reps=1, interval=1', () {
      final item = SpacedReviewItem(itemId: 'q1001');
      final updated = engine.evaluateRating(
        item: item,
        rating: ReviewRating.good,
        now: fixedNow,
      );

      expect(updated.state, ReviewState.review);
      expect(updated.reps, 1);
      expect(updated.lapses, 0);
      expect(updated.interval, 1);
      expect(updated.easeFactor, 2.5);
      expect(updated.lastRating, ReviewRating.good);
      expect(
        updated.dueDate,
        DateTime(2026, 11, 9).millisecondsSinceEpoch,
      );
    });

    test('item evaluated with Hard on first rep gets interval=1 with reduced EF', () {
      final item = SpacedReviewItem(itemId: 'q1002');
      final updated = engine.evaluateRating(
        item: item,
        rating: ReviewRating.hard,
        now: fixedNow,
      );

      expect(updated.reps, 1);
      expect(updated.interval, 1);
      expect(updated.easeFactor, 2.35); // 2.5 - 0.15
      expect(updated.lastRating, ReviewRating.hard);
    });

    test('item evaluated with Easy on first rep jumps to interval=4 with increased EF', () {
      final item = SpacedReviewItem(itemId: 'q1003');
      final updated = engine.evaluateRating(
        item: item,
        rating: ReviewRating.easy,
        now: fixedNow,
      );

      expect(updated.reps, 1);
      expect(updated.interval, 4);
      expect(updated.easeFactor, 2.65); // 2.5 + 0.15
      expect(updated.lastRating, ReviewRating.easy);
      expect(
        updated.dueDate,
        DateTime(2026, 11, 12).millisecondsSinceEpoch,
      );
    });

    test('consecutive Good reviews follow SM-2 intervals (1 -> 6 -> interval * EF)', () {
      var item = SpacedReviewItem(itemId: 'q1004');

      // Rep 1
      item = engine.evaluateRating(item: item, rating: ReviewRating.good, now: fixedNow);
      expect(item.reps, 1);
      expect(item.interval, 1);

      // Rep 2
      item = engine.evaluateRating(item: item, rating: ReviewRating.good, now: fixedNow);
      expect(item.reps, 2);
      expect(item.interval, 6);

      // Rep 3: 6 * 2.5 = 15
      item = engine.evaluateRating(item: item, rating: ReviewRating.good, now: fixedNow);
      expect(item.reps, 3);
      expect(item.interval, 15);

      // Rep 4: 15 * 2.5 = 37.5 -> 38
      item = engine.evaluateRating(item: item, rating: ReviewRating.good, now: fixedNow);
      expect(item.reps, 4);
      expect(item.interval, 38);
    });

    test('Again resets reps to 0, increments lapses and sets interval=1', () {
      var item = const SpacedReviewItem(
        itemId: 'q1005',
        reps: 3,
        interval: 15,
        lapses: 0,
        easeFactor: 2.5,
        state: ReviewState.review,
      );

      item = engine.evaluateRating(item: item, rating: ReviewRating.again, now: fixedNow);

      expect(item.reps, 0);
      expect(item.lapses, 1);
      expect(item.interval, 1);
      expect(item.state, ReviewState.learning);
      expect(item.easeFactor, 2.30); // 2.5 - 0.20
      expect(
        item.dueDate,
        DateTime(2026, 11, 9).millisecondsSinceEpoch,
      );
    });

    test('easeFactor respects minEaseFactor floor (1.30)', () {
      var item = const SpacedReviewItem(
        itemId: 'q1006',
        easeFactor: 1.35,
      );

      item = engine.evaluateRating(item: item, rating: ReviewRating.again, now: fixedNow);
      expect(item.easeFactor, 1.30); // clamped to minEaseFactor
    });

    test('graduates to Mastered when reps >= threshold and interval >= 30', () {
      var item = const SpacedReviewItem(
        itemId: 'q1007',
        reps: 4,
        interval: 20,
        easeFactor: 2.5,
      );

      item = engine.evaluateRating(item: item, rating: ReviewRating.good, now: fixedNow);
      // reps becomes 5, interval becomes 20 * 2.5 = 50 >= 30 -> mastered
      expect(item.reps, 5);
      expect(item.interval, 50);
      expect(item.state, ReviewState.mastered);
    });

    test('evaluateObjectiveAnswer maps correctly to again, good, and easy', () {
      final item = SpacedReviewItem(itemId: 'q1008');

      // Incorrect -> Again
      final wrong = engine.evaluateObjectiveAnswer(
        item: item,
        isCorrect: false,
        durationSeconds: 10,
        now: fixedNow,
      );
      expect(wrong.lastRating, ReviewRating.again);
      expect(wrong.interval, 1);

      // Correct normal duration -> Good
      final normalRight = engine.evaluateObjectiveAnswer(
        item: item,
        isCorrect: true,
        durationSeconds: 12,
        now: fixedNow,
      );
      expect(normalRight.lastRating, ReviewRating.good);
      expect(normalRight.interval, 1);

      // Correct quick answer <= 5s -> Easy
      final quickRight = engine.evaluateObjectiveAnswer(
        item: item,
        isCorrect: true,
        durationSeconds: 3,
        now: fixedNow,
      );
      expect(quickRight.lastRating, ReviewRating.easy);
      expect(quickRight.interval, 4);
    });

    test('supports different ReviewItemTypes seamlessly', () {
      final question = SpacedReviewItem(
        itemId: '101',
        itemType: ReviewItemType.question,
      );
      final fillBlank = SpacedReviewItem(
        itemId: '202',
        itemType: ReviewItemType.fillBlank,
      );
      final subjective = SpacedReviewItem(
        itemId: '303',
        itemType: ReviewItemType.subjective,
      );
      final note = SpacedReviewItem(
        itemId: 'note_001',
        itemType: ReviewItemType.note,
      );
      final flashcard = SpacedReviewItem(
        itemId: 'card_001',
        itemType: ReviewItemType.flashcard,
        extra: {'front': 'Q?', 'back': 'A!'},
      );

      for (final it in [question, fillBlank, subjective, note, flashcard]) {
        final result = engine.evaluateRating(
          item: it,
          rating: ReviewRating.good,
          now: fixedNow,
        );
        expect(result.itemType, it.itemType);
        expect(result.interval, 1);
        expect(result.reps, 1);
        if (it.extra != null) {
          expect(result.extra?['front'], 'Q?');
        }
      }
    });

    test('previewNextIntervals gives accurate projections for all 4 ratings', () {
      final item = const SpacedReviewItem(
        itemId: 'preview',
        reps: 2,
        interval: 6,
        easeFactor: 2.5,
      );

      final preview = engine.previewNextIntervals(item);
      expect(preview[ReviewRating.again], 1);
      expect(preview[ReviewRating.hard], (6 * 1.2).round()); // 7
      expect(preview[ReviewRating.good], (6 * 2.5).round()); // 15
      expect(preview[ReviewRating.easy], (6 * 2.5 * 1.3).round()); // 20
    });
  });
}
