# 当前开发状态

## 2026-11-23 医不帮 ↔ 医考帮官方双向同步深度审计与全链路修复（完成）

1. **新建笔记 `pushNote` 空 `data: {}` 闭环与防重认领 ([lib/services/note_service.dart](../../lib/services/note_service.dart))**：
   - 修复医考帮 `POST /allQuestion/Note/pushNote` 返回 `{"code":"200","data":{}}` 不含笔记 ID 时被误判为 `protocol_error` 导致队列永久 `paused` 的 P0 缺陷：上传成功后自动回查 `getNote` 按正文与首图精确绑定远端分配的 `remote_id`；
   - `syncNotesForQuestion` 拉取合并时支持认领本地尚未绑定 `remote_id` 但正文一致的笔记，杜绝产生双份重复笔记；
   - `uploadImage` 补齐 `code == '309'` 登录失效守护与重登弹窗通知。
2. **离线队列错误分级与重登自动唤醒 ([lib/db/durable_sync_queue.dart](../../lib/db/durable_sync_queue.dart) / [lib/common/request.dart](../../lib/common/request.dart) / [lib/services/auth_service.dart](../../lib/services/auth_service.dart))**：
   - 区分客户端发包前/无网异常（`SocketException`、`HandshakeException`、`309_TOKEN_EXPIRED`）与服务端结果未明的 `uncertain` 异常，离线做题或写笔记不再被首次网络失败直接锁死为 `paused`；
   - 新增 `DurableSyncQueue.wakeOnLogin`，登录成功后立即清零当前账号 `pending` 任务的退避等待时间并拉起 `YkbSyncService` 与 `NoteService` 队列。
3. **统一题目同步元数据解析与消除胶水代码 ([lib/services/ykb_sync_service.dart](../../lib/services/ykb_sync_service.dart) / [lib/screens/question_detail/question_note_view.dart](../../lib/screens/question_detail/question_note_view.dart))**：
   - 封装 `YkbSyncService.resolveQuestionMeta`，统一按「显式参数 → 章节/题目实体 → 用户库 `QuestionRelations` 投影 → 题库 `Question`/`IdentityQuestion` → 全局偏好」解析 `subjectId`、`chapterId`、`identityId` 与 `appId`，解决从「我的笔记 / 笔记详情 / 已斩题目 / 每日复习」操作时缺失科目与身份 ID 的问题；
   - 移除 `YkbSyncService.syncRedoChapter` 死代码与 `_markError` 双重递增 `retry_count`；合并 `QuestionNoteView` 中重复的 250 行笔记编辑器弹窗至共享组件 `showNoteEditorSheet`。
4. **斩题、做题、重做与拉取双向链路补齐 ([lib/repositories/question_search_repository.dart](../../lib/repositories/question_search_repository.dart) / [lib/services/daily_review_service.dart](../../lib/services/daily_review_service.dart) / [lib/models/question.dart](../../lib/models/question.dart) / [lib/services/ykb_pull_service.dart](../../lib/services/ykb_pull_service.dart) / [lib/services/ykb_bank_smart_sync_service.dart](../../lib/services/ykb_bank_smart_sync_service.dart))**：
   - 补齐「我的 - 已斩题目」取消斩题与「每日复习」熟练斩题/带选项作答向医考帮的同步调用；
   - `syncAnswer` 自动对多选题答案字母排序，并过滤非选择题/主观题自评（避免向官方选择题接口发送“已掌握”）；
   - `syncCutQuestion` / `syncAnswer` 入队时自动折叠同题未发送的旧 `pending` 任务；`resetQuestionAnswers` 全章节重做时自动清理该章节未发送的旧 `answer` 任务；
   - `YkbPullService` 重构为预取题库映射 + 单事务 `Batch` 批量合并（消除逐题 N+1 查询），支持解析远端时间戳、耗时与斩题状态；`YkbBankSmartSyncService` 增量同步题库时将远端已斩状态（`cut_question == '1'`）安全合并入用户库 `Question` 表。
