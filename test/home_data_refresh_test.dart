import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/user_database_coordinator.dart';
import 'package:yibubang/models/answer_statistics.dart';
import 'package:yibubang/screens/choosed_subjects_page.dart';
import 'package:yibubang/screens/statistics_page.dart';
import 'package:yibubang/services/cloud_sync_service.dart';
import 'support/startup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cloud = CloudSyncService.instance;
  late StartupFixture fixture;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async => fixture = await StartupFixture.create());
  tearDown(() => fixture.close());

  Future<List<SubjectWithChapters>>? courseFuture(WidgetTester tester) => tester
      .widget<FutureBuilder<List<SubjectWithChapters>>>(
        find.byWidgetPredicate(
          (w) => w is FutureBuilder<List<SubjectWithChapters>>,
        ),
      )
      .future;
  Future<void> showCourses(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChoosedSubjectsPage()));
    await pumpReady(tester, find.text('启动课程'));
  }

  http.Response page(
    http.Request req, {
    List<Map<String, Object?>> questions = const [],
    List<Map<String, Object?>> activities = const [],
    List<String> deleted = const [],
    int cursor = 1,
    int high = 1,
    bool more = false,
  }) {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    return http.Response(
      jsonEncode({
        'data': {
          'protocol': 2,
          'server_time': 100,
          'accepted_seqs': (body['mutations'] as List)
              .map((e) => e['seq'])
              .toList(),
          'next_cursor': cursor,
          'high_watermark': high,
          'has_more': more,
          'pull_questions': questions,
          'pull_activities': activities,
          'pull_deleted_activities': deleted,
        },
      }),
      200,
    );
  }

  testWidgets('初始化、状态、失败和空同步都不重读已显示课程', (tester) async {
    await showCourses(tester);
    final original = courseFuture(tester);
    final before = cloud.dataRevision.value;
    await tester.runAsync(() => cloud.init());
    await tester.pump();
    expect(courseFuture(tester), same(original));
    var statusNotifications = 0;
    void listen() => statusNotifications++;
    cloud.addListener(listen);
    try {
      await tester.runAsync(
        () => http.runWithClient(
          () async {
            final bad = await cloud.sync();
            expect(bad.success, false);
          },
          () => MockClient(
            (_) async => http.Response('{"data":{"server_time":1}}', 200),
          ),
        ),
      );
      expect(
        await tester.runAsync(() => fixture.userDb.query('CloudOutbox')),
        isNotEmpty,
      );
      await tester.runAsync(
        () => http.runWithClient(() async {
          expect((await cloud.sync()).success, true);
        }, () => MockClient((req) async => page(req))),
      );
      await tester.pump();
      expect(cloud.dataRevision.value, before);
      expect(statusNotifications, 4);
      expect(courseFuture(tester), same(original));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('启动课程'), findsOneWidget);
    } finally {
      cloud.removeListener(listen);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('下载落库后刷新一次，等待查询时保留课程，完成后显示新计数', (tester) async {
    await tester.runAsync(() => cloud.init());
    await showCourses(tester);
    final original = courseFuture(tester);
    final before = cloud.dataRevision.value;
    final entered = Zone.root.run(() => Completer<void>());
    final release = Zone.root.run(() => Completer<void>());
    late Future<void> blocked;
    void blockAfterCommit() {
      blocked = Zone.root.run(
        () => UserDatabaseCoordinator.instance.run(() async {
          entered.complete();
          await release.future;
        }),
      );
    }

    cloud.dataRevision.addListener(blockAfterCommit);
    try {
      await tester.runAsync(
        () => http.runWithClient(
          () async {
            expect((await cloud.sync()).success, true);
            await entered.future;
          },
          () => MockClient(
            (req) async => page(
              req,
              questions: const [
                {'id': 'q', 'status': 2, 'user_answer': 'B', 'updated_at': 1},
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(cloud.dataRevision.value, before + 1);
      expect(courseFuture(tester), isNot(same(original)));
      expect(find.text('启动课程'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      cloud.dataRevision.removeListener(blockAfterCommit);
      await tester.runAsync(() async {
        release.complete();
        await blocked;
      });
    }
    await pumpUntil(tester, () {
      final widget = tester.widget<FutureBuilder<List<SubjectWithChapters>>>(
        find.byWidgetPredicate(
          (w) => w is FutureBuilder<List<SubjectWithChapters>>,
        ),
      );
      return widget.future != null && find.text('启动课程').evaluate().isNotEmpty;
    });
    final data = await tester.runAsync(() => courseFuture(tester)!);
    expect(data!.single.subject.correct, 0);
    expect(data.single.subject.incorrect, 1);
    expect(
      (await tester.runAsync(
        () => fixture.userDb.query('Question'),
      ))!.single['user_answer'],
      'B',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('后续页失败仍通知已提交页，坏页无部分数据落库', (tester) async {
    await tester.runAsync(() => cloud.init());
    await showCourses(tester);
    final before = cloud.dataRevision.value;
    var requests = 0;
    await tester.runAsync(
      () => http.runWithClient(
        () async {
          final result = await cloud.sync();
          expect(result.success, false);
        },
        () => MockClient((req) async {
          if (++requests == 2) return http.Response('failure', 500);
          return page(
            req,
            cursor: 1,
            high: 2,
            more: true,
            questions: const [
              {'id': 'q', 'status': 2, 'user_answer': 'B', 'updated_at': 1},
            ],
          );
        }),
      ),
    );
    expect(cloud.dataRevision.value, before + 1);
    expect(
      (await tester.runAsync(
        () => fixture.userDb.query('Question'),
      ))!.single['status'],
      2,
    );
    final after = cloud.dataRevision.value;
    await tester.runAsync(
      () => http.runWithClient(
        () async {
          expect((await cloud.sync()).success, false);
        },
        () => MockClient(
          (req) async => page(
            req,
            cursor: 2,
            high: 2,
            questions: const [
              {'id': 'q', 'status': 1},
              {'status': 2},
            ],
          ),
        ),
      ),
    );
    expect(cloud.dataRevision.value, after);
    expect(
      (await tester.runAsync(
        () => fixture.userDb.query('Question'),
      ))!.single['status'],
      2,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('统计页不随状态重载，下载流水及删除墓碑仍刷新，答题通知保留', (tester) async {
    await tester.runAsync(() => cloud.init());
    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    final futureFinder = find.byWidgetPredicate((w) => w is FutureBuilder);
    Future<dynamic>? current() =>
        tester.widget<FutureBuilder>(futureFinder.first).future;
    final original = current();
    await tester.runAsync(
      () => http.runWithClient(() async {
        expect((await cloud.sync()).success, true);
      }, () => MockClient((req) async => page(req))),
    );
    await tester.pump();
    expect(current(), same(original));
    final before = cloud.dataRevision.value;
    await tester.runAsync(
      () => http.runWithClient(
        () async {
          expect((await cloud.sync()).success, true);
        },
        () => MockClient(
          (req) async => page(
            req,
            cursor: 2,
            high: 2,
            activities: [
              {
                'id': 'a',
                'title': 'NewAnswer',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'question_id': 'q',
                'is_right': '1',
                'duration': 1000,
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(cloud.dataRevision.value, before + 1);
    expect(current(), isNot(same(original)));
    final afterInsert = current();
    await tester.runAsync(
      () => http.runWithClient(
        () async {
          expect((await cloud.sync()).success, true);
        },
        () => MockClient(
          (req) async => page(req, cursor: 3, high: 3, deleted: ['a']),
        ),
      ),
    );
    await tester.pump();
    expect(cloud.dataRevision.value, before + 2);
    expect(current(), isNot(same(afterInsert)));
    expect(
      await tester.runAsync(() => fixture.userDb.query('Activities')),
      isEmpty,
    );
    final beforeAnswer = current();
    notifyAnswersChanged();
    await tester.pump();
    expect(current(), isNot(same(beforeAnswer)));
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('同步完成前退出页面，不向失活页面通知', (tester) async {
    await tester.runAsync(() => cloud.init());
    await showCourses(tester);
    final original = cloud.dataRevision.value;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => http.runWithClient(
        () async {
          expect((await cloud.sync()).success, true);
        },
        () => MockClient(
          (req) async => page(
            req,
            questions: const [
              {'id': 'q', 'status': 2},
            ],
          ),
        ),
      ),
    );
    expect(cloud.dataRevision.value, original + 1);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
