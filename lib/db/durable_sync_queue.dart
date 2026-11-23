import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// 官方同步义务持久化：失败暂停而不删除；每张表共享后台/手动互斥入口。
class DurableSyncQueue {
  static final _busy = <String>{};
  static final _wake = <String, Timer>{};
  static final _requested = <String>{};
  static Future<void> install(DatabaseExecutor db) async {
    for (final table in ['YkbSyncQueue', 'NoteSyncQueue']) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info($table)',
      )).map((r) => r['name']).toSet();
      for (final field in {
        'owner_user_id': "TEXT NOT NULL DEFAULT ''",
        'queue_state': "TEXT NOT NULL DEFAULT 'pending'",
        'next_attempt_at': 'INTEGER NOT NULL DEFAULT 0',
      }.entries) {
        if (!columns.contains(field.key)) {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN ${field.key} ${field.value}',
          );
        }
      }
      // 旧任务无法可靠推断账号，保留供用户手动认领，禁止自动投给当前账号。
      await db.rawUpdate(
        "UPDATE $table SET queue_state='paused' WHERE owner_user_id='' AND queue_state!='paused'",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_due ON $table(owner_user_id,queue_state,next_attempt_at,created_at)',
      );
    }
  }

  static Future<String> owner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('loggedin') == true
          ? prefs.getString('user_id') ?? ''
          : '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> enqueue(
    String table,
    Map<String, dynamic> row, {
    DatabaseExecutor? executor,
  }) async {
    final account = row['owner_user_id'] as String? ?? await owner();
    await (executor ?? await UserDBHelper().database).insert(table, {
      ...row,
      'owner_user_id': account,
      'queue_state': account.isEmpty ? 'paused' : 'pending',
      'next_attempt_at': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 登录成功后立即唤醒当前账号下所有处于退避冷却中的 pending 任务。
  static Future<void> wakeOnLogin([String? userId]) async {
    final account = (userId != null && userId.isNotEmpty)
        ? userId
        : await owner();
    if (account.isEmpty) return;
    final db = await UserDBHelper().database;
    for (final table in ['YkbSyncQueue', 'NoteSyncQueue']) {
      await db.update(
        table,
        {'next_attempt_at': 0},
        where: "owner_user_id=? AND queue_state='pending'",
        whereArgs: [account],
      );
    }
  }

  static Future<bool> reset(String table, {String? id}) async {
    if (_busy.contains(table)) return false;
    final account = await owner();
    if (account.isEmpty) return false;
    final db = await UserDBHelper().database;
    final count = await db.update(
      table,
      {
        'owner_user_id': account,
        'queue_state': 'pending',
        'next_attempt_at': 0,
        'retry_count': 0,
        'last_error': null,
      },
      where:
          "(owner_user_id=? OR owner_user_id='')${id == null ? '' : ' AND id=?'}",
      whereArgs: [account, if (id != null) id],
    );
    return count > 0;
  }

  /// 判断捕获的异常是否属于「尚未到达服务端或服务端明确拒绝（未落库）」的可安全自动重试错误。
  static bool _isSafePreSendOrAuthError(Object? error, String? responseCode) {
    if (responseCode == '309') return true;
    if (error == null) return false;
    if (error is SocketException || error is HandshakeException) return true;
    final msg = error.toString();
    if (msg.contains('309_TOKEN_EXPIRED') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Network is unreachable') ||
        msg.contains('Connection refused') ||
        msg.contains('同步账号已切换') ||
        msg.contains('笔记图片尚未上传成功')) {
      return true;
    }
    return false;
  }

  static Future<bool> run(
    String table,
    Future<bool> Function(Map<String, dynamic>) execute, {
    String? onlyId,
  }) async {
    if (_busy.contains(table)) {
      _requested.add(table);
      return false;
    }
    _busy.add(table);
    _wake.remove(table)?.cancel();
    var completed = false;
    try {
      while (true) {
        final account = await owner();
        if (account.isEmpty) break;
        final db = await UserDBHelper().database;
        _requested.remove(table);
        final rows = await db.query(
          table,
          where:
              "owner_user_id=? AND queue_state='pending' AND next_attempt_at<=?${onlyId == null ? '' : ' AND id=?'}",
          whereArgs: [
            account,
            DateTime.now().millisecondsSinceEpoch,
            if (onlyId != null) onlyId,
          ],
          orderBy: 'created_at,id',
          limit: 15,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (await owner() != account) break;
          // 先持久化发包状态；进程被杀后保留为待人工核对，不盲目重复非幂等操作。
          await db.update(
            table,
            {'queue_state': 'sending', 'last_error': '请求进行中；若应用中断，请核对远端后手动重试'},
            where: 'id=? AND owner_user_id=?',
            whereArgs: [row['id'], account],
          );
          bool success = false;
          Object? caughtError;
          String? error;
          try {
            success = await execute(Map<String, dynamic>.from(row));
          } catch (e) {
            caughtError = e;
            error = e.toString();
          }
          // 同 id 的新 payload 不能被旧请求的确认/失败清掉。
          final where = 'id=? AND owner_user_id=? AND payload IS ?';
          final args = [row['id'], account, row['payload']];
          if (success) {
            completed =
                await db.delete(table, where: where, whereArgs: args) > 0 ||
                completed;
          } else {
            final latest = await db.query(
              table,
              columns: ['last_response', 'last_error'],
              where: where,
              whereArgs: args,
            );
            String? code;
            String? persistedError;
            if (latest.isNotEmpty) {
              persistedError = latest.single['last_error'] as String?;
              try {
                code =
                    (jsonDecode(latest.single['last_response'] as String)
                            as Map)['code']
                        ?.toString();
              } catch (_) {}
            }
            final nonIdempotent =
                (table == 'YkbSyncQueue' && row['type'] == 'answer') ||
                (table == 'NoteSyncQueue' && row['action'] == 'upload');
            final isPreSendSafe = _isSafePreSendOrAuthError(caughtError, code);
            final uncertain =
                nonIdempotent &&
                !isPreSendSafe &&
                (error != null ||
                    code == 'http_error' ||
                    code == 'protocol_error');
            final retry = (row['retry_count'] as int? ?? 0) + 1;
            final delay = 30 * (1 << (retry.clamp(1, 8) - 1));
            final hasSpecificError =
                persistedError != null &&
                persistedError.isNotEmpty &&
                !persistedError.startsWith('请求进行中');
            await db.update(
              table,
              {
                'retry_count': retry,
                'queue_state': retry >= 5 || uncertain ? 'paused' : 'pending',
                'next_attempt_at':
                    DateTime.now().millisecondsSinceEpoch + delay * 1000,
                if (error != null && !hasSpecificError) 'last_error': error,
                if (error != null &&
                    (latest.isEmpty || latest.single['last_response'] == null))
                  'last_response': jsonEncode({'error': error}),
              },
              where: where,
              whereArgs: args,
            );
          }
        }
        if (onlyId != null) break;
      }
    } finally {
      try {
        final account = await owner();
        if (account.isNotEmpty) {
          final db = await UserDBHelper().database;
          final rows = await db.rawQuery(
            "SELECT MIN(next_attempt_at) AS due FROM $table WHERE owner_user_id=? AND queue_state='pending'",
            [account],
          );
          final due = rows.single['due'] as int?;
          if (due != null) {
            final wait = (due - DateTime.now().millisecondsSinceEpoch).clamp(
              0,
              3600000,
            );
            _wake[table] = Timer(
              Duration(milliseconds: wait),
              () => unawaited(run(table, execute)),
            );
          }
        }
        if (_requested.remove(table)) {
          _wake.remove(table)?.cancel();
          _wake[table] = Timer(
            Duration.zero,
            () => unawaited(run(table, execute)),
          );
        }
      } finally {
        _busy.remove(table);
      }
    }
    return completed;
  }

  @visibleForTesting
  static void cancelWakeups() {
    for (final timer in _wake.values) {
      timer.cancel();
    }
    _wake.clear();
    _requested.clear();
  }
}