5. **开发者模式「同步队列」监控对齐 ([lib/screens/developer_page.dart](../../lib/screens/developer_page.dart))**：
   - `YkbSyncQueue` 与 `NoteSyncQueue` 补齐 `SELECT COUNT(*)` 真实总数统计，列表直观展示 `queue_state`（`pending`/`sending`/`paused`）、下次重试时间与归属账号；
   - `SyncResponseCache` 支持按 `type:itemId` 复合键精确索引，消除同题不同操作响应码串扰；
   - 修复 `_showOutboxEntityDialog` 查询 `SpacedReviewItem` 的主键列名（`item_id`），并在 `Activities` 流水中新增 `YkbPull` 与 `ReviewAnswer` 专属类型徽章。
6. **笔记与主观题自评纳入 Cloudflare D1 增量同步及每日复习医考帮同步独立开关 ([backend/schema.sql](../../backend/schema.sql) / [backend/src/sync_v2.ts](../../backend/src/sync_v2.ts) / [lib/db/cloud_outbox.dart](../../lib/db/cloud_outbox.dart) / [lib/screens/settings_page.dart](../../lib/screens/settings_page.dart))**：
   - 服务端 `schema.sql` 与 `sync_v2.ts` 新增 `sync_notes`、`sync_deleted_notes` 及 `ensureNotesSchema` 自动建表，支持 `note` / `note_delete` 的批量 `pushMutations` 与 `pullChanges`；
   - 客户端 `CloudOutbox` 新增 `cloud_note_insert/update/delete`、`cloud_note_no_resurrection` 触发器与 `CloudDeletedNotes` 墓碑，支持历史笔记自动回填与远端笔记 LWW 合并；
   - 主观题自评（`'已掌握'` / `'未掌握'`）严格保留在本地与 Cloudflare D1 同步，绝不发往医考帮官方接口；
   - 「设置 - 医考帮」新增「每日复习做题同步到医考帮」与「每日复习熟练斩题同步到医考帮」两个独立开关；
   - `NoteService` 在笔记编辑移除图片或删除笔记时自动清理沙盒 `note_images` 孤儿图片。
7. **质量门禁**：
   - `dart analyze lib/ test/`：0 issues；
   - 后端测试：`tsc --noEmit` 0 errors，14/14 项全部 PASS；
   - `flutter test`：380 passed, 3 skipped (联网用例), 0 failed。

## 2026-11-23 Windows 专属字体打包与证书/CI 排查闭环（完成）

1. **Windows Gitee 题库下载 TLS 报错定位与文档化 (`README.md` / `README_EN.md`)**：
   - 定位 `unable to get local issuer certificate` 根因为 Gitee 证书链（`TrustAsia TLS RSA Root CA` ← `Certum Trusted Network CA`）与 Windows 根证书懒加载 + Dart BoringSSL 仅读已落盘存储区之间的差异；
   - 用户 Windows 实测执行 `Invoke-WebRequest -Uri "https://gitee.com" -Method Head` 后恢复下载，已将排查方法写入中英文 README。
2. **Windows 专属 Noto Sans SC 字体按平台打包与动态加载 (`windows/fonts/` / `windows/CMakeLists.txt` / `lib/main.dart`)**：
   - 避免在 `pubspec.yaml` 全局声明 30 MB 字体导致 Android APK 体积膨胀，改为仅在 Windows 构建时通过 CMake 复制 `NotoSansSC-{Regular,Medium,Bold}.ttf` 至 `data/fonts/`；
   - `lib/main.dart` 新增 `_loadWindowsFonts()`，仅在 Windows 启动时通过 `FontLoader` 动态注册，缺失时回退 `'Microsoft YaHei UI'`；其他平台保持 0 字节增量；
   - `dart analyze lib/main.dart` 0 issues，`flutter test test/app_markdown_test.dart` 4/4 PASS；已提交 `f6e780d` 并与 `f661407` 一并推送至 `origin/main`。
3. **GitHub Actions `flutter analyze --no-fatal-infos` 失败排查闭环**：
   - 定位 CI 失败原因为 `pubspec.yaml` 残留已清空的 `assets/images/` 声明（本地因 `.DS_Store` 存在而未复现，CI 触发 `asset_directory_does_not_exist` warning），已在 `f661407` 清理。

## 2026-11-18 口腔教材并入知识库（70 本）与 24 小时会话级页图签名上线（完成）

