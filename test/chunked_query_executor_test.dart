import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/chunked_query_executor.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChunkedQueryExecutor 基础分片行为测试', () {
    test('runChunked 对空列表直接返回空列表', () async {
      var callCount = 0;
      final res = await ChunkedQueryExecutor.runChunked<int, int>(
        items: [],
        action: (chunk) async {
          callCount++;
          return chunk;
        },
      );
      expect(res, isEmpty);
      expect(callCount, 0);
    });

    test('runChunked 列表元素不超过 chunkSize 时仅执行一次', () async {
      final items = List.generate(100, (i) => i);
      var callCount = 0;
      final res = await ChunkedQueryExecutor.runChunked<int, int>(
        items: items,
        chunkSize: 200,
        action: (chunk) async {
          callCount++;
          return chunk.map((e) => e * 2).toList();
        },
      );
      expect(callCount, 1);
      expect(res.length, 100);
      expect(res.first, 0);
      expect(res.last, 198);
    });

    test('runChunked 对大列表（如 1250 项）按指定分片正确切分并平铺聚合', () async {
      final items = List.generate(1250, (i) => i);
      final receivedChunks = <int>[];
      final res = await ChunkedQueryExecutor.runChunked<int, int>(
        items: items,
        chunkSize: 500,
        action: (chunk) async {
          receivedChunks.add(chunk.length);
          return chunk;
        },
      );
      expect(receivedChunks, [500, 500, 250]);
      expect(res.length, 1250);
      expect(res, items);
    });

    test('runChunkedVoid 分批执行无返回值操作', () async {
      final items = List.generate(1100, (i) => i);
      final handled = <int>[];
      await ChunkedQueryExecutor.runChunkedVoid<int>(
        items: items,
        chunkSize: 400,
        action: (chunk) async {
          handled.addAll(chunk);
        },
      );
      expect(handled.length, 1100);
      expect(handled, items);
    });

    test('chunkSize <= 0 时抛出 ArgumentError', () async {
      expect(
        () => ChunkedQueryExecutor.runChunked<int, int>(
          items: [1, 2, 3],
          chunkSize: 0,
          action: (c) async => c,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ChunkedQueryExecutor SQLite 内存数据库分片查询测试', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE TestItems (
          id TEXT PRIMARY KEY,
          category TEXT,
          val INTEGER
        )
      ''');

      // 插入 1500 条数据，远超 999 变量限制
      final batch = db.batch();
      for (var i = 0; i < 1500; i++) {
        batch.insert('TestItems', {
          'id': 'item_$i',
          'category': i % 2 == 0 ? 'even' : 'odd',
          'val': i,
        });
      }
      await batch.commit(noResult: true);
    });

    tearDown(() async {
      await db.close();
    });

    test('queryIn 自动突破 999 变量限制，成功分片查出 1500 条数据', () async {
      final allIds = List.generate(1500, (i) => 'item_$i');

      final results = await ChunkedQueryExecutor.queryIn(
        db: db,
        table: 'TestItems',
        column: 'id',
        values: allIds,
        chunkSize: 500,
      );

      expect(results.length, 1500);
    });

    test('queryIn 支持附加 where 条件与额外参数', () async {
      final targetIds = List.generate(1000, (i) => 'item_$i');

      final results = await ChunkedQueryExecutor.queryIn(
        db: db,
        table: 'TestItems',
        column: 'id',
        values: targetIds,
        additionalWhere: 'category = ?',
        additionalWhereArgs: ['even'],
        chunkSize: 400,
      );

      // 0..999 中 even 的数量为 500
      expect(results.length, 500);
      for (final row in results) {
        expect(row['category'], 'even');
      }
    });

    test('deleteIn 分批删除超量数据', () async {
      final deleteIds = List.generate(1200, (i) => 'item_$i');

      final count = await ChunkedQueryExecutor.deleteIn(
        db: db,
        table: 'TestItems',
        column: 'id',
        values: deleteIds,
        chunkSize: 500,
      );

      expect(count, 1200);

      final remain = await db.rawQuery('SELECT COUNT(*) as c FROM TestItems');
      expect(remain.first['c'], 300);
    });
  });
}
