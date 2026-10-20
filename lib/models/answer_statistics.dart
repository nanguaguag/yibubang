import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../db/question_bank_manager.dart';
import 'question.dart';

/// 全局刷题流水变更通知，当写入新的答题记录时自增触发监听
final ValueNotifier<int> answersChangedNotifier = ValueNotifier<int>(0);

void notifyAnswersChanged() {
  answersChangedNotifier.value++;
}

/// 格式化日期为 YYYY-MM-DD 字符串作为稳定的日期键
String formatDayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// 时间段统计：某段时间内的总用时、累及作答数、正确数。
///
/// 数据来源为 user_data 的 `Activities` 表。作答判定口径与现有“课程/章节
/// 正确错误计数”一致：只统计真正提交对/错（status 1/2）的记录
/// （`is_right` 为 `'1'` 或 `'0'`），测试模式 / 撤题不计入作答数。
class PeriodStats {
  final Duration totalDuration;
  final int answeredCount;
  final int correctCount;

  const PeriodStats({
    required this.totalDuration,
    required this.answeredCount,
    required this.correctCount,
  });

  /// 正确率（0.0 ~ 1.0），无作答时返回 0。
  double get accuracy => answeredCount == 0 ? 0 : correctCount / answeredCount;
}

/// 单日聚合：给定日期内的作答数与总时长（毫秒）。
class DailyStat {
  final DateTime date;
  final int count;
  final int durationMs;

  const DailyStat({
    required this.date,
    required this.count,
    required this.durationMs,
  });
}

/// 按时间段聚合作答记录（跨题库场景也可传入 bankId 过滤）。
Future<List<Map<String, dynamic>>> _queryAnswersInRange({
  required int startMs,
  required int endMs,
  String? bankId,
  String? subjectId,
  String? chapterId,
}) async {
  final userDb = await UserDBHelper().database;
  final conditions = <String>[
    'title IN (?, ?)',
    'timestamp >= ?',
    'timestamp < ?',
    "(is_right = '0' OR is_right = '1' OR is_right = 0 OR is_right = 1)",
  ];
  // NewAnswer 为实时答题流水；Backfill 为历史数据修复补记，两者都计入统计。
  final args = <Object>['NewAnswer', 'Backfill', startMs, endMs];
  if (bankId != null) {
    conditions.add('bank_id = ?');
    args.add(bankId);
  }
  if (subjectId != null) {
    conditions.add('subject_id = ?');
    args.add(subjectId);
  }
  if (chapterId != null) {
    conditions.add('chapter_id = ?');
    args.add(chapterId);
  }
  return userDb.rawQuery(
    'SELECT timestamp, COALESCE(duration, 0) AS duration, is_right '
    'FROM Activities WHERE ${conditions.join(' AND ')}',
    args,
  );
}

/// 计算 [startMs, endMs) 时间段内的作答统计。
Future<PeriodStats> getPeriodStats({
  required int startMs,
  required int endMs,
  String? bankId,
  String? subjectId,
  String? chapterId,
}) async {
  final rows = await _queryAnswersInRange(
    startMs: startMs,
    endMs: endMs,
    bankId: bankId,
    subjectId: subjectId,
    chapterId: chapterId,
  );
  int durationMs = 0;
  int answered = 0;
  int correct = 0;
  for (final row in rows) {
    answered += 1;
    durationMs += (row['duration'] as num?)?.toInt() ?? 0;
    final ir = row['is_right'];
    if (ir == '1' || ir == 1) correct += 1;
  }
  return PeriodStats(
    totalDuration: Duration(milliseconds: durationMs),
    answeredCount: answered,
    correctCount: correct,
  );
}

/// 获取指定自然日的做题统计数据
Future<PeriodStats> getDayStats(DateTime date, {String? bankId}) {
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  return getPeriodStats(
    startMs: start.millisecondsSinceEpoch,
    endMs: end.millisecondsSinceEpoch,
    bankId: bankId,
  );
}

