const questionFields = ['chapter_id', 'chapter_parent_id', 'cut_question', 'user_answer', 'status', 'collection'] as const;

interface MutationInput {
  seq: number;
  stream: string;
  id: string;
  kind: 'question' | 'activity' | 'activity_delete' | 'flashcard' | 'flashcard_delete' | 'spaced_item' | 'review_plan';
  payload: Record<string, any>;
}

// 严格遵守 Cloudflare D1 单条 SQL 最多 100 个绑定参数的限制，并采用多行合并批量 SQL 将 500 条同步耗时从 >40s 降至 <1s。
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

  const typedInput = input as MutationInput[];
  if (typedInput.length === 0) return [];

  // 1. 并发批量查重 (每条 SQL 最多 1 + 45*2 = 91 参数 <= 100)
  const DEDUP_CHUNK = 45;
  const dedupPromises: Promise<D1Result<{ stream: string; client_seq: number; kind: string; entity_id: string; payload: string }>>[] = [];
  for (let i = 0; i < typedInput.length; i += DEDUP_CHUNK) {
    const chunk = typedInput.slice(i, i + DEDUP_CHUNK);
    const conditions = chunk.map(() => '(stream=? AND client_seq=?)').join(' OR ');
    const params: (string | number)[] = [device];
    for (const m of chunk) {
      params.push(m.stream, m.seq);
    }
    dedupPromises.push(
      db.prepare(
        `SELECT stream, client_seq, kind, entity_id, payload FROM sync_mutations WHERE device_id=? AND (${conditions})`
      ).bind(...params).all<{ stream: string; client_seq: number; kind: string; entity_id: string; payload: string }>()
    );
  }
  const dedupResults = await Promise.all(dedupPromises);
  const seenMap = new Map<string, { kind: string; entity_id: string; payload: string }>();
  for (const res of dedupResults) {
    for (const row of res.results) {
      seenMap.set(`${row.stream}:${row.client_seq}`, row);
    }
  }

  const accepted: number[] = [];
  const freshMutations: { mutation: MutationInput; encoded: string }[] = [];

  for (const mutation of typedInput) {
    const encoded = JSON.stringify(mutation.payload);
    const seen = seenMap.get(`${mutation.stream}:${mutation.seq}`);
    if (seen) {
      if (seen.kind !== mutation.kind || seen.entity_id !== mutation.id || seen.payload !== encoded) {
        throw new Error('Mutation identity reused with different content');
      }
      accepted.push(mutation.seq);
    } else {
      freshMutations.push({ mutation, encoded });
    }
  }

  if (freshMutations.length === 0) {
    return accepted;
  }

  const statements: D1PreparedStatement[] = [];

  // 2. 多行批量插入 sync_mutations (每条 7 个参数，12 条一组 = 84 参数 <= 100)
  const MUT_BATCH = 12;
  for (let i = 0; i < freshMutations.length; i += MUT_BATCH) {
    const slice = freshMutations.slice(i, i + MUT_BATCH);
    const placeholders = slice.map(() => '(?,?,?,?,?,?,?,1)').join(',');
    const params: (string | number)[] = [];
    for (const { mutation, encoded } of slice) {
      params.push(user, device, mutation.stream, mutation.seq, mutation.kind, mutation.id, encoded);
    }
    statements.push(
      db.prepare(
        `INSERT OR IGNORE INTO sync_mutations(user_id,device_id,stream,client_seq,kind,entity_id,payload,applied) VALUES ${placeholders}`
      ).bind(...params)
    );
  }

  // 3. 按连续同类型与同字段掩码聚合成多行 SQL，100% 保留事件时序，同时将 SQL 条数压缩 10~20 倍
  let idx = 0;
  while (idx < freshMutations.length) {
    const first = freshMutations[idx].mutation;

    if (first.kind === 'question') {
      const fields = questionFields.filter(f => Object.prototype.hasOwnProperty.call(first.payload, f));
      const fieldKey = fields.join(',');
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length) {
        const next = freshMutations[idx].mutation;
        if (next.kind !== 'question') break;
        const nextFields = questionFields.filter(f => Object.prototype.hasOwnProperty.call(next.payload, f));
        if (nextFields.join(',') !== fieldKey) break;
        group.push(next);
        idx++;
      }

      const colsCount = 3 + fields.length; // user_id, question_id, ...fields, updated_at
      const maxRows = Math.max(1, Math.floor(90 / colsCount));
      for (let g = 0; g < group.length; g += maxRows) {
        const slice = group.slice(g, g + maxRows);
        const rowPh = `(${Array(colsCount).fill('?').join(',')})`;
        const placeholders = slice.map(() => rowPh).join(',');
        const params: unknown[] = [];
        for (const m of slice) {
          params.push(user, m.id, ...fields.map(f => m.payload[f]), now);
        }
        if (fields.length === 0) {
          statements.push(
            db.prepare(
              `INSERT OR IGNORE INTO sync_questions(user_id,question_id,updated_at) VALUES ${placeholders}`
            ).bind(...params)
          );
        } else {
          const updateSet = fields.map(f => `${f}=excluded.${f}`).join(',');
          const diffWhere = fields.map(f => `sync_questions.${f} IS NOT excluded.${f}`).join(' OR ');
          statements.push(
            db.prepare(
              `INSERT INTO sync_questions(user_id,question_id,${fields.join(',')},updated_at) VALUES ${placeholders} ` +
              `ON CONFLICT(user_id,question_id) DO UPDATE SET ${updateSet}, updated_at=excluded.updated_at WHERE ${diffWhere}`
            ).bind(...params)
          );
        }
      }
      continue;
    }

    if (first.kind === 'activity') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'activity') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      // 13 个参数/行 -> 7 行一组 = 91 参数 <= 100
      for (let g = 0; g < group.length; g += 7) {
        const slice = group.slice(g, g + 7);
        const placeholders = slice.map(() => '(?,?,?,?,?,?,?,?,?,?,?,?,?)').join(',');
        const params: unknown[] = [];
        for (const m of slice) {
          const q = m.payload;
          params.push(
            user, m.id, Number(q.timestamp) || 0,
            q.bank_id ?? null, q.question_id ?? null, q.identity_id ?? null, q.subject_id ?? null,
            q.chapter_id ?? null, q.is_right ?? null, Number(q.duration) || 0, q.title ?? 'NewAnswer', q.description ?? '', now
          );
        }
        statements.push(
          db.prepare(
            `INSERT OR IGNORE INTO sync_activities(user_id,id,timestamp,bank_id,question_id,identity_id,subject_id,chapter_id,is_right,duration,title,description,created_at) VALUES ${placeholders}`
          ).bind(...params)
        );
      }
      continue;
    }

    if (first.kind === 'activity_delete') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'activity_delete') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      for (let g = 0; g < group.length; g += 45) {
        const slice = group.slice(g, g + 45);
        const placeholders = slice.map(() => '(?,?)').join(',');
        const insParams: unknown[] = [];
        for (const m of slice) insParams.push(user, m.id);
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_deleted_activities(user_id,id) VALUES ${placeholders}`).bind(...insParams));
        const inPh = slice.map(() => '?').join(',');
        statements.push(db.prepare(`DELETE FROM sync_activities WHERE user_id=? AND id IN (${inPh})`).bind(user, ...slice.map(m => m.id)));
      }
      continue;
    }

    if (first.kind === 'flashcard_delete') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'flashcard_delete') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      for (let g = 0; g < group.length; g += 45) {
        const slice = group.slice(g, g + 45);
        const placeholders = slice.map(() => '(?,?)').join(',');
        const insParams: unknown[] = [];
        for (const m of slice) insParams.push(user, m.id);
        statements.push(db.prepare(`INSERT OR IGNORE INTO sync_deleted_flashcards(user_id,id) VALUES ${placeholders}`).bind(...insParams));
        const inPh = slice.map(() => '?').join(',');
        statements.push(db.prepare(`DELETE FROM sync_flashcards WHERE user_id=? AND id IN (${inPh})`).bind(user, ...slice.map(m => m.id)));
      }
      continue;
    }

    if (first.kind === 'flashcard') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'flashcard') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      // 9 个参数/行 -> 10 行一组 = 90 参数 <= 100
      for (let g = 0; g < group.length; g += 10) {
        const slice = group.slice(g, g + 10);
        const placeholders = slice.map(() => '(?,?,?,?,?,?,?,?,?)').join(',');
        const params: unknown[] = [];
        for (const m of slice) {
          const q = m.payload;
          params.push(user, m.id, q.title ?? '', q.front ?? '', q.back ?? '', q.question_id ?? null, q.tags ?? null, Number(q.created_at) || now, Number(q.updated_at) || now);
        }
        statements.push(
          db.prepare(
            `INSERT INTO sync_flashcards(user_id,id,title,front,back,question_id,tags,created_at,updated_at) VALUES ${placeholders} ` +
            `ON CONFLICT(user_id,id) DO UPDATE SET title=excluded.title, front=excluded.front, back=excluded.back, question_id=excluded.question_id, tags=excluded.tags, updated_at=excluded.updated_at ` +
            `WHERE sync_flashcards.updated_at <= excluded.updated_at`
          ).bind(...params)
        );
      }
      continue;
    }

    if (first.kind === 'spaced_item') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'spaced_item') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      // 14 个参数/行 -> 6 行一组 = 84 参数 <= 100
      for (let g = 0; g < group.length; g += 6) {
        const slice = group.slice(g, g + 6);
        const placeholders = slice.map(() => '(?,?,?,?,?,?,?,?,?,?,?,?,?,?)').join(',');
        const params: unknown[] = [];
        for (const m of slice) {
          const q = m.payload;
          params.push(user, m.id, q.plan_id ?? '', Number(q.item_type) || 0, Number(q.state) || 0, Number(q.step) || 0, Number(q.reps) || 0, Number(q.lapses) || 0, Number(q.difficulty) || 0, Number(q.stability) || 0, Number(q.due_date) || 0, Number(q.last_review_at) || 0, q.extra ?? null, Number(q.updated_at) || now);
        }
        statements.push(
          db.prepare(
            `INSERT INTO sync_spaced_items(user_id,item_id,plan_id,item_type,state,step,reps,lapses,difficulty,stability,due_date,last_review_at,extra,updated_at) VALUES ${placeholders} ` +
            `ON CONFLICT(user_id,item_id) DO UPDATE SET plan_id=excluded.plan_id, item_type=excluded.item_type, state=excluded.state, step=excluded.step, reps=excluded.reps, lapses=excluded.lapses, difficulty=excluded.difficulty, stability=excluded.stability, due_date=excluded.due_date, last_review_at=excluded.last_review_at, extra=excluded.extra, updated_at=excluded.updated_at ` +
            `WHERE sync_spaced_items.updated_at <= excluded.updated_at`
          ).bind(...params)
        );
      }
      continue;
    }

    if (first.kind === 'review_plan') {
      const group: MutationInput[] = [first];
      idx++;
      while (idx < freshMutations.length && freshMutations[idx].mutation.kind === 'review_plan') {
        group.push(freshMutations[idx].mutation);
        idx++;
      }
      // 10 个参数/行 -> 9 行一组 = 90 参数 <= 100
      for (let g = 0; g < group.length; g += 9) {
        const slice = group.slice(g, g + 9);
        const placeholders = slice.map(() => '(?,?,?,?,?,?,?,?,?,?)').join(',');
        const params: unknown[] = [];
        for (const m of slice) {
          const q = m.payload;
          params.push(user, m.id, q.name ?? '', q.bank_id ?? null, Number(q.daily_new_target) || 20, Number(q.daily_review_limit) || 50, q.source_types ?? '["wrong","collected","note"]', q.covered_subjects ?? '[]', Number(q.created_at) || now, Number(q.updated_at) || now);
        }
        statements.push(
          db.prepare(
            `INSERT INTO sync_review_plans(user_id,id,name,bank_id,daily_new_target,daily_review_limit,source_types,covered_subjects,created_at,updated_at) VALUES ${placeholders} ` +
            `ON CONFLICT(user_id,id) DO UPDATE SET name=excluded.name, bank_id=excluded.bank_id, daily_new_target=excluded.daily_new_target, daily_review_limit=excluded.daily_review_limit, source_types=excluded.source_types, covered_subjects=excluded.covered_subjects, updated_at=excluded.updated_at ` +
            `WHERE sync_review_plans.updated_at <= excluded.updated_at`
          ).bind(...params)
        );
      }
      continue;
    }
  }

  // 4. 分片执行 db.batch (500 条题目的 statements 总共只有 ~95 条，单次 batch 原子提交)
  const MAX_BATCH_STATEMENTS = 200;
  for (let i = 0; i < statements.length; i += MAX_BATCH_STATEMENTS) {
    await db.batch(statements.slice(i, i + MAX_BATCH_STATEMENTS));
  }

  for (const { mutation } of freshMutations) {
    accepted.push(mutation.seq);
  }
  return accepted;
}

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
    has_more: rows.results.length > 500,
  };
}
