# SESSION_HANDOFF.md - 跨会话开发交接记录

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A14 / 已修复**。按已安装且启用的题库解析全库范围，ATTACH真实题目关系验证课程/身份，实体携带来源bankId、共享题去重；范围池SQL聚合、缺失实体过滤后补抽。实体/用户/笔记查询分块500，课程集合用户TEMP表避免参数溢出。新增跨库及1005题/课程预算回归，相关35/35、analyze 0 issues；commit：修复 A14 全库复习范围与批量查询参数上限。参数限制由真实FFI执行器加999预算验证，Android旧宿主仍待实机。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v23；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：A01–A15已逐项提交；接着处理A16导入验证、原库备份与崩溃恢复，随后A17–A20。 保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
<!-- /A01_A20_REPAIR_STATUS -->


## 最新交接：2026-11-10 v2.2.3 白盒审计完成

- **实际Git现场**：分支main，HEAD `aa0a2d9c959128d647b5109cd447c450c150d593`；开始时干净。本轮仅有审计/知识库变更，未commit、push或部署，未改应用逻辑和依赖。
- **文件管理边界**：`.gitignore:61`忽略整个docs目录，因此Git status/diff仍为空；审计/知识库已写入本地磁盘，未强制add或修改忽略规则。下一会话读取本地文件，不可把Git无差异解释为本轮无文档更新。
- **完成项**：数据库、业务生命周期、网络/云同步、调度内核源码调用链审计；[20项完整报告](audits/V2_2_3_WHITE_BOX_AUDIT.md)，含P0/P1/P2、精确源码位置、最小复现和修复代码/长期演进；17项显式隔离生产调用探针及后端原始SQL探针；既有相关测试38/38通过。
- **关键新证据**：同步期间变动不再上传；10441题首次恢复只拿10000、剩441被游标跳过；失败批次重传500；坏HTTP200响应删除官方队列；第五次失败删除持久化任务；图片上传覆盖笔记新编辑；并行状态转移重复计数；复习多表部分提交/单位错误；固定候选前缀饥饿；坏导入先覆盖原用户库；Notes自愈失败外键OFF。
- **原交接线索校正**：当前ATTACH路径已转义，明确HTTP4xx/5xx已不降级备用；EF低下限仍增长/Easy可回升；5000timeout位于暂存题库。不要按旧行号和旧风险描述重复修复已解决路径。
- **未完成项**：A01～A20均未修复，历史v1～v8迁移夹具未补、线上D1部署未对照、低端Android/Windows锁压测及国内DNS/SNI实机未做；本轮未重复全量205项，不能把17个缺陷探针通过记作产品修复验证。
- **下一会话第一步**：读取本最新段和审计报告，核对Git未提交文档；优先认领A01/A02作为同步完整性目标，明确客户端/后端协议版本与实际部署，再实现持久化outbox、独立游标及完整分页。其他P0按单一闭环逐项修复，禁止自动commit或大规模重构。
- **复现入口**：`flutter test --no-pub --reporter expanded docs/antigravity/audits/v2_2_3_reproduction_test.dart`（刻意断言旧缺陷，非CI门禁）；`python3 docs/antigravity/audits/backend_sql_probe.py`（内存库、无D1访问）。下面v2.2.3发布交接内容保留为历史。
- **最终检查**：静态分析0 issues；局部格式化和分析修正后隔离探针再次17/17通过；相关既有测试38/38。最终Git status/diff无产品变更，审计源代码链接54处均核对文件/行存在（主体函数已人工追踪）。

> **记录时间**：2026-11-10  
> **当前分支**：`main`（HEAD: `aa0a2d9`）  
> **发布版本**：`v2.2.3`（Build: `2.2.3+213`，用户数据库 schema `v15`，题库 schema `v1`）  
> **质量基线**：`flutter analyze --no-pub` 保持 **0 warnings / 0 errors**；全量自动化测试 **205/205** 项全部通过。  
> **交接目标**：本会话已全面闭环 **Issue #22**（每日计划、闪卡系统、跨章节差异化蓄力手势）与 **Issue #23**（低版本宿主 SQLite 兼容性缺陷 BUG-19、淘汰 ON CONFLICT、万级数据切片同步）。已完成 v2.2.3 发布。现全面梳理系统在**数据库、业务逻辑、网络与云同步、算法内核**四个维度的深度排查线索，供后续交接给 Codex 开展深度系统审计。

---

## 1. 最新交付总览与版本基线

