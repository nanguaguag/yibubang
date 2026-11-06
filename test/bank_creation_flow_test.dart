import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/question_bank_manager.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/screens/bank_creation_page.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/services/ykb_bank_sync_service.dart';
import 'package:yibubang/widgets/bank_creation_dialogs.dart';

class _CreationFixture extends BankCreationService {
  _CreationFixture()
    : super(
        request: (_, __) async => {
          'code': 200,
          'data': [
            {
              'chapter_id': 's',
              'title': '解剖学',
              'children': [
                for (final id in ['成功章节', '无权限章节', '服务异常章节', '另一失败章节'])
                  {'chapter_id': id, 'title': id, 'count': 1},
              ],
            },
          ],
        },
        fetchChapter: (_, id) async => id == '成功章节'
            ? const YkbChapterFetchResult(
                code: '200',
                message: '',
                questions: [
                  {'id': 'q'},
                ],
              )
            : YkbChapterFetchResult(
                code: id == '无权限章节' ? '203' : '500',
                message: '无法读取',
              ),
      );

  @override
  Future<List<BankIdentityNode>> identities() async => [
    BankIdentityNode({'identity_id': '38', 'title': '西医综合'}, []),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'loggedin': true});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('creation-flow-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'databases'));
    await QuestionBankRepository().initialize();
  });
  tearDown(() async {
    await QuestionBankDatabaseManager().closeAll();
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(finder, findsWidgets);
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BankCreationPage(service: _CreationFixture())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('开始创建'));
    await waitFor(tester, find.text('当前账号没有查看权限（203）。'));
    expect(find.text('忽略'), findsOneWidget);
    expect(find.text('忽略全部'), findsOneWidget);
    expect(find.text('终止'), findsOneWidget);
  }

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'creation supports ignore and ignore all, then reports saved content and all failures at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await start(tester);
        await tester.tap(find.text('忽略'));
        await waitFor(tester, find.text('错误 500：无法读取'));
        await tester.tap(find.text('忽略全部'));
        await waitFor(tester, find.byType(BankCreationReportDialog));
        expect(find.text('已保存 1 个题库 · 1 道题'), findsOneWidget);
        expect(
          find.text('成功（2）'),
          findsOneWidget,
        ); // directory + one complete chapter
        expect(find.text('失败（3）'), findsOneWidget);
        expect(find.text('题库创建遇到问题'), findsNothing);
        await tester.tap(find.text('失败（3）'));
        await tester.pumpAndSettle();
        expect(find.textContaining('无权限章节'), findsOneWidget);
        expect(find.textContaining('服务异常章节'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('另一失败章节'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(BankCreationReportDialog),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        expect(find.textContaining('另一失败章节'), findsOneWidget);
        final banks = await tester.runAsync(
          () => QuestionBankRepository().listBanks(),
        );
        expect(
          banks!
              .where((b) => b.bankId.startsWith('custom_') && b.isInstalled)
              .length,
          1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'terminate produces a report and preserves existing banks without installing the unfinished bank',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('终止'));
      await waitFor(tester, find.byType(BankCreationReportDialog));
      expect(find.text('已保存 0 个题库 · 0 道题'), findsOneWidget);
      expect(find.text('失败（1）'), findsOneWidget);
      final banks = await tester.runAsync(
        () => QuestionBankRepository().listBanks(),
      );
      expect(banks!.where((b) => b.bankId.startsWith('custom_')), isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('查看创建报告'), findsOneWidget);
      expect(find.text('开始创建'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
