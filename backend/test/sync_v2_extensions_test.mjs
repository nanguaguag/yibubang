import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pushMutations, pullChanges } from '../src/sync_v2.ts';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function createTestDatabase() {
  const db = new DatabaseSync(':memory:');
  const schemaPath = path.join(__dirname, '..', 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf8');
  db.exec(schema);

  const wrapper = {
    prepare(sql) {
      const stmt = db.prepare(sql);
      return {
        bind(...args) {
          return {
            async all() {
              const results = stmt.all(...args);
              return { results };
            },
            async first() {
              return stmt.get(...args);
            },
            async run() {
              return stmt.run(...args);
            }
          };
        }
      };
    },
    async batch(statements) {
      db.exec('BEGIN');
      try {
        for (const s of statements) {
          if (s.run) await s.run();
        }
        db.exec('COMMIT');
      } catch (err) {
        db.exec('ROLLBACK');
        throw err;
      }
    }
  };
  return { db, wrapper };
}

test('D1 增量扩展：卡片、记忆曲线与复习计划成功 push 并通过 pullChanges 拉取', async () => {
  const { wrapper } = createTestDatabase();
  const userId = 'u_test_ext';
  const deviceId = 'd_device_1';
  const stream = '0123456789abcdef0123456789abcdef';
  const now = Date.now();

  const mutations = [
    {
      seq: 1,
      stream,
      kind: 'flashcard',
      id: 'fc_001',
      payload: {
        title: '测试卡片',
        front: '正面题干',
        back: '反面解析',
        question_id: 'q_123',
        tags: '生理,核心',
        created_at: now,
        updated_at: now,
      }
    },
    {
      seq: 2,
      stream,
      kind: 'spaced_item',
      id: 'fc_001',
      payload: {
        plan_id: 'plan_main',
        item_type: 1, // flashcard
        state: 1, // learning
        step: 1,
        reps: 2,
        lapses: 0,
        difficulty: 4.5,
        stability: 2.1,
        due_date: now + 86400000,
        last_review_at: now,
        extra: JSON.stringify({ fsrs_history: [] }),
        updated_at: now,
      }
    },
    {
      seq: 3,
      stream,
      kind: 'review_plan',
      id: 'plan_main',
      payload: {
        name: '期末冲刺计划',
        bank_id: 'dental_final',
        daily_new_target: 30,
        daily_review_limit: 80,
        source_types: '["wrong","collected"]',
        covered_subjects: '["201","202"]',
        created_at: now,
        updated_at: now,
      }
    }
  ];

  const accepted = await pushMutations(wrapper, userId, deviceId, mutations, now);
  assert.deepEqual(accepted, [1, 2, 3]);

  // 从 0 游标拉取变更
  const page = await pullChanges(wrapper, userId, 0);
  assert.equal(page.pull_flashcards.length, 1);
  assert.equal(page.pull_flashcards[0].id, 'fc_001');
  assert.equal(page.pull_flashcards[0].title, '测试卡片');

  assert.equal(page.pull_spaced_items.length, 1);
  assert.equal(page.pull_spaced_items[0].item_id, 'fc_001');
  assert.equal(page.pull_spaced_items[0].reps, 2);

  assert.equal(page.pull_review_plans.length, 1);
  assert.equal(page.pull_review_plans[0].id, 'plan_main');
  assert.equal(page.pull_review_plans[0].daily_new_target, 30);
});

test('D1 增量扩展：笔记 (note / note_delete) 与主观题自评状态双向同步与防复活', async () => {
  const { wrapper } = createTestDatabase();
  const userId = 'u_test_notes';
  const deviceId = 'd_device_notes';
  const stream = 'abcdef0123456789abcdef0123456789';
  const now = Date.now();

  const accepted = await pushMutations(wrapper, userId, deviceId, [
    {
      seq: 1,
      stream,
      kind: 'question',
      id: 'q_subj_1',
      payload: {
        chapter_id: 'ch_1',
        chapter_parent_id: 'sub_1',
        user_answer: '已掌握',
        status: 1,
        updated_at: now,
      }
    },
    {
      seq: 2,
      stream,
      kind: 'note',
      id: 'local_note_1',
      payload: {
        remote_id: '1346299',
        question_id: 'q_subj_1',
        content: '前馈调节的作用是防止负反馈矫枉过正',
        imgs: JSON.stringify([{ b_img: 'https://img.example/1.jpg', s_img: 'https://img.example/1_s.jpg' }]),
        timestamp: now,
        updated_at: now,
      }
    }
  ], now);
  assert.deepEqual(accepted, [1, 2]);

  let page = await pullChanges(wrapper, userId, 0);
  assert.equal(page.pull_questions.length, 1);
  assert.equal(page.pull_questions[0].user_answer, '已掌握');
  assert.equal(page.pull_questions[0].status, 1);
  assert.equal(page.pull_notes.length, 1);
  assert.equal(page.pull_notes[0].id, 'local_note_1');
  assert.equal(page.pull_notes[0].remote_id, '1346299');
  assert.equal(page.pull_notes[0].content, '前馈调节的作用是防止负反馈矫枉过正');

  // 删除笔记
  await pushMutations(wrapper, userId, deviceId, [
    {
      seq: 3,
      stream,
      kind: 'note_delete',
      id: 'local_note_1',
      payload: {}
    }
  ], now + 20);

  page = await pullChanges(wrapper, userId, 0);
  assert.equal(page.pull_notes.length, 0);
  assert.deepEqual(page.pull_deleted_notes, ['local_note_1']);
});

test('D1 增量扩展：卡片删除墓碑防复活', async () => {
  const { wrapper } = createTestDatabase();
  const userId = 'u_test_del';
  const deviceId = 'd_device_del';
  const stream = 'fedcba9876543210fedcba9876543210';
  const now = Date.now();

  await pushMutations(wrapper, userId, deviceId, [
    {
      seq: 1,
      stream,
      kind: 'flashcard',
      id: 'fc_del',
      payload: {
        title: '即将删除的卡片',
        front: 'A',
        back: 'B',
        created_at: now,
        updated_at: now,
      }
    }
  ], now);

  // 删除卡片
  await pushMutations(wrapper, userId, deviceId, [
    {
      seq: 2,
      stream,
      kind: 'flashcard_delete',
      id: 'fc_del',
      payload: {}
    }
  ], now + 10);

  const page = await pullChanges(wrapper, userId, 0);
  assert.equal(page.pull_flashcards.length, 0); // 已从投影删除
  assert.deepEqual(page.pull_deleted_flashcards, ['fc_del']); // 墓碑下发
});
