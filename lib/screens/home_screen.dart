import 'package:flutter/material.dart';
import '../constants/app_strings.dart';
import '../screens/quiz_screen.dart';
import '../screens/my_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; // 默认主页为题库页

  // List of screens corresponding to the tabs
  final List<Widget> _screens = [
    QuizScreen(quizCategories: const [
      '口腔颌面外科学',
      '病理学',
      '诊断学',
      '内科学',
      '外科学',
    ]),
    MyScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: AppStrings.quizCategoryTitle,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: AppStrings.myScreenTitle,
          ),
        ],
      ),
    );
  }
}
