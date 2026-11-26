import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/services/sync_debug_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同步调试日志按顺序保存最近的记录，关闭后停止追加', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = SyncDebugLog.instance;

    await log.record('默认不记录');
    expect(log.entries(prefs), isEmpty);
    await prefs.setBool(SyncDebugLog.enabledKey, true);
    await Future.wait([
      for (var i = 0; i <= SyncDebugLog.maxEntries; i++)
        log.record('检查章节 $i'),
    ]);
    await prefs.reload();
    final retained = log.entries(prefs);
    expect(retained.length, SyncDebugLog.maxEntries);
    expect(retained.first, endsWith('检查章节 1'));
    expect(retained.last, endsWith('检查章节 ${SyncDebugLog.maxEntries}'));

    await prefs.setBool(SyncDebugLog.enabledKey, false);
    await log.record('关闭后不追加');
    expect(log.entries(prefs), retained);
    await log.clear();
    expect(log.entries(prefs), isEmpty);
  });
}