/// 按本地自然日聚合作答数与总时长。
///
/// 返回从 `startMs` 当天 0 点到 `endMs` 当天 24 点之间每天的记录，不足的
/// 日期以 count/duration 为 0 补齐，便于图表直接按序绘制。
Future<List<DailyStat>> getDailyAggregation({
  required int startMs,
  required int endMs,
  String? bankId,
  String? subjectId,
  String? chapterId,
}) async {
  final rows = await _queryAnswersInRange(
    startMs: startMs,
    endMs: endMs,
    bankId: bankId,
    subjectId: subjectId,
    chapterId: chapterId,
  );
  // 每天：count、durations 累加，使用精确的 formatDayKey 字符串作为键
  final dayData = <String, (int, int)>{};
  final dateMap = <String, DateTime>{};

  DateTime dayKey(DateTime t) => DateTime(t.year, t.month, t.day);

  for (final row in rows) {
    final ts = (row['timestamp'] as num).toInt();
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final date = dayKey(dt);
    final k = formatDayKey(date);
    dateMap[k] = date;
    final existing = dayData[k] ?? (0, 0);
    dayData[k] = (
      existing.$1 + 1,
      existing.$2 + ((row['duration'] as num?)?.toInt() ?? 0)
    );
  }

  // 补齐日期区间
  final startDay = dayKey(DateTime.fromMillisecondsSinceEpoch(startMs));
  final endDay = dayKey(DateTime.fromMillisecondsSinceEpoch(endMs));
  final result = <DailyStat>[];
  for (var d = startDay;
      !d.isAfter(endDay);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final k = formatDayKey(d);
    final data = dayData[k] ?? (0, 0);
    result.add(DailyStat(date: d, count: data.$1, durationMs: data.$2));
  }
  return result;
}

/// 针对某个章节（subjectId + chapterId）的时间段统计，用于侧边栏展示。
Future<PeriodStats> getChapterPeriodStats({
  required String subjectId,
  required String chapterId,
  required int startMs,
  required int endMs,
  String? bankId,
}) async {
  return getPeriodStats(
    startMs: startMs,
    endMs: endMs,
    bankId: bankId,
    subjectId: subjectId,
    chapterId: chapterId,
  );
}

/// 按小时聚合作答数与总时长（用于“今日”图表，返回 24 个整点桶）。
Future<List<DailyStat>> getHourlyAggregation({
  required int dayStartMs,
  String? bankId,
  String? subjectId,
  String? chapterId,
}) async {
  final endMs = dayStartMs + const Duration(days: 1).inMilliseconds;
  final rows = await _queryAnswersInRange(
    startMs: dayStartMs,
    endMs: endMs,
    bankId: bankId,
    subjectId: subjectId,
    chapterId: chapterId,
  );
  final hourData = List<(int, int)>.filled(24, (0, 0));
  for (final row in rows) {
    final ts = (row['timestamp'] as num).toInt();
    final hour = DateTime.fromMillisecondsSinceEpoch(ts).hour;
    final existing = hourData[hour];
    hourData[hour] = (
      existing.$1 + 1,
      existing.$2 + ((row['duration'] as num?)?.toInt() ?? 0)
    );
  }
  final start = DateTime.fromMillisecondsSinceEpoch(dayStartMs);
  return List.generate(24, (i) {
    final data = hourData[i];
    return DailyStat(
      date: DateTime(start.year, start.month, start.day, i),
      count: data.$1,
      durationMs: data.$2,
    );
  });
}

/// 读取当前激活题库的 bankId。
Future<String> activeBankId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('activeBankId') ?? 'dental_final';
}

// ---------------------------------------------------------------------------
// 时间区间工具（本地时区）
// ---------------------------------------------------------------------------

/// 今天 0 点（毫秒）。
int todayStartMs(DateTime now) =>
    DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

/// 明天 0 点（毫秒）。
int tomorrowStartMs(DateTime now) =>
    todayStartMs(now) + const Duration(days: 1).inMilliseconds;

/// 本周一 0 点（毫秒）。
int weekStartMs(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return monday.millisecondsSinceEpoch;
}

/// 下周一 0 点（毫秒）。
int nextWeekStartMs(DateTime now) =>
    weekStartMs(now) + const Duration(days: 7).inMilliseconds;

/// 本月 1 号 0 点（毫秒）。
int monthStartMs(DateTime now) =>
    DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

/// 下月 1 号 0 点（毫秒）。
int nextMonthStartMs(DateTime now) =>
    DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch;

/// 今天 0 点（本地天，用于小时粒度）。当 `now` 是 6 点时，
/// 返回从今天 0 点开始到 `now` 当天的完整 24 小时桶。
int todayDayMs(DateTime now) => todayStartMs(now);

/// 作答记录明细条目
class AnsweredRecordItem {
  final String activityId;
  final String questionId;
  final int timestamp;
  final bool isRight;
  final int durationMs;
  final String userAnswer;
  final String bankId;
  final String? subjectId;
  final String? chapterId;
  final Question? question;
  final UserQuestion? userQuestion;

  const AnsweredRecordItem({
    required this.activityId,
    required this.questionId,
    required this.timestamp,
    required this.isRight,
    required this.durationMs,
    required this.userAnswer,
    required this.bankId,
    this.subjectId,
    this.chapterId,
    this.question,
    this.userQuestion,
  });
}

