import 'dart:async';

import 'question_bank.dart';

String bankCreationErrorMessage(Object error) {
  if (error is TimeoutException) return '请求超时，请检查网络后重试';
  if (error is StateError) return error.message;
  if (error is FormatException) return error.message;
  return error.toString();
}

enum BankCreationErrorAction { ignore, ignoreAll, terminate }

typedef BankCreationErrorHandler =
    Future<BankCreationErrorAction> Function(BankCreationIssue issue);

class BankCreationIssue {
  const BankCreationIssue({
    required this.bankName,
    required this.stage,
    required this.item,
    required this.message,
    this.code,
  });
  final String bankName, stage, item, message;
  final String? code;
}

class BankCreationSuccess {
  const BankCreationSuccess({
    required this.bankName,
    required this.stage,
    required this.item,
    this.questions = 0,
  });
  final String bankName, stage, item;
  final int questions;
}

/// One creation run can span several banks; ignore-all and results persist
/// across the selected subjects without storing any account data in a bank.
class BankCreationReport {
  final successes = <BankCreationSuccess>[];
  final failures = <BankCreationIssue>[];
  final savedBanks = <QuestionBank>[];
  final questionCounts = <String, int>{};
  bool ignoreAllErrors = false;

  int get savedQuestionCount => savedBanks.fold(
    0,
    (count, bank) => count + (questionCounts[bank.bankId] ?? 0),
  );

  Future<void> handle(
    BankCreationIssue issue,
    Object error,
    BankCreationErrorHandler? onError,
  ) async {
    failures.add(issue);
    // Noninteractive callers (smart sync / full rebuild) remain strict.
    if (onError == null) throw error;
    if (ignoreAllErrors) return;
    final action = await onError(issue);
    if (action == BankCreationErrorAction.terminate) {
      throw BankCreationTerminated();
    }
    if (action == BankCreationErrorAction.ignoreAll) ignoreAllErrors = true;
  }
}

class BankCreationTerminated implements Exception {}
