import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/question_bank_file_service.dart';

/// Cancellation is allowed until atomic installation starts. A cancelled
/// transfer never publishes an incomplete package or changes a live bank.
class BankDownloadTask extends ChangeNotifier {
  bool _cancelled = false;
  final _callbacks = <VoidCallback>{};
  String stage = '准备下载';
  int received = 0;
  int? total;
  bool installing = false, finished = false;
  bool get cancelled => _cancelled;
  bool get canCancel => !installing && !finished && !cancelled;
  double? get progress =>
      total != null && total! > 0 ? (received / total!).clamp(0.0, 1.0) : null;
  void cancel() {
    if (!canCancel) return;
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    stage = '已取消';
    notifyListeners();
  }

  void checkCancelled() {
    if (cancelled) throw BankImportCancelled();
  }

  Future<T> wait<T>(Future<T> operation) async {
    final result = Completer<T>();
    void cancel() {
      if (!result.isCompleted) result.completeError(BankImportCancelled());
    }

    _callbacks.add(cancel);
    if (cancelled) cancel();
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace trace) {
        if (!result.isCompleted) result.completeError(error, trace);
      },
    );
    try {
      return await result.future;
    } finally {
      _callbacks.remove(cancel);
    }
  }

  void report(String value, {int? bytes, int? size}) {
    if (cancelled || finished) return;
    stage = value;
    if (bytes != null) received = bytes;
    if (size != null) total = size;
    notifyListeners();
  }

  void beginInstallation() {
    checkCancelled();
    installing = true;
    report('正在安装');
  }

  void finish({String? error}) {
    if (finished) return;
    finished = true;
    stage = cancelled
        ? '已取消'
        : error == null
        ? '已完成'
        : '操作失败';
    notifyListeners();
  }
}
