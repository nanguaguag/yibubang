import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/models/bank_source.dart';
import 'package:yibubang/models/question_bank.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/screens/bank_detail_page.dart';
import 'package:yibubang/screens/bank_subscriptions_page.dart';
import 'package:yibubang/screens/question_bank_page.dart';
import 'package:yibubang/screens/choosed_subjects_page.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/bank_subscription_loader.dart';
import 'package:yibubang/services/bank_subscription_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';
import 'package:yibubang/widgets/bank_action_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previous;
  late BankSubscriptionService service;
  late QuestionBank bank;
  late Map<String, dynamic> entry;
  var requests = 0;
  const url = 'https://example.org/fixture.sqlite';
  const manifest = 'https://example.org/manifest.json';
  setUpAll(() async {
    if (const bool.fromEnvironment('BANK_UI_CAPTURE')) {
      final font = FontLoader('Preview');
      font.addFont(
        File(
          const String.fromEnvironment('BANK_PREVIEW_FONT'),
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          const String.fromEnvironment('BANK_PREVIEW_ICONS'),
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await icons.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previous = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('bank-management-flow-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'db'));
    // Initialize the shared repository in the real clock zone so its cached
    // Future is reusable across independent widget-test fake clock zones.
    await QuestionBankRepository().initialize();
    final file =
        await BankCreationService(
          request: (_, __) async => {
            'code': 200,
            'data': [
              {
                'chapter_id': 's',
                'title': '解剖学',
                'children': [
                  {'chapter_id': 'c', 'title': '第一章', 'count': 1},
                ],
              },
            ],
          },
          fetchChapter: (_, __) async => const YkbChapterFetchResult(
            code: '200',
            message: '',
            questions: [
              {'id': '1', 'title': '试题'},
            ],
          ),
        ).build(
          root: BankIdentityNode({'identity_id': '38', 'title': '西医综合'}, []),
          bankId: 'fixture',
          name: '西医综合题库',
          version: '1.0.0',
          directory: directory,
        );
    final bytes = await file.readAsBytes();
    entry = {
      'bank_id': 'fixture',
      'identity_id': '38',
      'name': '西医综合题库',
      'version': '2.0.0',
      'schema_version': 1,
      'url': url,
      'sha256': sha256.convert(bytes).toString(),
    };
    requests = 0;
    service = BankSubscriptionService(
      loader: BankSubscriptionLoader(
        client: MockClient((r) async {
          requests++;
          if (r.url.path.endsWith('.json')) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'banks': [entry],
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response.bytes(
            bytes,
            200,
            headers: {'etag': 'v1', 'content-type': 'application/octet-stream'},
          );
        }),
      ),
    );
    bank = await service.importLink(url, subscribe: true);
    await service.addSource(manifest);
    await service.check(sourceId: BankSource.fresh(manifest).id);
    await service.selectSource(bank, BankSource.fresh(manifest).id);
  });
  tearDown(() async {
    service.stop();
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previous);
    await directory.delete(recursive: true);
  });

  Future<void> ready(WidgetTester tester, Finder finder) async {
    for (
      var i = 0;
      i < 80 &&
          (finder.evaluate().isEmpty ||
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    // Cached content remains visible during reloads. Wait for those SQLite
    // futures as well, so a live page cannot reopen the DB during tearDown.
    final loads = tester
        .widgetList<FutureBuilder<dynamic>>(
          find.byWidgetPredicate((widget) => widget is FutureBuilder),
        )
        .map((widget) => widget.future)
        .whereType<Future<dynamic>>()
        .toList();
    var loaded = loads.isEmpty;
    if (!loaded) {
      await tester.runAsync(() async {
        Future.wait(loads).then<void>(
          (_) {
            loaded = true;
          },
          onError: (Object _, StackTrace _) {
            loaded = true;
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      for (var i = 0; i < 120 && !loaded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(loaded, isTrue);
    }
    expect(
      finder,
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' / '),
    );
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('BANK_UI_CAPTURE')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(Directory.systemTemp.path, '$name.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'one update action, explicit source switching and local integrity at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: const bool.fromEnvironment('BANK_UI_CAPTURE')
                  ? 'Preview'
                  : null,
            ),
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: QuestionBankPage(subscriptionService: service),
            ),
          ),
        );
        await ready(tester, find.text('西医综合题库'));
        final card = find.ancestor(
          of: find.text('西医综合题库'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: card, matching: find.byTooltip('下载并更新')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.byTooltip('检查更新')),
          findsNothing,
        );
        await capture(tester, 'bank-management-${width.toInt()}');
        final activeBefore = await tester.runAsync(
          () => QuestionBankRepository().activeBankId(),
        );
        await tester.tap(find.text('西医综合题库'));
        await ready(tester, find.byKey(const ValueKey('bank-detail-totals')));
        final totals = find.descendant(
          of: find.byKey(const ValueKey('bank-detail-totals')),
          matching: find.byType(Text),
        );
        expect(
          tester.widgetList<Text>(totals).map((text) => text.data).toList(),
          ['1', '课程总数', '1', '章节总数', '1', '题目总数'],
        );
        expect(
          await tester.runAsync(() => QuestionBankRepository().activeBankId()),
          activeBefore,
        );
        await tester.drag(
          find.descendant(
            of: find.byType(BankDetailPage),
            matching: find.byType(ListView),
          ),
          const Offset(0, -260),
        );
        await ready(tester, find.text('最近检查'));
        expect(
          find.descendant(
            of: find.byType(BankDetailPage),
            matching: find.textContaining('有更新'),
          ),
          findsOneWidget,
        );
        final before = requests;
        await tester.tap(find.byTooltip('更多题库操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查本地完整性'));
        await ready(tester, find.text('题库完整性检查通过'));
        expect(requests, before);
        await tester.tap(find.text('完成'));
        await tester.pump();
        await ready(tester, find.text('最近检查'));
        expect(
          (await tester.runAsync(
            () => QuestionBankRepository().history('fixture'),
          ))!.length,
          1,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'saving a new bank link keeps primary until checked and explicitly selected at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: const bool.fromEnvironment('BANK_UI_CAPTURE')
                  ? 'Preview'
                  : null,
            ),
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: BankDetailPage(bank: bank, subscriptionService: service),
            ),
          ),
        );
        await ready(tester, find.text('最近检查'));
        await capture(tester, 'bank-detail-${width.toInt()}');
        await tester.ensureVisible(find.byTooltip('修改订阅链接'));
        await tester.tap(find.byTooltip('修改订阅链接'));
        await tester.pumpAndSettle();
        const proposed = 'https://example.org/replacement.json';
        await tester.enterText(find.byType(TextFormField), proposed);
        final before = requests;
        await tester.tap(find.text('确定'));
        await tester.pump();
        await ready(tester, find.text('新来源 · 待检查'));
        expect(requests, before);
        expect(
          (await service.store.read()).sourceFor('fixture')!.url,
          manifest,
        );
        await tester.ensureVisible(find.byTooltip('检查新来源'));
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('检查新来源'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await ready(tester, find.text('使用新来源'));
        expect(
          (await service.store.read()).sourceFor('fixture')!.url,
          manifest,
        );
        await tester.ensureVisible(find.text('使用新来源'));
        await tester.runAsync(() async {
          await tester.tap(find.text('使用新来源'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await ready(tester, find.text('最近检查'));
        expect(
          (await service.store.read()).sourceFor('fixture')!.url,
          proposed,
        );
        expect(
          (await tester.runAsync(
            () => QuestionBankRepository().history('fixture'),
          ))!.length,
          1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an open management page refreshes when an independent background source check finishes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: QuestionBankPage(subscriptionService: service)),
      );
      await ready(tester, find.text('西医综合题库'));
      expect(find.text('有更新'), findsOneWidget);
      entry['version'] = '1.0.0';
      entry['sha256'] = 'b' * 64;
      await tester.runAsync(() => service.check(bankId: 'fixture'));
      await ready(tester, find.text('来源内容变更'));
      // Same package + version as the applied release is recognized as current.
      entry['sqlite_sha256'] = bank.contentHash;
      await tester.runAsync(() => service.check(bankId: 'fixture'));
      await ready(tester, find.text('已是最新'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in [
    'all',
    'source',
    'official',
    'bank',
    'detail',
    'pending',
  ]) {
    testWidgets(
      'the $action operation replaces only its initiating icon with a circular indicator',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        const incomingUrl = 'https://example.org/new.sqlite';
        final source = (await tester.runAsync(
          () => service.store.read(),
        ))!.sourceFor('fixture')!;
        await tester.runAsync(
          () => service.store.change((catalog) {
            catalog.sources[source.id] = BankSource.fromJson({
              ...source.toJson(),
              'entries': [
                {...entry, 'url': incomingUrl},
              ],
            });
          }),
        );
        final pendingSource = BankSource.fresh(
          'https://example.org/pending.json',
        );
        if (action == 'pending') {
          await tester.runAsync(
            () => service.store.change((catalog) {
              catalog.sources[pendingSource.id] = pendingSource;
              catalog.pending['fixture'] = pendingSource.id;
            }),
          );
        }
        final bytes = (await tester.runAsync(
          () => File(bank.localPath).readAsBytes(),
        ))!;
        final delayed = BankSubscriptionService(
          loader: BankSubscriptionLoader(
            client: MockClient((request) async {
              await gate.future;
              if (request.url.path.endsWith('.json')) {
                return http.Response(
                  jsonEncode({
                    'banks': [
                      {...entry, 'url': incomingUrl},
                    ],
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }
              return http.Response.bytes(
                bytes,
                200,
                headers: {'content-type': 'application/octet-stream'},
              );
            }),
          ),
        );
        if (action == 'detail') {
          await tester.runAsync(() async {
            await (await UserDBHelper().database).delete(
              'BankContentState',
              where: 'bank_id = ?',
              whereArgs: ['fixture'],
            );
          });
        }
        await tester.pumpWidget(
          MaterialApp(
            home: ['source', 'official'].contains(action)
                ? BankSubscriptionsPage(subscriptionService: delayed)
                : ['detail', 'pending'].contains(action)
                ? BankDetailPage(bank: bank, subscriptionService: delayed)
                : QuestionBankPage(subscriptionService: delayed),
          ),
        );
        final key = action == 'all'
            ? const ValueKey('bank-check-all')
            : ['source', 'official'].contains(action)
            ? ValueKey(
                'source-check-${action == 'official' ? BankSourceCatalog.officialId : source.id}',
              )
            : action == 'detail'
            ? const ValueKey('bank-detail-update')
            : action == 'pending'
            ? const ValueKey('bank-pending-check')
            : const ValueKey('bank-update-fixture');
        // Details may build the action lazily below the statistics header.
        if (action == 'detail') {
          await ready(tester, find.text('订阅更新'));
          await tester.drag(find.byType(ListView), const Offset(0, -200));
        }
        if (action == 'pending') {
          await ready(tester, find.text('新来源 · 待检查'));
          await tester.ensureVisible(find.byKey(key));
        }
        await ready(tester, find.byKey(key));
        if (action == 'detail') {
          expect(find.textContaining('待比较'), findsOneWidget);
        }
        await tester.ensureVisible(find.byKey(key));
        // Run the operation on the real clock: its serialized persistence
        // futures are shared across widget tests, which use separate fake clocks.
        await tester.runAsync(() => tester.tap(find.byKey(key)));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
        final ring = find.descendant(
          of: find.byKey(key),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(ring, findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BankActionProgress),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        gate.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await ready(tester, find.byKey(key));
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'source expansion keeps selectable URL scroll state separate from expansion state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BankSubscriptionsPage(subscriptionService: service)),
      );
      await ready(tester, find.byType(ExpansionTile));
      final tile = find.byKey(PageStorageKey(BankSourceCatalog.officialId));
      await tester.tap(find.descendant(of: tile, matching: find.text('内置题库')));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.descendant(of: tile, matching: find.text('内置题库')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: tile, matching: find.text('内置题库')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing the courses page while bank management is open does not refresh a dead state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('首页')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const ChoosedSubjectsPage()),
      );
      await ready(tester, find.byTooltip('题库管理'));
      final previous = tester.state(find.byType(ChoosedSubjectsPage));
      final route = ModalRoute.of(
        tester.element(find.byType(ChoosedSubjectsPage)),
      )!;
      await tester.tap(find.byTooltip('题库管理'));
      await ready(tester, find.byType(QuestionBankPage));
      navigator.currentState!.removeRoute(route);
      await tester.pump(const Duration(seconds: 1));
      expect(previous.mounted, isFalse);
      navigator.currentState!.pop();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed checks show source and HTTP error without changing installed content',
    (tester) async {
      final failing = BankSubscriptionService(
        loader: BankSubscriptionLoader(
          client: MockClient((_) async => http.Response('', 503)),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: QuestionBankPage(subscriptionService: failing)),
      );
      await ready(tester, find.text('西医综合题库'));
      final before = (await service.store.read()).sourceFor('fixture')!.entries;
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('检查全部更新'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('检查更新失败'), findsOneWidget);
      expect(find.textContaining('HTTP 503'), findsWidgets);
      expect(
        (await service.store.read()).sourceFor('fixture')!.entries,
        before,
      );
      expect(
        (await tester.runAsync(
          () => QuestionBankRepository().history('fixture'),
        ))!.length,
        1,
      );
      await tester.tap(find.text('关闭'));
      await tester.pump();
      await ready(tester, find.text('检查失败'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adding duplicate sources persists without downloads and source page includes official source',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BankSubscriptionsPage(subscriptionService: service)),
      );
      await ready(tester, find.text('内置题库'));
      expect(find.text('内置题库'), findsOneWidget);
      final before = requests;
      await tester.ensureVisible(find.text('添加订阅'));
      await tester.tap(find.text('添加订阅'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), manifest);
      await tester.runAsync(() async {
        await tester.tap(find.text('确定'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await ready(tester, find.text('该订阅已存在'));
      expect(find.text('该订阅已存在'), findsOneWidget);
      expect(requests, before);
      expect(
        (await service.sources()).where((s) => s.url == manifest).length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
