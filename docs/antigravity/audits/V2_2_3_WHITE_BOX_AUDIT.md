# v2.2.3 白盒源码审计

审计日期：2026-11-10。代码基线：`main@aa0a2d9c959128d647b5109cd447c450c150d593`，应用 2.2.3+213，用户库 v15。开始时工作区干净。本轮只新增审计材料和更新知识库，未修改产品逻辑、依赖、数据库版本，也未提交或部署。

存储说明：项目`.gitignore:61`忽略整个`docs/`目录，知识库和审计材料是本地文件，Git status/diff仍为空；未修改忽略规则或强制暂存。迁移到团队仓库时需明确纳入版本管理。

**核心结论：优先修同步协议的游标与确认语义，其次修本地状态写入的一致性。** 500 切片解决的是请求体大小和单次执行负担，不能保证完整恢复、断点续传或节省写入额度。最严重的问题包括同步静默遗漏、错误响应被当作成功、笔记新编辑被旧快照覆盖，以及未验证导入文件直接覆盖用户库。

## 1. 审计范围、证据与优先级

追踪了题目详情/网格 → Controller → Question 写入 → 用户库/官方队列，以及每日计划 → DailyReviewService → SpacedReviewRepository → SQLite；云同步同时审查客户端与仓库中的 `backend/src/index.ts`、`backend/schema.sql`。后端源码不等于线上当前部署版本，依赖客户端与后端配合的结论以该后端实现为前提。

证据等级：

- **已复现**：隔离 FFI 用户库、调用生产 Dart 方法、模拟 HTTP；或执行从后端源码提取的原始 SQL。
- **源码确定**：完整调用链能确认缺失或错误分支，尚未做对应实机/故障注入。
- **条件风险**：有明确触发前提，但未宣称实际线上发生率或性能耗时。

[复现探针](v2_2_3_reproduction_test.dart) 显式运行 **17/17 通过**。这里“通过”表示成功证明当前缺陷或排除错误假设，**不表示缺陷修复**。它不位于常规 test 目录，不应作为产品正确性的 CI 门禁。使用临时库及模拟 HTTP，未读取真实用户数据、未请求线上接口。FFI 引擎输出 3.43.2；[后端原始 SQL 探针](backend_sql_probe.py) 另用 Python SQLite 模拟 999 参数限制，未宣称在 Android SQLite 3.22 实机重跑。

复现命令（项目根目录）：

```sh
flutter test --no-pub --reporter expanded docs/antigravity/audits/v2_2_3_reproduction_test.dart
python3 docs/antigravity/audits/backend_sql_probe.py
```

本轮相关既有测试 38/38 通过（cloud_sync_service、sqlite_compatibility、daily_review_service、spaced_review_repository、spaced_repetition_engine、flashcard_system）。未重复跑全量205项；此前205/205是发布基线。代码示例中的新增API/表为设计方案，尚未实现，不能直接当作已经落地的补丁。

最终`flutter analyze --no-pub`为0 issues；局部格式化后的17项探针重新通过。验证日志位于本机会话`/tmp/yibubang_v223_audit_flutter.log`，原始产品文件Git diff为空。

| ID | 优先级 | 问题 | 证据 |
| --- | --- | --- | --- |
| A01 | P0 | Push/Pull 共用时钟游标，漏掉同步期间及慢时钟的本地变动；整行 LWW 丢并发字段 | 已复现 + 源码确定 |
| A02 | P0 | Pull 硬限 10,000，无续页，游标越过剩余记录；慢时钟的新入库状态也不可见 | 原始后端 SQL 已复现 |
| A04 | P0 | HTTP 200 空体/坏 JSON/缺少业务码被官方队列视为成功 | 已复现 |
| A05 | P0 | 第五次失败物理删除队列，进程重启无法恢复；任务没有账号归属 | 已复现 + 源码确定 |
| A06 | P0 | 笔记上传旧快照覆盖新编辑；删除与在途上传无法协调 | 已复现 + 源码确定 |
| A07 | P0 | 收藏/斩题写回旧页面整行状态，覆盖刚同步的答案；保存 Future 不受管理 | 已复现 + 源码确定 |
| A16 | P0 | 导入替换先覆盖用户库再验证，损坏输入导致原库丢失 | 已复现 |
| A03 | P1 | 切片无持久化 ACK，失败重传已完成批次；D1 无变化仍更新 | 已复现 |
| A08 | P1 | 测试切章未交卷，计时不入答题流水；切章控制器销毁时序不安全 | 源码确定 |
| A09 | P1 | 复习状态、答案和流水不是一个事务，评分按钮也无提交互斥 | 已复现 + 源码确定 |
| A10 | P1 | 复习时长单位错、统计排除复习流水、章节缓存未更新 | 已复现 + 源码确定 |
| A11 | P1 | Again 尾队列在斩题后残留，可重新激活已归档题/卡 | 已复现服务行为 + 源码确定 UI 链 |
| A12 | P1 | 答题旧状态在事务外读取；占位插入竞态；跨库统计缓存漂移 | 已复现 |
| A13 | P1 | 固定前缀新题、过滤后截断到期队列造成确定性饥饿 | 已复现 |
| A14 | P1 | “全部范围”实际只加载一个题库，候选来自用户全库；大 IN 超参数上限 | 源码确定 + 参数上限模拟 |
| A15 | P1 | ATTACH 固定别名的复合操作没有互斥；busy_timeout 不能修逻辑竞态 | 源码确定/并发条件 |
| A17 | P1 | 保留笔记时清空 Question 违反外键；删除无同步 tombstone | 已复现 + 源码确定 |
| A19 | P1 | FSRS 设置仅作用于按钮预测，实际服务仍默认 SM-2；参数语义混用 | 源码确定 |
| A20 | P1 | Notes 自愈失败后外键留在 OFF；历史升级覆盖缺口、索引自愈不足 | 已复现 + 待补历史夹具 |
| A18 | P2 | 固定 24 小时不是自然日；EF 下限后 Good 无回升，但没有死循环 | 源码确定 + EF 已复现 |

P0 表示存在直接丢失状态、同步义务或原始文件的路径；其中部分本地流水仍保留，可以人工恢复，不能把“自动增量永远跳过”等同于所有副本的物理删除。P1 中数据缓存不一致与业务失败优先于纯性能优化。

## 2. 每个问题的详细分析

### A01 · P0：同步游标混用了服务端时间和本地变动时间