1. **17 本口腔教材提取与语料入库 (`scripts/knowledge_base/textbooks.py` / `config.json`)**：
   - 适配 `J01：` 前缀、`-第X版` 版次拆解与 macOS `._*` 过滤，提取 `/Volumes/My PSSD/书籍/口腔教科书全套/` 共 17 本 / 4,967 页，与原 53 本合并为 **70 本 / 25,636 页**；
   - `build.py` / `validate.py` 通过：全库 **175,084** 文档、**177,020** 检索块（新增 **5,557** 条口腔教材块），并完成 Google AI Search `yibubang-medical-v1` 增量导入。
2. **口腔页图压缩与 Cloudflare R2 全量上传**：
   - 将 17 本口腔教材页图压缩为长边 `2000px` / WebP `quality=75`（1.214 GB），70 本合计 51,272 对象（25,636 页图 + 25,636 缩略图），总计 **9.034 GB (8.414 GiB)**，控制在 R2 10 GB 免费额度内。
3. **24 小时会话级页图签名与静默续签 (`textbook_worker/worker.js` / `ai_backend/` / `lib/`)**：
   - `ai_backend` 新增 `GET /v1/textbooks/session`（部署版本 `yibubang-ai-search-00019-mdm`，含 70 本书目录）；
   - `worker.js` 支持 `scope=session` 24 小时鉴权；Flutter `TextbookClient` 持久化会话令牌至 `SharedPreferences`，翻页与缩略图直连 `textbooks.melonhu.com`，遇 403 自动静默续签重试。

## 2026-11-16 P1 修复推进与架构重构第二阶段（完成）

用户指示推进 P1 级剩余项修复与专项重构，完成测试后中文 commit。
1. **[M04 剩余项] `_countDueItems` 轻量化计数 (`lib/services/daily_review_service.dart`)**：
   - 彻底消除了复习概览接口在计算 `remainingDue` 时调用 `_fetchDueReviewQueue` 反序列化完整 `Question`（大文本题干、选项、解析）与笔记的内存及磁盘开销；
   - 新增 `_countDueItems`、`_countFilteredDuePage` 与 `_checkQuestionIdsExist`，概览纯走轻量 ID 校验，彻底不加载大实体。
2. **[M03 剩余项] 启动期多题库按需懒加载 (`lib/repositories/question_bank_repository.dart` / `lib/screens/home_page.dart`)**：
   - 抽象 `_initSingleBank`，新增 `initializeActiveBank({String? bankId})`；
   - 首屏启动时仅优先就绪当前活跃题库（耗时从 300ms+ 降至 20~50ms），其余题库在后台静默完成扫描与校验；
   - 用户切换题库或进入题库管理时平滑无缝。
3. **[M10 / A14] 统一 SQLite >999 变量分片执行器 (`lib/db/chunked_query_executor.dart`)**：
   - 封装通用安全的 `ChunkedQueryExecutor`（`runChunked`, `runChunkedVoid`, `queryIn`, `deleteIn`，默认分片 500），统一替代散落在 `question_search_repository.dart`、`spaced_review_repository.dart`、`daily_review_service.dart` 中的手动 `sublist` 分片与参数拼接；
   - 新增 `test/chunked_query_executor_test.dart` 全面验证 1250+ 项的分片切分、平铺聚合、附加条件与删除行为。
4. **AI 搜索多轮上下文 20 轮滑动窗口控制 (`lib/models/ai_search_options.dart` / `lib/services/ai_search_client.dart` / `lib/widgets/ai_search_settings.dart`)**：
   - 废除原先硬编码的 3 轮截断，建立默认 20 轮上下文滑动窗口控制（支持在设置中 5~50 轮自定义调节），防止 Token 消耗不可控；
   - 保持 60KB UTF-8 长度兜底防护，形成轮数与字节数的双重防御。
5. **升级 Android 编译工具链与统一 CI Flutter SDK (`android/settings.gradle` / `gradle-wrapper.properties` / `.github/workflows/*.yml`)**：
   - Android Gradle 插件 (AGP) 升级至 `9.1.1`，Gradle Wrapper 升级至 `gradle-9.5.0-all.zip`；
   - 消除 CI 工作流中为了规避编译报错而钉死在 `3.44.6` 的版本分裂，统一对齐为 `channel: 'stable'`。
