import 'dart:async';
import 'package:sqflite/sqflite.dart';

/// 用户库连接操作的 FIFO 临界区。复合 ATTACH / 文件维护必须持有整个临界区。
/// 不锁网络请求；事务内继续使用 sqflite 提供的 Transaction。
class UserDatabaseCoordinator {
  static final instance = UserDatabaseCoordinator();
  final Object _zoneKey = Object();
  Future<void> _tail = Zone.root.run(() => Future<void>.value());
  Future<T> run<T>(Future<T> Function() work) {
    final inherited = Zone.current[_zoneKey];
    if (inherited is _Lease && inherited.active) return work();
    final previous = _tail;
    final done = Zone.root.run(() => Completer<void>());
    _tail = done.future;
    // 调度器本身不能依赖 UI Zone 的微任务泵（部件测试的 fakeAsync 会暂停它）。
    // 临界区只承载数据库/本地文件操作，禁止网络及 UI 交互进入该执行 Zone。
    final result = Completer<T>();
    Zone.root.run(() async {
      await previous;
      final lease = _Lease();
      try {
        result.complete(await runZoned(work, zoneValues: {_zoneKey: lease}));
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        lease.active = false;
        done.complete();
      }
    });
    return result.future;
  }
}

class _Lease {
  bool active = true;
}

/// 保持 Database API，普通请求和缓存连接也遵守维护临界区。
class CoordinatedUserDatabase implements Database {
  final Database _db;
  final UserDatabaseCoordinator _coordinator;
  CoordinatedUserDatabase(this._db)
    : _coordinator = UserDatabaseCoordinator.instance;
  Future<T> _run<T>(Future<T> Function() work) => _coordinator.run(() async {
    if (!_db.isOpen) throw StateError('用户库连接已更换，请重新读取并重试');
    return work();
  });
  @override
  Database get database => this;
  @override
  String get path => _db.path;
  @override
  bool get isOpen => _db.isOpen;
  @override
  Future<void> close() => _coordinator.run(() => _db.close());
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => _run(() => _db.transaction(action, exclusive: exclusive));
  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction) action) =>
      _run(() => _db.readTransaction(action));
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _run(() => _db.execute(sql, arguments));
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _run(() => _db.rawInsert(sql, arguments));
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _run(() => _db.rawUpdate(sql, arguments));
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _run(() => _db.rawDelete(sql, arguments));
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _run(() => _db.rawQuery(sql, arguments));
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _run(
    () => _db.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _run(
    () => _db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _run(() => _db.delete(table, where: where, whereArgs: whereArgs));
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _run(
    () => _db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );
  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _run(() => _db.rawQueryCursor(sql, arguments, bufferSize: bufferSize));
  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _run(
    () => _db.queryCursor(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      bufferSize: bufferSize,
    ),
  );
  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) => _run(
    // ignore: deprecated_member_use
    () => _db.devInvokeMethod<T>(method, arguments),
  );
  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) => _run(
    // ignore: deprecated_member_use
    () => _db.devInvokeSqlMethod<T>(method, sql, arguments),
  );
  @override
  Batch batch() => _CoordinatedBatch(_db.batch(), _run);
}

class _CoordinatedBatch implements Batch {
  final Batch _batch;
  final Future<T> Function<T>(Future<T> Function()) _run;
  _CoordinatedBatch(this._batch, this._run);
  @override
  int get length => _batch.length;
  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _batch.execute(sql, arguments);
  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _batch.rawInsert(sql, arguments);
  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _batch.rawUpdate(sql, arguments);
  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _batch.rawDelete(sql, arguments);
  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _batch.rawQuery(sql, arguments);
  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _batch.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _batch.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _batch.delete(table, where: where, whereArgs: whereArgs);
  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _batch.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) => _run(
    () => _batch.commit(
      exclusive: exclusive,
      noResult: noResult,
      continueOnError: continueOnError,
    ),
  );
  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) => _run(
    () => _batch.apply(noResult: noResult, continueOnError: continueOnError),
  );
}

/// sqflite 的默认版本扩展强制转换其内部执行器；通过公共 SQL API 保持适配器兼容。
/// Database 比 DatabaseExecutor 更具体，导入 UserDBHelper 后优先选用此扩展。
extension UserDatabaseVersion on Database {
  Future<int> getVersion() async =>
      Sqflite.firstIntValue(await rawQuery('PRAGMA user_version')) ?? 0;
  Future<void> setVersion(int version) {
    if (version < 0) throw ArgumentError.value(version, 'version');
    return execute('PRAGMA user_version = $version');
  }
}
