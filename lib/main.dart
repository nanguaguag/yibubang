import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'common/app_strings.dart';
import 'db/settings.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future main() async {
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

  // 设置系统UI样式，透明小白条背景
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent, // 设置小白条背景颜色透明
    systemNavigationBarIconBrightness: Brightness.light, // 图标颜色（亮色）
    systemNavigationBarDividerColor: Colors.transparent, // 分割线颜色透明
  ));

  await initSettings();
  runApp(const Yibubang());
}

class Yibubang extends StatelessWidget {
  const Yibubang({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appTitle,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
