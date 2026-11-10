const questionFields = ['chapter_id', 'chapter_parent_id', 'cut_question', 'user_answer', 'status', 'collection'] as const;

// 每个事件在同一 D1 batch 内记录与应用。重复投递只确认，不再应用旧字段。
// 离线设备之间无法推断真实作答先后；保留事件历史供冲突恢复，投影按入库顺序。
export async function pushMutations(db: D1Database, user: string, device: string, input: unknown, now: number): Promise<number[]> {
  if (!Array.isArray(input) || input.length > 500) throw new Error('Invalid mutation batch');
  const accepted: number[] = [];
  for (const mutation of input) {
    if (!mutation || !Number.isSafeInteger(mutation.seq) || mutation.seq <= 0 ||
        typeof mutation.stream !== 'string' || !/^[a-f0-9]{32}$/.test(mutation.stream) ||
        typeof mutation.id !== 'string' || !mutation.id ||
        !['question', 'activity'].includes(mutation.kind) ||
        !mutation.payload || typeof mutation.payload !== 'object') throw new Error('Invalid mutation');
    const q = mutation.payload;
    const key = [device, mutation.stream, mutation.seq];
    if (mutation.kind === 'question') {
      for (const f of ['chapter_id','chapter_parent_id']) {
        if (Object.prototype.hasOwnProperty.call(q,f) && q[f] !== null && typeof q[f] !== 'string') throw new Error('Invalid question relation');
      }
      if (('collection' in q && ![0,1].includes(q.collection)) ||
          ('status' in q && ![0,1,2,4].includes(q.status)) ||
          ('cut_question' in q && !['0','1'].includes(q.cut_question)) ||
          ('user_answer' in q && typeof q.user_answer !== 'string')) throw new Error('Invalid question fields');
    }
    const encoded = JSON.stringify(q);
    const seen = await db.prepare('SELECT kind,entity_id,payload FROM sync_mutations WHERE device_id=? AND stream=? AND client_seq=?').bind(...key).first<{kind:string,entity_id:string,payload:string}>();
    if (seen) {
      if (seen.kind !== mutation.kind || seen.entity_id !== mutation.id || seen.payload !== encoded) throw new Error('Mutation identity reused with different content');
      accepted.push(mutation.seq);
      continue;
    }
    const active = 'EXISTS (SELECT 1 FROM sync_mutations WHERE device_id=? AND stream=? AND client_seq=? AND applied=0)';
    const statements = [db.prepare(`INSERT OR IGNORE INTO sync_mutations(user_id,device_id,stream,client_seq,kind,entity_id,payload) VALUES(?,?,?,?,?,?,?)`)
      .bind(user, ...key, mutation.kind, mutation.id, encoded)];
    if (mutation.kind === 'question') {
      const fields = questionFields.filter(f => Object.prototype.hasOwnProperty.call(q, f));
      statements.push(db.prepare(`INSERT OR IGNORE INTO sync_questions(user_id,question_id${fields.length ? ','+fields.join(',') : ''},updated_at) VALUES(?,?${fields.map(()=>',?').join('')},?)`).bind(user, mutation.id, ...fields.map(f=>q[f]), now));
      if (fields.length) statements.push(db.prepare(`UPDATE sync_questions SET ${fields.map(f => `${f}=?`).join(',')}, updated_at=? WHERE user_id=? AND question_id=? AND ${active} AND (${fields.map(f=>`${f} IS NOT ?`).join(' OR ')})`)
        .bind(...fields.map(f => q[f]), now, user, mutation.id, ...key, ...fields.map(f=>q[f])));
    } else {
      statements.push(db.prepare(`INSERT OR IGNORE INTO sync_activities(user_id,id,timestamp,bank_id,question_id,identity_id,subject_id,chapter_id,is_right,duration,title,description,created_at)
        SELECT ?,?,?,?,?,?,?,?,?,?,?,?,? WHERE ${active}`).bind(user, mutation.id, Number(q.timestamp) || 0,
        q.bank_id ?? null, q.question_id ?? null, q.identity_id ?? null, q.subject_id ?? null,
        q.chapter_id ?? null, q.is_right ?? null, Number(q.duration) || 0, q.title ?? 'NewAnswer', q.description ?? '', now, ...key));
    }
    statements.push(db.prepare('UPDATE sync_mutations SET applied=1 WHERE device_id=? AND stream=? AND client_seq=? AND applied=0').bind(...key));
    await db.batch(statements);
    accepted.push(mutation.seq);
  }
  return accepted;
}

// 固定提交上界；同毫秒、慢时钟及晚提交均不会跳过，按页恢复游标。
export async function pullChanges(db: D1Database, user: string, cursor: number, through?: number) {
  if (!Number.isSafeInteger(cursor) || cursor < 0 ||
      (through !== undefined && (!Number.isSafeInteger(through) || through < cursor))) throw new Error('Invalid pull cursor');
  const maximum = await db.prepare('SELECT COALESCE(MAX(seq),0) AS seq FROM sync_changes WHERE user_id=?').bind(user).first<{seq: number}>();
  const high = through ?? maximum!.seq;
  const rows = await db.prepare('SELECT seq FROM sync_changes WHERE user_id=? AND seq>? AND seq<=? ORDER BY seq LIMIT 501').bind(user,cursor,high).all<{seq:number}>();
  const page = rows.results.slice(0,500);
  const next = page.length ? page[page.length-1].seq : high;
  const activities = await db.prepare(`SELECT DISTINCT a.id,a.timestamp,a.bank_id,a.question_id,a.identity_id,a.subject_id,a.chapter_id,a.is_right,a.duration,a.title,a.description
    FROM sync_changes c JOIN sync_activities a ON a.user_id=c.user_id AND a.id=c.entity_id
    WHERE c.user_id=? AND c.kind='activity' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all();
  const questions = await db.prepare(`SELECT DISTINCT q.question_id AS id,q.chapter_id,q.chapter_parent_id,q.cut_question,q.user_answer,q.status,q.collection,q.updated_at
    FROM sync_changes c JOIN sync_questions q ON q.user_id=c.user_id AND q.question_id=c.entity_id
    WHERE c.user_id=? AND c.kind='question' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all();
  return { pull_activities: activities.results, pull_questions: questions.results,
    next_cursor: next, high_watermark: high, has_more: rows.results.length > 500 };
}