6. **质量门禁**：
   - Flutter 自动化测试：367 项全部 PASS（3 联网 skip，无 failure）；
   - `dart analyze lib/` 与 `dart analyze test/`：0 errors, 0 warnings, 0 issues；
   - 后端测试：11/11 项全部 PASS，`tsc --noEmit` 0 errors。

## 2026-11-16 P1 级架构优化与性能重构（完成）

用户指示推进 P1 级 issue 修复与部分代码重构，完成测试后中文 commit。
1. **[M04] 每日复习概览纯 SQL EXISTS 聚合优化与请求去重 (`lib/services/daily_review_service.dart`)**：
   - 彻底优化了 `_scopePoolCounts` 逻辑：当 `QuestionRelations` 投影有效时，直接基于用户库走纯 SQL `EXISTS` 范围统计，消除了每次查询将十万道题 ID 拷贝入 `temp.review_pool_ids` 的巨大磁盘与内存开销；
   - 十万题合成数据库概览耗时实测从 **228ms 骤降至 8ms**（降低 96.5%）；
   - 为 `getTodaySummary` 增加了 in-flight Future 自动请求去重，避免页面首帧多个卡片与 Tab 并发重复查询数据库。
2. **[M05] 消除纯流水云同步时的无意义全库章节重算 (`lib/services/cloud_sync_service.dart`)**：
   - 修复了云同步拉取到任意记录（包含纯流水）即无条件遍历所有题库执行 `rebuildQuestionCount` 的性能缺陷；改为仅在真正拉取到 `pulledQuestions > 0` 时重算受影响题库，大幅减轻后台同步对主写锁的占用。
3. **[M04] 章节合并由 $O(C^2)$ 线性扫描优化为 $O(C)$ Map 映射 (`lib/models/chapter.dart`)**：
   - 将 `getChaptersBySubject` 中主数据与用户数据合并时的 `userRows.firstWhere` 替换为 Map 键值查找，并安全处理了空值兜底。
4. **交卷逻辑空指针安全保护 (`lib/screens/question_detail/question_detail_controller.dart`)**：
   - 统一优化交卷前未保存题目的查找逻辑，防止 `firstWhere` 在弱网或异常退出时因题目未命中抛出 `StateError: Bad state: No element`。
5. **质量门禁**：
   - Flutter 自动化测试：359 项全部 PASS（3 联网 skip）；
   - `dart analyze lib/`：0 errors, 0 warnings, 0 issues；
   - 后端测试：11/11 项全部 PASS，`tsc --noEmit` 0 errors。

## 2026-11-16 P0 级缺陷修复与云同步 Worker 批处理性能优化（完成）

用户明确指示立即修复 P0 级 issue 并在测试通过后中文 commit。
1. **[M13] 每日计划卡片入口算法配置修复 (`lib/widgets/daily_review_card.dart` / `lib/services/daily_review_service.dart`)**：
   - 修复了 `DailyReviewCard` 默认使用未配置 SM-2 算法服务进入 `DailyReviewPage` 的隐性缺陷，增加 `_ensureConfiguredService()` 动态加载与校验引擎机制；
   - `DailyReviewService` 新增 `createConfigured(...)` 静态异步工厂方法，统一根据用户偏好（轻量化 FSRS / SM-2）构造服务；
   - 更新 `post_a20_current_state_probe_test.dart` 断言与 `test/daily_review_ui_test.dart`（覆盖配置 FSRS 后从卡片直接进入复习的场景）。
2. **云同步 Worker `pushMutations` 批量操作聚合 (`backend/src/sync_v2.ts`)**：
   - 将原先对最多 500 个 mutation 的逐条串行 SELECT 检查与独立 D1 batch 写入，优化为按 25 条切片批量查询已存在变动（`seenMap`）并在单个 D1 batch 事务中聚合提交；
   - 将单次 500 条突发上传的网络往返次数从 1000 次急剧降至 40 次以内，彻底消除了 Cloudflare Worker CPU 耗尽与子请求（subrequests）超限风险。
3. **后端环境与测试规范标准化 (`backend/package.json`)**：
   - 明确声明 `"engines": { "node": ">=22.11.0" }`，增加 `"test"` 与 `"typecheck"` 脚本，统一测试运行标准。
