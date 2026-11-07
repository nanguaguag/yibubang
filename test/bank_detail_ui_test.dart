import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/models/question_bank.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/screens/bank_detail_page.dart';
import 'package:yibubang/screens/question_bank_page.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';
import 'package:yibubang/widgets/common/info_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  late QuestionBank bank;
  const url = 'https://example.org/clinical_final.sqlite.zip';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('bank-detail-ui-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'databases'));
    final root = BankIdentityNode(
      {'identity_id': '38', 'title': '空分组'},
      [
        BankIdentityNode({'identity_id': '381', 'title': '大一'}, []),
      ],
    );
    final file =
        await BankCreationService(
          request: (_, __) async => {
            'code': 200,
            'data': [
              {
                'chapter_id': 's',
                'title': '解剖学',
                'children': [
                  {'chapter_id': 'c1', 'title': '第一章', 'count': 1},
                  {'chapter_id': 'c2', 'title': '第二章', 'count': 1},
                ],
              },
            ],
          },
          fetchChapter: (_, __) async => const YkbChapterFetchResult(
            code: '200',
            message: '',
            questions: [
              {'id': 'q', 'title': '共享题'},
            ],
          ),
        ).build(
          root: root,
          bankId: 'fixture',
          name: '测试题库',
          version: '1.0.0',
          directory: directory,
        );
    // Modify a staging fixture, never an installed bank.
    final db = await openDatabase(file.path, singleInstance: false);
    await db.insert('Identity', {
      'id': '382',
      'name': '空学科',
      'parent_id': '38',
    });
    await db.close();
    await QuestionBankRepository().initialize();
    bank = await QuestionBankRepository().importFile(file.path);
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'bank_subscription_entries': jsonEncode([
        {'bank_id': 'fixture', 'subscription_url': url, 'url': url},
      ]),
    }),
  );
  tearDownAll(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  Future<void> loaded(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(finder, findsWidgets);
  }

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'details match shared cards, hide empty subjects and count unique questions at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: BankDetailPage(bank: bank)));
        await loaded(tester, find.text('覆盖课程'));
        final totals = find.descendant(
          of: find.byKey(const ValueKey('bank-detail-totals')),
          matching: find.byType(Text),
        );
        expect(
          tester.widgetList<Text>(totals).map((text) => text.data).toList(),
          ['1', '课程总数', '2', '章节总数', '1', '题目总数'],
        );
        expect(find.byType(InfoCard), findsWidgets);
        expect(find.text('空分组'), findsNothing);
        expect(find.text('空学科'), findsNothing);
        expect(find.text('大一'), findsOneWidget);
        expect(find.textContaining('章节关系'), findsNothing);
        expect(find.textContaining('根'), findsNothing);
        await tester.ensureVisible(find.text('大一'));
        await tester.tap(find.text('大一'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('解剖学'));
        // The same question appears in two chapters, but the course has one question.
        expect(find.text('1 道题'), findsWidgets);
        expect(find.text('2 道题'), findsNothing);
        await tester.tap(find.text('解剖学'));
        await tester.pumpAndSettle();
        expect(find.text('第一章'), findsOneWidget);
        expect(find.text('第二章'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('修改订阅链接'));
        await tester.tap(find.byTooltip('修改订阅链接'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          url,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'management offers adjacent detail, subscription update and export icons at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(const MaterialApp(home: QuestionBankPage()));
        await loaded(tester, find.text('测试题库'));
        final card = find.ancestor(
          of: find.text('测试题库'),
          matching: find.byType(Card),
        );
        final detail = find.descendant(
          of: card,
          matching: find.byTooltip('题库详情'),
        );
        final update = find.descendant(
          of: card,
          matching: find.byTooltip('检查更新'),
        );
        final export = find.descendant(
          of: card,
          matching: find.byTooltip('导出题库'),
        );
        expect(update, findsOneWidget);
        expect(export, findsOneWidget);
        expect(tester.getCenter(detail).dy, tester.getCenter(update).dy);
        expect(tester.getCenter(update).dy, tester.getCenter(export).dy);
        await tester.ensureVisible(export);
        await tester.tap(export);
        await tester.pumpAndSettle();
        expect(find.text('ZIP'), findsOneWidget);
        expect(find.text('SQLite'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