/// 查询指定时间范围内的所有刷题记录及题目对象
Future<List<AnsweredRecordItem>> getAnsweredRecordsInRange({
  required int startMs,
  required int endMs,
  String? bankId,
}) async {
  final userDb = await UserDBHelper().database;
  final conditions = <String>[
    'title IN (?, ?)',
    'timestamp >= ?',
    'timestamp < ?',
    "(is_right = '0' OR is_right = '1' OR is_right = 0 OR is_right = 1)",
  ];
  final args = <Object>['NewAnswer', 'Backfill', startMs, endMs];
  if (bankId != null) {
    conditions.add('bank_id = ?');
    args.add(bankId);
  }

  final rows = await userDb.rawQuery(
    'SELECT * FROM Activities WHERE ${conditions.join(' AND ')} ORDER BY timestamp DESC',
    args,
  );
  if (rows.isEmpty) return <AnsweredRecordItem>[];

  final questionIds = rows
      .map((r) => r['question_id']?.toString())
      .whereType<String>()
      .toSet()
      .toList();

  final userQuestionsMap = <String, UserQuestion>{};
  if (questionIds.isNotEmpty) {
    final placeholders = List.filled(questionIds.length, '?').join(',');
    final uqRows = await userDb.rawQuery(
      'SELECT * FROM Question WHERE id IN ($placeholders)',
      questionIds,
    );
    for (final r in uqRows) {
      final uq = UserQuestion.fromMap(r);
      userQuestionsMap[uq.id] = uq;
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final currentBankId = prefs.getString('activeBankId') ?? 'dental_final';
  final questionMap = <String, Question>{};

  final bankToQids = <String, Set<String>>{};
  for (final row in rows) {
    final qid = row['question_id']?.toString();
    if (qid == null || qid.isEmpty) continue;
    final bId = (row['bank_id'] as String?)?.isNotEmpty == true
        ? (row['bank_id'] as String)
        : currentBankId;
    bankToQids.putIfAbsent(bId, () => <String>{}).add(qid);
  }

  final dbManager = QuestionBankDatabaseManager();
  for (final entry in bankToQids.entries) {
    final bId = entry.key;
    final qids = entry.value.toList();
    try {
      final qDb = await dbManager.openBank(bId);
      final placeholders = List.filled(qids.length, '?').join(',');
      final qRows = await qDb.rawQuery(
        'SELECT * FROM Question WHERE id IN ($placeholders)',
        qids,
      );
      for (final qr in qRows) {
        final q = Question.fromMap(qr);
        questionMap[q.id] = q;
      }
    } catch (_) {}
  }

  final missingQids =
      questionIds.where((id) => !questionMap.containsKey(id)).toList();
  if (missingQids.isNotEmpty) {
    try {
      final qDb = await dbManager.openBank(currentBankId);
      final placeholders = List.filled(missingQids.length, '?').join(',');
      final qRows = await qDb.rawQuery(
        'SELECT * FROM Question WHERE id IN ($placeholders)',
        missingQids,
      );
      for (final qr in qRows) {
        final q = Question.fromMap(qr);
        questionMap[q.id] = q;
      }
    } catch (_) {}
  }

  final result = <AnsweredRecordItem>[];
  for (final row in rows) {
    final qid = row['question_id']?.toString() ?? '';
    final isRight = row['is_right'] == '1' || row['is_right'] == 1;
    final duration = (row['duration'] as num?)?.toInt() ?? 0;
    final timestamp = (row['timestamp'] as num).toInt();

    String userAns = '';
    try {
      final desc = row['description'] as String?;
      if (desc != null && desc.isNotEmpty) {
        final decoded = jsonDecode(desc) as Map<String, dynamic>;
        userAns = decoded['answer']?.toString() ?? '';
      }
    } catch (_) {}
    if (userAns.isEmpty && userQuestionsMap.containsKey(qid)) {
      userAns = getLastAnswer(userQuestionsMap[qid]!.userAnswer);
    }

    result.add(AnsweredRecordItem(
      activityId: row['id']?.toString() ?? '',
      questionId: qid,
      timestamp: timestamp,
      isRight: isRight,
      durationMs: duration,
      userAnswer: userAns,
      bankId: (row['bank_id'] as String?) ?? currentBankId,
      subjectId: row['subject_id'] as String?,
      chapterId: row['chapter_id'] as String?,
      question: questionMap[qid],
      userQuestion: userQuestionsMap[qid],
    ));
  }
  return result;
}
