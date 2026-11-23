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
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudPullCursor(owner TEXT PRIMARY KEY, cursor INTEGER NOT NULL DEFAULT 0)',
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
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudDeletedActivities(id TEXT PRIMARY KEY)',
    );
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_activity_no_resurrection BEFORE INSERT ON Activities
      WHEN EXISTS(SELECT 1 FROM CloudDeletedActivities WHERE id=NEW.id)
      BEGIN SELECT RAISE(IGNORE); END""",
    );
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_activity_delete AFTER DELETE ON Activities
      BEGIN
        INSERT OR IGNORE INTO CloudDeletedActivities(id) VALUES(OLD.id);
        DELETE FROM CloudOutbox WHERE kind='activity' AND entity_id=OLD.id;
        INSERT INTO CloudOutbox(owner,kind,entity_id)
          SELECT owner,'activity_delete',OLD.id FROM CloudSyncContext WHERE id=1 AND applying=0 AND OLD.is_right IN ('0','1');
      END""",
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
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudDeletedFlashcards(id TEXT PRIMARY KEY)',
    );
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_flashcard_no_resurrection BEFORE INSERT ON CustomFlashcards
      WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=1 AND EXISTS(SELECT 1 FROM CloudDeletedFlashcards WHERE id=NEW.id)
      BEGIN SELECT RAISE(IGNORE); END""",
    );
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_flashcard_delete AFTER DELETE ON CustomFlashcards
      BEGIN
        INSERT OR IGNORE INTO CloudDeletedFlashcards(id) VALUES(OLD.id);
        DELETE FROM CloudOutbox WHERE kind='flashcard' AND entity_id=OLD.id;
        INSERT INTO CloudOutbox(owner,kind,entity_id)
          SELECT owner,'flashcard_delete',OLD.id FROM CloudSyncContext WHERE id=1 AND applying=0;
      END""",
    );
    for (final event in ['INSERT', 'UPDATE']) {
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS cloud_flashcard_${event.toLowerCase()}
        AFTER $event ON CustomFlashcards
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0
        BEGIN
          DELETE FROM CloudOutbox WHERE kind='flashcard' AND entity_id=NEW.id AND owner=(SELECT owner FROM CloudSyncContext WHERE id=1);
          INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
          SELECT owner, 'flashcard', NEW.id, NEW.updated_at FROM CloudSyncContext WHERE id=1;
        END''',
      );
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS cloud_spaced_item_${event.toLowerCase()}
        AFTER $event ON SpacedReviewItem
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0 AND (NEW.state != 0 OR NEW.reps > 0)
        BEGIN
          DELETE FROM CloudOutbox WHERE kind='spaced_item' AND entity_id=NEW.item_id AND owner=(SELECT owner FROM CloudSyncContext WHERE id=1);
          INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
          SELECT owner, 'spaced_item', NEW.item_id, NEW.last_review_at FROM CloudSyncContext WHERE id=1;
        END''',
      );
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS cloud_review_plan_${event.toLowerCase()}
        AFTER $event ON ReviewPlans
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0
        BEGIN
          DELETE FROM CloudOutbox WHERE kind='review_plan' AND entity_id=NEW.id AND owner=(SELECT owner FROM CloudSyncContext WHERE id=1);
          INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
          SELECT owner, 'review_plan', NEW.id, NEW.updated_at FROM CloudSyncContext WHERE id=1;
        END''',
      );
    }
    final noteCols = (await db.rawQuery("PRAGMA table_info('Notes')"))
        .map((r) => r['name'] as String)
        .toSet();
    if (noteCols.isNotEmpty) {
      final noteUpdatedAtExpr = noteCols.contains('updated_at')
          ? 'NEW.updated_at'
          : (noteCols.contains('timestamp') ? 'NEW.timestamp' : '0');
      for (final event in ['INSERT', 'UPDATE']) {
        await db.execute(
          '''CREATE TRIGGER IF NOT EXISTS cloud_note_${event.toLowerCase()}
          AFTER $event ON Notes
          WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0
          BEGIN
            DELETE FROM CloudOutbox WHERE kind='note' AND entity_id=NEW.id AND owner=(SELECT owner FROM CloudSyncContext WHERE id=1);
            INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
            SELECT owner, 'note', NEW.id, $noteUpdatedAtExpr FROM CloudSyncContext WHERE id=1;
          END''',
        );
      }
      await db.execute(
        'CREATE TABLE IF NOT EXISTS CloudDeletedNotes(id TEXT PRIMARY KEY)',
      );
      await db.execute(
        """CREATE TRIGGER IF NOT EXISTS cloud_note_no_resurrection BEFORE INSERT ON Notes
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=1 AND EXISTS(SELECT 1 FROM CloudDeletedNotes WHERE id=NEW.id)
        BEGIN SELECT RAISE(IGNORE); END""",
      );
      await db.execute(
        """CREATE TRIGGER IF NOT EXISTS cloud_note_delete AFTER DELETE ON Notes
        BEGIN
          INSERT OR IGNORE INTO CloudDeletedNotes(id) VALUES(OLD.id);
          DELETE FROM CloudOutbox WHERE kind='note' AND entity_id=OLD.id;
          INSERT INTO CloudOutbox(owner,kind,entity_id)
            SELECT owner,'note_delete',OLD.id FROM CloudSyncContext WHERE id=1 AND applying=0;
        END""",
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SavedComments (
        id TEXT PRIMARY KEY,
        comment_id TEXT NOT NULL,
        question_id TEXT NOT NULL,
        category TEXT NOT NULL,
        user_id TEXT NOT NULL DEFAULT '',
        nickname TEXT NOT NULL DEFAULT '',
        avatar TEXT NOT NULL DEFAULT '',
        school TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        praise_num INTEGER NOT NULL DEFAULT 0,
        oppose_num INTEGER NOT NULL DEFAULT 0,
        replies INTEGER NOT NULL DEFAULT 0,
        floor_num TEXT NOT NULL DEFAULT '1',
        ctime TEXT NOT NULL DEFAULT '',
        img_watermark TEXT NOT NULL DEFAULT '',
        reply_json TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_comments_question_cat ON SavedComments(question_id, category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_comments_cat_time ON SavedComments(category, timestamp DESC)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS CloudDeletedSavedComments(id TEXT PRIMARY KEY)',
    );
    for (final event in ['INSERT', 'UPDATE']) {
      await db.execute(
        '''CREATE TRIGGER IF NOT EXISTS cloud_saved_comment_${event.toLowerCase()}
        AFTER $event ON SavedComments
        WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=0
        BEGIN
          DELETE FROM CloudOutbox WHERE kind='saved_comment' AND entity_id=NEW.id AND owner=(SELECT owner FROM CloudSyncContext WHERE id=1);
          INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
          SELECT owner, 'saved_comment', NEW.id, NEW.updated_at FROM CloudSyncContext WHERE id=1;
        END''',
      );
    }
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_saved_comment_no_resurrection BEFORE INSERT ON SavedComments
      WHEN (SELECT applying FROM CloudSyncContext WHERE id=1)=1 AND EXISTS(SELECT 1 FROM CloudDeletedSavedComments WHERE id=NEW.id)
      BEGIN SELECT RAISE(IGNORE); END""",
    );
    await db.execute(
      """CREATE TRIGGER IF NOT EXISTS cloud_saved_comment_delete AFTER DELETE ON SavedComments
      BEGIN
        INSERT OR IGNORE INTO CloudDeletedSavedComments(id) VALUES(OLD.id);
        DELETE FROM CloudOutbox WHERE kind='saved_comment' AND entity_id=OLD.id;
        INSERT INTO CloudOutbox(owner,kind,entity_id)
          SELECT owner,'saved_comment_delete',OLD.id FROM CloudSyncContext WHERE id=1 AND applying=0;
      END""",
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
    // 增量补齐本地已有但尚未进入过 Outbox 的笔记与归纳评论（兼容老版本已绑定账号升级后首次同步）
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
      SELECT ?, 'note', id, updated_at FROM Notes n
      WHERE NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='note' AND o.entity_id=n.id)''',
      [owner, owner],
    );
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
      SELECT ?, 'saved_comment', id, updated_at FROM SavedComments sc
      WHERE NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='saved_comment' AND o.entity_id=sc.id)''',
      [owner, owner],
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
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
      SELECT ?, 'flashcard', id, updated_at FROM CustomFlashcards f
      WHERE NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='flashcard' AND o.entity_id=f.id)''',
      [owner, owner],
    );
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
      SELECT ?, 'spaced_item', item_id, last_review_at FROM SpacedReviewItem s WHERE state != 0
      AND NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='spaced_item' AND o.entity_id=s.item_id)''',
      [owner, owner],
    );
    await tx.rawInsert(
      '''INSERT INTO CloudOutbox(owner, kind, entity_id, updated_at)
      SELECT ?, 'review_plan', id, updated_at FROM ReviewPlans p
      WHERE NOT EXISTS (SELECT 1 FROM CloudOutbox o WHERE o.owner=? AND o.kind='review_plan' AND o.entity_id=p.id)''',
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
    int through, {
    int limit = 500,
  }) => db.query(
    'CloudOutbox',
    where: 'owner=? AND seq>? AND seq<=?',
    whereArgs: [owner, after, through],
    orderBy: 'seq',
    limit: limit,
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
    } else if (row['kind'] == 'activity_delete' ||
        row['kind'] == 'flashcard_delete' ||
        row['kind'] == 'note_delete' ||
        row['kind'] == 'saved_comment_delete') {
      // 不可变实体ID的删除意图无需读取已删除实体。
    } else if (row['kind'] == 'note') {
      final rows = await db.query(
        'Notes',
        where: 'id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isNotEmpty) payload.addAll(rows.single);
    } else if (row['kind'] == 'saved_comment') {
      final rows = await db.query(
        'SavedComments',
        where: 'id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isNotEmpty) payload.addAll(rows.single);
    } else if (row['kind'] == 'flashcard') {
      final rows = await db.query(
        'CustomFlashcards',
        where: 'id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isNotEmpty) payload.addAll(rows.single);
    } else if (row['kind'] == 'spaced_item') {
      final rows = await db.query(
        'SpacedReviewItem',
        where: 'item_id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isNotEmpty) payload.addAll(rows.single);
    } else if (row['kind'] == 'review_plan') {
      final rows = await db.query(
        'ReviewPlans',
        where: 'id=?',
        whereArgs: [row['entity_id']],
      );
      if (rows.isNotEmpty) payload.addAll(rows.single);
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
      for (final id in (data['pull_deleted_activities'] as List? ?? const [])) {
        if (id is! String || id.isEmpty) {
          throw const FormatException('云端流水删除缺少id');
        }
        await tx.insert('CloudDeletedActivities', {
          'id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await tx.delete(
          'CloudOutbox',
          where: "kind='activity' AND entity_id=?",
          whereArgs: [id],
        );
        await tx.delete('Activities', where: 'id=?', whereArgs: [id]);
      }
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
      for (final id in (data['pull_deleted_flashcards'] as List? ?? const [])) {
        if (id is! String || id.isEmpty) continue;
        await tx.insert(
          'CloudDeletedFlashcards',
          {'id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await tx.delete(
          'CloudOutbox',
          where: "kind='flashcard' AND entity_id=?",
          whereArgs: [id],
        );
        await tx.delete('CustomFlashcards', where: 'id=?', whereArgs: [id]);
      }
      for (final value in (data['pull_flashcards'] as List? ?? const [])) {
        final fc = Map<String, dynamic>.from(value as Map);
        final id = fc['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await tx.insert(
          'CustomFlashcards',
          fc,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final value in (data['pull_spaced_items'] as List? ?? const [])) {
        final item = Map<String, dynamic>.from(value as Map);
        final itemId = item['item_id']?.toString();
        if (itemId == null || itemId.isEmpty) continue;
        await tx.insert(
          'SpacedReviewItem',
          item,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final value in (data['pull_review_plans'] as List? ?? const [])) {
        final plan = Map<String, dynamic>.from(value as Map);
        final planId = plan['id']?.toString();
        if (planId == null || planId.isEmpty) continue;
        await tx.insert(
          'ReviewPlans',
          plan,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final id in (data['pull_deleted_notes'] as List? ?? const [])) {
        if (id is! String || id.isEmpty) continue;
        await tx.insert(
          'CloudDeletedNotes',
          {'id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await tx.delete(
          'CloudOutbox',
          where: "kind='note' AND entity_id=?",
          whereArgs: [id],
        );
        await tx.delete('Notes', where: 'id=?', whereArgs: [id]);
      }
      for (final value in (data['pull_notes'] as List? ?? const [])) {
        final note = Map<String, dynamic>.from(value as Map);
        final noteId = note['id']?.toString();
        final qId = note['question_id']?.toString();
        if (noteId == null || noteId.isEmpty || qId == null || qId.isEmpty) {
          continue;
        }
        await tx.insert(
          'Question',
          {'id': qId, 'chapter_id': '', 'chapter_parent_id': ''},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final localRows = await tx.query(
          'Notes',
          columns: ['updated_at', 'sync_status', 'remote_id'],
          where: 'id=?',
          whereArgs: [noteId],
          limit: 1,
        );
        final remoteUpdated = (note['updated_at'] as num?)?.toInt() ?? 0;
        if (localRows.isNotEmpty) {
          final localUpdated =
              (localRows.first['updated_at'] as num?)?.toInt() ?? 0;
          if (localUpdated > remoteUpdated) continue;
        }
        await tx.insert(
          'Notes',
          {
            'id': noteId,
            'remote_id':
                note['remote_id'] ??
                (localRows.isEmpty ? null : localRows.first['remote_id']),
            'question_id': qId,
            'content': note['content']?.toString() ?? '',
            'imgs': note['imgs']?.toString() ?? '[]',
            'timestamp': (note['timestamp'] as num?)?.toInt() ?? remoteUpdated,
            'updated_at': remoteUpdated,
            'sync_status': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final id in (data['pull_deleted_saved_comments'] as List? ?? const [])) {
        if (id is! String || id.isEmpty) continue;
        await tx.insert(
          'CloudDeletedSavedComments',
          {'id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await tx.delete(
          'CloudOutbox',
          where: "kind='saved_comment' AND entity_id=?",
          whereArgs: [id],
        );
        await tx.delete('SavedComments', where: 'id=?', whereArgs: [id]);
      }
      for (final value in (data['pull_saved_comments'] as List? ?? const [])) {
        final sc = Map<String, dynamic>.from(value as Map);
        final scId = sc['id']?.toString();
        final qId = sc['question_id']?.toString();
        if (scId == null || scId.isEmpty || qId == null || qId.isEmpty) {
          continue;
        }
        await tx.insert(
          'Question',
          {'id': qId, 'chapter_id': '', 'chapter_parent_id': ''},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final localRows = await tx.query(
          'SavedComments',
          columns: ['updated_at'],
          where: 'id=?',
          whereArgs: [scId],
          limit: 1,
        );
        final remoteUpdated = (sc['updated_at'] as num?)?.toInt() ?? 0;
        if (localRows.isNotEmpty) {
          final localUpdated =
              (localRows.first['updated_at'] as num?)?.toInt() ?? 0;
          if (localUpdated > remoteUpdated) continue;
        }
        await tx.insert(
          'SavedComments',
          {
            'id': scId,
            'comment_id': sc['comment_id']?.toString() ?? '',
            'question_id': qId,
            'category': sc['category']?.toString() ?? 'praise',
            'user_id': sc['user_id']?.toString() ?? '',
            'nickname': sc['nickname']?.toString() ?? '',
            'avatar': sc['avatar']?.toString() ?? '',
            'school': sc['school']?.toString() ?? '',
            'content': sc['content']?.toString() ?? '',
            'praise_num': (sc['praise_num'] as num?)?.toInt() ?? 0,
            'oppose_num': (sc['oppose_num'] as num?)?.toInt() ?? 0,
            'replies': (sc['replies'] as num?)?.toInt() ?? 0,
            'floor_num': sc['floor_num']?.toString() ?? '1',
            'ctime': sc['ctime']?.toString() ?? '',
            'img_watermark': sc['img_watermark']?.toString() ?? '',
            'reply_json': sc['reply_json']?.toString() ?? '[]',
            'timestamp': (sc['timestamp'] as num?)?.toInt() ?? remoteUpdated,
            'updated_at': remoteUpdated,
            'sync_status': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
