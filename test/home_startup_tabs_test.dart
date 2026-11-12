import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/models/bottom_nav_config.dart';
import 'package:yibubang/repositories/question_bank_repository.dart';
import 'package:yibubang/screens/choosed_subjects_page.dart';
import 'package:yibubang/screens/daily_plan_page.dart';
import 'package:yibubang/screens/home_page.dart';
import 'package:yibubang/screens/my_page.dart';
import 'package:yibubang/screens/statistics_page.dart';
import 'support/startup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StartupFixture fixture;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PackageInfo.setMockInitialValues(
      appName: '医不帮',
      packageName: 'yibubang',
      version: '2.2.3',
      buildNumber: '213',
      buildSignature: 'test',
    );
  });
  setUp(() async {
    fixture = await StartupFixture.create();
    // 仓库共享 Future 在真实时钟 Zone 初始化，避免跨部件 fake 时钟缓存。
    await QuestionBankRepository().initialize();
    BottomNavConfig.configNotifier.value = BottomNavConfig.getDefaultItems();
  });
  tearDown(() => fixture.close());
  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
  }

  Future<void> mount(WidgetTester tester, {double width = 1000}) async {
    size(tester, Size(width, 900));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await pumpReady(tester, find.text('启动课程'));
  }

  Future<void> select(WidgetTester tester, String text) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(text),
      ),
    );
    await tester.pump();
  }

  Future<void> planReady(WidgetTester tester) =>
      pumpReady(tester, find.text('默认每日刷题计划'));

  testWidgets('桌面首页只初始化选中课程，隐藏统计/计划/我的不挂载', (tester) async {
    await mount(tester);
    expect(
      find.byType(ChoosedSubjectsPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(DailyPlanPage, skipOffstage: false), findsNothing);
    expect(find.byType(StatisticsPage, skipOffstage: false), findsNothing);
    expect(find.byType(MyPage, skipOffstage: false), findsNothing);
    expect(
      await tester.runAsync(() => fixture.userDb.query('ReviewPlans')),
      isEmpty,
    );
    expect(
      tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .length,
      4,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首次访问加载计划，反复切换保留已访问页面和课程展开状态', (tester) async {
    await mount(tester);
    await tester.tap(find.text('启动课程'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('启动章节'), findsOneWidget);
    final courses = tester.state(find.byType(ChoosedSubjectsPage));
    await select(tester, '每日计划');
    await planReady(tester);
    final plan = tester.state(find.byType(DailyPlanPage));
    await select(tester, '我的课程');
    expect(tester.state(find.byType(ChoosedSubjectsPage)), same(courses));
    expect(find.text('启动章节'), findsOneWidget);
    await select(tester, '每日计划');
    expect(tester.state(find.byType(DailyPlanPage)), same(plan));
    expect(
      (await tester.runAsync(
        () => fixture.userDb.query('ReviewPlans'),
      ))!.length,
      1,
    );
    expect(find.byType(StatisticsPage, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自定义首个Tab生效，隐藏课程不会被提前初始化', (tester) async {
    final items = BottomNavConfig.getDefaultItems();
    items.insert(0, items.removeAt(3));
    await BottomNavConfig.saveConfig(items);
    size(tester, const Size(1000, 900));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await pumpUntil(
      tester,
      () =>
          tester
                  .widget<NavigationRail>(find.byType(NavigationRail))
                  .destinations
                  .first
                  .label
              is Text &&
          find.byType(MyPage).evaluate().isNotEmpty,
    );
    // 先前默认首项可能在配置从磁盘读入前已挂载，读入后只显示用户的首项。
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      0,
    );
    expect(find.byType(DailyPlanPage, skipOffstage: false), findsNothing);
    expect(find.byType(StatisticsPage, skipOffstage: false), findsNothing);
    await select(tester, '我的课程');
    await pumpReady(tester, find.text('启动课程'));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('导航重排和禁用未访问Tab保留已访问状态，不加载被禁用统计', (tester) async {
    await mount(tester);
    await select(tester, '每日计划');
    await planReady(tester);
    final plan = tester.state(find.byType(DailyPlanPage));
    await select(tester, '我的课程');
    final items = BottomNavConfig.getDefaultItems();
    items[2].enabled = false;
    items.insert(1, items.removeAt(3));
    await tester.runAsync(() => BottomNavConfig.saveConfig(items));
    await tester.pump();
    expect(find.byType(StatisticsPage, skipOffstage: false), findsNothing);
    expect(find.byType(MyPage, skipOffstage: false), findsNothing);
    await select(tester, '每日计划');
    expect(tester.state(find.byType(DailyPlanPage)), same(plan));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('宽窄布局切换保持选择索引，窄屏滑动仍显示下一Tab', (tester) async {
    await mount(tester);
    await select(tester, '每日计划');
    await planReady(tester);
    size(tester, const Size(600, 900));
    await tester.pump();
    await planReady(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round(),
      1,
    );
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpReady(tester, find.byType(StatisticsPage));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    size(tester, const Size(1000, 900));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
    );
    expect(find.byType(StatisticsPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
