# SESSION_HANDOFF.md - 跨会话开发交接记录

<!-- MEDICAL_KNOWLEDGE_BASE -->
## 最新交接：2026-11-12 可迁移医学知识库构建/导入/验证完成

- 完成：五份只读内容库→149448题/149472块、源SHA256/完整产物/3医学探针PASS、Python14/14、缓存无变化build零delta；标准文档/块/来源版本、Google工具、RAG证据、PDF接口、未来Embedding缓存/Qdrant导出、中文手册。
- 云端：yibubang-search/global/yibubang-medical-v1，Standard Engine yibubang-medical-search，私有bucket yibubang-search-kb-520065588983；pilot12/12 + 全量149460/149460成功0失败，最终12:04:20 UTC完成。三题搜索3/3（排名5/1/1），CD8自然语言改写Top1，后续sync上传/导入0、删除0。artifacts/cloud保留149472个成功ID/hash基线、import/search/rag/final-summary回执。
- 未完成的扩展：53本教材PDF未提供；6923题配图未OCR；167题来源答案正文分歧已提示、未医学审核；EmbeddingAPI/Qdrant未实际调用/部署；专项creditSKU/有效期、预算和账单未从结算控制台确认。Flutter/应用后端尚未接入这个独立检索工具，yibubang://引用标识还不是现有App deep link路由。
- Git：main@d862099；开始已有5个产品文件、首页测试和4份文档改动全部保留；本轮新增scripts/knowledge_base与知识库本段/技术债记录，不commit/push。artifacts/密钥忽略；TECHNICAL_DEBT仍受既有docs忽略规则影响。
- 控制台复核：用户打开agent-platform/rag/corpus与agent-retrieval/collections为空，实际资源是gen-app-builder下Search Data Store；已在线GET资源/导入回执/文档并查询CD8 Top1验证。README新增入口与三产品/API对照；未新建Corpus/Collection或启用vectorsearch API。回执artifacts/cloud/resource-location-check.json。
- 下一会话第一步：核对Git及[VALIDATION.md](../../scripts/knowledge_base/VALIDATION.md)/[README](../../scripts/knowledge_base/README.md)，按用户下一目标提供实际PDF路径或认领检索接入；新增来源修改config→build→validate→cloud sync即可。不重复创建同名资源，不用FULL导入delta，不重新导入本次已经成功的数据；保留artifacts/cloud成功基线。
<!-- /MEDICAL_KNOWLEDGE_BASE -->


<!-- HOME_STARTUP_OPTIMIZATION -->
## 最新交接：2026-11-11 首页启动最小优化完成