4. **质量门禁**：
   - Flutter 测试：全量 359 项 100% PASS（3 联网 skip）；
   - `dart analyze lib/`：0 errors, 0 warnings, 0 issues；
   - 后端测试：`sync_v2_test.mjs` / `deployment_test.mjs` 11 项全部 PASS，`tsc --noEmit` 0 errors。

## 2026-11-15 云同步协议 v2 正式发布（完成）

用户明确授权云服务升级；起始main@468e72b/干净。正式D1已增量迁移并保留17账号/31设备/18313题状态/20584流水，补齐38897变更序号；Worker b482e035-765f-4563-b964-32b9a863cb8f/100%。健康明确protocol2，生产HTTP500+1分页/重试去重/删除跨设备及实际CloudSyncService临时SQLite链路通过；后端11/11、tsc/dry-run、Flutter相关18/18，联网1/1。迁移计费77813行写入，免费额度仍需预算。详见[发布记录](audits/SYNC_V2_DEPLOYMENT.md)。未改App/AI/教材，未commit/push；测试账号清理后原数据数量和完整性检查保持。

## 2026-11-15 版本发布：v2.2.4+214

- **版本号升级**：`pubspec.yaml` 正式递增至 `2.2.4+214`。
- **更新清单同步**：更新 `yibubang_update.json`，写入 v2.2.4 各平台资产直链与结构化版本更新说明，保证客户端在线更新能够正确检出与解析。
- **发布说明归档**：建立 `docs/release-notes/v2.2.4.md`，汇总自 v2.2.3 以来的四大核心变更（AI 搜索与 53 本教材知识库上线、UI Material 3 动效与交互打磨、A01~A20 白盒深度缺陷修复、跨平台 CI 与工具链稳定性加固）。
- **质量门禁**：全量 358 项自动化测试全部通过，`flutter analyze` 零 issues。

## 2026-11-14 AI 搜索全模块 UI 重构与细节体验升级

针对用户对 AI 搜索、教材检索与设置界面的全面体验反馈，完成整体重构与细节打磨：
1. **设置-AI搜索与全局设置提示统一 (`lib/widgets/info_hint_banner.dart` / `lib/widgets/ai_search_settings.dart` / `lib/screens/settings_page.dart` / `lib/screens/shortcut_settings_page.dart` / `lib/widgets/bank_subscription_settings.dart`)**：
   - 模型选择改为自适应居中卡片 / 底部抽屉，内置推荐稳定版与预览版徽章，支持无感离线切换与单项高亮；
   - 检索条目与比例设置：将独立的双色彩带与下方滑块直接融为一体（`SliderTheme` 轨道自身展示 primary 教材色与 tertiary 题目色），去除多余图例行，彻底消除了小屏 320px 宽度下的 29px 布局溢出；
   - 设置页中的所有说明提示（记忆算法弹窗、导入模式弹窗、快捷键单选/多选提示、底栏设置提示、AI 搜索说明、题库自动检查更新说明）全部统一替换为标准化 `InfoHintBanner` 组件。
2. **底栏-AI搜索页面 (`lib/screens/ai_search_page.dart`)**：
   - 增加进入页面的平滑淡入与位移动画（FadeTransition + SlideTransition）；
   - 欢迎界面卡片式排版，内置 30+ 医学高质量精选问题库，每次随机抽选 3 个问题展示；
   - 聊天视图区分用户气泡与 AI 卡片，流式输出时平滑锁定当前提问顶部不强制跳滚；
   - 参考资料折叠状态本地持久化（`SharedPreferences`），下次进入自动保持用户选择；
   - 参考资料课本标题精简化（去除冗长前缀后缀，只保留书名），页码精炼为右上角微型角标（如 `P299`），整洁美观且通过 `Tooltip` 完整保留原引用来源说明。
3. **AI搜索-教材检索页面与直接查页 (`lib/screens/textbook_search_page.dart`)**：
   - 废除原生的 `DropdownButtonFormField`，改为多选模态卡片，移除多余的书本图标避免与打勾图标重叠；
   - 右上角落地「直接查页」功能，支持选择课本、输入 PDF 页码快速验证并调阅真实高清页图。
4. **自制闪卡体验优化 (`lib/widgets/flashcard_deck_dialog.dart`)**：
   - 展开 AppBar 搜索框时自动获取焦点（`autofocus`），光标即刻就绪。
