import { Hono } from 'hono';
import { cors } from 'hono/cors';

type Bindings = {
  DB: D1Database;
};

interface DeviceAuth {
  deviceId: string;
  userId: string;
  deviceName: string;
}

const app = new Hono<{ Bindings: Bindings }>();

// 跨域支持
app.use('*', cors());

// 生成简单 UUID
function generateUUID(): string {
  return crypto.randomUUID();
}

// 生成 6 位随机数字配对码
function generatePairingCode(): string {
  const num = Math.floor(100000 + Math.random() * 900000);
  return num.toString();
}

// 鉴权中间件辅助函数
async function authenticateDevice(
  db: D1Database,
  authHeader: string | undefined
): Promise<DeviceAuth | null> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  const token = authHeader.substring(7).trim();
  if (!token) return null;

  const row = await db
    .prepare('SELECT device_id, user_id, device_name FROM devices WHERE device_token = ?')
    .bind(token)
    .first<{ device_id: string; user_id: string; device_name: string }>();

  if (!row) return null;
  return {
    deviceId: row.device_id,
    userId: row.user_id,
    deviceName: row.device_name,
  };
}

// 1. 健康检查
app.get('/', (c) => {
  return c.json({
    service: 'yibubang-sync-server',
    version: '1.0.0',
    status: 'ok',
    timestamp: Date.now(),
  });
});