| 模块 | 核心交付内容 | 关联与状态 |
| :--- | :--- | :--- |
| **SQLite 宿主引擎兼容 (Issue #23)** | 1. 彻底淘汰全库 8 处 SQLite ≥ 3.24 `ON CONFLICT` 语法依赖，重构成 `INSERT OR IGNORE` + 条件原子 `UPDATE` / `INSERT OR REPLACE`，彻底根除 Android 10 (SQLite 3.22) 下的 `near "ON": syntax error`；<br>2. 引入 `sqlite3_flutter_libs` 内嵌现代 SQLite 动态库；<br>3. 用户库启动主动输出 `sqlite_version()` 诊断信息 | refs #23 (BUG-19) `CLOSED` |
| **云同步性能与熔断防护 (Issue #23)** | 1. `CloudSyncService.sync()` 落地 `batchChunkSize = 500` 切片推送机制，根治万级数据（如 20,850 行）打爆 Cloudflare Worker 30s 运行时限导致的超时中断；<br>2. 优化容灾降级：主域名返回 4xx/5xx 时精准抛出错误并向用户透传清晰原因，禁止盲目将大包流量重试至受限域名（如国内受阻的 `workers.dev`） | refs #23 (BUG-19) `CLOSED` |
| **滑动切章手感与蓄力 (Issue #22)** | 1. 章节九宫格上下滑（`QuestionGridPage`）启用 **500ms** 蓄力停顿（Dwell Hold），拉满 100% 保持按住满 500ms 震动并自动切章，中途松手或回弹立即取消，彻底消除触控板惯性误触；<br>2. 题目页左右滑（`QuestionDetailPage`）恢复轻快即时手感（拉满阈值后**松手即切**，无停顿等待）；<br>3. `ChapterCrossIndicator` 垂直方向启用 500ms 动态充满光环，水平方向拉满即高能 | refs #22 (BUG-17) `CLOSED` |
| **每日计划与自制闪卡 (Issue #22)** | 1. 独立 Tab「每日计划」及抽题来源多选；<br>2. 3D Matrix4 翻转闪卡百词斩刷题流；<br>3. 题目笔记一键转自制闪卡；<br>4. 卡包管理（横向标签筛选、按题干/背面模糊检索、随时斩卡） | refs #22 `CLOSED` |
| **自动化测试与基线维护** | 新增 `test/sqlite_compatibility_test.dart`（4 项）；全量更新 `test/cross_chapter_navigation_test.dart`（15 项）与 `test/daily_review_ui_test.dart`，总计 **205/205** 项测试全绿 | 质量基线已验证 |

---

## 2. 系统核心架构铁律与设计契约（不可妥协）

任何接入代码分析或修改的代理必须严格遵守以下系统架构契约：

1. **题库库只读隔离契约**：
   - 题库文件（`QuestionBank/<bank_id>/<bank_id>.sqlite`）在客户端**必须以只读方式（`readOnly: true`）打开**。严禁编写任何对题库库执行 `INSERT`、`UPDATE`、`DELETE` 或 DDL 的代码。
   - 所有用户行为（作答记录 `Question`、做题流水 `Activities`、收藏、斩题、用时、笔记、复习计划、自制闪卡）一律落入 `user_data.sqlite`。
2. **全局 `question_id` 单列唯一与跨库共享契约**：
   - `question_id` 全系统唯一。同一题目出现在不同题库中时共享同一份用户做题与复习状态。
   - `Question` 表的主键永远是单列 `id`，严禁擅自改为 `(bank_id, id)` 联合主键。
3. **跨库聚合重算必须走 SQLite 原生 `ATTACH DATABASE`**：
   - 跨题库与用户库的章节统计（对、错、未做题数）重算，必须在 `UserDBHelper` 中利用 SQLite 原生 `ATTACH DATABASE` 在 SQL 引擎层批量完成（参考 `lib/db/data_transfer.dart` 中的 `rebuildQuestionCount`），严禁在 Dart 内存中进行双重循环查询拼接。
4. **Context 与路由生命周期安全性**：
   - 严禁在 `Navigator.pop(context)` 后继续使用该失活的 `context` 执行跳转（如 `pushAdaptiveModalPage`）。桌面端模态弹窗若包含子路由交互，必须确保返回值能正确冒泡至外层调用方。

---

## 3. 供 Codex 深入排查的四大维度潜在问题清单

在当前 v2.2.3 基线上，针对系统深层隐患梳理了四大维度的重点关注领域与已知技术债务（详见 [`docs/antigravity/TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md)）：

### 维度一：数据库底层 (Database & SQLite)
1. **多线程/后台并发与锁争用 (Lock Contention & Busy Timeout)**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart`, `lib/services/ykb_sync_service.dart`, `lib/services/note_service.dart`, `lib/db/database_helper.dart`
   - **风险**：应用启动时后台并行触发多路同步队列写入 `user_data.sqlite`，若前台用户正在快速答题或重算章节统计，偶发可能抛出 `database is locked`。当前各处 `busy_timeout` 设置分散在 3000ms~5000ms，低端 Android 机存在锁争用风险（[DEBT-13]）。
2. **动态 SQL 路径拼接与特殊字符注入风险**:
   - **痛点代码**：`lib/db/data_transfer.dart:18` (`ATTACH DATABASE '$bankPath' AS ...`)
   - **风险**：若题库路径包含单引号（如 Windows 用户名或特殊目录名），字符串模板直接拼接会导致语法错误甚至安全隐患，未做 `bankPath.replaceAll("'", "''")`（[DEBT-14]）。
3. **长事务与批量更新性能**:
   - **痛点代码**：`lib/screens/question_grid_page.dart:277-291`（全部重做/错题重做）
   - **风险**：遍历题目串行 `await updateQuestion(...)`，大章节（数百道题）会触发数百次单独 SQLite 事务与 WAL 同步，导致 UI 掉帧（[DEBT-06]）。
4. **Schema 迁移无损性与历史版本兼容**:
   - **痛点代码**：`lib/db/database_helper.dart:184-280` (`_onUpgrade`)
   - **风险**：从早期版本（v1~v10）跨多版本升级到 v15 的迁移链路是否存在列缺失容错兜底？

---

### 维度二：业务逻辑与生命周期 (Logic & Lifecycle)
1. **跨学科/叶子节点切换时的目录与状态一致性**:
   - **痛点代码**：`lib/screens/subject_page.dart`, `lib/services/question_bank_manifest_service.dart`
   - **风险**：部分题库在医考帮体系下存在多层树结构与叶子入口，深层章节的父子级联选择状态是否在缓存与重算时保持全局唯一？
2. **章节翻页与 PopScope 返回拦截时序**:
   - **痛点代码**：`lib/screens/question_detail_page.dart`, `lib/screens/question_grid_page.dart`
   - **风险**：在切章、交卷、重做及快速滑动的边界情况下，路由栈退出时是否有遗漏的未保存做题时长（`duration`）或答题状态？
3. **多端 LWW (Last-Write-Wins) 冲突仲裁时序**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart:154-184`
   - **风险**：当两台设备离线答题后同时联网同步，若设备时钟存在漂移，基于 `updated_at` 的毫秒级比较是否会导致有效答案被旧数据覆盖？

---

### 维度三：网络通信与云同步 (Network & Cloud Sync)
1. **Cloudflare D1 免费版配额熔断与流控**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart`
   - **风险**：Cloudflare D1 免费版限制每日写入上限为 100,000 行。初次全量同步（如 10,441 题 + 10,409 流水 = 20,850 行写入）若遭遇网络抖动重试 4~5 次即突破限额，触发 D1 服务端抛出 `HTTP 500 (exceeded D1 free tier daily row write limit)`（[DEBT-12]）。
2. **多节点容灾降级与国内网络可用性**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart:28-36`
   - **风险**：备用域名 `*.workers.dev` 在国内部分网络环境下存在 DNS 污染与 SNI 阻断；若因业务错误（如 4xx / 5xx 配额满）盲目重试备用节点，会导致请求假死超时（45s）。
3. **离线队列丢包与指数退避恢复机制**:
   - **痛点代码**：`lib/services/ykb_sync_service.dart`, `lib/services/note_service.dart`
   - **风险**：后台离线队列在遭遇连续网络失败时虽然触发了退避，但在应用杀进程重启后，队列游标与内存重试计数器是否能无损恢复？

---

### 维度四：算法内核与调度 (Algorithm & Engine)
1. **SM-2 艾宾浩斯间隔算法的自然日边界截断**:
   - **痛点代码**：`lib/utils/spaced_repetition_engine.dart:45-80`
   - **风险**：`calculateNextReviewDate` 采用自然日截断（`DateTime(now.year, now.month, now.day)`）。若用户跨时区飞行或在 23:59~00:01 临界点做题，会导致到期日出现 0 天或多算 1 天的跳变抖动（[DEBT-15]）。
2. **EF (Easiness Factor) 衰减死锁与回弹机制**:
   - **痛点代码**：`lib/utils/spaced_repetition_engine.dart:17`
   - **风险**：当极难题目多次评分为 `Again`（Grade 1）时，EF 会快速跌落至 1.3 的强制下限，导致之后即使用户答对，间隔增长也极其缓慢，缺乏长周期自适应动态回弹测试。
3. **抽题分布与随机洗牌算法公平性**:
   - **痛点代码**：`lib/services/daily_review_service.dart:180-240`
   - **风险**：混合多来源（错题、收藏、笔记、新题）且受限于每日总题量上限时，截断逻辑是否会导致后排课程或来源被永久饥饿遗忘？

---

## 4. 下一次会话交接建议

### 当前工作区状态：
- 分支：`main`（已推送 `origin/main`，Tag `v2.2.3` 已发布）
- 代码质量：`flutter analyze --no-pub` 0 warnings / 0 errors
- 自动化测试：`flutter test --no-pub` 205 项全绿通过

### 下一会话操作建议：
1. **将第四部分整理的高信息密度 Prompt 提交给 Codex** 进行四大维度的源码级扫描与审查；
2. 收集 Codex 的审查报告，对高价值的潜在漏洞与优化点归档至 [`docs/antigravity/TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) 并制定 Sprint 重构计划。