5. **底栏设置安全兜底 (`lib/screens/bottom_nav_settings_page.dart` / `lib/models/bottom_nav_config.dart`)**：
   - 限制「我的」页面不可取消勾选，保证系统设置入口始终可达。
6. **全量与静态检查**：
   - `test/ai_search_ui_test.dart`、`test/ai_search_settings_test.dart`、`test/textbook_search_test.dart`、`test/bank_subscription_test.dart` 100% PASS；
   - `dart analyze lib/` 0 issues。


## 2026-11-16 Cloudflare D1+R2 混合冷热同步架构与开发者同步队列接入

- **D1 同步真空补齐**：卡片（`CustomFlashcards`）、记忆曲线（`SpacedReviewItem`）、复习计划（`ReviewPlans`）全面纳入 Cloudflare D1 增量同步流水线，支持批量推送、拉取合并与防复活墓碑控制。
- **D1 增量 + R2 冷备快照**：
  - Cloudflare Worker 绑定 R2 Bucket `BACKUP_BUCKET` 并提供备份上传、列表、下载与自动修剪接口；
  - 客户端实现 `CloudBackupService`，支持 WAL checkpoint 截断、GZip 压缩、SHA-256 校验和、双端点主备容灾轮询、防损回滚与自动周期调度（默认关、7天/10份可调）；
  - `CloudSyncPage` 提供完整的冷备快照管理面板与抽屉还原交互。
- **官方图床接入**：自制闪卡（正面与背面）支持直接调用医考帮官方图床上传接口，在光标处插入 Markdown 图片语法。
- **开发者模式同步队列升级**：
  - `DeveloperPage` 接入「Cloudflare D1 增量变动队列 (CloudOutbox)」与「Cloudflare R2 冷备快照」卡片，支持实时监控、实体详情穿透查阅与单项移出；
  - 修复 `Activities` 渲染将闪卡/记忆项自评误判为做题提交的展示 bug；
  - 补齐数据库统计中缺失的 6 张核心数据表计数。
- **全量回归验证**：
  - `dart analyze lib/`：0 issues；
  - 后端测试：`tsc --noEmit` 0 errors，13/13 项全量通过；
  - `flutter test`：371 passed，100% 全部通过。

## 2026-11-13 Windows复习测试超时修复

起始main@2b80da1与origin一致/干净。Windows Actions43432164278与43436136566均在daily_review_service_test的数据准备阶段超30秒：502题+502复习项逐条自动提交，timeout后tearDown关闭库，未完成insert报database_closed；尚未调用buildDailySession。

仅该用例改为题目Batch和现有repo.batchSaveItems两批事务；保留501条不在覆盖范围的到期题与最后q_4，增加首批500条均为outside的断言，继续通过真实服务验证翻页找到q_4。保留默认30秒门禁，不改生产服务/SQLite配置/CI并发或SDK。

Flutter3.44.6与Windows CI同版3.50.0的该文件均11 PASS；3.50全量357 PASS/3联网默认skip。dart analyze与CI分析均exit0、0 errors/warnings、119弃用info，单文件格式/diff及62份文档547链接通过。本机为macOS，Windows runner修复后仍需push重跑；上一提交2b80da1的Android/macOS/Linux远程已成功。

## 2026-11-13 Android Release工具链修复

起始main@4deacbb/工作区干净。该提交的Android Actions已通过Analyze/Tests，但release构建报ApplicationExtension.getDefaultConfig不存在；Flutter3.50.0要求AGP>=9.1.1，项目AGP8.11.1/Gradle8.14不兼容，本机同SDK复现原报错。

Android日常与Release build-android固定Flutter3.44.6，保留现有Gradle/AGP/Kotlin配置，移除跳过依赖检查参数。隔离工作树Java17实际release通用80.1MB、armeabi-v7a28.5MB、arm64-v8a30.4MB、x86_64 32.1MB均exit0；APK签名/包名/版本/ABI检查通过。同SDK dart analyze和CI分析均No issues/exit0，全量357 PASS/3联网默认skip。YAML解析、本地545链接与diff检查通过。

其他平台和Release verify继续stable。新修复尚未推送或触发Release，未改App业务代码/README或云资源；旧4deacbb的Linux/macOS已成功，Windows独立测试timeout待处理，见问题账本。

