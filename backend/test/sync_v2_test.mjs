import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const source = ts.transpileModule(readFileSync(new URL('../src/sync_v2.ts', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const { pushMutations } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
export function fixture() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
  const db = {
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
      try { const r=[]; for (const s of statements) r.push(await s.run()); sqlite.exec('COMMIT'); return r; }
      catch(e) { sqlite.exec('ROLLBACK'); throw e; }
    },
  };
  return { db, sqlite };
}
const mutation = (seq, payload, id='q') => ({seq, stream: 'a'.repeat(32), kind: 'question', id, payload});
test('慢时钟答案及独立收藏均保留，冲突历史可恢复', async () => {
  const { db, sqlite } = fixture();
  await pushMutations(db, 'u', 'a', [mutation(1,{user_answer:'A',status:1,updated_at:99999})],100);
  await pushMutations(db, 'u', 'b', [mutation(1,{collection:1,updated_at:1})],101);
  await pushMutations(db, 'u', 'a', [mutation(2,{user_answer:'B',status:2,updated_at:0})],102);
  const q=sqlite.prepare('SELECT * FROM sync_questions').get();
  assert.equal(q.user_answer,'B'); assert.equal(q.collection,1);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_mutations').get().n,3);
  sqlite.close();
});
test('ACK丢失后的重试不覆盖后续变更', async () => {
  const { db, sqlite } = fixture();
  const old=mutation(1,{user_answer:'A'});
  await pushMutations(db,'u','a',[old],100);
  await pushMutations(db,'u','a',[mutation(2,{user_answer:'B'})],101);
  assert.deepEqual(await pushMutations(db,'u','a',[old],102),[1]);
  assert.equal(sqlite.prepare('SELECT user_answer FROM sync_questions').get().user_answer,'B');
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_mutations').get().n,2);
  sqlite.close();
});
test('事件写入与投影更新同事务回滚', async () => {
  const { db, sqlite } = fixture();
  await assert.rejects(pushMutations(db,'u','a',[mutation(1,{collection:null})],100));
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_mutations').get().n,0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_questions').get().n,0);
  sqlite.close();
});