app.get('/api/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// 2. 设备注册 / 初始化
app.post('/api/device/register', async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const deviceName = body.device_name || 'My Device';
  let userId = body.user_id as string | undefined;

  const now = Date.now();
  const db = c.env.DB;

  // 如果没有传入已存在的 userId，则新建用户
  if (!userId) {
    userId = generateUUID();
    const passphrase = `${Math.random().toString(36).substring(2, 8)}-${Math.random()
      .toString(36)
      .substring(2, 8)}`.toUpperCase();

    await db
      .prepare('INSERT INTO users (user_id, sync_passphrase, created_at, last_sync_at) VALUES (?, ?, ?, ?)')
      .bind(userId, passphrase, now, now)
      .run();
  } else {
    // 检查传入的 userId 是否存在
    const user = await db
      .prepare('SELECT user_id FROM users WHERE user_id = ?')
      .bind(userId)
      .first();
    if (!user) {
      await db
        .prepare('INSERT INTO users (user_id, sync_passphrase, created_at, last_sync_at) VALUES (?, ?, ?, ?)')
        .bind(userId, null, now, now)
        .run();
    }
  }

  const deviceId = generateUUID();
  const deviceToken = `tk_${generateUUID().replace(/-/g, '')}`;

  await db
    .prepare(
      'INSERT INTO devices (device_id, user_id, device_name, device_token, created_at, last_sync_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(deviceId, userId, deviceName, deviceToken, now, now)
    .run();

  const user = await db
    .prepare('SELECT sync_passphrase FROM users WHERE user_id = ?')
    .bind(userId)
    .first<{ sync_passphrase: string | null }>();

  return c.json({
    code: 0,
    message: 'Registered successfully',
    data: {
      user_id: userId,
      device_id: deviceId,
      device_token: deviceToken,
      sync_passphrase: user?.sync_passphrase ?? null,
    },
  });
});

// 3. 生成配对码 (由已配对的主设备发起)
app.post('/api/pair/create', async (c) => {
  const db = c.env.DB;
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  // 10 分钟有效期
  const now = Date.now();
  const expiresAt = now + 10 * 60 * 1000;
  const code = generatePairingCode();

  // 清除该设备先前已过期的配对码
  await db.prepare('DELETE FROM pairing_codes WHERE expires_at < ?').bind(now).run();

  await db
    .prepare(
      'INSERT OR REPLACE INTO pairing_codes (code, user_id, created_by_device, expires_at, attempts) VALUES (?, ?, ?, ?, 0)'
    )
    .bind(code, auth.userId, auth.deviceId, expiresAt)
    .run();

  return c.json({
    code: 0,
    message: 'Pairing code generated',
    data: {
      code,
      expires_at: expiresAt,
      expires_in_seconds: 600,
    },
  });
});

// 3.1 查询当前设备生成的未过期配对码
app.get('/api/pair/active', async (c) => {
  const db = c.env.DB;
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const now = Date.now();
  const record = await db
    .prepare(
      'SELECT code, expires_at FROM pairing_codes WHERE created_by_device = ? AND expires_at > ? ORDER BY expires_at DESC LIMIT 1'
    )
    .bind(auth.deviceId, now)
    .first<{ code: string; expires_at: number }>();

  if (!record) {
    return c.json({ code: 0, data: null });
  }

  const remainingSeconds = Math.max(0, Math.floor((record.expires_at - now) / 1000));
  return c.json({
    code: 0,
    data: {
      code: record.code,
      expires_at: record.expires_at,
      expires_in_seconds: remainingSeconds,
    },
  });
});

// 3.2 使用备份口令恢复多端同步
app.post('/api/pair/restore-passphrase', async (c) => {
  const db = c.env.DB;
  const body = await c.req.json().catch(() => ({}));
  const rawPass = (body.passphrase || '').toString().trim().toUpperCase();
  const deviceName = body.device_name || 'Restored Device';

  if (!rawPass) {
    return c.json({ code: 400, message: '备份口令不能为空' }, 400);
  }

  const user = await db
    .prepare('SELECT user_id, sync_passphrase FROM users WHERE UPPER(sync_passphrase) = ?')
    .bind(rawPass)
    .first<{ user_id: string; sync_passphrase: string }>();

  if (!user) {
    return c.json({ code: 404, message: '未找到该备份口令对应的云端记录，请检查是否输入正确' }, 404);
  }

  const now = Date.now();
  const deviceId = generateUUID();
  const deviceToken = `tk_${generateUUID().replace(/-/g, '')}`;

  await db
    .prepare(
      'INSERT INTO devices (device_id, user_id, device_name, device_token, created_at, last_sync_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(deviceId, user.user_id, deviceName, deviceToken, now, now)
    .run();

  return c.json({
    code: 0,
    message: 'Restored successfully',
    data: {
      user_id: user.user_id,
      device_id: deviceId,
      device_token: deviceToken,
      sync_passphrase: user.sync_passphrase,
    },
  });
});

// 4. 输入配对码认领 (由新设备发起)
app.post('/api/pair/claim', async (c) => {
  const db = c.env.DB;
  const body = await c.req.json().catch(() => ({}));
  const code = (body.code || '').toString().trim();
  const deviceName = body.device_name || 'Paired Device';

  if (!code) {
    return c.json({ code: 400, message: 'Pairing code is required' }, 400);
  }

  const now = Date.now();
  const record = await db
    .prepare('SELECT code, user_id, expires_at, attempts FROM pairing_codes WHERE code = ?')
    .bind(code)
    .first<{ code: string; user_id: string; expires_at: number; attempts: number }>();

  if (!record) {
    return c.json({ code: 404, message: '配对码无效或不存在' }, 404);
  }

  if (record.expires_at < now) {
    await db.prepare('DELETE FROM pairing_codes WHERE code = ?').bind(code).run();
    return c.json({ code: 410, message: '配对码已过期，请在主设备重新生成' }, 410);
  }

  if (record.attempts >= 5) {
    await db.prepare('DELETE FROM pairing_codes WHERE code = ?').bind(code).run();
    return c.json({ code: 429, message: '配对码尝试错误过多，已自动作废' }, 429);
  }

  // 配对成功：删除配对码（一次性使用）
  await db.prepare('DELETE FROM pairing_codes WHERE code = ?').bind(code).run();

  // 为新设备分配凭证
  const deviceId = generateUUID();
  const deviceToken = `tk_${generateUUID().replace(/-/g, '')}`;

  await db
    .prepare(
      'INSERT INTO devices (device_id, user_id, device_name, device_token, created_at, last_sync_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(deviceId, record.user_id, deviceName, deviceToken, now, now)
    .run();

  const user = await db
    .prepare('SELECT sync_passphrase FROM users WHERE user_id = ?')
    .bind(record.user_id)
    .first<{ sync_passphrase: string | null }>();

  return c.json({
    code: 0,
    message: 'Paired successfully',
    data: {
      user_id: record.user_id,
      device_id: deviceId,
      device_token: deviceToken,
      sync_passphrase: user?.sync_passphrase ?? null,
    },
  });
});

// 5. 核心增量同步接口 (Push & Pull)
app.post('/api/sync', async (c) => {
  const db = c.env.DB;
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const body = await c.req.json().catch(() => ({}));
  const lastSyncTime = Number(body.last_sync_time) || 0;
  const pushActivities = Array.isArray(body.push_activities) ? body.push_activities : [];
  const pushQuestions = Array.isArray(body.push_questions) ? body.push_questions : [];

  const now = Date.now();
  const statements: D1PreparedStatement[] = [];

  // 1. 处理 push_activities (Append-Only，以 INSERT OR IGNORE 去重)
  for (const act of pushActivities) {
    if (!act.id) continue;
    statements.push(
      db
        .prepare(`
          INSERT OR IGNORE INTO sync_activities (
            user_id, id, timestamp, bank_id, question_id, identity_id,
            subject_id, chapter_id, is_right, duration, title, description, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `)
        .bind(
          auth.userId,
          act.id,
          Number(act.timestamp) || now,
          act.bank_id || null,
          act.question_id || null,
          act.identity_id || null,
          act.subject_id || null,
          act.chapter_id || null,
          act.is_right ?? null,
          Number(act.duration) || 0,
          act.title || 'NewAnswer',
          act.description || '',
          now
        )
    );
  }

  // 2. 处理 push_questions (LWW Upsert: updated_at 较大者胜出)
  for (const q of pushQuestions) {
    if (!q.id) continue;
    const qUpdatedAt = Number(q.updated_at) || now;
    statements.push(
      db
        .prepare(`
          INSERT INTO sync_questions (
            user_id, question_id, chapter_id, chapter_parent_id,
            cut_question, user_answer, status, collection, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id, question_id) DO UPDATE SET
            chapter_id = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.chapter_id ELSE sync_questions.chapter_id END,
            chapter_parent_id = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.chapter_parent_id ELSE sync_questions.chapter_parent_id END,
            cut_question = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.cut_question ELSE sync_questions.cut_question END,
            user_answer = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.user_answer ELSE sync_questions.user_answer END,
            status = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.status ELSE sync_questions.status END,
            collection = CASE WHEN excluded.updated_at >= sync_questions.updated_at THEN excluded.collection ELSE sync_questions.collection END,
            updated_at = MAX(sync_questions.updated_at, excluded.updated_at)
        `)
        .bind(
          auth.userId,
          q.id,
          q.chapter_id ?? null,
          q.chapter_parent_id ?? null,
          q.cut_question ?? '0',
          q.user_answer ?? '',
          Number(q.status) || 0,
          Number(q.collection) || 0,
          qUpdatedAt
        )
    );
  }


  // 更新设备和用户的活跃时间
  statements.push(
    db
      .prepare('UPDATE devices SET last_sync_at = ? WHERE device_id = ?')
      .bind(now, auth.deviceId)
  );
  statements.push(
    db
      .prepare('UPDATE users SET last_sync_at = ? WHERE user_id = ?')
      .bind(now, auth.userId)
  );

  // 批量原子执行写入 (D1 事务)
  if (statements.length > 0) {
    // D1 batch 单次支持最多 128 条，若超过分批
    const chunkSize = 100;
    for (let i = 0; i < statements.length; i += chunkSize) {
      await db.batch(statements.slice(i, i + chunkSize));
    }
  }

  // 3. 查询 Pull 增量：拉取云端在 lastSyncTime 之后入库的变动 (按 created_at 判定，确保补录与历史流水不丢失)
  // 拉取流水 (最多拉 10000 条)
  const pullActivitiesResult = await db
    .prepare(`
      SELECT id, timestamp, bank_id, question_id, identity_id,
             subject_id, chapter_id, is_right, duration, title, description
      FROM sync_activities
      WHERE user_id = ? AND created_at > ?
      ORDER BY created_at ASC
      LIMIT 10000
    `)
    .bind(auth.userId, lastSyncTime)
    .all();

  // 拉取题目进度 (最多拉 10000 条)
  const pullQuestionsResult = await db
    .prepare(`
      SELECT question_id as id, chapter_id, chapter_parent_id,
             cut_question, user_answer, status, collection, updated_at
      FROM sync_questions
      WHERE user_id = ? AND updated_at > ?
      ORDER BY updated_at ASC
      LIMIT 10000
    `)
    .bind(auth.userId, lastSyncTime)
    .all();

  return c.json({
    code: 0,
    message: 'Synced successfully',
    data: {
      server_time: now,
      pull_activities: pullActivitiesResult.results || [],
      pull_questions: pullQuestionsResult.results || [],
      pushed_activities_count: pushActivities.length,
      pushed_questions_count: pushQuestions.length,
    },
  });
});

export default app;