## 2026-11-13 README恢复与新版CI分析修复

用户选择仅撤销814a20d对README的精简改写，保留1–25检索/选择修复与docs整理。当前父基线082f205（用户已合并/同步远端），不reset或改写共享历史；恢复ec0fdf6的品牌页/徽章/章节/截图并补最新App功能，英文同步恢复。

四平台Actions在Analyze阶段因Flutter自动更新至3.50.0而失败，本地此前3.44.6静态0不能代替该SDK。修复note_service.syncNotesForQuestion中try内返回Future缺await；3.50.0/Dart3.14.0独立工作树实际dart analyze与CI的flutter analyze --no-fatal-infos均exit0、0 errors/warnings、119弃用info。新版全量首次暴露设置测试触发后台网络的Timer，fixture补最近检查时间，避免无关网络；定向6 PASS，旧SDK笔记/队列27 PASS。同版SDK最终全量357 PASS/3联网默认skip，修改后两种分析命令再次exit0。

不升级现有本机SDK、不修改CI warning阻断规则、不迁移全项目Material导入；3.50源码/缓存/隔离工作树/日志仅在ai_backend/.local。没有云重新部署或数据上传，远程Actions尚未重新运行。

恢复后62份文档/544个本地链接检查通过，git diff --check通过；用原analysis_options的同版dart analyze仍exit0/119 infos。主工作区未引入SDK自动迁移或依赖配置变化。

更新：2026-11-13；main；本轮修正提交父基线082f205，上一轮814a20d父基线ec0fdf6。用户已授权恢复README并保留功能修复和docs整理；本次不push或发布Release。准确HEAD以`git log -1`为准。

[当前进度](../CURRENT_STATUS.md)是完整状态入口，[交接](SESSION_HANDOFF.md)列下一步。此前各阶段记录已完整保留在[历史状态](../archive/development-history/DEVELOPMENT_STATUS.md)，其中“未提交/未实现/旧模型”等描述仅属于对应阶段。

## 已完成

- A01–A20源码修复独立提交；M01精准刷新、M02投影真实路径、M03隐藏Tab延迟挂载切片完成，后续维护范围没有顺手扩大。
- 149472题块+21991教材块已导入原Google Store；53本/20669页复用OCR，原PDF留本地；全部页图/小图在私有R2，自定义域和鉴权缓存完成。
- 独立Cloud Run内置Answer/streamAnswer、模型本机目录回退、200额度/1–2–3规则、本地session、教材引用/缩放/缓存/键盘和默认Tab完成。
- 最新证据数量可调1–25/默认12，来源比例随总数变化；后台二源独立检索、严格扣额前校验、预算保留。25条默认17教材/8题；增加条数不保证模型全部使用。
- lastSelectionResult段落选择断言精确复现并修复，正文选择/引用点击仍可用。
- 项目说明移至docs/project、AI手册至docs/ai-search、数据手册至docs/knowledge-base；旧入口原文归档，链接与Release说明路径更新；文档纳入Git，私有本地资料继续忽略。

## 验证与部署

当前Cloud Run00018-q7c/100%。Flutter357 PASS/3联网默认skip、最终相关8 PASS、后端39 PASS、analyze0、Android/macOS Debug构建通过；App真实25条17:8→内置回答→SQLite→引用2联网PASS，非法输入400且额度不变。[详细记录](../ai-search/VALIDATION.md)。文档整理后再检查链接、静态分析和Git范围，不无理由重复付费生成或数据上传。

文档整理复核：62份Markdown/HTML引用共520个本地链接通过，无失效或指向未版本化私有文件的链接；静态分析0。旧审计凭据示例已脱敏；最终暂存范围只含本轮源码/测试、文档及必要的忽略/Release说明路径调整。

## 独立待完成

同步服务真实用户/目标网络及全天配额验收（v2/schema已发布）；M03目录阶段化、M04/M05、M13算法入口等维护；375页医学符号/公式与版次ISBN、167题答案冲突；Android/Windows/Linux/iOS实机、目标地区网络、Release发布；专项赠金SKU/Advanced实际账单；真正Embedding/向量库迁移。[问题账本](KNOWN_ISSUES.md)和[技术债](TECHNICAL_DEBT.md)保留边界。
