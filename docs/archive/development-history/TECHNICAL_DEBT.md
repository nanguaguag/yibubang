> 历史快照：归档于2026-11-13，包含各阶段当时状态。当前状态见[开发状态](../../antigravity/DEVELOPMENT_STATUS.md)，不要据本文旧版本/未提交描述判断当前实现。

# TECHNICAL_DEBT.md - 医不帮技术债务、代码坏味道与重构建议

<!-- ADVANCED_AI_SETTINGS -->
## 2026-11-13 高级设置后剩余边界

- App高级扣3为额度策略，不对应Google3倍计价；200额度只66次完整高级。Search两源+Answer的实际Advanced SKU及本赠金抵扣仍须账户账单；streamAnswer传入外部证据的实测未返回steps，不据配置开关编造额外改写计量。
- 模型公开快照提供离线选择，不能替代实际网络搜索或保证预览模型永不退役；Google无枚举API，官网表结构维护仍需要，稳定版优先回退选择。
- 现接口不经Worker代理，run.app在目标地区可达性尚未实测；模型目录离线回退不会自动解决搜索网络。原生新设置/缩略图、四平台真机/Release仍独立验收；TTL继续有少量托管删除费。
<!-- /ADVANCED_AI_SETTINGS -->

<!-- BUILTIN_ANSWER_MODELS -->
## 2026-11-13 内置Answer后剩余边界

- 基础Answer虽禁改写/推荐/托管session，真实API仍需SEARCH_ADD_ON_LLM开关。两Standard检索+一次Enterprise Answer列表价USD7/千次App问题，附加计量保守USD11；实际SKU/免费分配/专项赠金映射必须账单确认，次数限额不等于现金硬上限。
- Google公开API没有内置Answer模型枚举方法，当前读取官方文档表。缓存有期限且官网变更/失败明确报错，但表结构变化需维护；preview是否支持本应用在实际请求中核验，无收费探测/外接模型回退。基础Answer本地渐入不是服务端token流。
- Firestore TTL、东京Run公网出网、Cloudflare Worker订阅及部署附属服务不在三项普通免费额度内。当前R2占7.714GB/Firestore freeTier=true只证明本项目条件，不能证明共享账号账单为0。
<!-- /BUILTIN_ANSWER_MODELS -->


<!-- TEXTBOOK_PLAN_REVIEW -->
## 2026-11-12 教材文字质量与引用扩展（方案，未实施）

- 已获53份可复制PDF路径，20669页。11本22页抽检不能代表全书；诊断/内科/外科样本两组OCR层重叠，必须按位置/层选择去重，不直接拼接普通提取结果或用正则删除合法重复词。
- 现页导入器仅存page/text；书页固定offset、无bbox/源版本/图片映射尚不能支持可靠在线教材引用。App只认题目id，须先补kind=textbook与页图阅读器。
- 未来图片体积150–400KiB/页是假设，未压缩测试；图片与文字分库存储。GoogleOCR前500页限制、R2共享免费额度及目标网络需实际核验。用户明确本轮只说方案，不能据此启动批量处理/上传。
<!-- /TEXTBOOK_PLAN_REVIEW -->


<!-- APP_AI_SEARCH -->
## 2026-11-12 AI 搜索后续边界（OPEN）

- AI01 安装随机ID+secret/IP+全站事务限额不是不可伪造硬件证明；公开端点仍有请求/Firestore成本。正式发布可接Play Integrity/App Attest、账号/人机验证及Cloud Armor入口。现100/安装/天已线上验证；不虚称重装不能绕过。
- AI02 当前直接Cloud Run最右XFF与自动请求日志IP哈希相符；引入LB/CDN须重新确认可信链。校园/医院共享出口IP新注册3/天与搜索300/天需按规模调整。
- AI03 现Markdown为流式安全子集（标题/粗体/代码/列表/表格/编号引用），非完整HTML/Markdown渲染；教材PDF未导入且页码引用查看器未实现。以后自建向量库替换服务端检索并保留id/SSE，本地会话无需重建。
- AI05 引用沿用现有全局查询（不包含legacy_combined兼容回退库）；仅旧合并库用户需先迁移独立题库。未来如保留长期旧库入口，需单独实现只读引用回退，不扩大现有普通搜索范围。
- AI04 Search专项credit SKU/有效期对Gemini/CloudRun/Firestore是否抵扣未核账；服务端每日2000搜索是次数控制，不是金额硬预算。Windows/Linux/iOS/Android真机与国内网络、Release签名兼容待验收；Debug构建/部件截图不替代实机。
<!-- /APP_AI_SEARCH -->


