import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'screens/question_grid_page.dart';
import 'common/app_strings.dart';
import 'package:get/get.dart';

void main() {
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
