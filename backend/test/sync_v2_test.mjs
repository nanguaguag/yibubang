import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const source = ts.transpileModule(readFileSync(new URL('../src/sync_v2.ts', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const { pushMutations, pullChanges } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
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
  sqlite.exec("CREATE TRIGGER reject_question BEFORE INSERT ON sync_questions BEGIN SELECT RAISE(ABORT, 'fixture failure'); END");
  await assert.rejects(pushMutations(db,'u','a',[mutation(1,{collection:1})],100));
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_mutations').get().n,0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_questions').get().n,0);
  sqlite.close();
});

test('10441题和10409流水全部分页恢复，相同时间戳不遗漏', async () => {
  const { db, sqlite }=fixture();
  sqlite.exec('BEGIN');
  const question=sqlite.prepare('INSERT INTO sync_questions(user_id,question_id,updated_at) VALUES(?,?,?)');
  const activity=sqlite.prepare('INSERT INTO sync_activities(user_id,id,timestamp,created_at) VALUES(?,?,?,?)');
  for(let i=0;i<10441;i++) question.run('u',`q${i}`,1);
  for(let i=0;i<10409;i++) activity.run('u',`a${i}`,1,1);
  sqlite.exec('COMMIT');
  let cursor=0, high, more=true; const qs=new Set(), acts=new Set();
  while(more) {
    const page=await pullChanges(db,'u',cursor,high);
    high=page.high_watermark; cursor=page.next_cursor; more=page.has_more;
    page.pull_questions.forEach(q=>qs.add(q.id)); page.pull_activities.forEach(a=>acts.add(a.id));
  }
  assert.equal(qs.size,10441); assert.equal(acts.size,10409);
  await pushMutations(db,'u','d',[mutation(1,{user_answer:'late',updated_at:0},'slow')],0);
  const late=await pullChanges(db,'u',cursor);
  assert.equal(late.pull_questions[0].id,'slow');
  sqlite.close();
});
test('固定快照期间新增提交留到下一轮，无关账户不进入本页', async () => {
  const {db,sqlite}=fixture();
  await pushMutations(db,'u','d',[mutation(1,{collection:1})],1);
  const first=await pullChanges(db,'u',0);
  await pushMutations(db,'u','d',[mutation(2,{collection:0},'later')],1);
  await pushMutations(db,'other','other',[mutation(1,{collection:1})],1);
  const fixed=await pullChanges(db,'u',first.next_cursor,first.high_watermark);
  assert.equal(fixed.pull_questions.length,0);
  const next=await pullChanges(db,'u',fixed.next_cursor);
  assert.equal(next.pull_questions.length,1); assert.equal(next.pull_questions[0].id,'later');
  sqlite.close();
});

test('重复ACK零写入，相同字段新事件不改投影与拉取序号', async () => {
  const {db,sqlite}=fixture(); const m=mutation(1,{collection:1});
  await pushMutations(db,'u','d',[m],1);
  const before=sqlite.prepare('SELECT total_changes() AS n').get().n;
  await pushMutations(db,'u','d',[m],2);
  assert.equal(sqlite.prepare('SELECT total_changes() AS n').get().n,before);
  const seq=sqlite.prepare('SELECT MAX(seq) AS n FROM sync_changes').get().n;
  await pushMutations(db,'u','d',[mutation(2,{collection:1})],3);
  assert.equal(sqlite.prepare('SELECT MAX(seq) AS n FROM sync_changes').get().n,seq);
  assert.equal(sqlite.prepare('SELECT updated_at FROM sync_questions').get().updated_at,1);
  await assert.rejects(pushMutations(db,'u','d',[mutation(1,{collection:0})],4),/identity reused/);
  sqlite.close();
});

test('历史斩题状态3仍可同步，放回题库只改变cut和条件状态', async () => {
  const {db,sqlite}=fixture();
  await pushMutations(db,'u','d',[mutation(1,{status:3,cut_question:'1'})],1);
  await pushMutations(db,'u','d',[mutation(2,{status:0,cut_question:'0'})],2);
  assert.equal(sqlite.prepare('SELECT status FROM sync_questions').get().status,0);
  sqlite.close();
});

test('流水删除分页传递，旧设备与重复事件无法复活，账户隔离', async () => {
  const {db,sqlite}=fixture();
  const activity=(seq,kind='activity')=>({seq,stream:'b'.repeat(32),kind,id:'a',payload:kind==='activity'?{timestamp:1,is_right:'1'}:{}});
  await pushMutations(db,'u','d',[activity(1)],1);
  const first=await pullChanges(db,'u',0);
  await pushMutations(db,'u','d',[activity(2,'activity_delete')],2);
  const page=await pullChanges(db,'u',first.next_cursor);
  assert.deepEqual(page.pull_deleted_activities,['a']);
  await pushMutations(db,'u','old',[activity(1)],3);
  await pushMutations(db,'u','d',[activity(1),activity(2,'activity_delete')],4);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM sync_activities WHERE user_id=?').get('u').n,0);
  await pushMutations(db,'other','other',[activity(1)],5);
  assert.equal((await pullChanges(db,'other',0)).pull_activities.length,1);
  sqlite.close();
});
