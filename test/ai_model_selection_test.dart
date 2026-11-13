import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/services/ai_search_client.dart';
import 'package:yibubang/services/ai_search_controller.dart';
import 'package:yibubang/widgets/ai_search_settings.dart';

const chosen = 'gemini-3.5-flash/answer_gen/v1';
final modelJson = {
  'models': [
    {
      'id': 'stable',
      'label': '自动（稳定版）',
      'resolved_model': chosen,
      'context_window': '128K',
    },
    {
      'id': chosen,
      'label': 'Gemini 3.5 Flash',
      'resolved_model': chosen,
      'context_window': '128K',
    },
  ],
  'source_url':
      'https://docs.cloud.google.com/generative-ai-app-builder/docs/answer-generation-models',
  'fetched_at': 1794484800,
  'stale': false,
};

class ModelGateway implements AiSearchGateway, AiModelGateway {
  @override
  String selectedModel = 'stable';
  int queries = 0;
  @override
  Future<AiModelCatalog> models({bool refresh = false}) async {
    queries++;
    return AiModelCatalog.fromJson(modelJson);
  }

  @override
  Future<void> selectModel(String model) async => selectedModel = model;
  @override
  Future<AiQuota> quota() async =>
      const AiQuota(remaining: 100, day: '2026-11-13');
  @override
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String requestId,
  ) async* {
    yield AiStreamEvent('model', {'id': selectedModel});
    yield const AiStreamEvent('delta', {
      'text': '第一行\n\n第二行',
      'reveal': 'lines',
    });
    yield const AiStreamEvent('done', {});
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'chosen built-in model persists and is sent to the backend after reopening',
    () async {
      const base = 'https://models.test';
      SharedPreferences.setMockInitialValues({
        'ai_installation_id': 'a' * 32,
        'ai_installation_secret': 'b' * 64,
        'ai_device_registered': base,
      });
      final requests = <http.Request>[];
      http.Client factory() => MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/v1/models') {
          return http.Response(
            jsonEncode(modelJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('event: done\ndata: {}\n\n', 200);
      });
      final client = AiSearchClient(baseUrl: base, clientFactory: factory);
      expect((await client.models(refresh: true)).models.length, 2);
      await client.selectModel(chosen);
      client.dispose();
      final reopened = AiSearchClient(baseUrl: base, clientFactory: factory);
      await reopened.search('定义', [], 'request_123').toList();
      expect(jsonDecode(requests.last.body)['model'], chosen);
      expect(
        (await SharedPreferences.getInstance()).getString('ai_answer_model'),
        chosen,
      );
      reopened.dispose();
    },
  );

  test(
    'line reveal completes and the selected turn model is saved locally',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      await AiSearchStore.install(db);
      final store = AiSearchStore(database: () async => db);
      final gateway = ModelGateway()..selectedModel = chosen;
      final ai = AiSearchController(store: store, gateway: gateway)
        ..loading = false;
      try {
        await ai.send('慢阻肺定义');
        expect(ai.turns.single.answer, '第一行\n\n第二行');
        expect(ai.turns.single.status, 'complete');
        expect((await store.turns(ai.session!.id)).single.model, chosen);
      } finally {
        ai.dispose();
        await db.close();
      }
    },
  );

  testWidgets(
    'model sheet queries and selects without consuming the daily search quota',
    (tester) async {
      final gateway = ModelGateway();
      final ai = AiSearchController(gateway: gateway)..loading = false;
      addTearDown(ai.dispose);
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AiSearchSettingsGroup(gateway: gateway)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答模型'));
      await tester.pumpAndSettle();
      expect(gateway.queries, 1);
      await tester.tap(find.text('Gemini 3.5 Flash'));
      await tester.pumpAndSettle();
      expect(ai.selectedModel, chosen);
      expect(ai.quota, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