**位置/函数**：[cloud_sync_service.dart:351](../../../lib/services/cloud_sync_service.dart#L351) `CloudSyncService.sync`，本地筛选 382/391，快照查询 370/389，合并 526，游标提交 568；[question.dart:649](../../../lib/models/question.dart#L649) `updateQuestion`。

**最小链路**：T0 提取上传快照；T1 用户完成一题；T2 请求返回 server_time；把 T2 保存为下一次筛选下界。T1 不在 T0 快照中，且 T1 < T2，下一次永远不再上传。探针用 100/199/200 时间值调用真实 sync 两次，第二次 push 为空，199 的本地记录仍在库中。设备比服务端慢几分钟时，连同步结束后新做的题也可能落在下界之前；老日期补写 Activities 也会被 `timestamp > cursor` 漏掉。

**根因**：一个 `_lastSyncTime` 同时担当本地上传确认、服务端拉取位置与设备时钟。LWW 的另一个独立问题是整行覆盖：A 离线改答案，B 离线只收藏，B 的旧答案随更新收藏整行上传，可能覆盖 A。时钟慢的后答记录输给时钟快的先答记录，`>=` 相等时间也没有稳定设备 tie-break。

**最小修复**：立即拆开 Push/Pull 游标；上传以本地可持久化变更序号确认，不能拿 server_time 筛本地操作。保存行为和 outbox 同事务，只确认此次实际发送的版本；下载用服务端变更序号。过渡期可用“本次提取前本地上界 + 稳定主键”分页和重叠窗口降低遗漏，但不能彻底解决时钟回拨、历史补录和并发字段冲突。

```sql
-- 仅在 user_data.sqlite 新增；Question.id 保持单列主键。
CREATE TABLE SyncOutbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL UNIQUE,
  payload TEXT NOT NULL
);
-- 与 Question / Activities 的本地写入处于同一事务。
INSERT INTO SyncOutbox(entity_type, entity_id, mutation_id, payload)
VALUES (?, ?, ?, ?);
```

```dart
final entries = await loadOutboxPage(limit: 500);
final ack = await api.push(entries);
await db.transaction((tx) async {
  // 服务端必须先持久化确认；按实际 mutation_id 确认，保留同题的新变更。
  await acknowledgeExactMutations(tx, ack.acceptedMutationIds);
});
```

冲突仲裁长期采用按字段版本（answer / collection / cut 分离）+ HLC/设备计数器及稳定 device_id。HLC 能建立确定性顺序，**不能从互不通信的离线设备恢复真实先后时间**；需保留所有答题事件及冲突记录，让冲突可解释、可恢复。

### A02 · P0：10,000 拉取上限造成不完整恢复

**位置/函数**：[backend/src/index.ts:300](../../../backend/src/index.ts#L300) `POST /api/sync`；流水查询 402，题目查询 415，返回游标 431；[cloud_sync_service.dart:439](../../../lib/services/cloud_sync_service.dart#L439) `sync` 后续批次改用上次 server_time。

**最小链路**：云端已有 10,441 题，新设备无待上传数据，所以只发 1 个请求。后端返回最早 10,000 条，客户端保存 now，剩余 441 条更新时间均 <= now，下次返回 0。对从源码提取的题目 Pull SQL实测：10441 → 10000 → 0。10,409 条历史流水同样会遗漏 409 条。多次强制同步仍可能只返回同一前 10,000 条。

**根因**：只有 LIMIT，没有 has_more、next_cursor、稳定同时间戳排序或快照上界。题目 Pull 用设备 updated_at，而非服务端入库版本；“新提交的慢时钟题目”也会被读过该时间的其他设备永远跳过。此外，后端 now 在异步写入前取得：另一请求可较早取 now、较晚提交，在客户端已推进之后才可见，时间游标仍可能漏记录。

**最小修复**：增加服务端提交顺序的 changelog（事务内分配 seq），响应 page_cursor / high_watermark / has_more。按页合并和提交游标，只有读完整个固定快照才推进完成位置。不能仅把 LIMIT 改成 500 或换成更大数字。

```sql
SELECT seq, entity_type, entity_id, payload
FROM SyncChanges
WHERE user_id = ? AND seq > ? AND seq <= ?
ORDER BY seq
LIMIT ?;
```

```dart
do {
  final page = await api.pull(cursor: cursor, through: highWatermark);
  await db.transaction((tx) async {
    await mergePage(tx, page);
    await savePullCursor(tx, accountId, page.nextCursor);
  });
  cursor = page.nextCursor;
  hasMore = page.hasMore;
} while (hasMore);
```

若临时采用 (server_ingested_at, id) keyset，必须处理晚提交早时间、相同毫秒与一致读；服务端事务内序号更可靠。

### A03 · P1：切片重复写放大 D1 额度消耗

**位置/函数**：[cloud_sync_service.dart:418](../../../lib/services/cloud_sync_service.dart#L418) `sync`，568 才持久化；[backend/src/index.ts:344](../../../backend/src/index.ts#L344) 题目写入，391 的多个 db.batch。

**最小链路**：501 题，首批 500 成功，第二批失败；下一次重新上传 500+1。生产方法模拟 HTTP 已观测上传量 [500,1,500,1]。21 个批次时第 21 批失败，会重传前 20 批；进程被杀也没有批次 ACK。一个 HTTP 内又切成多个 100 statement 的 db.batch，**仅每个 batch 原子**，不是整个请求原子。

**根因**：切片索引、ACK 只在内存；题目 SQL 的 CASE 仅决定写什么，旧/相等版本仍进入 UPDATE。执行原始 SQL确认，相同内容重放依然产生一次 SQLite UPDATE。流水 ignore 能保持逻辑去重，不等于所有 D1 执行都零计费。500 题 + 500 流水是最多 1,000 实体，不是最多 500 行。

**最小修复**：采用 A01 的持久化 outbox/精确 ACK；每个服务端批次带稳定 batch_id，收到 ACK 后删除对应 mutation。先对已有云端数据做摘要/版本对账，不能让每台新设备把同一历史都全量上传。旧/相同版本做条件 UPDATE，真正没有内容变化时不写：

```sql
INSERT OR IGNORE INTO sync_questions
  (user_id, question_id, status, collection, cut_question, user_answer, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?);
UPDATE sync_questions
SET status=?, collection=?, cut_question=?, user_answer=?, updated_at=?
WHERE user_id=? AND question_id=? AND updated_at < ?;
```

两阶段 SQL 必须在同一原子事务中。若保留同版本不同内容的仲裁，使用明确的版本元组和字段比较。**不能用更大时间戳“修复”已冲突的旧内容。**

配额按本项目给定免费额度 100,000 写行/天评估：20,850×4=83,400，×5=104,250；这是逻辑行量估算，实际还包含索引维护、账号活跃更新及去重写语义，应以 D1 的实际 rows_written 为准。源码没有自动无限重试循环；风险来自启动、手动重试、强制同步和网络异常后的再触发，不能宣称已有指数退避无限重试。

### A04 · P0：网络状态被错误转换为业务成功

**位置/函数**：[request.dart:79](../../../lib/common/request.dart#L79) `basicReq` 空体分支与 91 解析失败分支；[ykb_sync_service.dart:450](../../../lib/services/ykb_sync_service.dart#L450) `_executeItemRequest`。

**最小链路**：官方端/代理返回 HTTP 200，但 body 是空串、HTML 或坏 JSON。basicReq 返回 code='200' 的错误 map；队列判断 code='200'，物理删除任务。探针输入 `not-json` 已证实队列清空。另 `resp['code'] ?? '200'` 把缺失业务 code 的 JSON 也当成功。

**根因**：HTTP code 和业务 code 共用字段，且默认成功。

**最小修复**：传输异常与协议异常必须抛出/返回明确失败类型，成功必须校验业务码和该接口所需 ACK。不要凭存在 HTTP 200 认定已保存。

```dart
if (response.statusCode != 200) throw HttpException('HTTP failure');
final Object? value = jsonDecode(response.body);
if (value is! Map || value['code'] == null) {
  throw const FormatException('invalid business response');
}
final success = value['code'].toString() == '200';
```

JSON解析异常也不能回填 code=HTTP200；可将原始 body 持久化诊断，但保持队列待处理。

### A05 · P0：离线队列会永久丢义务，没有真正的退避/账号隔离

**位置/函数**：[ykb_sync_service.dart:535](../../../lib/services/ykb_sync_service.dart#L535) `processQueue`（562、591删除）；[note_service.dart:474](../../../lib/services/note_service.dart#L474) `processQueue`（529、550删除）；[request.dart:23](../../../lib/common/request.dart#L23) 当前登录信息；[database_helper.dart:940](../../../lib/db/database_helper.dart#L940) 队列表定义。

**最小链路**：弱网/服务错误累计 5 次 → 队列行被删除 → 重启不能恢复，笔记 delete 甚至没有本地正文可重建删除意图。探针以 retry_count=4、HTTP500 证实官方任务被删。A账号离线入队，退出后登录B账号；任务没有 owner_user_id，basicReq 发送时注入B账号凭据，A的待上传数据会被提交给B。

**根因**：retry_count/created_at/payload 实际已经落 SQLite，问题不是它们只在内存；是失败项被物理删除。没有 next_attempt_at、dead-letter 状态、lease 或服务端 idempotency key。Note 每次最多消费 15 项且不会主动续批；处理中新增任务的 processQueue 调用因 busy 返回，结束后没有再唤醒，余下项可能一直等到下一次外部触发。retryItem 也绕开后台互斥。网络响应丢失后重发官方答题是否产生远端重复流水，取决于官方接口幂等性，尚未实测。

[request.dart:50](../../../lib/common/request.dart#L50)的基础HTTP请求没有应用层timeout；遇到连接未断但服务端不返回的弱网，请求可长时间占住_isProcessingQueue。增加持久化退避前，也必须给请求总deadline并在超时后关闭此次client，不能只设置计数。

**最小修复**：增加待处理/暂停/死信状态，失败超过上限暂停而保留；将尝试时间、账号、事件ID持久化。旧任务账号不可推断时隔离为待认领，不自动发送。

```sql
-- 用户库下一版本按缺列检查迁移：
ALTER TABLE YkbSyncQueue ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE YkbSyncQueue ADD COLUMN owner_user_id TEXT;
ALTER TABLE YkbSyncQueue ADD COLUMN state TEXT NOT NULL DEFAULT 'pending';
UPDATE YkbSyncQueue
SET retry_count=retry_count+1, next_attempt_at=?, state=?, last_error=?
WHERE id=?;
```

```dart
// retryDelay = min(maxDelay, baseDelay * 2^attempt) + jitter。
// 只消费 owner == 当前账号 && 到期 && pending 的任务；启动从数据库恢复定时。
if (isAuthenticationFailure(error)) await pauseAccountQueue(owner);
else await scheduleRetryOrDeadLetter(item, error);
```

后台与手动重试使用同一任务 lease；远端不能提供幂等键时，承认只能 at-least-once，提供回查/对账，不能承诺 exactly-once。

### A06 · P0：笔记上传的旧快照覆盖新编辑，远端身份关联不可靠

**位置/函数**：[note_service.dart:578](../../../lib/services/note_service.dart#L578) `_processUploadItem`；图片回写 662、remoteId 回查 720/736、完成标记 742；`deleteNote` 107。

**最小链路**：上传开始读取 content=old、updated_at=100 → 图片 HTTP 慢 → 用户保存 new/200 → 图片完成后把 note.toMap 整行写回 → old/100 覆盖 new/200。模拟图片上传中更新数据库已复现。另一链路：新笔记上传在途，用户删除本地笔记及队列，没有 remoteId 所以不创建删除任务；在途请求仍在服务端创建笔记，之后拉取可复活。返回后的 sync_status=0 无版本条件，也会错误宣称新编辑已同步。

**根因**：网络 await 前后的本地对象不是同一版本；删除队列行不能取消已经发出的请求。创建后的 remoteId 通过 getNote 的第一项猜测，多条笔记时可能关联错误对象。

**最小修复**：只更新图片/远端身份字段，使用本地 revision CAS；新内容仍待上传。正文保存与 outbox 同事务；删除保存 tombstone；晚到上传 ACK 若已删除，要补远端删除。创建必须取得该次操作返回的真实 ID，或可靠的 client_mutation_id/精确回查。

```dart
final version = note.updatedAt;
final affected = await db.update(
  'Notes', {'imgs': encodedUploadedImages},
  where: 'id = ? AND updated_at = ?', whereArgs: [note.id, version],
);
if (affected == 0) {
  // 新编辑仍保留；重读当前版本再排队，不能写回旧正文。
  await enqueueCurrentNoteVersion(note.id);
}
```

相同毫秒可能有多次编辑，正式修复应使用单调 revision，而非仅毫秒 CAS。完成状态仅能确认服务端实际收到的那一版本。

### A07 · P0：旧页面对象写回整行，保存和生命周期脱节

**位置/函数**：[question.dart:489](../../../lib/models/question.dart#L489) `updateQuestionSimple`；[question_detail_controller.dart:293](../../../lib/screens/question_detail/question_detail_controller.dart#L293) `submitAnswer`，415 `toggleCollection`，425 `toggleCut`；[question_detail_page.dart:173](../../../lib/screens/question_detail_page.dart#L173) 相邻章节预取。

**最小链路**：详情页持有未做题 uq0 → 后台云同步把DB更新为已答A → 用户只点收藏 → updateQuestionSimple 把旧 status=0、answer='' 连同收藏写回，赋新时间戳 → 答案被清除并有机会反向覆盖云端。直接调用真实方法已复现。预取用户状态长时间缓存，也会带入过时状态。提交/收藏/斩题调用的 Future 不 await、不捕获错误；UI 已显成功，但落库失败没有恢复。普通 Pop 本身不会取消 Dart Future，不能把“返回”一概说成必丢；真正风险是未落盘就杀进程、异常未处理、对象在 await 期间又被修改。

**根因**：字段意图被转换为整行旧快照；没有版本检查、保存完成边界或错误回滚。题目计时以 wall clock 记录，在后台停留/时钟跳变会污染时长；未答离开的思考时间也没有明确累计策略。

**最小修复**：收藏/斩题用字段专用更新；答题传不可变提交值；Controller追踪pending Future，按钮/返回等待本地事务完成，网络上传只由已持久化 outbox 执行。恢复用户状态时重读数据库，不复用长寿命预取快照。

```dart
await db.update('Question',
  {'collection': newCollection, 'updated_at': clock.nowMs()},
  where: 'id = ?', whereArgs: [questionId]);
// 答案和斩题有各自意图 API；均在事务中记录同步变更。
```

计时改用每题 Stopwatch 与应用生命周期暂停/继续，持久化测试会话和每题累计值；明确“仅答题时间”还是“阅读总时间”的产品契约。

### A08 · P1：测试退出/切章不闭环，控制器在异步空档已失效

**位置/函数**：[question_detail_page.dart:267](../../../lib/screens/question_detail_page.dart#L267) `_switchToChapter`（确认 275、销毁 335、await init 344）；[question_detail_controller.dart:668](../../../lib/screens/question_detail/question_detail_controller.dart#L668) `dispose`，485 `onModeChanged`；[question.dart:375](../../../lib/models/question.dart#L375) `gradePendingQuestions`。

**最小链路**：测试模式留下 status=4 → 切章弹窗确认 → 直接换Controller，没有gradePendingQuestions，也没切mode=0 → 新Controller加载全局mode=2，测试并未真正结束，旧章节答案待提交。系统返回详情页也无测试交卷拦截。真正交卷时每题durationMs=0，测试总耗时只有SharedPreferences的全局testElapsedMs；可见计时不会进入正确的单题统计。

切章在旧Controller.dispose后等待newController.init，此时State仍指向旧Controller；用户返回会再次dispose旧实例，新Controller未释放；异步刷新还可能订阅已dispose notifier。新Controller.init本身也可能失败，没有finally释放切章锁。详情默认返回不带当前Chapter，网格期待Chapter返回值的811分支接不到切章结果。

**最小修复**：统一 `finishTestAndFlush`，所有模式退出、切章、返回复用；在新Controller初始化完成且mounted后原子交换，再释放旧实例；失活时dispose新实例；锁用try/finally。交卷从每题累计时间落库，不把整个总时长重复记给每题。

```dart
await oldController.finishTestAndFlush();
final next = await createInitializedController(target);
if (!mounted) { next.dispose(); return; }
setState(() => _controller = next);
oldController.dispose();
```

返回拦截只拦一次：先等待flush/确认，再Navigator.pop(currentChapter)；桌面嵌套路由结果继续按既有冒泡契约处理。

### A09 · P1：复习多表更新不原子，快速评分会重复推进

**位置/函数**：[daily_review_service.dart:185](../../../lib/services/daily_review_service.dart#L185) `submitReviewResult`：210先存调度，224/233存答案，271存流水；126 `cutQuestion`；[daily_review_page.dart:226](../../../lib/screens/daily_review_page.dart#L226) `_onRatingSelected`，1198按钮回调。

**最小链路**：保存调度成功，Question成功，Activities因SQL/磁盘失败 → 方法抛出但前两项已提交。探针用Activities插入触发器RAISE(ABORT)已复现 reps=1、答案正确、流水0。快速双击评分，在第一次await前没有_busy，两个调用可取相同item，形成两条流水/丢失一次reps增量或跳过下一题；同毫秒id=rev_time_question还可能冲突。await后页面已pop，setState/弹窗仍可执行。

**根因**：可选executor只是透传，不自动提供事务；UI默认调用没有executor，saveItem默认单次REPLACE写。异步业务操作无互斥/幂等键。

**最小修复**：公开服务入口默认开启用户库事务，事务内函数接受DatabaseExecutor；读取旧item也在事务里。请求ID先生成、去重后再演进。UI禁用重复提交且await后检查mounted。

```dart
Future<SpacedReviewItem> submitReviewResult(...) async {
  final db = await _userDbHelper.database;
  return db.transaction((tx) => submitReviewInTransaction(tx, ...));
}
// InTransaction 内：读item → 算法 → 答案/缓存 → review事件 → outbox。
```

事务内禁止通过全局db再次发SQL，也不等待网络；不依赖batch外部读取来保证原子状态转换。

### A10 · P1：复习流水/统计/缓存契约不一致

**位置/函数**：[daily_review_service.dart:267](../../../lib/services/daily_review_service.dart#L267) `submitReviewResult`，279写durationSeconds；[answer_statistics.dart:55](../../../lib/models/answer_statistics.dart#L55) `_queryAnswersInRange` 与115 `getPeriodStats`；[daily_review_service.dart:438](../../../lib/services/daily_review_service.dart#L438) `_countCompletedToday`。

**最小链路**：8秒复习写duration=8（已复现），统一毫秒消费者只可解释成8ms。更直接的是统计仅接纳NewAnswer/Backfill，复习标题“记忆曲线复习/闪卡复习”被全部排除。普通复习更新Question.status，却不更新IdentitySubject/IdentityChapter、不notifyAnswersChanged；bank_id来自plan.bankId，默认全范围时可能为空，章节/学科字段也缺失。昨日学过、今日Again后Good的题，最终reps=1/lapses>0；初次Again被分到“复习”，非“新学”，按当前状态倒推今日完成数会误计，Cram再次评分也覆盖当天计数依据。

**根因**：多入口写同一表，却未共享事件单位、分类与投影维护；学习统计从最终状态猜测事件种类。

**最小修复**：统一ReviewEvent（kind、was_new、plan_id、duration_ms、题库来源）；Question行为和章节缓存共用事务或标dirty按ATTACH重算。实体来源记录实际resolvedBankId及权威IdentityQuestion关系；统计显式定义哪些事件计作答/学习，避免把斩卡伪装为答对。

```dart
final durationMs = Duration(seconds: durationSeconds).inMilliseconds;
await tx.insert('ReviewEvents', {
  'id': eventId, 'item_id': itemId, 'plan_id': planId,
  'was_new': wasNew ? 1 : 0, 'duration_ms': durationMs, 'rating': rating.value,
});
```

先确定真实事件类型/历史范围，再对该类历史Activities做×1000迁移；禁止全表倍乘，正常答题本来就是毫秒。

### A11 · P1：斩题后 Again 队列仍可复活归档状态

**位置/函数**：[daily_review_page.dart:248](../../../lib/screens/daily_review_page.dart#L248) Again加入尾队列，282 `_handleCutQuestion`；[daily_review_service.dart:126](../../../lib/services/daily_review_service.dart#L126) `cutQuestion`，185 `submitReviewResult`；[spaced_review_repository.dart:528](../../../lib/repositories/spaced_review_repository.dart#L528) `deleteFlashcard`。

**最小链路**：q Again入尾队列 → 下一次遇到q斩掉 → 只移动currentIndex，尾部其他q副本没清 → 以后再评分 → submitReviewResult无条件cut_question='0'，算法将mastered改成learning/review。服务链“cut后再submit”已复现。闪卡类似，虽然不改原Question，也会重启自身mastered状态。删除闪卡的数据库事务会删除SpacedReviewItem，这是正确实现；但仍打开的会话保留对象，提交不存在项会按question类型兜底创建，可能产生孤儿记忆项。

**根因**：只在构建会话时过滤，提交时不验证当前cut/实体存在；队列副本没有失效机制。原题和关联闪卡是独立实体，是否斩原题自动斩卡应由产品明确，不能擅自强制级联。

**最小修复**：斩后从剩余队列按itemId清除所有副本；提交在事务里重查实体与suspended/cut状态，归档后的旧会话提交返回冲突，显式“重新学习”才能解除斩题。删除/编辑事件让已打开会话失效。

```dart
_queue.removeWhere((entry) => entry.questionId == cutItemId);
// 在服务事务中也验证：若已cut/mastered-by-cut/deleted，则拒绝旧提交。
```

自然掌握与用户主动斩题目前共用mastered，建议额外保存suspension_reason/cut来源，否则不能区分主动复习与旧会话复活。

### A12 · P1：事务外旧状态读取、占位创建竞态及跨库缓存漂移

**位置/函数**：[question.dart:510](../../../lib/models/question.dart#L510) `updateQuestion`，527读previousStatus，547 batch，721提交；432 `getUserQuestions`；[data_transfer.dart:59](../../../lib/db/data_transfer.dart#L59) `rebuildAttachedQuestionCount`。

**最小链路**：同题两个并行update都读到status=0，一个写正确、一个写错误 → 两次都加1 → 单题最终只有一状态，课程correct=1/incorrect=1。已复现。两个getUserQuestions同时读缺失，后续普通INSERT第二个UNIQUE失败，也已复现。批处理事务的原子性不能保护事务外的旧值读取。

共享题存在A/B库，redo B仅减B统计，A仍旧值；以后在A答同题又增A，可超过总题量。现有非零delta分支也没有下限保护，计数基线已漂移时撤回可负数；注释中的“截断”分支实际只处理delta=0情况。

**最小修复**：先读取只读题库关系；再在用户库单事务读取最新status、计算delta、保存state/Activities/outbox。所有相关题库统计视为可重建投影：标dirty后按需ATTACH重算，或通过权威映射批量更新，不加bank_id到Question主键。占位使用INSERT OR IGNORE，随后重读返回最新对象。不要忽略冲突后继续返回虚假的status=0。

```dart
await userDb.transaction((tx) async {
  final old = await tx.query('Question', where: 'id=?', whereArgs: [id]);
  final delta = transitionDelta(old, immutableNewAnswer);
  await applyAnswerAndCounters(tx, delta, relations);
  await appendActivityAndOutbox(tx, immutableNewAnswer);
});
```

计数下限可作防御，但不能用max(0,...)掩盖根本失配；需记录dirty并重算校验。

**章节重做的批量开销**：[question_grid_page.dart:459](../../../lib/screens/question_grid_page.dart#L459) `clearUserAnswers`（479循环）与523 `clearWrongAnswers`（563循环）逐题await updateQuestion；每题再查询关系、提交独立batch、追加一条重置Activities并广播刷新，大章节有数百个独立事务。数据库I/O/广播放大会拖慢完成，尚未做设备fsync/掉帧实测，不能把每条await等同主线程阻塞。重做期间没有独占操作状态，用户可再答题/切章；循环读取可变_currentChapter还会污染后续上下文。

最小方案：固定本次bank/chapter/filter的快照，ATTACH题库后在一个用户库事务用集合SQL重置，再一次重算和一次通知；官方redo任务与本地重置在同一事务持久化，网络在事务外执行。保留原答案历史分隔语义：

```sql
UPDATE main.Question
SET user_answer = user_answer || ';', status=0, updated_at=?
WHERE status IN (1,2) AND id IN (
  SELECT question_id FROM redo_bank.IdentityQuestion
  WHERE identity_id=? AND subject_id=? AND chapter_id=?
);
```

错题重做用status=2且保留现有筛选范围，不能不经产品确认重置更多题目；这仍是SQLite原生集合操作，不向题库写入。若章节事务实测过长，再设计具有显式中间状态的分批任务，不能静默半完成。

### A13 · P1：确定性抽题饥饿，不是单纯随机不均

**位置/函数**：[daily_review_service.dart:910](../../../lib/services/daily_review_service.dart#L910) `_queryBankNewQuestionIds`（932 LIMIT）；597 `_drawNewQuestionQueue`；469 `_fetchDueReviewQueue`（477先limit*3）；[spaced_review_repository.dart:258](../../../lib/repositories/spaced_review_repository.dart#L258) `getDueItems`。

**最小链路**：dailyNewTarget=1，只取固定前6题（count×2再×3），6题已在记忆曲线中 → 返回0，即使还有14题未学。探针20题实测；SQL无ORDER BY不能依赖固定排序，但同数据库查询计划下稳定前缀足以产生问题。到期上限=1，最早3项全属未覆盖学科，合法第4项永远读不到，探针已复现。

**根因**：在真正可用性筛选前LIMIT，并没有继续分页；候选源虽Set+shuffle，打乱的是已截断集合。错题/收藏/笔记的候选合并是每题均匀shuffle，不是已有“学科加权公平分配”；不同来源数量悬殊时稀有来源被概率压制，但不能称来源排列顺序必然饥饿。

**最小修复**：优先把可用性放到SQL中，再限额；或keyset续页直到填满/耗尽，保存抽题位置并环绕。跨库筛选用ATTACH SQL反连接用户状态；关系来自IdentityQuestion。

```sql
SELECT DISTINCT q.id
FROM review_bank.Question q
JOIN review_bank.IdentityQuestion iq ON iq.question_id=q.id
LEFT JOIN main.SpacedReviewItem sr ON sr.item_id=q.id
LEFT JOIN main.Question uq ON uq.id=q.id
WHERE (sr.item_id IS NULL OR sr.state=0)
  AND COALESCE(uq.cut_question,'0')!='1'
  AND q.id > ?
ORDER BY q.id
LIMIT ?;
```

按学科/来源做轮转配额、欠额结转及“等待天数”老化；shuffle在合格候选内部执行。大库不对全表ORDER BY RANDOM，不做Dart逐题跨库查询拼接。

### A14 · P1：全库计划只加载一个库；大列表超SQLite参数上限

**位置/函数**：[daily_review_service.dart:992](../../../lib/services/daily_review_service.dart#L992) `_resolveBankId`，942 `_loadQuestionsByIds`；[question.dart:442](../../../lib/models/question.dart#L442) `getUserQuestions`；[spaced_review_repository.dart:411](../../../lib/repositories/spaced_review_repository.dart#L411) `getFlashcardsByIds`。

**最小链路**：用户库含A/B学科错题，plan为all且未指定bankId；候选SQL从整个用户库挑qB，但实体只去activeBank A加载，得到question=null，合法B题进入不可作答或兜底自评队列。章节共享关系还被单一chapter_parent_id代替，跨章/库复用题可能错误排除或放行。题量/复习上限较大，构造1000+占位参数，Android宿主可能抛too many SQL variables；现代FFI 3.43.2通过并不能排除旧宿主限制。只对新候选分块100并未保护getUserQuestions、到期limit*3等链。

**根因**：ReviewPlan.targetType存在，实际范围解析没有枚举全库；entity加载、bankId来源与候选不一致。多数批量IN没有共用参数预算。

**最小修复**：构建scope-resolver，候选查询携带实际bankId；global question_id去重、多个来源只选择一份展示，状态仍共享。安装后维护题目到题库/学科只读关系的用户库投影，可由ATTACH刷新。实体不存在要继续补抽并显式记录不可用原因。

```dart
const parameterBudget = 500;
final result = <String, UserQuestion>{};
for (var i = 0; i < ids.length; i += parameterBudget) {
  final chunk = ids.sublist(i, min(i + parameterBudget, ids.length));
  result.addAll(await loadChunk(chunk)); // 每批一次SQL；非逐题查询。
}
```

getUserQuestions中existingRows.firstWhere还形成O(n²)对象归并；用id→row Map改为O(n)。这不涉及跨库统计聚合，仍严格保留SQL ATTACH聚合契约。

### A15 · P1：ATTACH复合操作竞争，单纯放大timeout不充分

**位置/函数**：[data_transfer.dart:13](../../../lib/db/data_transfer.dart#L13) `rebuildQuestionCount`（42-52）；[database_helper.dart:285](../../../lib/db/database_helper.dart#L285) `onConfigure`；[question_bank_repository.dart:624](../../../lib/repositories/question_bank_repository.dart#L624) 安装ATTACH；[ykb_bank_smart_sync_service.dart:1070](../../../lib/services/ykb_bank_smart_sync_service.dart#L1070) 暂存库timeout。

**最小链路**：两次重算并发，共用用户连接；A ATTACH qbank成功，A等待下一次SQL时B也ATTACH qbank → alias already in use。单条sqflite请求串行不等于“ATTACH→事务→DETACH”整个序列互斥。重算结束与另一ATTACH/备份关闭操作也可能相交。

**根因**：固定别名是连接级状态，未放入同一调度临界区。现状不是“所有用户库timeout分散3000~5000”：用户onConfigure根本没设置busy_timeout，重算设3000；找到的5000在题库暂存写连接，不是同一个用户库。正常单用户连接写事务被sqflite串行化，三路异步启动本身**不足以证明database is locked或死锁**；跨连接读写、长事务和连接关闭才需压力验证。

**最小修复**：统一DBCoordinator调度用户库复合操作，包括rebuild、install、import/export/close；锁内用唯一/受控别名，finally DETACH。连接级timeout可配置为10000，避免重算又覆写3000，但它只是外部锁等待上限，不修别名/快照/排队公平性。

```dart
await dbCoordinator.runExclusive(() async {
  await db.execute('ATTACH DATABASE ? AS rebuild_bank', [bankPath]);
  try {
    await db.transaction((tx) =>
      rebuildAttachedQuestionCount(tx, bankId, alias: 'rebuild_bank'));
  } finally {
    await db.execute('DETACH DATABASE rebuild_bank');
  }
});
```

题库只参与SELECT；若采用mode=ro URI强制ATTACH权限，必须验证sqflite各宿主的URI支持并正确Uri编码，不能未经验证把URI当普通文件路径。前台高优先级短事务与后台有界批次分开，批次耗时预算应实测；WAL不能让两个写事务并行。

### A16 · P0：用户库导入替换没有验证、备份或全局维护锁

**位置/函数**：[record_sync_service.dart:84](../../../lib/db/record_sync_service.dart#L84) `importReplace`，203 `_extractSqlite`；[database_helper.dart:339](../../../lib/db/database_helper.dart#L339) `close`，272 `database`；导出31 `exportRecords`。

**最小链路**：ZIP有名为user_data.sqlite的非SQLite内容 → close →直接writeAsBytes覆盖原库 → reopen才报错，旧库已消失。隔离真实v15库含答案，导入3字节[1,2,3]已复现，错误后文件仅剩3字节。合法输入写到一半掉电/磁盘满也有损坏路径。close把缓存先置null，后台服务可马上重开：导出读取主文件时后台重新产生WAL，备份可能不包含最新记录；导入期间重开/删除旧WAL更危险。

**根因**：文件级替换不属于SQLite事务；关闭单实例不是阻止后续访问。解压只验证文件名/字节类型，不校验数据库结构、完整性、可升级性。

**最小修复**：将ZIP限制尺寸解压到同目录暂存文件；对暂存用户库做只读quick/integrity、schema及版本校验；如要迁移，只迁移暂存用户库副本。全局维护锁阻止新操作并排空在途写；关闭后备份原库及相关状态，再同卷rename替换，打开并核验，失败恢复。记录install/restore阶段以恢复进程崩溃。

```dart
await maintenance.runExclusive(() async {
  await validateAndUpgradeStagedUserDatabase(stagedPath);
  await coordinator.drainAndClose();
  await backupCurrentUserDatabase();
  try {
    await atomicRenameStagedUserDatabase();
    await reopenAndValidateUserDatabase();
  } catch (_) {
    await restoreUserDatabaseBackup();
    rethrow;
  }
});
```

导出在维护锁中一致快照复制，再离锁压缩；用户库变大时流式归档。SQLite backup API可评估可用性；禁止为了兼容旧SQLite直接依赖较新VACUUM INTO。

### A17 · P1：清空记录的外键失败与同步复活

**位置/函数**：[data_transfer.dart:210](../../../lib/db/data_transfer.dart#L210) `clearAllRecords`；[database_helper.dart:922](../../../lib/db/database_helper.dart#L922) Notes→Question外键；[cloud_sync_service.dart:484](../../../lib/services/cloud_sync_service.dart#L484) append-only流水合并。

**最小链路**：存在笔记引用题q，clearAllRecords第一条DELETE Question违反外键，整个事务回滚，用户无法清理；真实v15初始化下已复现。无笔记时删除成功，也没有云端删除/tombstone；后续全量对齐可能把已删除答案/流水重新拉回。复习状态和官方待上传队列仍留着，与“清空”语义也未统一。

**根因**：Question既作状态行又是Notes父记录，物理删除与保留笔记冲突；append-only同步没有删除意图。

**最小修复**：保留被笔记引用的占位行，原子重置字段，写明确删除/重置信号。先明确清理是否保留收藏/斩题/笔记，以及仅本地清理或多端清理。多端删除需要tombstone/数据代际，不可靠清空后把游标设未来值。

```sql
UPDATE Question SET status=0, user_answer='', collection=0,
  cut_question='0', updated_at=?;
-- 同事务记录reset意图；Notes引用仍然有效。
```

全量流水擦除可由account epoch推进表达；服务器与客户端同时支持后才启用。题库文件完全不参与。

### A18 · P2：自然日与EF边界需校正，不能误报算法死锁

**位置/函数**：[spaced_repetition_engine.dart:92](../../../lib/services/spaced_repetition_engine.dart#L92) `startOfDay/calculateDueDate`，119 `_evaluateSM2`；[daily_review_service.dart:292](../../../lib/services/daily_review_service.dart#L292) 今日边界、447完成数量边界。

**最小链路**：23:59 Again，下日00:00就到期，只隔1分钟；这是按自然日设计，并非0天整数间隔，代码max(1,intervalDays)已保护。跨时区后epoch到期时刻不会自动移动，但显示日期与本地统计日会改变。更明确的是DST回拨：洛杉矶2026-11-01 00:00加固定24h得到同日23:00，在23:30评价时下次到期已过去；春季切换则不是下日零点。todayStart+86400000同样跨DST错一天窗口。

EF=1.3时Good六次实测间隔[1,6,8,10,13,17]；Easy恢复到1.45。**不存在EF把正确题永久锁在1天的死循环**。Good不回升EF是现有SM-2策略，Hard/Again会下降，是否需要补偿应依据长期复习数据评估。

**最小修复**：先定义计划时区/学习日切点（例如固定常住时区、04:00跨日）。同一明确时区内用日历日期构造次日，UTC序列化；不要把“全部用UTC零点”冒充本地自然日。

```dart
// 设备本地日策略的最小修复；固定计划时区需使用IANA时区数据。
final due = DateTime(base.year, base.month, base.day + max(1, intervalDays));
final tomorrow = DateTime(now.year, now.month, now.day + 1);
```

给Again→多次Good/Easy、DST、UTC输入、跨区、时间回拨做性质测试。若引入连续Good恢复，单独版本化策略并限定恢复上限，不能把新的经验参数宣称为经典SM-2标准修正。

### A19 · P1：配置算法与真正落库算法不一致

**位置/函数**：[daily_review_page.dart:71](../../../lib/screens/daily_review_page.dart#L71) 默认DailyReviewService，72加载配置仅赋页面_engine；1128预测；[daily_review_service.dart:40](../../../lib/services/daily_review_service.dart#L40) 默认SM-2；[spaced_repetition_engine.dart:222](../../../lib/services/spaced_repetition_engine.dart#L222) FSRS难度复用easeFactor。

**最小链路**：设置fsrs_lite，新卡Good按钮预测3天，实际submitReviewResult用默认服务SM-2落库1天。UI里的preview使用会话旧reviewItem，Again后重排没有把returned updatedItem写回副本，下一次预测还可能落后于数据库。若未来修好配置注入直接切算法，FSRS存Difficulty=8同字段后切SM-2会当EF=8，复习间隔暴涨。

**根因**：页面预测引擎与Service计算引擎是两个实例；同一个ease_factor字段承载方向相反的两个模型参数，没有algorithm_version。当前FSRS Lite没有实际使用targetRetention或lastReviewAt计算可提取性，不能把标签“DSR”和“效率提升25%”当作验证结论。

**最小修复**：加载配置后创建一次引擎，注入服务并共用预测；每次评分把返回状态更新到所有该item副本。算法切换有明确映射/重新初始化策略，保留历史事件；独立字段存difficulty/stability/SM2 EF。

```dart
final engine = await SpacedRepetitionEngine.loadConfigured();
_service = DailyReviewService(engine: engine);
_engine = engine; // 预测和持久化共用同一策略。
```

不建议在本轮审计直接扩大成FSRS架构重构。先修实际配置生效，再验证或移除无测量依据的产品效果数字。

### A20 · P1：迁移/自愈异常留下外键关闭，历史兼容仍未证实

**位置/函数**：[database_helper.dart:538](../../../lib/db/database_helper.dart#L538) `_repairNotesForeignKey`（546OFF、547事务、587ON）；306 `onOpen`吞异常；360 `_onUpgrade`；521 `_repairCustomFlashcards`。

**最小链路**：历史Notes指向questions，含content=NULL等脏数据 →关闭外键 → INSERT Notes_new触发NOT NULL失败 →事务回滚但最后ON没执行 → onOpen只日志后继续启动，整条连接外键变OFF。复现探针通过repairDatabaseForTesting已确认失败后PRAGMA foreign_keys=0。启动可能进一步产生孤儿数据。

**根因**：连接PRAGMA状态不随数据事务回滚；自愈有失败容忍但没有恢复配置/禁止损坏状态继续写。CustomFlashcards的qid索引仅在缺列时创建：列已存在但索引丢失时onOpen不补。历史oldVersion gate对“版本号高但缺列”的库不能全面修复。

**最小修复**：PRAGMA读取原状态、try/finally恢复；迁移前验证必须字段、可修复脏数据先明确保留策略，不能INSERT OR IGNORE后DROP旧表静默丢数据。保留原库备份，失败可诊断/重试。索引检查独立于列检查。onOpen自愈涉及DDL应纳入schema升级/有版本的修复状态，不无限反复试错。

```dart
final original = (await db.rawQuery('PRAGMA foreign_keys')).single.values.single;
await db.rawQuery('PRAGMA foreign_keys = OFF');
try {
  await db.transaction(repairLegacyNotes);
} finally {
  await db.rawQuery('PRAGMA foreign_keys = ${original == 1 ? 'ON' : 'OFF'}');
}
```

_onUpgrade多阶段有缺列检查、事务和独立新表，这是现有保障；已核查sqflite开启升级事务的兼容处理，**没有把_onUpgrade里面的db.transaction误报成已证实死锁**。现有测试主要覆盖v9/10、v11/12、v13/14、正常外键自愈，未找到v1~v8真实历史夹具。应补v1..v15（每个发布真实DDL/样本）、跳跃升级、中途失败重开、NULL/重复/丢索引样本，核对行数/校验和、Question单列主键、foreign_key_check与索引；未做这些验证前不承诺所有古早脏库升级无损。

## 3. 已排除的旧线索与验证边界

1. **ATTACH路径单引号**：[data_transfer.dart:43](../../../lib/db/data_transfer.dart#L43)已经replaceAll单引号；安装/合并多处已参数化。用户目录含单引号不构成该入口当前缺陷。可统一绑定参数减少维护风险，但不能把DEBT-14继续当未修复事实。
2. **HTTP 4xx/5xx盲目切备用**：[cloud_sync_service.dart:707](../../../lib/services/cloud_sync_service.dart#L707)已rethrow HttpException，配额满/401不会再试workers.dev。剩余风险是Socket/Timeout/FormatException等仍降级；一个同步请求最坏等待约45+45秒。应分类格式错误、取消、认证、配额、网关故障；给总请求预算和节点冷却。不要把所有5xx永久禁止容灾，真正主站网关故障与共享D1配额故障需要结构化错误码区分。
3. **SQLite语法**：运行时lib未发现ON CONFLICT UPSERT；后端index.ts仍有一处，D1并非Android宿主。用户若要求仓库所有SQL统一兼容，后端也用两阶段SQL；不应宣称后端这条语句导致Android3.22报错。未重新引入RETURNING、窗口函数或VACUUM INTO依赖。
4. **只读与全局ID**：所审查正式题库openBank明确readOnly:true；用户Question保持id单列主键；重算采用ATTACH原生聚合。报告中的方案仅写user_data/服务端或暂存用户库，未建议写正式题库或复合Question主键。
5. **205项绿色的局限**：cloud_sync_service_test里的切片测试只是独立算式，没有执行sync、分页、断点、LWW冲突链；daily_review_service_test还断言duration=8，恰好固化了单位错误。现有绿色结果能证明所断言的行为，不能证明恢复完整性和异常安全。
6. **性能没有虚构数值**：未在低端Android、Windows宿主、中国大陆DNS/SNI网络或真实D1配额上压测，也未检查线上部署差异。不存在“busy_timeout=10000即可保证安全”或“每批500一定不超配额”的保证。

## 4. 长期架构演进建议

### 4.1 把同步分成状态投影、追加事件和传输状态

用户库保留Question全局状态及Activities/ReviewEvents追加事件；所有本地写与outbox同事务。同步元数据在同一SQLite而非SharedPreferences多键保存：account_id、device_generation、mutation_id、push_ack、pull_cursor、next_attempt_at、lease状态。

服务端写后才确认mutation_id，返回每个实体实际接受的版本；同事务写changelog seq。客户端逐页合并并保存cursor，不把服务器now当完成位置。协议有version、has_more、high_watermark、明确错误码；绑定/解绑切换有generation令牌，在途返回不能写进新账号或重置后的库。只读查询/下载可以重试；已发写请求超时属于“提交结果未知”，必须用同一幂等ID重试。

对状态只同步发生变动的字段并保留来源版本；答案事件完整保留。复习计划、Notes、CustomFlashcards目前并未包含在CloudSyncService的push/pull中，不能把它当全用户库漫游。若扩展需加入实体版本、tombstone、附件同步、关联失效规则；与医考帮官方同步仍是不同系统、不同账号空间。

### 4.2 D1免费额度采用服务端预算与快照分层

100,000行/天是整个服务数据库的共享预算，单个客户端的剩余额度猜测不够。记录D1实际rows_read/rows_written，按账号/设备限流，配额错误返回如SYNC_QUOTA_EXHAUSTED、retry_after_utc；客户端持久化熔断时间，跨重启遵守，不在每次打开时再全量推送。批次限制行数与序列化字节双预算；避免每页空拉都更新users/devices两行，活跃心跳可粗粒度合并。

首次恢复优先下载已有用户快照，再对本地增量做摘要对账。规模上来后可用R2不可变压缩快照/事件分段，D1保存用户索引、快照版本、近期增量和游标；按时间/账号压实并保证快照与变更水位一致。R2也有成本与操作限制，不是零成本替代。根据产品使用量选择付费D1/PostgreSQL或自托管服务，WebDAV提供可选用户存储适配器，共用协议和加密/完整性校验。

服务端mutation去重表也会写入额度，必须压实/设保留窗并与客户端最旧未ACK水位协调；不要“为了去重”每次重试又写一行receipt。

### 4.3 FTS5保持题库只读，先验证宿主能力

当前[question_search_repository.dart:154](../../../lib/repositories/question_search_repository.dart#L154) loadPage实际串行逐库、5列LIKE、LIMIT/OFFSET；不能沿用文档“多库并行”描述。LIKE '%term%'不能靠普通B-tree优化，深OFFSET反复扫描；通配符%/_若用户想搜字面量应ESCAPE。先做输入防抖/旧结果generation丢弃、并发数有界、id keyset分页，再做生产端FTS。

优先由题库生产端Python构建**独立随包交付的只读搜索索引**；客户端readOnly打开，不向已安装题库CREATE VIRTUAL TABLE或建trigger。题庫schema v1需保持时，旁挂只读索引更合适；元数据记录content_hash/索引版本，题库原子安装时一起切换。跨库搜索共享question_id去重，并加载各自题库内容/用户共享状态。

运行时用 `PRAGMA compile_options` / 功能探测确认FTS5，不能从sqlite3_flutter_libs依赖推断Android sqflite JNI实际换了引擎。中文需要验证分词；unicode61通常不能满足汉字子串搜索。评估生产端中文分词/词条索引并把查询同样分词；trigram tokenizer需要较新SQLite能力，Android3.22不能直接依赖。缺功能回落到有界LIKE或兼容旁挂token表，索引打包兼容能力与客户端契约明确分开。

### 4.4 统一数据库调度与可观察性

DBCoordinator提供前台短事务、后台有界批次、独占维护阶段；只把复合ATTACH/文件替换/关闭放进必要锁，不把网络放进锁里。记录排队延迟、事务时间、SQLITE_BUSY/LOCKED码、WAL大小、checkpoint状态、恢复游标差额；对P95/P99延迟与内存实测再设批次/timeout。长事务切批后，业务需要全章节原子时改用单次SQL批量重置+ATTACH一次重算；不要让批次中间的半状态伪装为已完成。

每日复习由不可变ReviewEvent驱动，队列只是视图，不是最终真相；提交幂等、归档/删除重查、算法版本化、计划时区明确。公平抽题使用配额轮转+等待老化+可审计seed，监控每学科最长未抽到时间。

## 5. 建议实施顺序与验收

1. **同步完整性**：A01/A02，先实现独立游标、分页及本地outbox/服务端变更seq；验收10,441题/10,409流水全量恢复、同毫秒页边界、慢时钟、同步期间编辑、批次中杀进程。
2. **丢数据路径**：A04/A05/A06/A07/A16，失败响应不出队、持久化死信、账号隔离、版本CAS、导入暂存和回滚；验收网络结果未知、上传中编辑/删除、坏ZIP/SQL库、磁盘失败、回滚重启。
3. **本地一致性**：A09/A10/A11/A12/A15/A17/A20，统一事务入口/字段意图/缓存dirty与ATTACH，修单位和外键恢复；验收双击、重复事件、并行状态转换、全局共享题及所有历史迁移。
4. **调度和性能**：A08/A13/A14/A18/A19，公平抽题、范围正确、计时生命周期、算法共用配置、时区边界；再推进FTS/快照分层。

任何修复继续保持：正式题库只读、Question.id单列全局唯一、跨库统计ATTACH、Android宿主兼容SQL。一次修复一个闭环目标，新增以正确业务行为为断言的回归测试；本审计探针保留为基线证据，修复后不应继续要求它“证明旧缺陷”。
