import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/question_grid_screen.dart';
import 'constants/app_strings.dart';

void main() {
  runApp(const yibubang());
}

class yibubang extends StatelessWidget {
  const yibubang({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomeScreen(),
    );
  }
}
