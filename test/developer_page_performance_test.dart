import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/cloud_outbox.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/screens/developer_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DeveloperPage 性能与大量 Outbox 保护测试', () {
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'loggedin': false,
        'cloud_sync_enabled': false,
      });

      db = await UserDBHelper().database;
      await CloudOutbox.install(db);

      // 清空并模拟插入 120 条 CloudOutbox 变动
      await db.delete('CloudOutbox');
      final batch = db.batch();
      for (int i = 1; i <= 120; i++) {
        batch.insert('CloudOutbox', {
          'owner': 'test_user',
          'seq': i,
          'kind': 'question',
          'entity_id': 'q_$i',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });

    tearDown(() async {
      await UserDBHelper().close();
    });

    test('大量 Outbox 数据下 DeveloperPage 数据加载为纯本地且安全限流 50 条', () async {
      final state = const DeveloperPage().createState();
      final sw = Stopwatch()..start();

      // 执行全量加载
      await (state as dynamic).loadAllDataForTesting();
      sw.stop();

      // 验证加载耗时极短（纯本地，远小于网络超时）
      expect(sw.elapsedMilliseconds, lessThan(1000));

      final items = (state as dynamic).cloudOutboxItemsForTesting as List;
      final total = (state as dynamic).cloudOutboxTotalCountForTesting as int;

      // 验证总数正确，且只加载前 50 条防止 UI 假死
      expect(total, 120);
      expect(items.length, 50);
      expect(items.first['entity_id'], 'q_1');
    });
  });
}
