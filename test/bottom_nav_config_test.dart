import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/models/bottom_nav_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BottomNavConfig Tests', () {
    test('default items contains 4 tabs in expected initial order', () {
      final items = BottomNavConfig.getDefaultItems();
      expect(items.length, 4);
      expect(items[0].id, 'subjects');
      expect(items[1].id, 'daily_plan');
      expect(items[2].id, 'statistics');
      expect(items[3].id, 'profile');
      expect(items.every((i) => i.enabled), isTrue);
    });

    test('save and load persists custom reordering and visibility', () async {
      final items = BottomNavConfig.getDefaultItems();
      // 调整顺序：把 profile 移到最前，并隐藏 daily_plan
      final profile = items.removeAt(3);
      items.insert(0, profile);
      items.firstWhere((i) => i.id == 'daily_plan').enabled = false;

      await BottomNavConfig.saveConfig(items);

      final loaded = await BottomNavConfig.loadConfig();
      expect(loaded.length, 4);
      expect(loaded[0].id, 'profile');
      expect(loaded[0].enabled, isTrue);
      expect(loaded.firstWhere((i) => i.id == 'daily_plan').enabled, isFalse);
      expect(loaded.firstWhere((i) => i.id == 'subjects').enabled, isTrue);
    });

    test('at least two tabs are guaranteed to remain enabled for Material NavigationBar', () async {
      final items = BottomNavConfig.getDefaultItems();
      for (final item in items) {
        item.enabled = false;
      }
      // 尝试全关
      await BottomNavConfig.saveConfig(items);

      final loaded = await BottomNavConfig.loadConfig();
      expect(loaded.where((i) => i.enabled).length >= 2, isTrue);
    });

    test('resetToDefault restores original state', () async {
      final items = BottomNavConfig.getDefaultItems();
      items[0].enabled = false;
      await BottomNavConfig.saveConfig(items);

      await BottomNavConfig.resetToDefault();
      final loaded = await BottomNavConfig.loadConfig();
      expect(loaded.every((i) => i.enabled), isTrue);
      expect(loaded[0].id, 'subjects');
    });
  });
}
