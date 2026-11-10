import 'review_events.dart';
import 'package:sqflite/sqflite.dart';

/// 用户库事务内捕获字段变更；序号与设备时钟无关，下载合并不会再次入队。
class CloudOutbox {
  static const fields = <String, int>{
    'chapter_id': 1,
    'chapter_parent_id': 2,
    'cut_question': 4,
    'user_answer': 8,
    'status': 16,
    'collection': 32,
  };

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS CloudSyncContext (id INTEGER PRIMARY KEY, owner TEXT NOT NULL DEFAULT '', stream TEXT NOT NULL, applying INTEGER NOT NULL DEFAULT 0)",
    );
    await db.execute(
      'INSERT OR IGNORE INTO CloudSyncContext(id, stream) VALUES (1, lower(hex(randomblob(16))))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudSyncAccounts (owner TEXT PRIMARY KEY)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS CloudOutbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL,
      kind TEXT NOT NULL, entity_id TEXT NOT NULL, mask INTEGER NOT NULL DEFAULT 0,
      chapter_id TEXT, chapter_parent_id TEXT, cut_question TEXT,
      user_answer TEXT, status INTEGER, collection INTEGER, updated_at INTEGER
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_outbox_owner ON CloudOutbox(owner, seq)',
    );
    final names = fields.keys.join(', ');
    final values = fields.keys.map((f) => 'NEW.$f').join(', ');
    final changed = fields.entries
        .map(
          (e) =>
              '(CASE WHEN NEW.${e.key} IS NOT OLD.${e.key} THEN ${e.value} ELSE 0 END)',
        )
        .join(' + ');
    for (final event in ['INSERT', 'UPDATE']) {
      final initial = fields.entries
          .map(
            (e) =>
                "(CASE WHEN NEW.${e.key} IS NOT ${e.key == 'cut_question'
                    ? "'0'"
                    : e.key == 'status' || e.key == 'collection'
                    ? '0'
                    : e.key == 'user_answer'
                    ? "''"
                    : 'NULL'} THEN ${e.value} ELSE 0 END)",
          )
          .join(' + ');
      final mask = event == 'INSERT' ? initial : changed;
      final condition = event == 'INSERT'
          ? "(NEW.updated_at > 0 OR NEW.status != 0 OR NEW.collection != 0 OR NEW.cut_question = '1' OR COALESCE(NEW.user_answer, '') != '')"
          : '($changed) != 0';
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS cloud_question_${event.toLowerCase()}
        AFTER $event ON Question
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0 AND $condition
        BEGIN
          INSERT INTO CloudOutbox(owner, kind, entity_id, mask, $names, updated_at)
          SELECT owner, 'question', NEW.id, $mask, $values, NEW.updated_at FROM CloudSyncContext WHERE id=1;
        END''',
      );
    }
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS cloud_activity_insert AFTER INSERT ON Activities
      WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0 AND NEW.is_right IN ('0','1')
      BEGIN
        INSERT INTO CloudOutbox(owner, kind, entity_id)
        SELECT owner, 'activity', NEW.id FROM CloudSyncContext WHERE id=1;
      END''',
    );
  }

  static Future<void> bind(Database db, String owner) => db.transaction((
    tx,
  ) async {
    await tx.update('CloudSyncContext', {'owner': owner}, where: 'id=1');
    await tx.update('CloudOutbox', {'owner': owner}, where: "owner='' ");
    final known = await tx.query(
      'CloudSyncAccounts',
      where: 'owner=?',
      whereArgs: [owner],
    );
    if (known.isNotEmpty) return;
    final names = fields.keys.join(', ');
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, mask, $names, updated_at)
      SELECT ?, 'question', id, 63, $names, updated_at FROM Question q
      WHERE (updated_at>0 OR status!=0 OR collection!=0 OR cut_question='1' OR COALESCE(user_answer,'')!='')
      AND NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='question' AND o.entity_id=q.id)''',
      [owner, owner],
    );
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id)
      SELECT ?, 'activity', id FROM Activities a WHERE is_right IN ('0','1')
      AND NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='activity' AND o.entity_id=a.id)''',
      [owner, owner],
    );
    await tx.insert('CloudSyncAccounts', {'owner': owner});
  });

  static Future<List<Map<String, Object?>>> snapshot(
    Database db,
    String owner,
  ) => db.query(
    'CloudOutbox',
    where: 'owner=?',
    whereArgs: [owner],
    orderBy: 'seq',
  );

  static Future<int> upperBound(Database db, String owner) async =>
      (await db.rawQuery(
            'SELECT COALESCE(MAX(seq),0) AS seq FROM CloudOutbox WHERE owner=?',
            [owner],
          )).single['seq']
          as int;

  static Future<List<Map<String, Object?>>> page(
    Database db,
    String owner,
    int after,
    int through,
  ) => db.query(
    'CloudOutbox',
    where: 'owner=? AND seq>? AND seq<=?',
    whereArgs: [owner, after, through],
    orderBy: 'seq',
    limit: 500,
  );

  static Future<Map<String, Object?>> mutation(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final payload = <String, Object?>{};
    if (row['kind'] == 'question') {
      final mask = row['mask'] as int;
      for (final field in fields.entries) {
        if (mask & field.value != 0) payload[field.key] = row[field.key];
      }
      payload['updated_at'] = row['updated_at'];
    } else {
      final rows = await db.query(
        'Activities',
        where: 'id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isEmpty) throw StateError('待同步流水缺失: ${row['entity_id']}');
      payload.addAll(rows.single);
    }
    final context = await db.query(
      'CloudSyncContext',
      columns: ['stream'],
      where: 'id=1',
    );
    return {
      'stream': context.single['stream'],
      'seq': row['seq'],
      'kind': row['kind'],
      'id': row['entity_id'],
      'payload': payload,
    };
  }

  static Future<void> acknowledge(
    DatabaseExecutor db,
    String owner,
    List<int> sent,
    List<dynamic> accepted,
  ) async {
    final confirmed = accepted.whereType<num>().map((n) => n.toInt()).toSet();
    if (!sent.every(confirmed.contains)) {
      throw const FormatException('云端未完整确认上传变更');
    }
    for (final seq in sent) {
      await db.delete(
        'CloudOutbox',
        where: 'owner=? AND seq=?',
        whereArgs: [owner, seq],
      );
    }
  }

  static Future<int> pullCursor(
    Database db,
    String owner, {
    bool reset = false,
  }) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudPullCursor(owner TEXT PRIMARY KEY, cursor INTEGER NOT NULL DEFAULT 0)',
    );
    if (reset) {
      await db.delete('CloudPullCursor', where: 'owner=?', whereArgs: [owner]);
    }
    final rows = await db.query(
      'CloudPullCursor',
      where: 'owner=?',
      whereArgs: [owner],
    );
    return rows.isEmpty ? 0 : rows.single['cursor'] as int;
  }

  /// 页面数据和游标同一事务；崩溃只会重放本页，不会跳过未落库数据。
  static Future<void> mergePage(
    Database db,
    String owner,
    Map<String, dynamic> data,
    int previous,
  ) async {
    final next = data['next_cursor'];
    final high = data['high_watermark'];
    if (next is! int ||
        high is! int ||
        next < previous ||
        next > high ||
        data['has_more'] is! bool ||
        (data['has_more'] == true && next == previous)) {
      throw const FormatException('云端分页游标无效');
    }
    await db.transaction((tx) async {
      await tx.update('CloudSyncContext', {'applying': 1}, where: 'id=1');
      for (final value in data['pull_activities'] as List) {
        await tx.insert(
          'Activities',
          ReviewEvents.normalizeActivity(
            Map<String, dynamic>.from(value as Map),
          ),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final value in data['pull_questions'] as List) {
        await mergeQuestion(tx, Map<String, dynamic>.from(value as Map));
      }
      await tx.insert('CloudPullCursor', {
        'owner': owner,
        'cursor': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update('CloudSyncContext', {'applying': 0}, where: 'id=1');
    });
  }

  static Future<void> mergeQuestion(
    DatabaseExecutor tx,
    Map<String, dynamic> question,
  ) async {
    final id = question['id']?.toString();
    if (id == null || id.isEmpty) throw const FormatException('云端题目缺少 id');
    await tx.rawInsert('INSERT OR IGNORE INTO Question(id) VALUES (?)', [id]);
    final pending = await tx.query(
      'CloudOutbox',
      columns: ['mask'],
      where: "kind='question' AND entity_id=?",
      whereArgs: [id],
    );
    var mask = 0;
    for (final row in pending) {
      mask |= row['mask'] as int;
    }
    final patch = <String, Object?>{};
    for (final field in fields.entries) {
      if (mask & field.value == 0 && question.containsKey(field.key)) {
        patch[field.key] = question[field.key];
      }
    }
    if (mask == 0) patch['updated_at'] = question['updated_at'] ?? 0;
    if (patch.isNotEmpty) {
      await tx.update('Question', patch, where: 'id=?', whereArgs: [id]);
    }
  }
}
