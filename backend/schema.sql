-- 医不帮 (yibubang) Cloudflare D1 增量同步数据库架构

-- 1. 用户表
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    sync_passphrase TEXT,
    created_at INTEGER NOT NULL,
    last_sync_at INTEGER NOT NULL
);

-- 2. 设备授权表
CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_token TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    last_sync_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_devices_token ON devices(device_token);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- 3. 临时配对码表 (10分钟有效期)
CREATE TABLE IF NOT EXISTS pairing_codes (
    code TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_by_device TEXT,
    expires_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_pairing_expires ON pairing_codes(expires_at);

-- 4. 作答流水明细 (Append-Only 事件溯源表)
CREATE TABLE IF NOT EXISTS sync_activities (
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    bank_id TEXT,
    question_id TEXT,
    identity_id TEXT,
    subject_id TEXT,
    chapter_id TEXT,
    is_right TEXT,
    duration INTEGER NOT NULL DEFAULT 0,
    title TEXT NOT NULL DEFAULT 'NewAnswer',
    description TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);
CREATE INDEX IF NOT EXISTS idx_sync_activities_time ON sync_activities(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_sync_activities_created ON sync_activities(user_id, created_at);

-- 5. 题目作答进度与收藏斩题状态 (LWW 状态表)
CREATE TABLE IF NOT EXISTS sync_questions (
    user_id TEXT NOT NULL,
    question_id TEXT NOT NULL,
    chapter_id TEXT,
    chapter_parent_id TEXT,
    cut_question TEXT NOT NULL DEFAULT '0',
    user_answer TEXT NOT NULL DEFAULT '',
    status INTEGER NOT NULL DEFAULT 0,
    collection INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, question_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_questions_updated ON sync_questions(user_id, updated_at);

-- 协议 v2：保留每次字段变更，按服务端提交顺序仲裁，不使用设备墙钟。
CREATE TABLE IF NOT EXISTS sync_mutations (
    revision INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL, device_id TEXT NOT NULL, stream TEXT NOT NULL,
    client_seq INTEGER NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL,
    payload TEXT NOT NULL, applied INTEGER NOT NULL DEFAULT 0,
    UNIQUE(device_id, stream, client_seq)
);
CREATE INDEX IF NOT EXISTS idx_sync_mutations_user ON sync_mutations(user_id, revision);

-- 拉取位置使用事务内触发器分配的提交序号，覆盖旧客户端历史数据。
CREATE TABLE IF NOT EXISTS sync_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
  kind TEXT NOT NULL, entity_id TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sync_changes_user ON sync_changes(user_id, seq);
CREATE TRIGGER IF NOT EXISTS sync_question_insert AFTER INSERT ON sync_questions BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'question',NEW.question_id);
END;
CREATE TRIGGER IF NOT EXISTS sync_question_update AFTER UPDATE ON sync_questions BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'question',NEW.question_id);
END;
CREATE TRIGGER IF NOT EXISTS sync_activity_insert AFTER INSERT ON sync_activities BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'activity',NEW.id);
END;
-- 集合连接回填旧数据，重复执行不写入，避免逐行扫描同账号的整个变更历史。
INSERT INTO sync_changes(user_id,kind,entity_id)
 SELECT q.user_id,'question',q.question_id FROM sync_questions q
 LEFT JOIN (SELECT DISTINCT user_id,entity_id FROM sync_changes WHERE kind='question') c
 ON c.user_id=q.user_id AND c.entity_id=q.question_id
 WHERE c.entity_id IS NULL;
INSERT INTO sync_changes(user_id,kind,entity_id)
 SELECT a.user_id,'activity',a.id FROM sync_activities a
 LEFT JOIN (SELECT DISTINCT user_id,entity_id FROM sync_changes WHERE kind='activity') c
 ON c.user_id=a.user_id AND c.entity_id=a.id
 WHERE c.entity_id IS NULL;

