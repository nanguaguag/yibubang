import { pushMutations, pullChanges } from './sync_v2';
import { Hono } from 'hono';
import { cors } from 'hono/cors';

type Bindings = {
  DB: D1Database;
  BACKUP_BUCKET?: R2Bucket;
};

interface DeviceAuth {
  deviceId: string;
  userId: string;
  deviceName: string;
}

const app = new Hono<{ Bindings: Bindings }>();

// 全局异常拦截，确保透传真实服务端错误详情（如 D1 缺表/约束/校验错误），避免黑盒 500
app.onError((err, c) => {
  const msg = err instanceof Error ? err.message : String(err);
  console.error('[sync-server] Unhandled error:', msg, err);
  return c.json({ code: 500, message: msg }, 500);
});

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
    version: '2.0.0',
    protocol: 2,
    status: 'ok',
    timestamp: Date.now(),
  });
});

app.get('/api/health', (c) => {
  return c.json({ status: 'ok', protocol: 2, timestamp: Date.now() });
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

// 5. 核心增量同步接口 (Push & Pull，支持 GZip 请求体压缩与 push_only 批处理加速)
app.post('/api/sync', async (c) => {
  const db = c.env.DB;
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  let body: Record<string, any> = {};
  try {
    const contentEncoding = (c.req.header('Content-Encoding') || '').toLowerCase();
    if (contentEncoding.includes('gzip') && c.req.raw.body) {
      const ds = new DecompressionStream('gzip');
      const decompressed = c.req.raw.body.pipeThrough(ds);
      const text = await new Response(decompressed).text();
      body = JSON.parse(text);
    } else {
      body = await c.req.json();
    }
  } catch {
    body = {};
  }

  if (body.protocol !== 2) {
    return c.json({ code: 426, message: 'Please upgrade the client to sync protocol v2' }, 426);
  }
  const now = Date.now();
  const accepted = await pushMutations(db, auth.userId, auth.deviceId, body.mutations, now);
  // 只在有新上报时更新活跃时间，分页与空增量不产生用户表写放大。
  if (accepted.length > 0) {
    await db.batch([
      db.prepare('UPDATE devices SET last_sync_at=? WHERE device_id=? AND last_sync_at<?').bind(now,auth.deviceId,now-60000),
      db.prepare('UPDATE users SET last_sync_at=? WHERE user_id=? AND last_sync_at<?').bind(now,auth.userId,now-60000),
    ]);
  }

  // 批量上传中间分片启用 push_only=true，跳过 pullChanges 全量扫描，最后一片再统一拉取合并。
  if (body.push_only === true) {
    return c.json({
      code: 0,
      message: 'Synced successfully',
      data: {
        protocol: 2,
        accepted_seqs: accepted,
        server_time: now,
        push_only: true,
        has_more: false,
        accepted_count: accepted.length,
      },
    });
  }

  const page = await pullChanges(db, auth.userId, Number(body.pull_cursor) || 0,
    body.high_watermark == null ? undefined : Number(body.high_watermark));

  return c.json({
    code: 0,
    message: 'Synced successfully',
    data: {
      protocol: 2, accepted_seqs: accepted,
      server_time: now,
      ...page,
      accepted_count: accepted.length,
    },
  });
});

// 6. R2 SQLite 整库冷备快照管理接口
app.post('/api/backup/upload', async (c) => {
  const db = c.env.DB;
  const bucket = c.env.BACKUP_BUCKET;
  if (!bucket) {
    return c.json({ code: 501, message: 'R2 storage is not configured' }, 501);
  }
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const checksum = c.req.header('X-Backup-Checksum') || '';
  const timestampStr = c.req.header('X-Backup-Timestamp') || Date.now().toString();
  const maxRetained = Math.max(1, Math.min(50, Number(c.req.header('X-Max-Retained')) || 10));
  const filename = `${timestampStr}.sqlite.gz`;
  const key = `backups/${auth.userId}/${filename}`;

  const bodyStream = c.req.raw.body;
  if (!bodyStream) {
    return c.json({ code: 400, message: 'Empty backup stream' }, 400);
  }

  await bucket.put(key, bodyStream, {
    httpMetadata: { contentType: 'application/gzip' },
    customMetadata: {
      userId: auth.userId,
      checksum,
      timestamp: timestampStr,
    },
  });

  // 轮转自动清理：保留最近 maxRetained 个快照
  try {
    const listResult = await bucket.list({ prefix: `backups/${auth.userId}/` });
    if (listResult.objects.length > maxRetained) {
      const sorted = [...listResult.objects].sort((a, b) => b.key.localeCompare(a.key));
      const toDelete = sorted.slice(maxRetained);
      for (const obj of toDelete) {
        await bucket.delete(obj.key);
      }
    }
  } catch (err) {
    console.error('Failed to prune old backups:', err);
  }

  return c.json({
    code: 0,
    message: 'Backup uploaded successfully',
    data: {
      filename,
      key,
      timestamp: Number(timestampStr),
    },
  });
});

app.get('/api/backup/list', async (c) => {
  const db = c.env.DB;
  const bucket = c.env.BACKUP_BUCKET;
  if (!bucket) {
    return c.json({ code: 501, message: 'R2 storage is not configured' }, 501);
  }
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const listResult = await bucket.list({ prefix: `backups/${auth.userId}/` });
  const backups = listResult.objects
    .map(obj => {
      const filename = obj.key.split('/').pop() || '';
      return {
        key: obj.key,
        filename,
        size: obj.size,
        uploaded: obj.uploaded.getTime(),
        checksum: obj.customMetadata?.checksum || '',
        timestamp: Number(obj.customMetadata?.timestamp) || obj.uploaded.getTime(),
      };
    })
    .sort((a, b) => b.timestamp - a.timestamp);

  return c.json({
    code: 0,
    message: 'Success',
    data: { backups },
  });
});

app.get('/api/backup/download/:filename', async (c) => {
  const db = c.env.DB;
  const bucket = c.env.BACKUP_BUCKET;
  if (!bucket) {
    return c.json({ code: 501, message: 'R2 storage is not configured' }, 501);
  }
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const filename = c.req.param('filename');
  if (!filename || filename.includes('..') || filename.includes('/')) {
    return c.json({ code: 400, message: 'Invalid filename' }, 400);
  }

  const key = `backups/${auth.userId}/${filename}`;
  const object = await bucket.get(key);
  if (!object) {
    return c.json({ code: 404, message: 'Backup not found' }, 404);
  }

  return new Response(object.body, {
    headers: {
      'Content-Type': 'application/gzip',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'X-Backup-Checksum': object.customMetadata?.checksum || '',
      'X-Backup-Timestamp': object.customMetadata?.timestamp || '',
    },
  });
});

app.delete('/api/backup/:filename', async (c) => {
  const db = c.env.DB;
  const bucket = c.env.BACKUP_BUCKET;
  if (!bucket) {
    return c.json({ code: 501, message: 'R2 storage is not configured' }, 501);
  }
  const auth = await authenticateDevice(db, c.req.header('Authorization'));
  if (!auth) {
    return c.json({ code: 401, message: 'Unauthorized device' }, 401);
  }

  const filename = c.req.param('filename');
  if (!filename || filename.includes('..') || filename.includes('/')) {
    return c.json({ code: 400, message: 'Invalid filename' }, 400);
  }

  const key = `backups/${auth.userId}/${filename}`;
  await bucket.delete(key);
  return c.json({ code: 0, message: 'Backup deleted successfully' });
});

export default app;
