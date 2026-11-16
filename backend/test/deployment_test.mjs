import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const schema = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const legacySchema = readFileSync(new URL('./fixtures/schema_v1.sql', import.meta.url), 'utf8');
const asModule = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`;
const syncUrl = asModule(readFileSync(new URL('../src/sync_v2.ts', import.meta.url), 'utf8'));
const { pullChanges } = await import(syncUrl);
const index = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8')
  .replace("'./sync_v2'", JSON.stringify(syncUrl))
  .replace("'hono'", JSON.stringify(import.meta.resolve('hono')))
  .replace("'hono/cors'", JSON.stringify(import.meta.resolve('hono/cors')));
const { default: app } = await import(asModule(index));

function adapter(sqlite) {
  return {
    prepare(sql) {
      const stmt = sqlite.prepare(sql);
      return { bind(...args) { return {
        run: async () => stmt.run(...args),
        first: async () => stmt.get(...args),
        all: async () => ({ results: stmt.all(...args) }),
      }; } };
    },
    async batch(statements) {
      sqlite.exec('BEGIN');
      try {
        const result = [];
        for (const statement of statements) result.push(await statement.run());
        sqlite.exec('COMMIT');
        return result;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
  };
}

test('线上v1结构升级保留账号及20850条历史数据，重复迁移零写入并可完整分页', async () => {
  const sqlite = new DatabaseSync(':memory:');
  try {
    sqlite.exec(legacySchema);
    sqlite.exec("INSERT INTO users VALUES('u','TEST-PASSPHRASE',1,1),('other',NULL,1,1)");
    sqlite.exec("INSERT INTO devices VALUES('d','u','Test','test-token',1,1)");
    sqlite.exec("INSERT INTO pairing_codes VALUES('123456','u','d',999999,0)");
    sqlite.exec('BEGIN');
    const q = sqlite.prepare('INSERT INTO sync_questions(user_id,question_id,user_answer,updated_at) VALUES(?,?,?,?)');
    const a = sqlite.prepare('INSERT INTO sync_activities(user_id,id,timestamp,created_at) VALUES(?,?,?,?)');
    for (let i = 0; i < 10441; i++) q.run('u', `q${i}`, 'A', 1);
    for (let i = 0; i < 10409; i++) a.run('u', `a${i}`, 1, 1);
    q.run('other', 'q0', 'B', 1);
    sqlite.exec('COMMIT');
    const snapshot = () => ['users', 'devices', 'pairing_codes', 'sync_questions', 'sync_activities']
      .map(table => sqlite.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all());
    const before = snapshot();
    sqlite.exec(schema);
    assert.deepEqual(snapshot(), before);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_changes').get().n, 20851);
    const changes = sqlite.prepare('SELECT total_changes() AS n').get().n;
    sqlite.exec(schema);
    assert.equal(sqlite.prepare('SELECT total_changes() AS n').get().n, changes);
    const db = adapter(sqlite), questions = new Set(), activities = new Set();
    let cursor = 0, high, page;
    do {
      page = await pullChanges(db, 'u', cursor, high);
      cursor = page.next_cursor; high = page.high_watermark;
      page.pull_questions.forEach(q => questions.add(q.id));
      page.pull_activities.forEach(a => activities.add(a.id));
    } while (page.has_more);
    assert.equal(questions.size, 10441); assert.equal(activities.size, 10409);
    a.run('u', 'late', 0, 0);
    assert.equal((await pullChanges(db, 'u', cursor)).pull_activities[0].id, 'late');
    assert.equal(sqlite.prepare('PRAGMA quick_check').get().quick_check, 'ok');
    assert.deepEqual(sqlite.prepare('PRAGMA foreign_key_check').all(), []);
  } finally { sqlite.close(); }
});

test('两个健康入口明确声明协议v2且不查询数据库', async () => {
  const DB = { prepare() { assert.fail('Health endpoint must not query D1'); } };
  for (const path of ['/', '/api/health']) {
    const response = await app.request(path, {}, { DB });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.protocol, 2); assert.equal(body.status, 'ok');
    if (path === '/') assert.equal(body.version, '2.0.0');
  }
});

test('同步路由保持鉴权，旧协议明确426，v2空同步有精确ACK且零写入', async () => {
  const sqlite = new DatabaseSync(':memory:');
  try {
    sqlite.exec(schema);
    sqlite.exec("INSERT INTO users VALUES('u','TEST-PASSPHRASE',1,1)");
    sqlite.exec("INSERT INTO devices VALUES('d','u','Test','test-token',1,1)");
    const DB = adapter(sqlite);
    const request = (body, authorized = true) => app.request('/api/sync', {
      method: 'POST', headers: { 'Content-Type': 'application/json',
        ...(authorized ? { Authorization: 'Bearer test-token' } : {}) },
      body: JSON.stringify(body),
    }, { DB });
    assert.equal((await request({ protocol: 2 }, false)).status, 401);
    assert.equal((await request({ protocol: 1 })).status, 426);
    const before = sqlite.prepare('SELECT total_changes() AS n').get().n;
    const response = await request({ protocol: 2, mutations: [], pull_cursor: 0 });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.code, 0); assert.equal(body.data.protocol, 2);
    assert.deepEqual(body.data.accepted_seqs, []);
    assert.equal(body.data.has_more, false);
    assert.equal(sqlite.prepare('SELECT total_changes() AS n').get().n, before);
  } finally { sqlite.close(); }
});
