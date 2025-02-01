import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'common/app_strings.dart';
import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置系统UI样式，透明小白条背景
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent, // 设置小白条背景颜色透明
    systemNavigationBarIconBrightness: Brightness.light, // 图标颜色（亮色）
    systemNavigationBarDividerColor: Colors.transparent, // 分割线颜色透明
  ));

  runApp(const yibubang());
}

class yibubang extends StatelessWidget {
  const yibubang({super.key});

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
