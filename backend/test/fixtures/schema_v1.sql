-- 2026-11-15 部署前线上 v1 结构快照，仅 DDL、不含账号与数据。
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_token TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    last_sync_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);
CREATE TABLE pairing_codes (
    code TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_by_device TEXT,
    expires_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE sync_activities (
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
CREATE TABLE sync_questions (
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
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    sync_passphrase TEXT,
    created_at INTEGER NOT NULL,
    last_sync_at INTEGER NOT NULL
);
CREATE INDEX idx_devices_token ON devices(device_token);
CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_pairing_expires ON pairing_codes(expires_at);
CREATE INDEX idx_sync_activities_created ON sync_activities(user_id, created_at);
CREATE INDEX idx_sync_activities_time ON sync_activities(user_id, timestamp);
CREATE INDEX idx_sync_questions_updated ON sync_questions(user_id, updated_at);