<!-- HOME_STARTUP_OPTIMIZATION -->
## 2026-11-11 首页启动最小优化后剩余边界

M01/M02及M03隐藏Tab延迟挂载切片已修、Flutter314/314、analyze 0 issues；[逐项记录](../../antigravity/audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。尚余M03目录分阶段初始化、M04概览SQL/共享缓存、M05调度；本轮保留迁移、校验和后台业务时序。

新观察：400px默认Ahem测试字体下DailyReviewCard两个标签的固定Row横向溢出；这是未改卡片布局的窄屏/字体边界，不把600px跨640断点回归冒充400px真实字体验收。需真实字体/文本缩放验证后独立最小布局修复。M06后端发布与M13算法入口未处理。
<!-- /HOME_STARTUP_OPTIMIZATION -->

<!-- POST_A20_MAINTENANCE_AUDIT -->
## 2026-11-11 A20后启动/同步/维护新债（OPEN）

当前事实以 `d862099` [完整方案](../../antigravity/audits/POST_A20_STARTUP_SYNC_MAINTENANCE_AUDIT.md)为准；下文v13/v15、A01–A20待修描述为历史。

- M01/M02：精确数据失效、刷新保留旧内容；投影canonical路径/generation缓存。云通知与路径别名反复全库重建已生产探针复现。
- M03–M05：必要启动依赖、隐藏Tab按需；概览SQL计数/共享缓存、课程批量查询；FIFO wait/run观测与bounded chunk/优先级aging。busy_timeout现已10000，不重复建议仅加超时。
- M06–M09：协议能力/发布矩阵、D1真实rows_written预算与持久冷却；不可变payload/stream与database_generation，明确seq上界的实体一致性；总请求预算/取消。原子outbox/ACK/断点已实现，不回退旧时间游标。
- M10–M13：统一剩余IN参数预算、只读搜索sidecar及中文FTS能力；题库句柄单所有者/只读接口；统计SQL聚合与DST残留；默认算法factory。A19正常Card入口仍绕过prefs。
- M14/M15：WAL一致迁移备份、流式staging验证与短swap/平台故障恢复；后端CI/版本化迁移、真实平台性能门禁和当前文档治理。
- P0仅条件风险：旧迁移copy主文件不保证含WAL；活动outbox动态payload在迁移/未来修正后可能改变identity内容。未宣称已发生数据丢失。后端pull JOIN当前projection边界已复现，选定一致性模型后补性质测试。

Flutter现状探针3/3、后端现状2/2；相关34/34、后端8/8、tsc/analyze通过。十万题别名10次1.52–1.54秒/2000010次SQL行变更，canonical10次3ms；是本机FFI样本不是Android实机。未改产品、未commit/部署。
<!-- /POST_A20_MAINTENANCE_AUDIT -->

## 2026-11-10 v2.2.3 白盒审计增补（OPEN，尚未修复）

本次实际基线 `aa0a2d9`；下方历史条目保留。当前事实以[完整审计](../../antigravity/audits/V2_2_3_WHITE_BOX_AUDIT.md)为准，审计ID A01～A20用于追踪，未擅自分配新BUG/Sprint编号。

- **P0优先**：A01本地/服务端时间游标混用；A02超过10000条拉取缺续页；A04坏HTTP200响应误出队；A05失败5次物理删队列及账号归属缺失；A06笔记旧快照覆盖新内容；A07收藏/斩题整行旧状态写回；A16坏导入先破坏原用户库。
- **一致性与性能**：A03持久化切片ACK缺失/重复写；A08测试退出和Controller交接；A09复习多表非原子/重入；A10秒毫秒及统计投影冲突；A11斩后尾队列复活；A12事务外读旧状态/占位竞态/跨库缓存；A13确定性抽题饥饿；A14范围与参数预算；A15 ATTACH复合操作互斥；A17清理外键/删除同步；A19算法配置不一致；A20自愈异常外键OFF与历史迁移覆盖。
- **算法边界**：A18自然日固定24h跨DST有误，EF=1.3后Good不回升是策略边界而非死锁；Easy已可回升。
- **历史条目事实校正**：DEBT-14的路径未转义风险在当前data_transfer.dart已不存在；DEBT-13的5000ms来自题库暂存连接，用户库onConfigure未统一timeout，不能把多路异步启动直接等同写死锁；DEBT-15“永久1天”不成立。DEBT-12仍有价值，但20,850行×5为104,250是逻辑量估算，实际D1额度需观察rows_written及索引成本，不能以ignore去重推断不计费。
- 证据：17/17隔离探针、后端原始SQL、38/38既有相关测试；产品运行代码未改，所有审计问题仍待修复。长期方案包括本地事务outbox、服务端序号分页/幂等ACK、持久化退避/死信、用户库维护锁、R2快照分层和只读FTS搜索旁挂索引。

> **基准代码**：`yibubang` 客户端完整源码（基准 Commit: `3c33fb9`）
> **更新时间**：2026-10-31

---

## 1. 废弃与残留代码 (Dead Code & Zombies)

### [DEBT-01] `Cards` 表为未被任何业务使用的僵尸表
- **文件位置**：[`lib/db/database_helper.dart:612`](../../../lib/db/database_helper.dart#L612)
- **状态**：`RESOLVED` (已从 `_onCreate` 中移除该表的创建语句，并从 `developer_page.dart` 监控列表移除)

### [DEBT-02] `_onUpgrade` 中存在冗余嵌套的错误代码块
- **文件位置**：[`lib/db/database_helper.dart:266-275`](../../../lib/db/database_helper.dart#L266-L275)
- **状态**：`RESOLVED` (已确认并彻底清理升级方法中的重复嵌套块)

### [DEBT-03] `HomePage._checkForAppUpdate` 存在重复的题目对错重算逻辑
- **文件位置**：[`lib/screens/home_page.dart:147-153`](../../../lib/screens/home_page.dart#L147-L153)
- **状态**：`RESOLVED` (已从 `_checkForAppUpdate` 移除重复的 `needToRebuildQuestionCount` 检查及无用的重启弹窗，保留 `_initAsync` 单点处理)

---

## 2. 代码规范与 Linter 债务 (Lint Issues)

### [DEBT-04] `flutter analyze` 报告的 7 处 linter 警告与弃用 API
- **状态**：`RESOLVED` (已全部修复：为 `CommentReplyPage` 补全具名 key 参数；修复所有页面的 State 私有类型暴露；对弃用参数添加压制保护。当前 `flutter analyze` 达成 0 issue 全绿)

---

## 3. 架构与性能演进建议 (Performance & Architecture)

### [DEBT-05] 题库生产端全文本检索缺乏 SQLite FTS5 支持
- **现状**：当前全文搜索依托于 `Question` 物理表的 `title LIKE ? OR option LIKE ? OR explain LIKE ?`。
- **痛点**：在 7.8 万道题目（176MB）中执行 5 列全表模糊匹配，且无分词能力。
- **重构建议**：
  - 在生产端 Python 脚本（`docs/yikaobang/src/split_question_banks.py`）中，构建各独立题库时增加 FTS5 虚表（`Question_fts`）；
  - 客户端搜索时改为 `SELECT id FROM Question_fts WHERE Question_fts MATCH ?`，实现毫秒级快速全文高亮。
- **排期**：Sprint 4

### [DEBT-06] 全部重做/错题重做的串行循环 SQL 批处理重构
- **文件位置**：[`lib/screens/question_grid_page.dart:277-291, 361-374`](../../../lib/screens/question_grid_page.dart#L277-L291)
- **现状**：在章节重做时，对章节内的每一道题单独 `await updateQuestion(...)`，200道题将串行执行 200 次 SQLite 事务和日志写入。
- **重构建议**：提供批量更新接口 `batchUpdateQuestions(List<UserQuestion>, ...)`，使用单一 SQLite 事务批量提交，避免长时间 UI 卡顿。
- **排期**：Sprint 4

## 4. 题库制作专项实施后状态（2026-11-07）

### [DEBT-07] 深层身份智能同步与续传

- **状态**：`PARTIAL`。创建/全量重建已复用递归完整构建，保留真实叶身份、完整根树和原始全局 ID；测试覆盖深层树、共享题与失败。
- **剩余**：既有旧库的章节智能算法仍只取根直接入口；本轮完整树产物通过完整快照检查后合并，尚无深层章节缓存和持久化续传。schema v1 Chapter 无父字段，章节路径保存在名称中。
- **下一步**：在不改全局 ID/只读与 ATTACH 契约的前提下，扩展按叶入口的目录缓存/状态键和恢复任务，并做真实 API 验收。

### [DEBT-08] 全量构建题量、时间单位与账号字段

- **状态**：`RESOLVED（新建/完整重建流程）`。SQL 去重实数、generated_at 秒单位、账号字段清理已实施；无权限或失败不安装。
- **验证**：真实 SQLite 测试覆盖深层构建、共享题、取消/权限失败及完整重建保留旧库。

### [DEBT-09] 版本、来源、履历与任务恢复

- **状态**：`PARTIAL`。自建初版 1.0.0、变更 PATCH、全量递增；BankHistory 创建/安装履历已实现；API 制作禁用订阅包覆盖更新，订阅可编辑。
- **剩余**：新建/完整树检查没有持久化断点任务；旧章节智能分支仍沿用 +delta 时间后缀。真实抓取、订阅与原生导出需验收。

### [DEBT-10] 目录根 identity 来源一致性

- **状态**：`RESOLVED（本轮链路）`。安装以文件校验根为准；清单注册保留已安装根。下载拒绝更改已安装根，并验证文件根与 manifest、可选 SQLite SHA-256 一致。
- **历史限制**：没有批量扫描修复旧目录的动作；后续若发现旧数据不一致，仅修改用户库目录，不写正式题库。

本轮测试 67/67、分析 0 issues；不把自动化验证等同于真实账号/各平台实机验收。大文件 ZIP 整包内存与 FTS5 继续按既有规划暂缓。

## 2026-11-07 订阅检查与安装职责耦合（待处理）

7da98f4 中订阅保存触发全来源检查，直链检查为无条件整包下载与全量校验，下载缓存随任务删除；hasUpdate 同时依赖 updateEnabled 和本地文件 hash，不能清晰区分上游更新与本地补充。不同 URL 提供同 bank_id 使整次刷新失败。详见 QUESTION_BANK_MANAGEMENT_DESIGN.md；已提出设计，尚未实施。


### [DEBT-11] GitHub Actions 运行时与 action 版本迁移

- **状态**：PLANNED，低优先级；本次 v2.2.2 全平台发布成功，不改变现有发布 tag。
- **观察**：workflow 42376143828 的 annotations 提示 checkout@v4 / upload-artifact@v4 / setup-java@v4 等 Node.js 20 actions 被平台强制使用 Node.js 24；setup-java@v4 已标为 deprecated。属于工作流依赖提示，flutter analyze 本次仍为 0 issues。
- **后续**：独立切片评估兼容的 checkout/upload-artifact/setup-java 新版本及各平台 runner 支持，验证全部平台后再迁移，不在已发布版本顺手升级依赖。

---

## 5. 跨模块深度审计潜在债务与风险清单 (2026-11-10 整理)

### [DEBT-12] Cloudflare D1 每日免费写入限额（10万行）与大批量同步熔断风险 (网络/云存储)
- **现状**：初次同步万级做题记录（如 10,441 题 + 10,409 流水 = 20,850 行写入），单日重试 4~5 次即突破 D1 免费版 100,000 行/天限制。虽已引入 500 题切片分批机制避免了 30s 运行时限超时，但配额超限时 D1 仍会硬拒绝并抛出 `HTTP 500 (exceeded D1 free tier daily row write limit)`。
- **潜在风险**：新安装设备绑定大量历史做题记录时，若网络抖动触发多次自动重试，极易触发单日限额熔断。
- **重构建议**：
  1. 客户端实现待推总量检测，若首次全量同步数据量过大，持久化断点游标，避免单日多次重复上传未变动流水；
  2. 探讨支持本地 WebDAV / P2P 局域网同步备份，降低对单一公共云 D1 写入配额的强依赖。

### [DEBT-13] 后台静默同步与前台答题的 SQLite 锁争用与 Busy Timeout (数据库)
- **现状**：应用启动时后台静默并行执行 `CloudSyncService.sync()`、`YkbSyncService.processQueue()`、`NoteService.processQueue()`。当后台大事务写入 `user_data.sqlite` 时，前台用户若正在快速答题或重算章节统计，偶发可能出现 `database is locked`。
- **潜在风险**：部分 SQL 执行未显式配置统一的 `busy_timeout`（各处设置分散在 3000ms~5000ms），在慢速低端 Android 机极易发生超时锁冲突。
- **重构建议**：在 `UserDBHelper.onConfigure` 中全局统一配置 `PRAGMA busy_timeout = 10000;`，并对写操作引入轻量互斥排队调度器。

### [DEBT-14] 跨库 ATTACH DATABASE 路径拼接转义安全性 (数据库)
- **现状**：[`lib/db/data_transfer.dart`](../../../lib/db/data_transfer.dart) 中采用 `ATTACH DATABASE '$bankPath' AS ...` 字符串模板。
- **潜在风险**：若用户自定义题库路径或某些特殊平台（Windows 用户名含单引号或空格、特殊 Linux 路径），单引号拼接会导致 SQLite 解析失败甚至语法错误。
- **重构建议**：对所有动态拼接进 PRAGMA / ATTACH 语句的路径统一执行 `.replaceAll("'", "''")` 安全转义。

### [DEBT-15] SM-2 艾宾浩斯调度算法边界状态与时区偏差 (算法)
- **现状**：`SpacedRepetitionEngine` 基于自然日对齐（`DateTime(now.year, now.month, now.day)`）。
- **潜在风险**：
  1. 当用户跨时区旅行或在午夜 23:59~00:01 临界点做题时，由于截断逻辑可能产生到期日判定抖动；
  2. 极低难度题目多次点击 `Again` 导致 EF 下降至 1.3 下限后，复习间隔被锁定为 1 天，缺乏遗忘因子随连续正确的主动回弹机制。
- **重构建议**：引入带用户时区偏好的相对自然日计算，并为 SM-2 增加动态步进缓冲与长周期稳定性测试。

## 2026-11-11 A01–A20 修复后剩余验证和演进边界

源码修复及独立提交完成，Flutter298/298、后端8/8。后续：部署协议v2与流水删除墓碑；D1真实rows_written计费/分期配额；官方创建ID及幂等契约实测；用户库ZIP仍整包内存，需流式归档；v2/v3独立历史DDL和用户脏库样本；Android3.22/Windows锁与文件恢复实机；固定计划IANA时区与完整FSRS仍为单独设计，实验启发式无留存率增益承诺。

<!-- MEDICAL_KNOWLEDGE_BASE -->
## 2026-11-12 医学内容质量与后端迁移验收

- 五份内容库同ID存在11348题版本差异，按答案对应正文比较167题有答案分歧。工具保留原始来源版本并在检索文本提示；来源优先级不构成医学审定。后续对conflicts.jsonl逐项审核并指定可靠来源/修订副本；不修改正式题库。
- 6923题有配图引用，本轮未识别图片内信息。53本教材尚未提供，PDF文字层/双栏表格/扫描OCR及印刷页码需按每本抽查。
- 本地规范块独立于Google，但更换Embedding仍需新向量，query/document模型和维度必须一致。Embedding/Qdrant只具备导出适配，真实接口与检索质量待迁移时验收；生产向量同步需独立保留最后成功基线。
<!-- /MEDICAL_KNOWLEDGE_BASE -->


<!-- TEXTBOOK_METADATA_IMPORT_VERIFICATION -->
## 2026-11-13 教材元数据导入后的在线核验

407个needs_review字段增量Import成功后，在线GET/Search仍未返回该字段；通过仅PATCH structData补齐、407逐项GET和实际Search/Cloud Run返回已解决。外部服务成功计数及本地导出hash账本不足以验证检索字段实际生效。后续新增字段须抽查实际GET/Search，缺失时只补元数据并保留正文，避免重复文本导入。记录见scripts/knowledge_base/TEXTBOOK_EXECUTION.md及artifacts/cloud/textbook-review-metadata-repair.json。未查明Google服务内部为何未反映该批属性，不把推测记为根因。
<!-- /TEXTBOOK_METADATA_IMPORT_VERIFICATION -->