-- 流水ID不可变：删除墓碑永久阻止旧客户端和旧备份重放。
CREATE TABLE IF NOT EXISTS sync_deleted_activities(user_id TEXT NOT NULL,id TEXT NOT NULL,PRIMARY KEY(user_id,id));
CREATE TRIGGER IF NOT EXISTS sync_activity_tombstone AFTER INSERT ON sync_deleted_activities BEGIN
 INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'activity_delete',NEW.id);
END;
CREATE TRIGGER IF NOT EXISTS sync_activity_no_resurrection BEFORE INSERT ON sync_activities
 WHEN EXISTS(SELECT 1 FROM sync_deleted_activities WHERE user_id=NEW.user_id AND id=NEW.id)
 BEGIN SELECT RAISE(IGNORE); END;

-- 6. 自制闪卡表与删除墓碑
CREATE TABLE IF NOT EXISTS sync_flashcards (
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    question_id TEXT,
    tags TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);
CREATE INDEX IF NOT EXISTS idx_sync_flashcards_updated ON sync_flashcards(user_id, updated_at);
CREATE TRIGGER IF NOT EXISTS sync_flashcard_insert AFTER INSERT ON sync_flashcards BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'flashcard',NEW.id);
END;
CREATE TRIGGER IF NOT EXISTS sync_flashcard_update AFTER UPDATE ON sync_flashcards BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'flashcard',NEW.id);
END;

CREATE TABLE IF NOT EXISTS sync_deleted_flashcards(user_id TEXT NOT NULL, id TEXT NOT NULL, PRIMARY KEY(user_id, id));
CREATE TRIGGER IF NOT EXISTS sync_flashcard_tombstone AFTER INSERT ON sync_deleted_flashcards BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'flashcard_delete',NEW.id);
END;
CREATE TRIGGER IF NOT EXISTS sync_flashcard_no_resurrection BEFORE INSERT ON sync_flashcards
  WHEN EXISTS(SELECT 1 FROM sync_deleted_flashcards WHERE user_id=NEW.user_id AND id=NEW.id)
  BEGIN SELECT RAISE(IGNORE); END;

-- 7. 记忆曲线进度表 (SpacedReviewItem)
CREATE TABLE IF NOT EXISTS sync_spaced_items (
    user_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    plan_id TEXT NOT NULL DEFAULT '',
    item_type INTEGER NOT NULL DEFAULT 0,
    state INTEGER NOT NULL DEFAULT 0,
    step INTEGER NOT NULL DEFAULT 0,
    reps INTEGER NOT NULL DEFAULT 0,
    lapses INTEGER NOT NULL DEFAULT 0,
    difficulty REAL NOT NULL DEFAULT 0,
    stability REAL NOT NULL DEFAULT 0,
    due_date INTEGER NOT NULL DEFAULT 0,
    last_review_at INTEGER NOT NULL DEFAULT 0,
    extra TEXT,
    updated_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_spaced_items_due ON sync_spaced_items(user_id, due_date);
CREATE TRIGGER IF NOT EXISTS sync_spaced_item_insert AFTER INSERT ON sync_spaced_items BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'spaced_item',NEW.item_id);
END;
CREATE TRIGGER IF NOT EXISTS sync_spaced_item_update AFTER UPDATE ON sync_spaced_items BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'spaced_item',NEW.item_id);
END;

-- 8. 复习计划表 (ReviewPlans)
CREATE TABLE IF NOT EXISTS sync_review_plans (
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    bank_id TEXT,
    daily_new_target INTEGER NOT NULL DEFAULT 20,
    daily_review_limit INTEGER NOT NULL DEFAULT 50,
    source_types TEXT NOT NULL DEFAULT '["wrong","collected","note"]',
    covered_subjects TEXT NOT NULL DEFAULT '[]',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);
CREATE TRIGGER IF NOT EXISTS sync_review_plan_insert AFTER INSERT ON sync_review_plans BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'review_plan',NEW.id);
END;
CREATE TRIGGER IF NOT EXISTS sync_review_plan_update AFTER UPDATE ON sync_review_plans BEGIN
  INSERT INTO sync_changes(user_id,kind,entity_id) VALUES(NEW.user_id,'review_plan',NEW.id);
END;
