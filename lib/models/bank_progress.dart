class BankProgress {
  final String stage;
  final String chapter;
  final int completed;
  final int total;
  final int questions;
  final int expectedQuestions;
  final bool finished;

  const BankProgress({
    required this.stage,
    this.chapter = '',
    this.completed = 0,
    this.total = 0,
    this.questions = 0,
    this.expectedQuestions = 0,
    this.finished = false,
  });

  double? get fraction => finished ? 1 : total == 0 ? null : (completed / total).clamp(0.0, 0.98);
}

class BankTaskCancelled implements Exception {}

class BankTaskCancellation {
  bool cancelled = false;
  void check() {
    if (cancelled) throw BankTaskCancelled();
  }
}
