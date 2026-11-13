import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/models/ai_search_options.dart';
import 'package:yibubang/services/ai_search_client.dart';
import 'package:yibubang/services/ai_search_controller.dart';
import 'package:yibubang/widgets/ai_search_settings.dart';
import 'package:yibubang/widgets/common/info_card.dart';
import 'package:yibubang/widgets/common/styled_tile.dart';

class FragmentsGateway implements AiSearchGateway {
  @override
  Future<AiQuota> quota() async =>
      const AiQuota(remaining: 197, day: '2026-11-13');
  @override
  Stream<AiStreamEvent> search(String q, List<AiTurn> h, String id) async* {
    yield const AiStreamEvent('delta', {'text': '中文🙂'});
    yield const AiStreamEvent('delta', {'text': '回答。'});
    yield const AiStreamEvent('answer', {'text': '中文🙂回答。[1]'});
    yield const AiStreamEvent('done', {});
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class OfflineModels implements AiModelGateway {
  @override
  String selectedModel = 'stable';
  @override
  Future<AiModelCatalog> models({bool refresh = false}) async =>
      throw const AiSearchException('离线');
  @override
  Future<void> selectModel(String id) async {
    await (await SharedPreferences.getInstance()).setString(
      'ai_answer_model',
      id,
    );
    selectedModel = id;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'result count changes preserve source ratio and legacy settings',
    () async {
      SharedPreferences.setMockInitialValues({
        AiSearchOptions.textbookCountKey: 6,
      });
      final prefs = await SharedPreferences.getInstance();
      final legacy = AiSearchOptions.fromPreferences(prefs);
      expect(legacy.resultCount, 12);
      expect(legacy.ratioLabel, '6 : 6');
      final expanded = const AiSearchOptions().copyWith(resultCount: 25);
      expect(expanded.ratioLabel, '17 : 8');
      expect(expanded.quotaCost, 3);
      expect(
        const AiSearchOptions(
          textbookCount: 0,
        ).copyWith(resultCount: 25).textbookCount,
        0,
      );
      expect(
        const AiSearchOptions(
          textbookCount: 12,
        ).copyWith(resultCount: 25).textbookCount,
        25,
      );
      await expanded.save(prefs);
      expect(AiSearchOptions.fromPreferences(prefs).resultCount, 25);
      expect(AiSearchOptions.fromPreferences(prefs).ratioLabel, '17 : 8');
    },
  );
  setUpAll(() async {
    if (Platform.environment['AI_FEEDBACK_SCREENSHOTS'] != '1') return;
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fontFile = File(
      p.join(
        Platform.pathSeparator,
        'System',
        'Library',
        'Fonts',
        'PingFang.ttc',
      ),
    );
    if (await fontFile.exists()) {
      final font = FontLoader('FeedbackFont')
        ..addFont(
          Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
        );
      await font.load();
    }
  });
  setUp(() {
    rootBundle
        .clear(); // Do not share asset Futures across fake/real async zones.
    SharedPreferences.setMockInitialValues({});
  });
  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'AI rows match neighbouring settings and ratio persists at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final shot = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'FeedbackFont',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff4285f4),
                brightness: width == 1000 ? Brightness.dark : Brightness.light,
              ),
            ),
            builder: (context, child) =>
                RepaintBoundary(key: shot, child: child!),
            home: Scaffold(
              appBar: AppBar(title: const Text('设置')),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('通用'),
                        ),
                        InfoCard(
                          children: [
                            IconTile(
                              icon: Icons.system_update_alt,
                              label: '接受应用更新',
                              trailing: Switch(value: true, onChanged: (_) {}),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('AI 搜索'),
                        ),
                        AiSearchSettingsGroup(gateway: OfflineModels()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AiSearchSettingsGroup),
            matching: find.byType(IconTile),
          ),
          findsNWidgets(6),
        );
        expect(find.textContaining('1+1+1=3'), findsNothing);
        Future<void> capture(String name) async {
          if (Platform.environment['AI_FEEDBACK_SCREENSHOTS'] != '1') return;
          final boundary =
              shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory(
              p.join('ai_backend', '.local', 'screenshots'),
            );
            await dir.create(recursive: true);
            await File(
              p.join(dir.path, 'feedback-$name-${width.toInt()}.png'),
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('settings');
        await tester.tap(find.text('回答模型'));
        await tester.pumpAndSettle();
        expect(find.text('使用本机备用目录'), findsOneWidget);
        expect(find.byType(RadioListTile<String>), findsNWidgets(4));
        await capture('models-offline');
        final model = find.byType(RadioListTile<String>).last;
        await tester.ensureVisible(model);
        await tester.tap(model);
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getString('ai_answer_model'),
          isNot('stable'),
        );
        await tester.tap(find.text('教材与题目比例'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Slider));
        await tester.pumpAndSettle();
        expect(find.text('教材 6 条 · 题目 6 条'), findsOneWidget);
        await capture('ratio');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('6 : 6'), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getInt(
            AiSearchOptions.textbookCountKey,
          ),
          6,
        );
        await tester.tap(find.text('问题改写'));
        await tester.pumpAndSettle();
        expect(find.text('6 : 6'), findsOneWidget);
        await tester.tap(find.text('检索条目数'));
        await tester.pumpAndSettle();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(25);
        await tester.pumpAndSettle();
        expect(find.text('最多 25 条'), findsOneWidget);
        await capture('result-count');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('12 条'), findsOneWidget);
        await tester.tap(find.text('检索条目数'));
        await tester.pumpAndSettle();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(25);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('25 条'), findsOneWidget);
        expect(find.text('13 : 12'), findsOneWidget);
        await tester.tap(find.text('教材与题目比例'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(find.byType(Slider)).max, 25);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('使用说明'));
        await tester.pumpAndSettle();
        await capture('help');
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AiSearchSettingsGroup())),
        );
        await tester.pumpAndSettle();
        expect(find.text('13 : 12'), findsOneWidget);
        expect(find.text('25 条'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'settings default on, link switches and persist after reopening',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AiSearchSettingsGroup())),
      );
      await tester.pumpAndSettle();
      List<bool> values() => tester
          .widgetList<Switch>(find.byType(Switch))
          .map((s) => s.value)
          .toList();
      expect(values(), [true, true]);
      expect(find.textContaining('1+1+1=3'), findsNothing);
      await tester.tap(find.text('使用说明'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('1+1+1=3'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(values(), [false, false]);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(values(), [true, true]);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(values(), [true, false]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AiSearchOptions.rephraseKey), true);
      expect(prefs.getBool(AiSearchOptions.streamingKey), false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AiSearchSettingsGroup())),
      );
      await tester.pumpAndSettle();
      expect(values(), [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached and bundled models remain selectable with a failed backend',
    (tester) async {
      await tester.runAsync(() async {
        const base = 'https://offline.test';
        SharedPreferences.setMockInitialValues({
          'ai_installation_id': 'a' * 32,
          'ai_installation_secret': 'b' * 64,
          'ai_device_registered': base,
          'ai_answer_model_catalog': 'corrupt JSON',
        });
        final client = AiSearchClient(
          baseUrl: base,
          clientFactory: () =>
              MockClient((r) async => throw http.ClientException('offline')),
        );
        final result = await client.models();
        expect(result.stale, true);
        expect(result.catalogType, 'bundled_snapshot');
        expect(result.models.length, 4);
        await client.selectModel(result.models.last.id);
        expect(
          (await SharedPreferences.getInstance()).getString('ai_answer_model'),
          result.models.last.id,
        );
        await (await SharedPreferences.getInstance()).setString(
          'ai_answer_model_catalog',
          jsonEncode({
            'models': [
              {
                'id': 'stable',
                'label': '最近验证的稳定版',
                'resolved_model': 'gemini-3.5-flash/answer_gen/v1',
                'context_window': '128K',
              },
            ],
            'source_url': result.sourceUrl,
            'fetched_at': 1794549434,
          }),
        );
        final cached = await client.models();
        expect(cached.catalogType, 'local_cache');
        expect(cached.models.single.label, '最近验证的稳定版');
        client.dispose();
      });
    },
  );

  test(
    'existing client reads the latest flags and model for every new request',
    () async {
      const base = 'https://options.test';
      SharedPreferences.setMockInitialValues({
        'ai_installation_id': 'a' * 32,
        'ai_installation_secret': 'b' * 64,
        'ai_device_registered': base,
      });
      final bodies = <Map<String, dynamic>>[];
      final client = AiSearchClient(
        baseUrl: base,
        clientFactory: () => MockClient((r) async {
          bodies.add(jsonDecode(r.body));
          return http.Response('event: done\ndata: {}\n\n', 200);
        }),
      );
      await client.search('q', [], 'request_001').toList();
      expect(bodies.last['rephrase'], true);
      expect(bodies.last['streaming'], true);
      expect(bodies.last['textbook_count'], 8);
      expect(bodies.last['result_count'], 12);
      final prefs = await SharedPreferences.getInstance();
      await const AiSearchOptions(
        rephrase: false,
        streaming: false,
        textbookCount: 6,
        resultCount: 25,
      ).save(prefs);
      await prefs.setString(
        'ai_answer_model',
        'gemini-3.5-flash/answer_gen/v1',
      );
      await client.search('q', [], 'request_002').toList();
      expect(bodies.last['rephrase'], false);
      expect(bodies.last['streaming'], false);
      expect(bodies.last['textbook_count'], 6);
      expect(bodies.last['result_count'], 25);
      expect(bodies.last['model'], 'gemini-3.5-flash/answer_gen/v1');
      client.dispose();
    },
  );

  test(
    'late final citations replace the streamed answer without duplicating it',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      await AiSearchStore.install(db);
      final store = AiSearchStore(database: () => Future.value(db));
      final controller = AiSearchController(
        store: store,
        gateway: FragmentsGateway(),
      )..loading = false;
      await controller.send('q');
      expect(controller.turns.single.answer, '中文🙂回答。[1]');
      expect(controller.turns.single.status, 'complete');
      expect(
        (await store.turns(controller.session!.id)).single.answer,
        '中文🙂回答。[1]',
      );
      controller.dispose();
      await db.close();
    },
  );
}
