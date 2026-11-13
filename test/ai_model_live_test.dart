// Opt-in production client/controller checks use real time; UI renders the result.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/models/ai_search_options.dart';
import 'package:yibubang/screens/ai_search_page.dart';
import 'package:yibubang/services/ai_search_client.dart';
import 'package:yibubang/services/ai_search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'live built-in Answer in the App',
    () {
      late Database db;
      late AiSearchClient gateway;
      late AiSearchController controller;
      HttpOverrides? previous;
      final textbookCount = int.tryParse(
        Platform.environment['AI_TEXTBOOK_COUNT'] ?? '',
      );
      final resultCount =
          int.tryParse(Platform.environment['AI_RESULT_COUNT'] ?? '') ?? 12;
      setUpAll(() async {
        previous = HttpOverrides.current;
        HttpOverrides.global = null;
        final identity = jsonDecode(
          File(
            p.join('ai_backend', '.local', 'smoke-device.json'),
          ).readAsStringSync(),
        );
        SharedPreferences.setMockInitialValues({
          'ai_installation_id': identity['installation_id'],
          'ai_installation_secret': identity['secret'],
          'ai_device_registered': AiSearchClient.endpoint,
          'ai_answer_model': 'stable',
          if (textbookCount != null)
            AiSearchOptions.textbookCountKey: textbookCount,
          AiSearchOptions.resultCountKey: resultCount,
        });
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        db = await openDatabase(inMemoryDatabasePath);
        await AiSearchStore.install(db);
        gateway = AiSearchClient();
        controller = AiSearchController(
          store: AiSearchStore(database: () async => db),
          gateway: gateway,
        )..loading = false;
      });
      tearDownAll(() async {
        controller.dispose();
        await db.close();
        HttpOverrides.global = previous;
      });

      test(
        'queries actual models, selects, saves and reveals a grounded answer',
        () async {
          final before = (await gateway.quota()).remaining;
          await controller.refreshModels(refresh: true);
          expect(controller.modelError, isNull);
          expect(
            controller.modelCatalog!.models.length,
            greaterThanOrEqualTo(4),
          );
          expect((await gateway.quota()).remaining, before);
          final selected = controller.modelCatalog!.models.singleWhere(
            (m) => m.id == 'gemini-3.5-flash/answer_gen/v1',
          );
          await controller.selectModel(selected);
          await controller.send('三角肌粗隆位于哪里？');
          final turn = controller.turns.single;
          expect(turn.status, 'complete', reason: turn.error);
          expect(turn.model, selected.id);
          expect(turn.answer, contains('肱骨'));
          expect(turn.answer, contains('['));
          expect(turn.citations.where((c) => c.isTextbook), isNotEmpty);
          if (textbookCount != null) {
            expect(
              turn.citations.where((c) => c.isTextbook).length,
              textbookCount,
            );
            expect(
              turn.citations.where((c) => !c.isTextbook).length,
              resultCount - textbookCount,
            );
          }
          expect(
            (await controller.store.turns(controller.session!.id)).single.model,
            selected.id,
          );
          expect((await gateway.quota()).remaining, before - 3);
          File(
            p.join('ai_backend', '.local', 'builtin-app-live.json'),
          ).writeAsStringSync(
            jsonEncode({
              'status': 'CONTROLLER_PASS',
              'model': turn.model,
              'citation_count': turn.citations.length,
              'textbook_count': turn.citations
                  .where((c) => c.isTextbook)
                  .length,
              'question_count': turn.citations
                  .where((c) => !c.isTextbook)
                  .length,
              'answer_chars': turn.answer.length,
              'answer': turn.answer,
              'chain':
                  'AiSearchController -> AiSearchClient -> Cloud Run -> Search :answer -> local SQLite',
            }),
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets('renders the production answer and opens its source', (
        tester,
      ) async {
        expect(controller.turns.single.status, 'complete');
        final font = FontLoader('AiLiveChinese')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  p.join(
                    Platform.pathSeparator,
                    'System',
                    'Library',
                    'Fonts',
                    'PingFang.ttc',
                  ),
                ).readAsBytesSync(),
              ),
            ),
          );
        await font.load();
        final iconPath = Platform.environment['TEXTBOOK_ICONS_FONT'];
        if (iconPath != null) {
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(File(iconPath).readAsBytesSync()),
              ),
            );
          await icons.load();
        }
        tester.view.physicalSize = const Size(1000, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final shotKey = GlobalKey();
        AiCitation? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, fontFamily: 'AiLiveChinese'),
            home: RepaintBoundary(
              key: shotKey,
              child: AiSearchPage(
                controller: controller,
                openCitation: (_, c) async => opened = c,
              ),
            ),
          ),
        );
        final source = find.byType(ActionChip).first;
        await tester.ensureVisible(source);
        await tester.tap(source);
        expect(opened, isNotNull);
        await tester.runAsync(() async {
          final boundary =
              shotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 2);
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          File(
            p.join(
              'ai_backend',
              '.local',
              'screenshots',
              'builtin-ai-live.png',
            ),
          ).writeAsBytesSync(png!.buffer.asUint8List());
          picture.dispose();
          final file = File(
            p.join('ai_backend', '.local', 'builtin-app-live.json'),
          );
          final report =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          report['status'] = 'PASS';
          report['opened'] = opened!.toJson();
          report['ui'] =
              'AiSearchPage displays real answer and citation callback';
          file.writeAsStringSync(jsonEncode(report));
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
    skip: Platform.environment['AI_MODEL_LIVE_TEST'] != '1',
  );
}
