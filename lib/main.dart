import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'common/app_shapes.dart';
import 'common/app_strings.dart';
import 'db/settings.dart';
import 'repositories/question_bank_repository.dart';
import 'services/cloud_sync_service.dart';
import 'services/note_service.dart';
import 'services/ykb_sync_service.dart';
import 'widgets/theme_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future main() async {
  final swStartup = Stopwatch()..start();
  // Use sqflite on MacOS/iOS/Android.
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Use web implementation on the web.
    databaseFactory = databaseFactoryFfiWeb;
  } else {
    // Use ffi on Linux and Windows and MacOS.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      databaseFactory = databaseFactoryFfi;
      sqfliteFfiInit();
    }
  }

  // 设置系统UI样式，透明小白条背景（沉浸式）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent, // 设置小白条背景颜色透明
    systemNavigationBarIconBrightness: Brightness.dark, // 图标颜色（深色，适配浅色背景）
    systemNavigationBarDividerColor: Colors.transparent, // 分割线颜色透明
  ));

  await initSettings();
  debugPrint('[startup] initSettings 完成(${swStartup.elapsedMilliseconds}ms)');
  runApp(const Yibubang());
  debugPrint('[startup] runApp 完成(${swStartup.elapsedMilliseconds}ms)');

  // 题库目录包含 SQLite 完整性校验，不应阻塞 Flutter 首帧。
  // HomePage 会复用同一个初始化 Future，避免重复扫描。
  unawaited(_initializeQuestionBank());
}

Future<void> _initializeQuestionBank() async {
  final sw = Stopwatch()..start();
  try {
    await QuestionBankRepository().initialize();
    debugPrint('[startup] 题库目录初始化完成(${sw.elapsedMilliseconds}ms)');

    // 题库初始化完成后，静默进行云端增量同步 (不阻塞主线程)
    final syncService = CloudSyncService.instance;
    await syncService.init();
    if (syncService.isConfigured && syncService.autoSync) {
      unawaited(syncService.sync());
    }

    // 后台静默处理医考帮离线同步队列
    unawaited(YkbSyncService.instance.processQueue());
    unawaited(NoteService.instance.processQueue());
  } catch (error) {
    // 目录迁移失败时仍启动应用，让用户可以通过题库管理或备份恢复继续处理。
    debugPrint('题库目录初始化失败：$error');
  }
}

/// 参照 cgfkr 设计系统构建主题：MD3 种子色 + 统一的形状令牌。
ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    // 统一页面转场为 Material 3，去除 iOS 风格滑入
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    colorScheme: colorScheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: const AppBarTheme(
      toolbarHeight: 48,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppShapes.largeIncreased)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppShapes.extraLarge)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShapes.extraLarge),
        ),
      ),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder())),
    ),
    elevatedButtonTheme: const ElevatedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder())),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder())),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder())),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(height: 64),
  );
}

class Yibubang extends StatelessWidget {
  const Yibubang({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppStrings.appTitle,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: themeMode,
          home: const HomePage(),
        );
      },
    );
  }
}
