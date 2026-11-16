import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';

/// 统一 SQLite 变量超限 (>999) 分片查询与分批执行器。
///
/// 避免 Android/iOS 底层 SQLite 抛出 "too many SQL variables" 异常。
class ChunkedQueryExecutor {
  /// 默认每批变量数量（远低于 SQLite 999 限制，兼顾性能与安全）
  static const int defaultChunkSize = 500;

  /// 分批执行异步映射操作，并将各批次的结果平铺合并返回。
  static Future<List<R>> runChunked<T, R>({
    required List<T> items,
    required Future<List<R>> Function(List<T> chunk) action,
    int chunkSize = defaultChunkSize,
  }) async {
    if (items.isEmpty) return <R>[];
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', '必须大于 0');
    }
    if (items.length <= chunkSize) {
      return await action(items);
    }

    final results = <R>[];
    for (var i = 0; i < items.length; i += chunkSize) {
      final end = math.min(i + chunkSize, items.length);
      final chunk = items.sublist(i, end);
      final chunkResult = await action(chunk);
      results.addAll(chunkResult);
    }
    return results;
  }

  /// 分批执行无返回值的异步操作（如分批 UPDATE / DELETE 等）。
  static Future<void> runChunkedVoid<T>({
    required List<T> items,
    required Future<void> Function(List<T> chunk) action,
    int chunkSize = defaultChunkSize,
  }) async {
    if (items.isEmpty) return;
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', '必须大于 0');
    }
    if (items.length <= chunkSize) {
      await action(items);
      return;
    }

    for (var i = 0; i < items.length; i += chunkSize) {
      final end = math.min(i + chunkSize, items.length);
      final chunk = items.sublist(i, end);
      await action(chunk);
    }
  }

  /// 针对 `WHERE column IN (...)` 模式的安全分片查询。
  ///
  /// 当 [values] 数量超过 [chunkSize] 时，自动分批查询并聚合结果。
  static Future<List<Map<String, Object?>>> queryIn({
    required DatabaseExecutor db,
    required String table,
    required String column,
    required List<Object?> values,
    List<String>? columns,
    String? additionalWhere,
    List<Object?>? additionalWhereArgs,
    String? orderBy,
    int chunkSize = defaultChunkSize,
  }) async {
    if (values.isEmpty) return const <Map<String, Object?>>[];

    return runChunked<Object?, Map<String, Object?>>(
      items: values,
      chunkSize: chunkSize,
      action: (chunk) async {
        final placeholders = List.filled(chunk.length, '?').join(',');
        final whereClause = additionalWhere != null && additionalWhere.isNotEmpty
            ? '$column IN ($placeholders) AND ($additionalWhere)'
            : '$column IN ($placeholders)';
        final whereArgs = <Object?>[
          ...chunk,
          if (additionalWhereArgs != null) ...additionalWhereArgs,
        ];

        return await db.query(
          table,
          columns: columns,
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: orderBy,
        );
      },
    );
  }

  /// 针对 `WHERE column IN (...)` 模式的安全分批删除。
  static Future<int> deleteIn({
    required DatabaseExecutor db,
    required String table,
    required String column,
    required List<Object?> values,
    String? additionalWhere,
    List<Object?>? additionalWhereArgs,
    int chunkSize = defaultChunkSize,
  }) async {
    if (values.isEmpty) return 0;

    var totalDeleted = 0;
    await runChunkedVoid<Object?>(
      items: values,
      chunkSize: chunkSize,
      action: (chunk) async {
        final placeholders = List.filled(chunk.length, '?').join(',');
        final whereClause = additionalWhere != null && additionalWhere.isNotEmpty
            ? '$column IN ($placeholders) AND ($additionalWhere)'
            : '$column IN ($placeholders)';
        final whereArgs = <Object?>[
          ...chunk,
          if (additionalWhereArgs != null) ...additionalWhereArgs,
        ];

        totalDeleted += await db.delete(
          table,
          where: whereClause,
          whereArgs: whereArgs,
        );
      },
    );
    return totalDeleted;
  }
}
