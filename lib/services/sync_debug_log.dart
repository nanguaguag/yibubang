import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机同步诊断。调用方只记录进度、计数和错误类型。
class SyncDebugLog extends ChangeNotifier {
  SyncDebugLog._();
  static final instance = SyncDebugLog._();
  static const enabledKey = 'sync_debug_log_enabled';
  static const _entriesKey = 'sync_debug_log_entries';
  static const maxEntries = 300;

  Future<void> _writes = Future<void>.value();

  List<String> entries(SharedPreferences prefs) =>
      prefs.getStringList(_entriesKey) ?? const [];

  Future<void> record(String message) => _write((prefs) async {
    if (prefs.getBool(enabledKey) != true) return false;
    final history = [...entries(prefs)];
    final timestamp = DateTime.now().toIso8601String().substring(0, 19);
    final line = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    history.add('$timestamp  ${line.length <= 320 ? line : line.substring(0, 320)}');
    if (history.length > maxEntries) {
      history.removeRange(0, history.length - maxEntries);
    }
    return prefs.setStringList(_entriesKey, history);
  });

  Future<void> clear() => _write((prefs) => prefs.remove(_entriesKey));

  Future<void> _write(Future<bool> Function(SharedPreferences) operation) {
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (await operation(prefs)) notifyListeners();
      } catch (_) {
        debugPrint('[sync-debug] 无法保存同步诊断日志');
      }
    });
    return _writes;
  }
}
