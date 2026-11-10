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
    const active = 'EXISTS (SELECT 1 FROM sync_mutations WHERE device_id=? AND stream=? AND client_seq=? AND applied=0)';
    const statements = [db.prepare(`INSERT OR IGNORE INTO sync_mutations(user_id,device_id,stream,client_seq,kind,entity_id,payload) VALUES(?,?,?,?,?,?,?)`)
      .bind(user, ...key, mutation.kind, mutation.id, JSON.stringify(q))];
    if (mutation.kind === 'question') {
      const fields = questionFields.filter(f => Object.prototype.hasOwnProperty.call(q, f));
      statements.push(db.prepare(`INSERT OR IGNORE INTO sync_questions(user_id,question_id) VALUES(?,?)`).bind(user, mutation.id));
      if (fields.length) statements.push(db.prepare(`UPDATE sync_questions SET ${fields.map(f => `${f}=?`).join(',')}, updated_at=? WHERE user_id=? AND question_id=? AND ${active}`)
        .bind(...fields.map(f => q[f]), now, user, mutation.id, ...key));
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
