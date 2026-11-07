import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/screens/bank_creation_page.dart';
import 'package:yibubang/screens/bank_subscriptions_page.dart';
import 'package:yibubang/screens/question_bank_page.dart';
import 'package:yibubang/widgets/bank_link_import_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String previousPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    previousPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('bank-nav-test-');
    await databaseFactory.setDatabasesPath(p.join(directory.path, 'databases'));
    await QuestionBankRepository().initialize();
    await (await UserDBHelper().database).insert('QuestionBank', {
      'bank_id': 'fixture',
      'name': 'A测试题库',
      'identity_id': '38',
      'built_in': 1,
    });
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDownAll(() async {
    await UserDBHelper().close();
    await databaseFactory.setDatabasesPath(previousPath);
    await directory.delete(recursive: true);
  });

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'bank creation and subscription routes are reachable at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(const MaterialApp(home: QuestionBankPage()));
        // SQLite FFI uses a real isolate, outside the widget test's fake clock.
        for (
          var attempt = 0;
          attempt < 20 && find.text('A测试题库').evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('A测试题库'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final tag = tester.widget<Chip>(
          find.ancestor(of: find.text('38'), matching: find.byType(Chip)),
        );
        expect(tag.shape, isA<StadiumBorder>());
        expect(find.textContaining('根 identity'), findsNothing);
        expect(find.byTooltip('创建题库'), findsOneWidget);
        expect(find.byTooltip('管理订阅'), findsOneWidget);

        await tester.tap(find.byTooltip('更多导入方式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('从链接导入'));
        await tester.pumpAndSettle();
        expect(find.byType(BankLinkImportDialog), findsOneWidget);
        expect(find.text('订阅后续更新'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('创建题库'));
        await tester.pumpAndSettle();
        expect(find.byType(BankCreationPage), findsOneWidget);
        expect(find.textContaining('请先登录医考帮'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final close = find.byType(CloseButton);
        await tester.tap(
          close.evaluate().isNotEmpty
              ? close.last
              : find.byType(BackButton).last,
        );
        await tester.pump(const Duration(seconds: 1));
        for (
          var attempt = 0;
          attempt < 20 && find.text('A测试题库').evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('A测试题库'), findsOneWidget);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('管理订阅'));
        await tester.pumpAndSettle();
        expect(find.byType(BankSubscriptionsPage), findsOneWidget);
        await tester.tap(find.text('添加订阅'));
        await tester.pumpAndSettle();
        expect(find.text('HTTPS 订阅地址'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