- M02查/存投影stamp统一真实路径；M01Cloud数据revision只在已提交非空拉取后递增一次（含部分失败与删除墓碑），首页/统计精确订阅，云刷新保留课程；M03宽屏KeepAlive壳首次访问才挂业务页，GlobalKey保存导航重排/当前页布局切换，窄屏PageView模式保持。
- 全量Flutter314/314（新增6+5+5），后端8/8、tsc及analyze 0 issues；修复后审计探针3/3，十万题别名10次2ms/0次SQL行变更。日志见[逐项记录](audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。不是旧SQLite或四平台真机保证。
- Git main@d862099；5个产品文件、3个测试套件/1辅助文件与文档有未提交改动，保留上轮4份已有文档现场。未commit/push/部署；docs新报告/探针仍受忽略规则影响但本地已保存。
- 未处理M03完整目录分阶段初始化、M04/M05统计调度重构、M06后端部署、M13默认算法入口；未测实机profile/国内网络/断电。新增宽窄测试覆盖1000↔600；400px默认Ahem字体发现旧每日卡片Row溢出，真实字体未验收，未在本目标改布局。
- 下一步第一项：核对git diff及逐项记录，再运行用户设备冷/热启动和答题/同步并行验收；按现场数据认领后续独立问题。不要重复运行aa0a2d9旧缺陷探针作为修复门禁。当前post_a20探针已把M01/M02转为正确行为，M13保留未修现状。
<!-- /HOME_STARTUP_OPTIMIZATION -->

<!-- POST_A20_MAINTENANCE_AUDIT -->
## 最新交接：2026-11-11 启动、同步与维护架构审计

- **完成**：用户三问源码分析；[报告](audits/POST_A20_STARTUP_SYNC_MAINTENANCE_AUDIT.md)与15项M01–M15方案；[当前Flutter探针](audits/post_a20_current_state_probe_test.dart)3/3、[后端探针](audits/post_a20_backend_probe.mjs)2/2；相关Flutter34/34、后端8/8、tsc通过、analyze 0 issues。
- **真实发现**：Cloud状态通知触发首页/统计无差别重读；投影查stamp用传入路径而写stamp用SQLite路径，macOS路径别名导致十万题10次重建1.52–1.54秒/2000010次SQL行变更，规范路径10次3ms；宽屏隐藏Tab抢用户库FIFO；正常Card→Page传默认SM2服务绕过fsrs；pull seq固定但JOIN当前实体，非固定payload快照。
- **同步错误**：客户端未收到protocol2/accepted_seqs所以拒绝ACK，pending保留；本地v2后端尚未部署高度相关。只匿名GET主域health/root均ok且无protocol，version1.0.0也为本地写死，不能确认线上版本。未登录、未发线上sync、未部署。
- **现场**：main@d862099；本轮开始干净；只写docs/探针，没有产品修改、commit、push。DEVELOPMENT_STATUS/SESSION_HANDOFF/KNOWN_ISSUES/FEATURE_MATRIX跟踪差异；新报告、探针与TECHNICAL_DEBT被gitignore忽略但本地已保存。
- **未完成**：M01–M15未实施；平台/等待时长/现场日志问题暂无用户回复；后端真实版本及D1schema验收、真实计费、旧SQLite/Windows/国内网络/断电未测。A19标记正常入口残留PARTIAL，不冒充全链已修。上轮Flutter298/298为历史基线。
- **下一步第一项**：git现场与本段核对，读取报告第1/4节；按单问题认领M02路径指纹修复，再M01精准刷新/M13默认算法factory；收集现场日志以决定启动重构深度。发布步骤先核对远端再按发布授权执行。不要把新的“断言现状缺陷”探针作为修复后必须保持的CI门禁。
<!-- /POST_A20_MAINTENANCE_AUDIT -->

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A20 / 已修复**。Notes自愈finally恢复原外键状态，失败保留旧表并拒绝继续开库，修订号无损复制；闪卡/核心索引独立补齐。从Git提取13个历史版本DDL夹具（v1、v4–v15），新增17项跳跃升级/坏行/重试/回滚/索引回归；相关26/26，最终Flutter全量298/298、后端8/8、analyze 0 issues、tsc通过；commit：修复 A20 数据库自愈外键恢复与历史迁移验证。未找到独立v2/v3历史快照，未冒充全历史真实用户脏数据或Android旧SQLite实机验收。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v24；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：A01–A20源码修复均已独立中文提交，无未提交产品改动；下一会话先核对Git，再按发布授权部署后端schema/Worker并做真实账号及跨平台验收。未授权push/部署，本轮不执行。 保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
完成项：本次继续完成 A14、A16、A17、A18、A19、A20，各项最小修复、测试及中文独立提交；之前的 A01–A13、A15 保留。
未完成的外部验证：后端协议v2及删除墓碑schema尚未部署；官方非幂等请求和真实ID、低端Android SQLite3.22/Windows锁压测、国内网络、真实断电/平台文件恢复、v2/v3独立历史DDL样本仍待验收。A17仅清本机已有记录，未下载云端记录与官方记录保留；A18采用设备本地自然日，固定计划时区仍为后续设计；实验调度不是完整FSRS。
验证：Flutter最终全量298/298；洛杉矶DST相关32/32；后端SQLite8/8；flutter analyze --no-pub 0 issues；npx tsc --noEmit通过。SQLite测试FFI3.43.2与999参数预算不能替代旧Android实机。
下一次第一步：git status/HEAD和本段核对，按用户明确发布授权推进后端schema/Worker部署及账号/跨设备同步验证；不复跑历史缺陷断言探针作为当前正确性门禁。

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
