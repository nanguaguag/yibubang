// 内存 SQLite 调用真实后端函数；不访问线上账号或 D1。
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const require = createRequire(new URL('../../../backend/package.json', import.meta.url));
const ts = require('typescript');
const source = ts.transpileModule(readFileSync(new URL('../../../backend/src/sync_v2.ts', import.meta.url), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
}).outputText;
const { pushMutations, pullChanges } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
function fixture() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../../../backend/schema.sql', import.meta.url), 'utf8'));
  const db = {
    prepare(sql) {
      const stmt = sqlite.prepare(sql);
      return { bind(...args) { return {
        run: async () => stmt.run(...args), first: async () => stmt.get(...args),
        all: async () => ({ results: stmt.all(...args) }),
      }; } };
    },
    async batch(statements) {
      sqlite.exec('BEGIN');
      try { const result = []; for (const s of statements) result.push(await s.run()); sqlite.exec('COMMIT'); return result; }
      catch (e) { sqlite.exec('ROLLBACK'); throw e; }
    },
  };
  return { db, sqlite };
}
const mutation = (seq, payload, kind='question') => ({ seq, stream: 'a'.repeat(32), kind, id: 'q', payload });
test('固定变更序号上界仍会返回同题上界之后的当前投影', async () => {
  const { db, sqlite } = fixture();
  try {
    await pushMutations(db, 'u', 'd', [mutation(1, { user_answer: 'A' })], 1);
    const high = sqlite.prepare('SELECT MAX(seq) AS seq FROM sync_changes').get().seq;
    await pushMutations(db, 'u', 'd', [mutation(2, { user_answer: 'B' })], 2);
    const fixed = await pullChanges(db, 'u', 0, high);
    assert.equal(fixed.high_watermark, high);
    assert.equal(fixed.next_cursor, high);
    assert.equal(fixed.pull_questions[0].user_answer, 'B');
  } finally { sqlite.close(); }
});
test('逻辑事件存在多行写入，重复确认跳过写入', async () => {
  const { db, sqlite } = fixture();
  try {
    const total = () => sqlite.prepare('SELECT total_changes() AS n').get().n;
    const delta = async (m) => { const before = total(); await pushMutations(db, 'u', 'd', [m], 1); return total() - before; };
    const first = await delta(mutation(1, { user_answer: 'A' }));
    const update = await delta(mutation(2, { user_answer: 'B' }));
    const activity = await delta(mutation(3, { timestamp: 1, is_right: '1' }, 'activity'));
    const duplicate = await delta(mutation(3, { timestamp: 1, is_right: '1' }, 'activity'));
    assert.ok(first > 1 && update > 1 && activity > 1);
    assert.equal(duplicate, 0);
    console.log(`AUDIT_WRITE_CHANGES first_question=${first} question_update=${update} activity=${activity} duplicate=${duplicate}; SQLite total_changes 非 D1 rows_written`);
  } finally { sqlite.close(); }
});
