import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SharedPreferences _prefs;
  bool _loaded = false;

  /// 全局设置
  bool acceptUpdate = true;
  bool syncQuestionBank = true;

  static const String keyAcceptUpdate = 'accept_update';
  static const String keySyncQuestionBank = 'sync_question_bank';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    acceptUpdate = _prefs.getBool(keyAcceptUpdate) ?? true;
    syncQuestionBank = _prefs.getBool(keySyncQuestionBank) ?? false;
    debugPrint("$acceptUpdate$syncQuestionBank");
    setState(() {
      _loaded = true;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildSectionTitle('通用设置'),
          SwitchListTile(
            title: const Text('接受应用更新'),
            value: acceptUpdate,
            onChanged: (v) {
              setState(() => acceptUpdate = v);
              _setBool(keyAcceptUpdate, v);
            },
          ),
          SwitchListTile(
            title: const Text('同步题库'),
            value: syncQuestionBank,
            onChanged: (v) {
              setState(() => syncQuestionBank = v);
              _setBool(keySyncQuestionBank, v);
            },
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
