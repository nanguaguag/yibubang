const questionFields = ['chapter_id', 'chapter_parent_id', 'cut_question', 'user_answer', 'status', 'collection'] as const;

// 每个事件在 D1 batch 内记录与应用，支持 25 条分块批量查询与事务聚合提交。重复投递只确认，不再应用旧字段。
// 离线设备之间无法推断真实作答先后；保留事件历史供冲突恢复，投影按入库顺序。
export async function pushMutations(db: D1Database, user: string, device: string, input: unknown, now: number): Promise<number[]> {
  if (!Array.isArray(input) || input.length > 500) throw new Error('Invalid mutation batch');
  for (const mutation of input) {
    if (!mutation || !Number.isSafeInteger(mutation.seq) || mutation.seq <= 0 ||
        typeof mutation.stream !== 'string' || !/^[a-f0-9]{32}$/.test(mutation.stream) ||
        typeof mutation.id !== 'string' || !mutation.id ||
        !['question', 'activity', 'activity_delete', 'flashcard', 'flashcard_delete', 'spaced_item', 'review_plan'].includes(mutation.kind) ||
        !mutation.payload || typeof mutation.payload !== 'object') throw new Error('Invalid mutation');
    const q = mutation.payload;
    if (mutation.kind === 'question') {
      for (const f of ['chapter_id','chapter_parent_id']) {
        if (Object.prototype.hasOwnProperty.call(q,f) && q[f] !== null && typeof q[f] !== 'string') throw new Error('Invalid question relation');
      }
      if (('collection' in q && ![0,1].includes(q.collection)) ||
          ('status' in q && ![0,1,2,3,4].includes(q.status)) ||
          ('cut_question' in q && !['0','1'].includes(q.cut_question)) ||
          ('user_answer' in q && typeof q.user_answer !== 'string')) throw new Error('Invalid question fields');
    }
  }

  const accepted: number[] = [];
  const CHUNK_SIZE = 25;

  for (let i = 0; i < input.length; i += CHUNK_SIZE) {
    const chunk = input.slice(i, i + CHUNK_SIZE);
    const conditions = chunk.map(() => '(stream=? AND client_seq=?)').join(' OR ');
    const params: (string | number)[] = [device];
    for (const m of chunk) {
      params.push(m.stream, m.seq);
    }
    const seenRows = await db.prepare(
      `SELECT stream, client_seq, kind, entity_id, payload FROM sync_mutations WHERE device_id=? AND (${conditions})`
    ).bind(...params).all<{ stream: string; client_seq: number; kind: string; entity_id: string; payload: string }>();

    const seenMap = new Map<string, { kind: string; entity_id: string; payload: string }>();
    for (const row of seenRows.results) {
      seenMap.set(`${row.stream}:${row.client_seq}`, row);
    }

    const statements: D1PreparedStatement[] = [];
    const chunkAccepted: number[] = [];

    for (const mutation of chunk) {
      const q = mutation.payload;
      const key = [device, mutation.stream, mutation.seq];
      const encoded = JSON.stringify(q);
      const seen = seenMap.get(`${mutation.stream}:${mutation.seq}`);
      if (seen) {
        if (seen.kind !== mutation.kind || seen.entity_id !== mutation.id || seen.payload !== encoded) {
          throw new Error('Mutation identity reused with different content');
        }
        accepted.push(mutation.seq);
        continue;
      }
      const active = 'EXISTS (SELECT 1 FROM sync_mutations WHERE device_id=? AND stream=? AND client_seq=? AND applied=0)';
      statements.push(db.prepare(`INSERT OR IGNORE INTO sync_mutations(user_id,device_id,stream,client_seq,kind,entity_id,payload) VALUES(?,?,?,?,?,?,?)`)
        .bind(user, ...key, mutation.kind, mutation.id, encoded));
      if (mutation.kind === 'question') {
        const fields = questionFields.filter(f => Object.prototype.hasOwnProperty.call(q, f));
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_questions(user_id,question_id${fields.length ? ','+fields.join(',') : ''},updated_at) VALUES(?,?${fields.map(()=>',?').join('')},?)`).bind(user, mutation.id, ...fields.map(f=>q[f]), now));
        if (fields.length) {
          statements.push(db.prepare(`UPDATE sync_questions SET ${fields.map(f => `${f}=?`).join(',')}, updated_at=? WHERE user_id=? AND question_id=? AND ${active} AND (${fields.map(f=>`${f} IS NOT ?`).join(' OR ')})`)
            .bind(...fields.map(f => q[f]), now, user, mutation.id, ...key, ...fields.map(f=>q[f])));
        }
      } else if (mutation.kind === 'activity_delete') {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_deleted_activities(user_id,id) SELECT ?,? WHERE ${active}`).bind(user,mutation.id,...key));
        statements.push(db.prepare(`DELETE FROM sync_activities WHERE user_id=? AND id=? AND ${active}`).bind(user,mutation.id,...key));
      } else if (mutation.kind === 'flashcard') {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_flashcards(user_id,id,title,front,back,question_id,tags,created_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?,?)`).bind(user, mutation.id, q.title ?? '', q.front ?? '', q.back ?? '', q.question_id ?? null, q.tags ?? null, Number(q.created_at) || now, Number(q.updated_at) || now));
        statements.push(db.prepare(`UPDATE sync_flashcards SET title=?, front=?, back=?, question_id=?, tags=?, updated_at=?
          WHERE user_id=? AND id=? AND ${active} AND updated_at<=?`).bind(q.title ?? '', q.front ?? '', q.back ?? '', q.question_id ?? null, q.tags ?? null, Number(q.updated_at) || now, user, mutation.id, ...key, Number(q.updated_at) || now));
      } else if (mutation.kind === 'flashcard_delete') {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_deleted_flashcards(user_id,id) SELECT ?,? WHERE ${active}`).bind(user,mutation.id,...key));
        statements.push(db.prepare(`DELETE FROM sync_flashcards WHERE user_id=? AND id=? AND ${active}`).bind(user,mutation.id,...key));
      } else if (mutation.kind === 'spaced_item') {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_spaced_items(user_id,item_id,plan_id,item_type,state,step,reps,lapses,difficulty,stability,due_date,last_review_at,extra,updated_at)
          VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(user, mutation.id, q.plan_id ?? '', Number(q.item_type) || 0, Number(q.state) || 0, Number(q.step) || 0, Number(q.reps) || 0, Number(q.lapses) || 0, Number(q.difficulty) || 0, Number(q.stability) || 0, Number(q.due_date) || 0, Number(q.last_review_at) || 0, q.extra ?? null, Number(q.updated_at) || now));
        statements.push(db.prepare(`UPDATE sync_spaced_items SET plan_id=?, item_type=?, state=?, step=?, reps=?, lapses=?, difficulty=?, stability=?, due_date=?, last_review_at=?, extra=?, updated_at=?
          WHERE user_id=? AND item_id=? AND ${active} AND updated_at<=?`).bind(q.plan_id ?? '', Number(q.item_type) || 0, Number(q.state) || 0, Number(q.step) || 0, Number(q.reps) || 0, Number(q.lapses) || 0, Number(q.difficulty) || 0, Number(q.stability) || 0, Number(q.due_date) || 0, Number(q.last_review_at) || 0, q.extra ?? null, Number(q.updated_at) || now, user, mutation.id, ...key, Number(q.updated_at) || now));
      } else if (mutation.kind === 'review_plan') {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_review_plans(user_id,id,name,bank_id,daily_new_target,daily_review_limit,source_types,covered_subjects,created_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?,?,?)`).bind(user, mutation.id, q.name ?? '', q.bank_id ?? null, Number(q.daily_new_target) || 20, Number(q.daily_review_limit) || 50, q.source_types ?? '["wrong","collected","note"]', q.covered_subjects ?? '[]', Number(q.created_at) || now, Number(q.updated_at) || now));
        statements.push(db.prepare(`UPDATE sync_review_plans SET name=?, bank_id=?, daily_new_target=?, daily_review_limit=?, source_types=?, covered_subjects=?, updated_at=?
          WHERE user_id=? AND id=? AND ${active} AND updated_at<=?`).bind(q.name ?? '', q.bank_id ?? null, Number(q.daily_new_target) || 20, Number(q.daily_review_limit) || 50, q.source_types ?? '["wrong","collected","note"]', q.covered_subjects ?? '[]', Number(q.updated_at) || now, user, mutation.id, ...key, Number(q.updated_at) || now));
      } else {
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_activities(user_id,id,timestamp,bank_id,question_id,identity_id,subject_id,chapter_id,is_right,duration,title,description,created_at)
          SELECT ?,?,?,?,?,?,?,?,?,?,?,?,? WHERE ${active}`).bind(user, mutation.id, Number(q.timestamp) || 0,
          q.bank_id ?? null, q.question_id ?? null, q.identity_id ?? null, q.subject_id ?? null,
          q.chapter_id ?? null, q.is_right ?? null, Number(q.duration) || 0, q.title ?? 'NewAnswer', q.description ?? '', now, ...key));
      }
      statements.push(db.prepare('UPDATE sync_mutations SET applied=1 WHERE device_id=? AND stream=? AND client_seq=? AND applied=0').bind(...key));
      chunkAccepted.push(mutation.seq);
    }
    if (statements.length > 0) {
      await db.batch(statements);
    }
    accepted.push(...chunkAccepted);
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
  const deleted = await db.prepare(`SELECT DISTINCT d.id FROM sync_changes c JOIN sync_deleted_activities d ON d.user_id=c.user_id AND d.id=c.entity_id WHERE c.user_id=? AND c.kind='activity_delete' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all<{id:string}>();
  const flashcards = await db.prepare(`SELECT DISTINCT f.id, f.title, f.front, f.back, f.question_id, f.tags, f.created_at, f.updated_at
    FROM sync_changes c JOIN sync_flashcards f ON f.user_id=c.user_id AND f.id=c.entity_id
    WHERE c.user_id=? AND c.kind='flashcard' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all();
  const deletedFlashcards = await db.prepare(`SELECT DISTINCT d.id FROM sync_changes c JOIN sync_deleted_flashcards d ON d.user_id=c.user_id AND d.id=c.entity_id WHERE c.user_id=? AND c.kind='flashcard_delete' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all<{id:string}>();
  const spacedItems = await db.prepare(`SELECT DISTINCT s.item_id, s.plan_id, s.item_type, s.state, s.step, s.reps, s.lapses, s.difficulty, s.stability, s.due_date, s.last_review_at, s.extra, s.updated_at
    FROM sync_changes c JOIN sync_spaced_items s ON s.user_id=c.user_id AND s.item_id=c.entity_id
    WHERE c.user_id=? AND c.kind='spaced_item' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all();
  const reviewPlans = await db.prepare(`SELECT DISTINCT p.id, p.name, p.bank_id, p.daily_new_target, p.daily_review_limit, p.source_types, p.covered_subjects, p.created_at, p.updated_at
    FROM sync_changes c JOIN sync_review_plans p ON p.user_id=c.user_id AND p.id=c.entity_id
    WHERE c.user_id=? AND c.kind='review_plan' AND c.seq>? AND c.seq<=? ORDER BY c.seq`).bind(user,cursor,next).all();

  return {
    pull_deleted_activities: deleted.results.map(d=>d.id),
    pull_activities: activities.results,
    pull_questions: questions.results,
    pull_flashcards: flashcards.results,
    pull_deleted_flashcards: deletedFlashcards.results.map(d=>d.id),
    pull_spaced_items: spacedItems.results,
    pull_review_plans: reviewPlans.results,
    next_cursor: next,
    high_watermark: high,
    has_more: rows.results.length > 500
  };
}
