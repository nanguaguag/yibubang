import 'package:flutter/material.dart';
import '../common/app_strings.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 默认主页为题库页

  // List of screens corresponding to the tabs
  final List<Widget> _screens = [
    const ChoosedSubjectsPage(),
    const MyPage(),
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
            label: AppStrings.selectedSubjectsTitle,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: AppStrings.myPageTitle,
          ),
        ],
      ),
    );
  }
}
