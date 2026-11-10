import 'package:sqflite/sqflite.dart';

class ReviewEvents {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS ReviewItemTombstones(item_id TEXT PRIMARY KEY,item_type TEXT NOT NULL)",
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS ReviewEvents(
      id TEXT PRIMARY KEY, item_id TEXT NOT NULL, plan_id TEXT,
      kind TEXT NOT NULL, was_new INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0, rating INTEGER,
      timestamp INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_review_events_day ON ReviewEvents(plan_id,timestamp,item_id)',
    );
  }

  /// 仅旧复习入口用秒；真实作答及已转换事件保持毫秒，不进行全表倍乘。
  static Map<String, dynamic> normalizeActivity(Map<String, dynamic> row) {
    const titles = {
      '记忆曲线复习': 'ReviewAnswer',
      '记忆卡片复习': 'ReviewMemory',
      '闪卡复习': 'FlashcardReview',
    };
    final title = titles[row['title']];
    if (title == null) return row;
    return {
      ...row,
      'title': title,
      'duration': ((row['duration'] as num?)?.toInt() ?? 0) * 1000,
    };
  }

  static Future<void> migrateLegacyActivities(DatabaseExecutor tx) async {
    for (final entry in {
      '记忆曲线复习': 'ReviewAnswer',
      '记忆卡片复习': 'ReviewMemory',
      '闪卡复习': 'FlashcardReview',
    }.entries) {
      await tx.rawUpdate(
        'UPDATE Activities SET duration=COALESCE(duration,0)*1000,title=? WHERE title=?',
        [entry.value, entry.key],
      );
    }
  }
}
