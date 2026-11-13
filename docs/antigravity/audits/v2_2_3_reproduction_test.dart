// Audit witnesses for aa0a2d9. These assertions describe observed defects,
// not desired product behavior. Run explicitly; do not add to CI regression gates.
// All databases are temporary fixtures. HTTP is mocked; no live requests occur.
// This explicit test harness lives outside test/ so normal CI does not run
// assertions about old defects. Its use of test-only hooks is intentional.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/data_transfer.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/db/record_sync_service.dart';
import 'package:yibubang/models/note.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/models/spaced_review_item.dart';
import 'package:yibubang/repositories/spaced_review_repository.dart';
import 'package:yibubang/services/cloud_sync_service.dart';
import 'package:yibubang/services/daily_review_service.dart';
import 'package:yibubang/services/note_service.dart';
import 'package:yibubang/services/spaced_repetition_engine.dart';
import 'package:yibubang/services/ykb_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  late String previousPath;
  final repo = SpacedReviewRepository();
  final now = DateTime(2026, 11, 10, 12);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousPath = await getDatabasesPath();
    SharedPreferences.setMockInitialValues({
      'cloud_sync_enabled': true,
      'cloud_sync_user_id': 'fixture-user',
      'cloud_sync_device_token': 'fixture-token',
    });
    await CloudSyncService.instance.init();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yibubang_audit_');
    await databaseFactory.setDatabasesPath(directory.path);
    SharedPreferences.setMockInitialValues({'loggedin': true});
    await CloudSyncService.instance.resetSyncCursor();
    db = await UserDBHelper().database;
  });
  tearDown(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await directory.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previousPath);
  });

  Future<String> createBank(int count) async {
    final bankPath = p.join(directory.path, 'fixture.sqlite');
    final bank = await openDatabase(bankPath);
    await bank.execute(
      'CREATE TABLE Question (id TEXT PRIMARY KEY, title TEXT, chapter_id TEXT, chapter_parent_id TEXT, answer TEXT, type TEXT)',
    );
    final batch = bank.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('Question', {
        'id': 'q$i',
        'title': 'fixture',
        'chapter_id': 'c',
        'chapter_parent_id': 's',
        'answer': 'A',
        'type': '1',
      });
    }
    await batch.commit(noResult: true);
    await bank.close();
    return bankPath;
  }

  http.Response syncResponse(int timestamp) => http.Response(
    jsonEncode({
      'code': 0,
      'data': {
        'server_time': timestamp,
        'pull_questions': [],
        'pull_activities': [],
      },
    }),
    200,
  );

  test('A01: an edit during sync is skipped by the next push', () async {
    await db.insert('Question', {
      'id': 'before',
      'updated_at': 100,
      'status': 1,
    });
    var calls = 0;
    final pushed = <List<dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      pushed.add(body['push_questions'] as List<dynamic>);
      if (calls++ == 0) {
        await db.insert('Question', {
          'id': 'during',
          'updated_at': 199,
          'status': 1,
        });
      }
      return syncResponse(200);
    });
    await http.runWithClient(() async {
      expect((await CloudSyncService.instance.sync()).success, true);
      expect((await CloudSyncService.instance.sync()).success, true);
    }, () => client);
    expect(pushed.first.length, 1);
    expect(pushed.last, isEmpty);
    expect(
      (await db.query(
        'Question',
        where: 'id = ?',
        whereArgs: ['during'],
      )).length,
      1,
    );
  });

  test(
    'A03: a failed second chunk replays the acknowledged first 500 rows',
    () async {
      final batch = db.batch();
      for (var i = 0; i < 501; i++) {
        batch.insert('Question', {'id': 'q$i', 'status': 1, 'updated_at': 100});
      }
      await batch.commit(noResult: true);
      var calls = 0;
      final pushed = <List<dynamic>>[];
      final client = MockClient((request) async {
        pushed.add(
          (jsonDecode(request.body) as Map<String, dynamic>)['push_questions']
              as List<dynamic>,
        );
        if (++calls == 2) {
          return http.Response('{"message":"fixture failure"}', 500);
        }
        return syncResponse(200);
      });
      await http.runWithClient(() async {
        expect((await CloudSyncService.instance.sync()).success, false);
        expect(CloudSyncService.instance.lastSyncTime, 0);
        expect((await CloudSyncService.instance.sync()).success, true);
      }, () => client);
      expect(pushed.map((e) => e.length).toList(), [500, 1, 500, 1]);
    },
  );

  test(
    'A04: HTTP 200 with invalid JSON deletes an official answer queue item',
    () async {
      await db.insert('YkbSyncQueue', {
        'id': 'pending',
        'type': 'answer',
        'payload': '{}',
        'created_at': 100,
      });
      await http.runWithClient(
        () => YkbSyncService.instance.processQueue(),
        () => MockClient((_) async => http.Response('not-json', 200)),
      );
      expect(await db.query('YkbSyncQueue'), isEmpty);
    },
  );

  test(
    'A05: the fifth failed attempt permanently deletes a durable queue item',
    () async {
      await db.insert('YkbSyncQueue', {
        'id': 'pending',
        'type': 'answer',
        'payload': '{}',
        'created_at': 100,
        'retry_count': 4,
      });
      await http.runWithClient(
        () => YkbSyncService.instance.processQueue(),
        () => MockClient((_) async => http.Response('{"code":500}', 500)),
      );
      expect(await db.query('YkbSyncQueue'), isEmpty);
    },
  );

  test('A06: an image upload overwrites a newer local note edit', () async {
    final imageFile = File(p.join(directory.path, 'fixture.png'));
    await imageFile.writeAsBytes([1, 2, 3]);
    await db.insert('Question', {'id': 'q'});
    final note = QuestionNote(
      id: 'local_n',
      questionId: 'q',
      content: 'old',
      images: [NoteImage(bImg: '', sImg: '', localPath: imageFile.path)],
      timestamp: 100,
      updatedAt: 100,
    );
    await db.insert('Notes', note.toMap());
    await db.insert('NoteSyncQueue', {
      'id': 'upload',
      'action': 'upload',
      'note_id': note.id,
      'question_id': 'q',
      'payload': '{}',
      'created_at': 100,
    });
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/uploads')) {
        await db.update(
          'Notes',
          {'content': 'new', 'updated_at': 200},
          where: 'id = ?',
          whereArgs: [note.id],
        );
        return http.Response(
          '{"code":200,"data":{"b_img":"https://fixture/image"}}',
          200,
        );
      }
      if (request.url.path.endsWith('/getNote')) {
        return http.Response('{"code":"200","data":[{"id":"remote"}]}', 200);
      }
      return http.Response('{"code":200}', 200);
    });
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => client,
    );
    final saved = (await db.query('Notes')).single;
    expect(saved['content'], 'old');
    expect(saved['updated_at'], 100);
  });

  test(
    'A09: a failed activity insert leaves the review and answer committed',
    () async {
      await db.execute(
        "CREATE TRIGGER reject_activity BEFORE INSERT ON Activities BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      await expectLater(
        DailyReviewService().submitReviewResult(
          questionId: 'q',
          rating: ReviewRating.good,
          userAnswer: 'A',
          now: now,
          executor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.getItem('q', db))?.reps, 1);
      expect((await db.query('Question')).single['status'], 1);
      expect(await db.query('Activities'), isEmpty);
    },
  );

  test(
    'A10: an eight second review writes duration 8 instead of 8000',
    () async {
      await DailyReviewService().submitReviewResult(
        questionId: 'q',
        rating: ReviewRating.good,
        userAnswer: 'A',
        durationSeconds: 8,
        now: now,
        executor: db,
      );
      expect((await db.query('Activities')).single['duration'], 8);
    },
  );

  test(
    'A11: review submission after a cut revives the archived question',
    () async {
      final service = DailyReviewService();
      await service.cutQuestion(
        questionId: 'q',
        bankId: 'fixture',
        now: now,
        executor: db,
      );
      await service.submitReviewResult(
        questionId: 'q',
        rating: ReviewRating.again,
        now: now.add(const Duration(seconds: 1)),
        executor: db,
      );
      expect((await repo.getItem('q', db))?.state, ReviewState.learning);
      expect((await db.query('Question')).single['cut_question'], '0');
    },
  );

  test(
    'A13: exhausted fixed prefix hides fourteen remaining new questions',
    () async {
      final path = await createBank(20);
      final bank = await QuestionBankDatabaseManager().openBank(
        'fixture',
        filePath: path,
        validate: false,
      );
      final prefix = await bank.query('Question', columns: ['id'], limit: 6);
      for (final row in prefix) {
        await repo.saveItem(
          SpacedReviewItem(
            itemId: row['id'] as String,
            state: ReviewState.review,
          ),
          db,
        );
      }
      final service = DailyReviewService(bankPathResolver: (_) async => path);
      final session = await service.buildDailySession(
        customPlan: const ReviewPlan(
          id: 'p',
          name: 'fixture',
          bankId: 'fixture',
          sourceTypes: ['all'],
          dailyNewTarget: 1,
          dailyReviewLimit: 0,
        ),
        now: now,
        executor: db,
      );
      expect(session.newQueue, isEmpty);
    },
  );

  test('A13: filtered overdue prefix hides an eligible later review', () async {
    final path = await createBank(4);
    for (var i = 0; i < 4; i++) {
      await db.insert('Question', {
        'id': 'q$i',
        'chapter_parent_id': i < 3 ? 'excluded' : 'included',
      });
      await repo.saveItem(
        SpacedReviewItem(
          itemId: 'q$i',
          state: ReviewState.review,
          dueDate: now.millisecondsSinceEpoch - 1000 + i,
        ),
        db,
      );
    }
    final service = DailyReviewService(bankPathResolver: (_) async => path);
    final session = await service.buildDailySession(
      customPlan: const ReviewPlan(
        id: 'p',
        name: 'fixture',
        bankId: 'fixture',
        coveredSubjects: ['included'],
        sourceTypes: ['all'],
        dailyNewTarget: 0,
        dailyReviewLimit: 1,
      ),
      now: now,
      executor: db,
    );
    expect(session.dueQueue, isEmpty);
    expect((await repo.getItem('q3', db))?.isDue(now), true);
  });

  test(
    'A17: retained notes make clearAllRecords fail its foreign key',
    () async {
      await db.insert('Question', {'id': 'q', 'status': 1});
      await db.insert('Notes', {
        'id': 'n',
        'question_id': 'q',
        'content': 'fixture',
        'timestamp': 100,
      });
      await expectLater(clearAllRecords(), throwsA(isA<DatabaseException>()));
      expect((await db.query('Question')).single['status'], 1);
    },
  );

  test(
    'A18: SM2 has interval growth and Easy recovery even at its EF floor',
    () {
      const engine = SpacedRepetitionEngine();
      var item = const SpacedReviewItem(itemId: 'q', easeFactor: 1.3);
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
      expect(
        engine
            .evaluateRating(item: item, rating: ReviewRating.easy, now: now)
            .easeFactor,
        1.45,
      );
    },
  );

  test(
    'A12: concurrent creation of shared user placeholders fails uniqueness',
    () async {
      final outcomes = await Future.wait(
        List.generate(2, (_) async {
          try {
            await getUserQuestions(
              Future.value([Question(id: 'shared', userAnswer: '')]),
            );
            return 'ok';
          } on DatabaseException {
            return 'duplicate';
          }
        }),
      );
      expect(outcomes, contains('duplicate'));
      expect(await db.query('Question'), hasLength(1));
    },
  );

  test(
    'A12: parallel status changes count the same original status twice',
    () async {
      final path = await createBank(1);
      final bank = await openDatabase(path);
      await bank.execute(
        'CREATE TABLE IdentityQuestion (question_id TEXT, identity_id TEXT, subject_id TEXT, chapter_id TEXT)',
      );
      await bank.insert('IdentityQuestion', {
        'question_id': 'q0',
        'identity_id': 'i',
        'subject_id': 's',
        'chapter_id': 'c',
      });
      await bank.close();
      await QuestionBankDatabaseManager().openBank(
        'fixture',
        filePath: path,
        validate: false,
      );
      await db.insert('Question', {'id': 'q0'});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_answers_to_ykb', false);
      UserQuestion answer(int status) => UserQuestion(
        id: 'q0',
        chapterId: 'c',
        chapterParentId: 's',
        cutQuestion: '0',
        userAnswer: 'A',
        status: status,
        collection: 0,
      );
      await Future.wait([
        updateQuestion(
          answer(1),
          Question(id: 'q0', userAnswer: ''),
          bankId: 'fixture',
        ),
        updateQuestion(
          answer(2),
          Question(id: 'q0', userAnswer: ''),
          bankId: 'fixture',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      final counts = (await db.query('IdentitySubject')).single;
      expect(counts['correct'], 1);
      expect(counts['incorrect'], 1);
      expect(await db.query('Question'), hasLength(1));
    },
  );

  test(
    'A07: a stale collection toggle overwrites a freshly synced answer',
    () async {
      await db.insert('Question', {
        'id': 'q',
        'status': 1,
        'user_answer': 'A',
        'updated_at': 200,
      });
      final stale = UserQuestion(
        id: 'q',
        chapterId: 'c',
        chapterParentId: 's',
        cutQuestion: '0',
        userAnswer: '',
        status: 0,
        collection: 1,
      );
      await updateQuestionSimple(stale, Question(id: 'q', userAnswer: ''));
      final row = (await db.query('Question')).single;
      expect(row['status'], 0);
      expect(row['user_answer'], '');
      expect(row['collection'], 1);
    },
  );

  test(
    'A16: invalid replacement destroys the original database before validation',
    () async {
      await db.insert('Question', {'id': 'valuable', 'status': 1});
      final archive = Archive()
        ..addFile(ArchiveFile('user_data.sqlite', 3, [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      await expectLater(
        RecordSyncService.importReplace(bytes),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await File(p.join(directory.path, 'user_data.sqlite')).readAsBytes(),
        [1, 2, 3],
      );
    },
  );

  test('A20: failed legacy Notes repair leaves foreign keys disabled', () async {
    await db.execute('DROP TABLE Notes');
    await db.execute(
      'CREATE TABLE Notes (id TEXT PRIMARY KEY, question_id TEXT REFERENCES questions(id), content TEXT, imgs TEXT, timestamp INTEGER)',
    );
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('Notes', {
      'id': 'legacy',
      'question_id': 'q',
      'content': null,
      'imgs': '[]',
      'timestamp': 100,
    });
    await db.execute('PRAGMA foreign_keys = ON');
    await expectLater(
      UserDBHelper().repairDatabaseForTesting(db),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 0);
  });
}
