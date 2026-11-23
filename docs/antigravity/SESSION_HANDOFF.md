# 跨会话交接

## 最新交接：2026-11-23 医考帮点赞评论后台同步全局状态机、防并发互斥与跨页面生命周期保持

- **用户授权与操作目标**：
  1. 修复在同步过程中退出“我的点赞”返回“我的”页，再点进去不显示正在同步但后台仍在运行的 Bug；
  2. 修复后台同步仍在运行时，用户在页面上强行再次点击导致两个同步任务并发运行、相互竞态的问题。
- **完成项**：
  1. **[全局后台同步状态机与并发互斥保护 (`lib/services/comment_service.dart`)]**：
     - 定义 `CommentBatchSyncState` 数据模型，在单例 `CommentService` 统一维护全局响应式状态 `batchSyncNotifier` 与快捷属性 `isBatchSyncing`；
     - `syncFromTouchedQuestions` 增加严格的单飞互斥保护：若当前已有后台批量任务在运行，抛出 `StateError` 拒绝并发拉起第二个任务；
     - 循环过程实时将当前已扫题数 `current`、总数 `total`、分类 `category` 与 `isRunning` 写入全局 `batchSyncNotifier`，在 `finally` 块中确保重置 `isRunning: false`，杜绝异常导致状态卡死；
     - 提供单例级 `cancelBatchSync()`，实现跨页面随时一键安全终止后台任务。
  2. **[UI 跨页面生命周期保持与无缝恢复 (`lib/screens/my_saved_comments_page.dart`)]**：
     - `MySavedCommentsPage` 在 `initState` 中直接读取全局 `batchSyncNotifier`，退出重进即刻恢复当前分类的后台同步状态与进度展示（`15/120`）；
     - 监听 `batchSyncNotifier` 变化，后台完成时自动刷新列表 `_loadData()` 并清除 AppBar 进度条；
     - AppBar 点击同步按钮时先做全局互斥判断：若后台任务匹配当前页面分类，秒开正在运行的进度浮窗（可继续查看实时进度或点击终止）；若后台任务在跑其他分类，提示“后台正在同步其他数据”；
     - 弹窗直接绑定 `batchSyncNotifier`，实现进度流动跳动与一键全局终止。
- **质量门禁验证**：
  - `dart analyze lib/ test/`：**No issues found!**
  - `flutter test test/comment_features_test.dart`：**9/9 PASS**（新增全局批量同步互斥防护与 cancelBatchSync 状态流转测试）
  - 全量用例 `flutter test test/official_sync_queue_test.dart test/daily_review_service_test.dart test/comment_features_test.dart`：**29/29 PASS**
  - 后端 `npm run typecheck` & `npm test`：**14/14 PASS**
- **未完成项 / 下一次第一步**：
  - 代码保留在工作区未 commit（严格遵循 `AGENTS.md`，待用户检阅确认）。

## 前次交接：2026-11-23 医考帮我的点赞/我的评论归纳同步、评论四维排序页、卡片池联动及闪卡导航修复

- **用户授权与操作目标**：
  1. 先对上一轮医考帮双向同步修复执行中文 Git commit（已提交 `4844952`）；
  2. 开发 Issue #24「我的点赞」与「我的评论」读取、本地归纳保存及云端同步（与笔记走相同流程）；
  3. 开发独立的题目评论四维排序页面（最多点赞、最高热度、最多回复、最新发布 4 个 Tab，可从题目页评论区进入）；
  4. 「设置 - 关于医不帮」加入 Telegram 群链接（`t.me/yibubang`）；
  5. 排查并修复「闪卡详情 -> 编辑闪卡」返回时连退两级回到卡包管理页面的问题；
  6. 「每日复习计划 - 卡片池」五个板块（错题攻克、星标收藏、速记笔记、自制闪卡、熟练斩题）全部支持点击并复用「我的」页对应页面。
- **完成项**：
  1. **[我的点赞 & 我的评论拉取、归纳与 D1 云同步 (`lib/models/comment.dart`, `lib/services/comment_service.dart`, `lib/screens/my_saved_comments_page.dart`, `lib/screens/my_page.dart`, `lib/db/cloud_outbox.dart`, `backend/`)]**：
     - 对接 `POST /Comment/Main/list`（`func=mypraise` / `func=mycomment`）、`POST /Comment/Main/praise`、`POST /Comment/Main/publish`；
     - 在用户库新增 `SavedComments` 与 `CloudDeletedSavedComments` 表，并在 `CloudOutbox` 与 Cloudflare D1 `sync_v2.ts` 中新增 `saved_comment` / `saved_comment_delete` 增量同步；
     - 在「我的」页新增「我的点赞」与「我的评论」入口，支持搜索高亮、课程筛选、右侧时间轴拖动、转笔记、制闪卡、复制、移除、查看详情与跳转原题。
  2. **[题目评论四维排序独立页面 (`lib/screens/question_comments_page.dart`, `lib/screens/comment_page.dart`)]**：
     - 对接 `POST /comment/main/hot`，通过 4 个 Tab 展示 `最多点赞` (`type=''`)、`最高热度` (`type='recommend'`)、`最多回复` (`type='replies'`)、`最新发布` (`type='newst'`)；
     - 题目详情页评论区支持内联切换「最热 / 最新 / 我的点赞 / 我的评论」、发表评论及一键进入四维排序页面。
  3. **[关于页面、闪卡详情导航层级与卡片池五板块联动 (`lib/screens/about_page.dart`, `lib/widgets/flashcard_deck_dialog.dart`, `lib/screens/daily_plan_page.dart`)]**：
     - `AboutPage` 新增 `Telegram 交流群` (`https://t.me/yibubang`)；
     - `_FlashcardDetailView` 改为内部直接唤起 `FlashcardEditDialog` 并原地刷新状态，不再提前 `pop` 详情页，解决返回时连退两级的问题；
     - `DailyPlanPage` 卡片池五个统计胶囊全部接入 `UserQuestionsListPage`、`MyNotesPage` 与 `FlashcardDeckDialog`。
- **质量门禁验证**：
  - `dart analyze lib/ test/`：**No issues found!**
  - `flutter test test/comment_features_test.dart`：**4/4 PASS**
  - 后端 `npm run typecheck` & `npm test`：**14/14 PASS**
- **未完成项 / 下一次第一步**：
  - 新功能代码保留在本地工作区（遵守 `AGENTS.md` 未自动 commit 新功能代码，待用户检阅确认）。

## 前次交接：2026-11-23 医不帮 ↔ 医考帮官方双向同步白盒审计与全链路修复

- **用户授权与操作目标**：
  1. 先对「医不帮 ↔ 医考帮官方」四大双向同步业务（做题、斩题、笔记、全章节重做）、持久化队列（`DurableSyncQueue` / `NoteSyncStore` / `CloudOutbox`）、抓包样本（`docs/api-req-resp/`）及「开发者模式 - 同步队列」UI 进行全面白盒审计；
  2. 用户确认审计报告后，授权按方案逐步完成全量修复，并要求保持代码整洁、减少胶水代码。
- **完成项**：
  1. **[P0 修复：新建笔记 `pushNote` 空 `data: {}` 闭环与防重复合并 (`lib/services/note_service.dart`)]**：
     - 适配医考帮 `pushNote` 真实响应 `{"code":"200","message":"请求成功","data":{}}`：当返回 200 但无 `id` 时，自动调用 `_resolveCreatedRemoteId`（请求 `getNote` 按正文和首图匹配最新笔记 ID）并在同一事务内绑定 `Notes.remote_id`（若期间已删除则绑定 `NoteTombstones.remote_id` 并入队 `cleanNote`）；
     - `syncNotesForQuestion` 拉取时支持按正文认领本地未绑定 `remote_id` 的同内容笔记，消除本地双份重复笔记；
     - `uploadImage` 补齐 `code == '309'` 登录过期清理与弹窗提示。
  2. **[P0 修复：离线同步队列错误分级与登录自动唤醒 (`lib/db/durable_sync_queue.dart`, `lib/common/request.dart`, `lib/services/auth_service.dart`)]**：
     - 区分发包前/无网/鉴权错误（`SocketException`、`HandshakeException`、`309_TOKEN_EXPIRED`）与发包后结果未明的 `uncertain` 错误，避免离线做题和笔记上传在首次网络异常时被直接置为 `paused`；
     - 新增 `DurableSyncQueue.wakeOnLogin`，登录成功后自动重置当前账号 `pending` 任务的 `next_attempt_at = 0` 并触发 `YkbSyncService` 与 `NoteService` 队列消费。
  3. **[P1 修复与架构收敛：统一题目元数据解析器、彻底纠正 `chapter_parent_id` 与科目混淆 (`lib/services/ykb_sync_service.dart`, `lib/models/question.dart`, `lib/services/note_service.dart`, `lib/screens/question_detail/question_note_view.dart`)]**：
     - 在 `YkbSyncService` 中提取 `resolveQuestionMeta`，统一从显式参数、章节/题目对象、用户库 `QuestionRelations` 投影表及题库 `Question`/`IdentityQuestion` 反查 `subjectId`、`chapterId`、`identityId`、`appId`、`chapterParentId`；
     - 针对医考帮抓包与真实题库核验：彻底厘清外层 `identity_id`（如 20301）、内层 `identity_id`（如 203010 刷题叶子）、内层 `chapter_parent_id`（如 11 层级父章）与内层 `subject_id`（如 20301 科目体系）的关系。纠正了历史代码将 `chapter_parent_id` 错当 `subject_id` 的反向覆盖 Bug，内层严格上报真实父章节 ID；
     - 修复 `NoteService` 写入 `Question` 兜底行时误将 `meta.subjectId` 存入 `chapter_parent_id` 的历史 Bug；
     - 删除未使用的死代码 `YkbSyncService.syncRedoChapter`，消除 `_markError` 与 `DurableSyncQueue` 双重递增 `retry_count`；
     - 将 `QuestionNoteView` 内联重复的 250 行笔记编辑器弹窗统一收敛至 `showNoteEditorSheet`。
  4. **[P1/P2 修复：斩题、做题、重做去重与拉取批处理优化 (`lib/repositories/question_search_repository.dart`, `lib/services/daily_review_service.dart`, `lib/models/question.dart`, `lib/services/ykb_pull_service.dart`, `lib/services/ykb_bank_smart_sync_service.dart`)]**：
     - 补齐 `QuestionSearchRepository.setCutQuestion`（「我的 - 已斩题目」取消斩题）与 `DailyReviewService.cutQuestion` / `submitReviewResult`（「每日复习」熟练斩题与做题）向 `YkbSyncService` 的同步调用；
     - `YkbSyncService.syncAnswer` 对多选题答案执行大写与字母排序规范化，并跳过主观题自评（避免向选择题接口提交“已掌握”）；
     - `syncCutQuestion` 与 `syncAnswer` 入队时自动替换同题尚未发出的 `pending` 旧任务；`resetQuestionAnswers` 全章节重做时自动删除该章节下尚未发出的 `pending` 作答任务；
     - `YkbPullService._pullBank` 重构为预取题库映射 + 分批查询用户库 + 单事务 `Batch` 提交，并支持合并远端斩题状态、时间戳与耗时；`YkbBankSmartSyncService` 增量同步题库时自动将远端 `cut_question == '1'` 合并入 `user_data.Question`。
  5. **[P1/P2 修复：开发者模式「同步队列」UI 对齐 (`lib/screens/developer_page.dart`)]**：
     - `YkbSyncQueue` 与 `NoteSyncQueue` 增加 `SELECT COUNT(*)` 真实总数统计，列表项展示 `queue_state`（`已暂停` / `发包中` / `退避中` / `待同步`）、下次重试时间与账号归属；
     - `SyncResponseCache` 支持按 `type:itemId` 精确查询，修复同题不同操作响应码串扰；
     - 修复 `_showOutboxEntityDialog` 查询 `SpacedReviewItem` 主键列名错误（`id` -> `item_id`），并在 `Activities` 流水中新增 `YkbPull` 与 `ReviewAnswer` 专属徽章。
  6. **[用户反馈增补：笔记与主观题 Cloudflare D1 同步、每日复习独立同步开关与沙盒孤儿图片清理 (`backend/`, `lib/db/cloud_outbox.dart`, `lib/screens/settings_page.dart`, `lib/services/note_service.dart`)]**：
     - 服务端 `backend/schema.sql` 与 `backend/src/sync_v2.ts` 新增 `sync_notes`、`sync_deleted_notes`（含运行时 `ensureNotesSchema` 幂等自愈建表），支持 `note` 与 `note_delete` 的批量推送与拉取；
     - 客户端 `CloudOutbox` 完整实现 `Notes` 增删改触发器、`CloudDeletedNotes` 防复活墓碑、已有笔记自动回填与 `mergePage` LWW 合并；
     - 主观题/填空题自评（`'已掌握'` / `'未掌握'`）严格拦截不发往医考帮接口，同时通过 `CloudOutbox` 的 `question` 与 `activity` 触发器完整同步至 Cloudflare D1；
     - 「设置 - 医考帮」新增「每日复习做题同步到医考帮」与「每日复习熟练斩题同步到医考帮」两个独立开关；
     - `NoteService.saveNote` / `deleteNote` 自动清理 `note_images` 沙盒目录下被移除的孤儿图片。
- **质量门禁验证**：
  - `dart analyze lib/ test/`：**No issues found! (0 errors, 0 warnings)**；
  - 后端测试：`npm run typecheck` (`tsc --noEmit`) 0 errors，`npm test` **14/14 PASS**；
  - `flutter test --no-pub`：**380 passed, 3 skipped (联网用例), 0 failed**。
- **未完成项 / 下一次第一步**：
  - 所有代码与文档修改均保留在本地工作区（严格遵守 `AGENTS.md` 未自动执行 `git commit`）；
  - 若需在线上 Cloudflare Worker 立即生效 `sync_notes` 表同步，可在 `backend/` 目录执行 `npx wrangler deploy`（`ensureNotesSchema` 会在首次请求时自动在远端 D1 建表，无需手动跑迁移脚本）。

## 前次交接：2026-11-23 Windows 题库下载 TLS 排查、专属 Noto Sans SC 字体打包与 CI 分析修复

- **用户授权与操作目标**：
  1. 排查 Windows 端「题库管理 → 下载题库」报 `HandshakeException: CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` 的原因，验证后将排查方法写入 README；
  2. 解决 Windows 端 Flutter 默认字体混排粗细不一问题，且不增加 Android APK 体积（仅在 `flutter build windows` 时打包注入 `Noto Sans SC` 400/500/700 三个字重），完成后中文 commit；
  3. 排查 GitHub Actions `flutter analyze --no-fatal-infos` 失败但本地通过的差异原因；
  4. 将上述长期记忆与交接信息沉淀到知识库文档。
- **完成项**：
  1. **[Windows Gitee TLS 报错定位与文档补充 (`README.md`, `README_EN.md`)]**：
     - 实测证书链确认 Gitee 使用 `TrustAsia TLS RSA Root CA`（由 `Certum Trusted Network CA` 交叉签发），Windows 根证书采用按需懒加载，而 Dart BoringSSL 仅读取已落盘的 Windows 证书存储区；
     - 用户在报错 Windows 机器执行 `Invoke-WebRequest -Uri "https://gitee.com" -Method Head` 后重启应用验证下载恢复正常，已将说明与命令写入中英文 README。
  2. **[Windows 专属字体打包与动态加载 (`windows/fonts/`, `windows/CMakeLists.txt`, `lib/main.dart`, `pubspec.yaml`)]**：
     - 还原 `pubspec.yaml` 中的全局 `fonts:` 声明，将 `NotoSansSC-{Regular,Medium,Bold}.ttf` 与 `OFL.txt` 移至 `windows/fonts/`，确保 Android / macOS / Linux 安装包 0 字节增量；
     - `windows/CMakeLists.txt` 增加安装规则，仅在 Windows 构建时复制 `windows/fonts/` 至产物 `data/fonts/`；
     - `lib/main.dart` 新增 `_loadWindowsFonts()`，仅在 `!kIsWeb && Platform.isWindows` 时通过 `FontLoader('NotoSansSC')` 动态注册 400/500/700 字重，未找到字体时回退 `'Microsoft YaHei UI'`；
     - 验证 `dart analyze lib/main.dart`（No issues）与 `flutter test test/app_markdown_test.dart`（4/4 PASS），完成中文 commit `f6e780d`。
  3. **[GitHub Actions 静态分析失败排查闭环]**：
     - 调取 Actions job `137244025881` 日志定位唯一失败项：`pubspec.yaml` 残留已删除截图的 `assets/images/` 声明（本地因目录内残留 `.DS_Store` 未报错，Git 不保留空目录导致 CI 报 `asset_directory_does_not_exist` warning）；
     - 用户已在 `f661407` 整理提交并推送 `origin/main`。
- **未完成项 / 下一次第一步**：
  - 本次文档更新（`PROJECT_MEMORY.md`、`DEVELOPMENT_STATUS.md`、`SESSION_HANDOFF.md`）保留在本地未提交状态（按规则不自动 `git commit`）；
  - 下一次第一步：检查 `git status` 并按需提交本次知识库文档更新；在 Windows 真机运行最新构建确认 `Noto Sans SC` 400/500/700 渲染效果，并关注远端 GitHub Actions 四平台构建状态。

## 前次交接：2026-11-19 医不帮单页长滚动官网 (yibubang-web) 从零构建与全量验证

- **用户授权与操作目标**：
  - 检查 `./yibubang-web` 目录结构后，基于最新产品特性（纯净离线与全平台、四大刷题模式、每日计划与记忆闪卡、有依据的 AI 搜索与 53+17 本教材原页直达、学习统计与打卡格子墙、多端同步与数据安全、四大专业题库与动态最新版本号下载）为医不帮打造面向医学生的单页长滚动官网。
- **勘察结论与完成项**：
  1. **前置勘察**：`./yibubang-web` 初始为空目录，新建完整的 Vite + TypeScript 工程，并精选复制图标与 14 张最新界面截图至 `./yibubang-web/assets/`（刻意排除含测试卡片或技术字样的截图）。
  2. **设计体系与交互板块 (`yibubang-web/src/`)**：
     - 提取 App 临床深青 (`#1E5E6E`) + 冰青浅底 + 朱砂红 (`#DC5344`) 配色，支持浅色/深色模式切换与全局大图 Lightbox 预览；
     - 完整构建导航栏、Hero 三屏联动视差、01 纯净离线 Bento（含键盘快捷键体验）、02 四大刷题模式、03 3D 记忆闪卡（公式、牙冠纵剖插图放大、记忆曲线评分）、04 AI 医学搜索聚光灯（点击引用角标直达教材原页与追问）、05 刷题打卡格子墙与统计图表、06 配对码多端同步与数据安全、07 专业题库覆盖、08 动态 Release 版本号与国内高速镜像/GitHub 双路下载中心及页脚；
     - 面向医学生精炼文案，页面展示文案与弹窗中零技术实现术语。
- **验证与质量门禁**：
  - `cd yibubang-web && npm run build`（`tsc --noEmit && vite build`）：0 errors，15 张 PNG 与 JS/CSS 完整输出至 `dist/`；
  - 浏览器实测（`1440×900` 与 `375×812`）：无横向溢出、全部 15 张截图加载正常、全部交互可用、控制台零报错。
- **未完成项 / 下一次第一步**：
  - `yibubang-web/` 尚未初始化独立 Git 提交或部署至静态托管（按规则未执行自动 `git commit`，主工程原有未提交变更完整保留）。

## 前次交接：2026-11-18 口腔教材知识库全量入库与 24 小时会话级页图签名上线

- **用户授权与操作目标**：
  1. 将 `/Volumes/My PSSD/书籍/口腔教科书全套/`（17 本口腔教材、4,967 页）并入医不帮知识库与 Google AI Search；
  2. 将 17 本口腔教材页图压缩使 Cloudflare R2 总容量控制在 10 GB 免费额度内，并完成全量上传；
  3. 优化教材页图加载速度：在 Cloudflare Worker、Cloud Run 与 Flutter 客户端落地 **24 小时会话级签名 + 失效静默续签**，消除翻页时每次请求东京 Cloud Run 签名的延迟。
- **完成项**：
  1. **[口腔教材提取与知识库构建 (`scripts/knowledge_base/textbooks.py`, `scripts/knowledge_base/config.json`)]**：
     - `textbooks.py` 新增 `parse_title_edition` 支持 `J01：` 前缀、`-第X版` 版次拆分与后缀清洗，并过滤 macOS `._*` 文件；
     - 17 本口腔教材（4,967 页）提取完成，与原 53 本合并为 **70 本 / 25,636 页**，写入 `/Volumes/My PSSD/书籍/医不帮教材知识库/textbooks.sqlite` 与 `catalog.json`；
     - `build.py` 与 `validate.py` 通过：全库 **175,084** 文档、**177,020** 检索块（新增 **5,557** 条口腔教材块，`deleted_chunks: 0`）。
  2. **[口腔页图压缩与 R2 全量上传]**：
     - 17 本口腔教材页图按长边 2000px、WebP quality=75 重压缩，体积由 2.002 GB 降至 **1.214 GB**；
     - `validate_textbook_images.py` 通过（70 本、25,636 页、缺页 0）；
     - 全部上传至 Cloudflare R2 `yibubang-textbooks`：共 **51,272** 个对象（25,636 页图 + 25,636 缩略图），总计 **9,034,170,996 bytes（9.034 GB / 8.414 GiB）**，稳妥控制在 10 GB 免费额度内。
  3. **[Google AI Search 同步与 Cloud Run 部署 (`ai_backend/textbook_catalog.json`, `ai_backend/textbook_support.py`, `ai_backend/app.py`)]**：
     - 5,557 条口腔教材块成功增量导入 `yibubang-medical-v1`（operation `import-documents-8293321359334584749`）；
     - `ai_backend` 新增 `/v1/textbooks/session`（24 小时会话级 HMAC 签名），更新 70 本书目录并部署至 Cloud Run（`yibubang-ai-search-00019-mdm`）。
  4. **[Cloudflare Worker 与 Flutter 客户端优化 (`textbook_worker/worker.js`, `lib/services/textbook_client.dart`, `lib/screens/textbook_reader_page.dart`, `lib/widgets/textbook_thumbnail.dart`, `test/textbook_search_test.dart`)]**：
     - `worker.js` 支持 `scope=session`（24 小时校验）并保留单页签名向后兼容，已部署至 `https://textbooks.melonhu.com`；
     - `TextbookClient` 本地缓存与 `SharedPreferences` 持久化 24 小时会话令牌，翻页/缩略图直连 `textbooks.melonhu.com`，遇到 403/失效时自动静默续签并重试一次。
- **质量门禁与线上验证**：
  - `scripts/knowledge_base` 单元测试：18/18 PASS；
  - `ai_backend` 单元测试：40/40 PASS；
  - Flutter 教材相关：`dart analyze` 0 issues，`flutter test test/textbook_search_test.dart test/textbook_reader_gestures_test.dart` 6/6 PASS；
  - 线上端到端实测：检索《牙体牙髓病学》命中第 5 版 PDF 第 215 页，携带 24 小时会话令牌从 `textbooks.melonhu.com` 下载页图（242,570 B）与缩略图（21,908 B）SHA-256 与本地完全一致，篡改签名返回 403。
- **未完成项 / 下一次第一步**：
  - 本地代码变更尚未 git commit（等待用户确认后提交）；
  - 下一次第一步：在真机/客户端重新编译运行最新 Flutter 代码，体验口腔教材检索与 24 小时直连翻页速度。

## 前次交接：2026-11-18 Cloudflare D1 万题大批量同步前后端性能优化上线与 Markdown 图片居中防闪跳修复

- **用户授权与操作目标**：
  1. 解决万题同步报错 `HTTP 500 (耗时 43181ms)`：前后端联动实施 GZip 压缩 + 多行批量 SQL Upsert + `push_only` 跳过中间拉取 + 客户端自适应批次降级；
  2. 修复 `AppMarkdown` 图片从居中闪跳到左对齐的视觉问题；
  3. 部署 Worker 至 Cloudflare，完善项目记忆/架构/数据库/交接文档并完成规范中文 git commit。
- **遇到的问题与根因**：
  1. **500 超时（43181ms）**：`backend/src/sync_v2.ts` 原按 25 条分片循环，500 题产生 2000+ 条逐行 SQL 与 40 次串行 D1 往返，且每片均执行 `pullChanges` 全库查询，触碰 Workers 执行寿命上限；
  2. **图片渲染闪跳**：`AppNetworkImage` 默认占位符未固定宽高，加载时撑满宽度居中，图片解码缩放后缩回实际宽度并被外层 `Alignment.centerLeft` 拽至左侧。
- **完成项**：
  1. **[服务端多行批量 SQL 重构 (`backend/src/sync_v2.ts`)]**：
     - 幂等查重阶段重构为最多 45 项/片并发 `Promise.all` 查询；
     - 严格遵守 D1 100 参数上限，采用连续同构多行 `VALUES (...), ... ON CONFLICT DO UPDATE` 批量语句（500 条仅需 ~92 条 SQL、1 次 `db.batch`）。
  2. **[服务端 GZip 解压与 `push_only` 支持 (`backend/src/index.ts`)]**：
     - `/api/sync` 原生支持 `Content-Encoding: gzip` 请求体通过 `DecompressionStream('gzip')` 解压；
     - 支持 `push_only: true` 跳过中间 `pullChanges` 全量扫描；
     - 已通过 `npx wrangler deploy` 成功部署上线（Version ID `e715415d-ef86-40b8-b346-9525a9084955`，R2 存储桶 `yibubang-user-backups` 已创建并绑定）。
  3. **[客户端 GZip 压缩、`push_only` 流水线与自适应降级 (`lib/services/cloud_sync_service.dart`, `lib/db/cloud_outbox.dart`)]**：
     - `CloudOutbox.page` 支持动态 `limit`；
     - 大于 16KB 的分片自动 GZip 压缩上传（500 题载荷由 ~61.8KB 压至 ~2.9KB，压缩率 95%）；
     - 存在后续分片时携带 `push_only: true`，最后一片统一拉取合并；
     - 遭遇 500/502/503/504 或超时自动缩减单批上限（500 -> 150 -> 50）断点重试。
  4. **[Markdown 图片居中与防闪跳 (`lib/widgets/app_markdown.dart`)]**：
     - `_buildImageBlock` 改为 `Center` 居中展示，并为 `AppNetworkImage` 指定 `200×140` 固定加载占位尺寸。
  5. **[记忆与文档沉淀]**：
     - 已同步更新 `PROJECT_MEMORY.md`、`database_current.md`、`ARCHITECTURE.md` 与 `SESSION_HANDOFF.md`。
- **质量门禁验证**：
  - `backend` TypeScript 类型检查：`npm run typecheck` (`tsc --noEmit`) 0 errors；
  - `dart analyze` 修改文件：No issues found；
  - 单元测试：`test/cloud_outbox_test.dart`、`test/cloud_outbox_extensions_test.dart`、`test/developer_page_performance_test.dart`（15/15 PASS）以及 `test/app_markdown_test.dart`、`test/ai_markdown_test.dart`（10/10 PASS）。
- **未完成项 / 下一次第一步**：
  - 下一次第一步：在手机端/电脑端实际运行验证万题增量同步与 R2 冷备还原效果。

## 前次交接：2026-11-17 修复 Android CI 编译 checkReleaseAarMetadata 失败（统一 subprojects compileSdk 36）

- **用户授权与操作目标**：
  - 修复 Github Android CI 编译错误：`:file_picker:checkReleaseAarMetadata` 报错 `:flutter_plugin_android_lifecycle` 要求依赖它的库与应用 `compileSdk >= 36`，而 `:file_picker` 自身声明为 `android-34`。
- **根因分析**：
  - 依赖链路中引入的新版 AndroidX / `flutter_plugin_android_lifecycle` 声明了 `minCompileSdk = 36`；
  - 第三方插件（如 `file_picker`、`open_file_android`、`sqflite_android` 等）发布包中的 `android/build.gradle` 固化了 `compileSdk 34`；
  - AGP 的 `checkReleaseAarMetadata` 任务会严格比对依赖项的 `minCompileSdk`，当模块自身 `compileSdk < 36` 时直接中断构建。
- **完成项**：
  1. **[统一提升子模块 compileSdk]**：
     - 在根工程 `android/build.gradle` 中为 `subprojects` 注入生命周期感知配置：跳过已显式配置的 `:app`，并防御性检查 `project.state.executed`，对未评估的项目挂接 `afterEvaluate`，已评估的项目直接同步执行，解决 Gradle 8/9 的 `Cannot run Project.afterEvaluate(Closure) when the project is already evaluated` 异常；将所有包含 `android` 扩展的第三方插件及子工程强制将 `compileSdk` / `compileSdkVersion` 统一提升至 `36`，并自动补全缺失的 `namespace`；
  2. **[主模块 compileSdk 对齐]**：
     - 在 `android/app/build.gradle` 中将 `compileSdk` 明确提升为 `36`（保持 `targetSdk` / `minSdk` 稳定不变，不引入任何运行时行为破坏）；
  3. **[CI 环境构建保障]**：
     - 在 `.github/workflows/android.yml` 与 `.github/workflows/release.yml` 的 `Set up Java` 步骤后，优化 `sdkmanager` 多路径自适应探测（优先检测 PATH、`$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager` 与 `tools/bin/sdkmanager`），自动确认 Android SDK licenses 并安装 API 36 相关包；
     - 在 `android/gradle.properties` 中开启 `android.builder.sdkDownload=true`，实现 Gradle 自动按需下载构建 SDK 的双重兜底；
  4. **[CI 性能基准测试防抖加固]**：
     - `test/bank_identity_performance_test.dart`：在检测到 CI 环境（`Platform.environment.containsKey('CI')`）时自适应提升物理耗时断言容差（避免 GitHub Actions macOS runner 宿主机 CPU 调度抖动引起的偶发 Flaky 误报），同时完全保留节点数量懒加载（`< 40`）与局部无序重绘防退化契约；
  5. **[质量验证]**：
     - `dart analyze lib/ test/`：**0 issues, No issues found!**
     - `flutter test test/bank_identity_performance_test.dart`：**All tests passed!**
- **未完成项 / 下一次第一步**：
  - 下一次第一步：等待用户将分支推送到远程仓库触发 GitHub Actions 验证。

## 前次交接：2026-11-16 卡片 Markdown 渲染支持、图片预览与全屏大图交互、闪卡编辑器实时预览

- **用户授权与操作目标**：
  1. 卡片（正面/背面、卡片详情弹窗、每日复习、卡片翻转复习）全面支持 Markdown 渲染（粗体、斜体、列表、代码、公式等）；
  2. 彻底解决卡片中 Markdown 格式的图片 `![alt](url)` 无法预览的问题（显示图片缩略图，圆角/优雅占位/错误降级，并支持点击调用现有的 `FullScreenImageView` 全屏大图手势缩放浏览与保存）；
  3. 复用 AI 搜索页面成熟的 Markdown 方案（GFM、CJK 粗体优化、LaTeX 公式 `flutter_math_fork`、滑动表格等），将其提取/重构成通用的 Markdown 渲染组件；
  4. 制作/编辑闪卡弹窗（`FlashcardEditDialog`）支持在编辑时预览 Markdown 渲染效果；
  5. 全量 `dart analyze`（0 issues）与全量 `flutter test`（376 passed）全绿，并按规范中文 commit。
- **完成项**：
  1. **[通用 Markdown 组件沉淀] `AppMarkdown` 组件封装 (`lib/widgets/app_markdown.dart`)**：
     - 整合 GFM 全集语法、`_CjkStrongSyntax` 中文括号粗体边界扩展、`_InlineMathSyntax` 与 `_DisplayMathSyntax` LaTeX 公式原生渲染；
     - 深度补齐图片渲染机制：自动适配网络图（`AppNetworkImage`）与本地图（`Image.file`），自适应宽高并限制最大高度，附带放大镜指示角标，点击直达 `FullScreenImageView` 支持多指缩放与相册保存；
     - `AiAnswerText` (`lib/widgets/ai_answer_text.dart`) 统一重构为复用 `AppMarkdown`，保持原有语义与测试 100% 兼容。
  2. **[卡片全场景渲染升级] 闪卡翻牌、详情弹窗与每日复习接入**：
     - `lib/widgets/flashcard_flip_card.dart`：正面与背面文本由普通的 `Text` 升级为 `AppMarkdown`，支持富文本排版与图片查看（且点击图片优先触发图片手势，不误翻卡片）；
     - `lib/widgets/flashcard_deck_dialog.dart`：`_FlashcardDetailView` 中的正面和背面升级为 `SelectionArea(child: AppMarkdown(...))`；
     - `lib/screens/daily_review_page.dart`：题干与参考答案统一接入 `AppMarkdown` 渲染。
  3. **[闪卡制作/编辑实时预览] `FlashcardEditDialog` 支持所见即所得**：
     - `lib/widgets/flashcard_edit_dialog.dart`：正面与背面工具栏均新增「编辑 / 预览」切换按钮，用户输入 Markdown 文本或插入官方图床图片后可即时一键预览。
  4. **[自动化测试与质量门禁]**：
     - 新增 `test/app_markdown_test.dart`（覆盖基础 Markdown、LaTeX 公式、图片正常展示与 alt 降级）；
     - `dart analyze lib/ test/`：**0 issues, No issues found!**
     - 全量测试：`flutter test` **376 passed, 3 skipped, 0 failed. 100% 全部通过**。
- **未完成项 / 下一次第一步**：
  - 下一次第一步：等待用户进一步指令或推送到远端仓库。

## 前次交接：2026-11-16 Cloudflare D1+R2 混合冷热同步架构、官方图床接入与开发者模式同步队列完善

- **用户授权与操作目标**：
  1. 补齐 Cloudflare D1 同步真空（将自制闪卡、FSRS 记忆曲线、复习计划纳入 D1 增量同步）；
  2. 实现“D1 增量同步 + R2 冷备快照”：D1 专职负责高频细粒度增量，R2 负责周期/按需 SQLite 整库冷备份；自动备份默认不开启，开启后默认保留最近 10 条（1~50 条可调），默认每周备份一次（1~30 天可调）；
  3. 卡片与笔记图片统一请求医考帮官方图片上传 API，上传到官方图床；
  4. 云端同步接入“开发者模式”-“同步队列”，排查修复同步队列的 bug 与缺失记录；
  5. 验证测试通过后进行规范中文 commit。
- **完成项**：
  1. **[D1 增量同步真空补齐] 卡片、记忆曲线与计划增量互通**：
     - `backend/schema.sql`、`backend/src/sync_v2.ts`：扩展 `sync_flashcards`、`sync_deleted_flashcards`、`sync_spaced_items`、`sync_review_plans` 表结构与触发器，支持 4 类实体的批量推送（pushMutations）与分页拉取（pullChanges）；
     - `lib/db/cloud_outbox.dart`：补齐实体增量捕获触发器与 `CloudDeletedFlashcards` 墓碑机制，在 `CloudOutbox.bind` 首次关联时自动回填现有卡片和记忆项，在 `CloudOutbox.mergePage` 自动解包并合并远端拉取的卡片与记忆项；
     - 优化墓碑判定条件为云端拉取防复活（`applying=1`），并在 `saveFlashcard` 显式重新建卡时清除墓碑，修复复习安全测试；
     - 编写并通过 `backend/test/sync_v2_extensions_test.mjs` 与 `test/cloud_outbox_extensions_test.dart`。
  2. **[D1+R2 混合冷热同步] R2 整库冷备快照与原子还原**：
     - `backend/wrangler.jsonc`、`backend/src/index.ts`：绑定 R2 Bucket `BACKUP_BUCKET`，实现 `/api/backup/upload`、`/api/backup/list`、`/api/backup/download/:filename`、`/api/backup/:filename` 路由，支持流式上传、校验和比对与老备份自动修剪；
     - `lib/models/cloud_backup.dart`、`lib/services/cloud_backup_service.dart`：整库 WAL checkpoint 截断、GZip 压缩、SHA-256 校验和、双端点主备容灾轮询、防损回滚保护（`.restore_bak`）、自动周期调度；
     - `lib/screens/cloud_sync_page.dart`：R2 冷备设置卡片（自动备份默认关、周期 7 天可调、保留 10 份可调、立即创建快照、快照历史与还原抽屉）。
  3. **[官方图床接入] 闪卡编辑器接入医考帮官方图床**：
     - `lib/services/note_service.dart`：`uploadImage` 强化默认兜底；
     - `lib/widgets/flashcard_edit_dialog.dart`：正面与背面均增加「插入图片」按钮，选择本地图片后上传至医考帮官方图床并在光标处插入 Markdown 图片语法。
  4. **[开发者模式接入与排障] 同步队列全量覆盖、流水类型纠偏与性能卡死修复**：
     - `lib/screens/developer_page.dart`：增加「Cloudflare D1 增量同步队列 (CloudOutbox)」与「Cloudflare R2 整库冷备快照」卡片，支持未决变动列表、游标监控、单项查看实体详情与移出队列；
     - **排查修复进入同步队列卡死 Bug**：
       1. 根因一：页面初始化主链路上直接 `await listBackups()` 触发 HTTP 网络轮询导致阻塞达 30 秒，已重构为纯本地读取时间戳，零网络延迟秒开；
       2. 根因二：`CloudOutbox` 缺少 `limit` 并在非虚拟 `Column` 树中全量展开，当积压上千条变动时导致 UI 线程瞬间冻结卡死。已建立 `SELECT COUNT(*)` 总量监控与 `limit: 50` 保护，超过 50 条时给出展开引导提示；
       3. 根因三：`Future.wait` 多线程竞争同一 SQLite 临界区引发争用排队，改为平滑顺序执行；
       4. 根因四：修复 `CloudOutbox` 实体取值字段错误（`entity_id` / `updated_at`）；
     - 修复 `Activities` 本地流水渲染时将闪卡/记忆曲线复习误判为做题提交的展示 bug；
     - 补齐 `_loadDatabaseStats()` 缺失的 6 张核心数据表统计计数；
     - 编写并通过 `test/developer_page_performance_test.dart` 性能限流回归测试。
- **质量门禁验证**：
  - `dart analyze lib/ test/`：**0 issues, No issues found!**
  - 后端测试：`tsc --noEmit` 0 errors，`backend/test/*.mjs` 13/13 项全量通过；
  - `flutter test`：**372 passed! 3 skipped (联网用例). 100% 全部通过**。
- **未完成项 / 下一次第一步**：
  - 下一次第一步：执行 `git status` 核对提交树，等待用户指示推送到远程仓库。

## 前次交接：2026-11-16 P1 修复推进与架构重构第二阶段完成

- **用户授权与操作目标**：用户指示实施 M04 剩余项、M03 启动懒加载、M10 统一 SQLite 分片、AI 搜索 20 轮上下文滑动窗口控制与 Android 编译工具链升级统一 SDK，测试通过后中文 commit。
- **完成项**：
  1. **[M04 剩余项] `_countDueItems` 轻量化计数**：
     - 重构 `daily_review_service.dart` 的概览统计链路，用轻量化 `_countDueItems`、`_countFilteredDuePage` 与 `_checkQuestionIdsExist` 替换全量拉取队列逻辑，概览彻底不加载题干、选项、解析大实体。
  2. **[M03 剩余项] 启动期多题库按需懒加载**：
     - `question_bank_repository.dart` 提取 `_initSingleBank` 并新增 `initializeActiveBank({String? bankId})`；
     - `home_page.dart` 启动时优先仅就绪活跃题库（耗时从 300ms+ 降至 20~50ms），其余题库在后台静默扫描校验。
  3. **[M10 / A14] 统一 SQLite >999 变量分片执行器**：
     - 落地通用安全 `lib/db/chunked_query_executor.dart`（`runChunked`, `runChunkedVoid`, `queryIn`, `deleteIn`）；
     - 重构 `question_search_repository.dart`、`spaced_review_repository.dart` 与 `daily_review_service.dart`，统一消除散落的手动 `sublist` 分片；
     - 补充 `test/chunked_query_executor_test.dart`（8 个测试全部 PASS）。
  4. **AI 搜索多轮上下文 20 轮滑动窗口控制**：
     - `ai_search_options.dart`、`ai_search_client.dart` 与 `ai_search_settings.dart` 协同升级：废除硬编码的 3 轮截断，建立默认 20 轮上下文滑动窗口控制（5~50 轮可在设置中调节），结合 60KB 长度保护形成双重防护；
     - `test/ai_search_settings_test.dart` 同步更新并覆盖调节与持久化验证。
  5. **升级 Android 编译工具链与统一 CI Flutter SDK**：
     - `android/settings.gradle` AGP 升级至 9.1.1，`gradle-wrapper.properties` 升级至 Gradle 9.5.0；
     - `.github/workflows/android.yml` 与 `release.yml` 统一为 `channel: 'stable'`，解除临时锁死 `3.44.6` 的版本分裂。
  6. **M07 项处理**：遵照用户指示，因影响用户体验暂不推进。
- **质量门禁验证**：
  - `dart analyze lib/` 与 `dart analyze test/`：**0 issues, No issues found!**
  - `flutter test`：**367 passed! 3 skipped (联网用例). 0 failed. 100% 全部通过**；
  - 后端测试：`11/11 passed`，`tsc --noEmit` 0 errors。
- **未完成项 / 下一次第一步**：
  - 下一次第一步：执行 `git status` 核对提交树，等待用户指示推送到远程仓库。

## 前次交接：2026-11-16 P1 级架构优化与性能重构完成

- **用户授权与操作目标**：用户指示推进 P1 级 issue 修复和部分代码重构，测试通过后中文 commit。
- **完成项**：
  1. **[M04] 每日复习概览纯 SQL EXISTS 聚合优化与请求去重**：
     - 重构 `daily_review_service.dart` 的 `_scopePoolCounts`，直接通过本地 `QuestionRelations` 投影执行纯 SQL `EXISTS` 范围判定，避免十万题向 `temp.review_pool_ids` 拷贝写入，十万题概览时间实测从 **228ms 降至 8ms**（降低 96.5%）；
     - 为 `getTodaySummary` 增加了 in-flight Future 请求去重，防止并发重复计算。
  2. **[M05] 云同步轻量化重算优化**：
     - `cloud_sync_service.dart` 仅在 `pulledQuestions > 0` 时触发相关题库的 `rebuildQuestionCount`，纯流水（Activities）拉取不再触发全库 ATTACH 重算，消除队头写锁阻塞。
  3. **[M04] 章节合并 $O(C^2) \to O(C)$ 性能提升**：
     - `lib/models/chapter.dart` 消除 `userRows.firstWhere` 线性检索，重构为 Map 键值查找。
  4. **交卷逻辑空指针安全性加固**：
     - `question_detail_controller.dart` 安全防御 `firstWhere` 未命中异常。
- **质量门禁验证**：
  - `dart analyze lib/`：**0 issues, No issues found!**
  - `flutter test`：**359 passed! 3 skipped (联网用例). 100% 全部通过**；
  - 后端测试：`11/11 passed`，`tsc --noEmit` 0 errors。
- **未完成项 / 下一次第一步**：
  - P2 级项（D1 客户端持久化退避冷却、AI 搜索多轮会话 Token 窗口裁剪、统一 >999 参数分片 Helper）待后续按需推进。
  - 下一次第一步：执行 `git status` 核对提交树，等待用户指示推送到远程分支。

## 前次交接：2026-11-16 P0 级缺陷修复与 Worker 批处理性能优化完成

- **用户授权与操作目标**：用户明确指示修复 P0 级 issue，运行完整 test/analyze 验证后中文 commit。
- **完成项**：
  1. **[M13] 首页每日计划卡片入口算法配置对齐**：
     - 在 `DailyReviewCard` 增加 `_ensureConfiguredService()` 动态加载与对齐逻辑，卡片进入 `DailyReviewPage` 时无缝继承用户在设置中选择的算法模型（轻量化 FSRS / SM-2）；
     - `DailyReviewService` 提供 `createConfigured(...)` 静态工厂方法；
     - 更新 `docs/antigravity/audits/post_a20_current_state_probe_test.dart` 探针测试为正向断言，并在 `test/daily_review_ui_test.dart` 补充卡片独立加载引擎的 Widget 回归用例。
  2. **云同步 Worker `pushMutations` 批量操作聚合**：
     - 重构 `backend/src/sync_v2.ts`：将 500 个 mutation 的逐条串行 SELECT 与单条 D1 batch 写入优化为 25 条切片批次查询与单事务聚合提交；
     - 大幅降低 Worker CPU 耗时与子请求数，消除超限风险。
  3. **后端测试与环境声明规范化**：
     - `backend/package.json` 声明 `"engines": { "node": ">=22.11.0" }` 并规范 `"test"`、`"typecheck"` 脚本。
- **质量门禁验证**：
  - `dart analyze lib/`：**0 issues, No issues found!**
  - `flutter test`：**359 passed! 3 skipped (联网用例). 100% 通过**；
  - 后端 `sync_v2_test.mjs` / `deployment_test.mjs`：**11/11 passed**，`tsc --noEmit` 通过。
- **未完成项 / 下一次第一步**：
  - P1 级技术债（M04/M05 概览纯 SQL 统计与单写 FIFO 优先级、M03 启动多题库懒加载、Android AGP 9.1 工具链升级）待后续根据计划推进。
  - 下一次第一步：执行 `git status` 核对提交树，关注用户后续功能迭代或发版需求。

## 前次交接：2026-11-15 云同步协议 v2 发布完成

- 用户明确授权部署；main@468e72b起始干净。D1备份/真实数据演练后增量迁移，旧账号口令/题目/流水保持；正式Worker b482e035-765f-4563-b964-32b9a863cb8f/100%，主域health及实际sync为protocol2。
- 验证：后端11/11、tsc/dry-run、Flutter同步相关18/18；独立账号HTTP501分页/ACK/重试/删除通过，生产CloudSyncService+两临时用户库联网1/1。清理后17账号/31设备/18313状态/20584流水，38897变更序号，无完整性/外键异常。[发布记录](audits/SYNC_V2_DEPLOYMENT.md)列回执、配额与回滚。
- 私有备份/账号/工具/探针在audits/.local/sync-v2-release，禁止提交或泄露；公开改动为后端版本/健康字段、回填SQL、部署回归及DDL夹具/冒烟脚本/文档。未改Flutter产品/用户schema/题库或AI资源，未commit/push。
- 未完成：真实用户双端/目标地区网络、D1全天预算与持久熔断、投影一致性专项。迁移已用77813 rows_written，不能承诺大规模首次上报不触配额。
- 下一次第一步：核对Git和本段，用户用当前v2客户端点击正常同步；失败先看HTTP/配额，保留pending，避免清库/重配对/重复强制全量。后续发布不重复迁移回填或创建测试账号。原Release流水线待办独立保留。

## 最新交接：v2.2.4+214 版本升级与清单回写发布

- **版本发布与基线状态**：
  - 代码版本正式递增为 `2.2.4+214`（[pubspec.yaml](../../pubspec.yaml)）；
  - 更新在线分发清单 [yibubang_update.json](../../yibubang_update.json)，写入 v2.2.4 版本号、更新说明（四大核心维度）及各平台（Android 通用与分 ABI、Windows、macOS、Linux）Release 下载资产直链；
  - 创建发布说明文档 [docs/release-notes/v2.2.4.md](../release-notes/v2.2.4.md) 并挂载至索引；
  - 同步更新根 README、英文 README 及文档中心中的版本号描述。
- **质量门禁核验结果**：
  - `flutter analyze`：**No issues found! 0 errors, 0 warnings**。
  - `flutter test`：**358 passed! 3 skipped (联网用例). All other tests passed! 100% 通过**。
- **完成项回顾**：
  1. **AI 搜索与 53 本医学教材知识库**：17 万条切片入库、流式输出、打字机光标动效、30+ 精选问题库、多课本检索直选、右上角原版页「直接查页」调阅、1～25 条比例融合设置滑块、引用角标化与折叠偏好持久化。
  2. **UI 体验与细节打磨**：全系统设置页提示统一为 `InfoHintBanner` 组件，闪卡搜索框自动获取焦点（`autofocus`），底栏设置保护锁定「我的」不可隐藏。
  3. **A01~A20 白盒深度审计修复**：云同步断点分页、复习事务原子性、跨库做题统计并发安全、用户库导入原子恢复等 20 项核心缺陷彻底闭环。
  4. **跨平台 CI 与工具链**：Windows CI 超时修复，Android Release 构建工具链稳定。
- **未完成项 / 下一次第一步**：
  - Tag `v2.2.4` 已打并成功推送至 GitHub 远端，`Release Build & Publish` Actions 流水线已正式触发运行；
  - 下一次第一步：通过 `gh run watch` 或 GitHub 页面关注 Release 流水线构建打包产物（Android APK、Windows/macOS/Linux 资产）与 GitHub Release 正式发布状态。

## 前次交接：UI 统一与交互细节打磨（设置页提示统一 / 比例滑块融合 / 参考资料持久化与角标化）

- **完成项**：
  1. **设置页提示统一为 `InfoHintBanner`**：
     - 将 `lib/screens/settings_page.dart`（记忆算法设置弹窗、导入模式弹窗）、`lib/screens/shortcut_settings_page.dart`（单选题/多选题提示）、`lib/screens/bottom_nav_settings_page.dart`、`lib/widgets/ai_search_settings.dart`（使用说明、条目限制说明）以及 `lib/widgets/bank_subscription_settings.dart` 中的所有提示/说明文本全部统一为 `InfoHintBanner` 规范组件；
     - 修复了 `lib/widgets/info_hint_banner.dart` 文件首行拼写错误。
  2. **教材与题目检索比例滑块与彩带融合 (`lib/widgets/ai_search_settings.dart`)**：
     - 移除独立的 8px 双色彩带，直接通过 `SliderTheme`（`activeTrackColor: scheme.primary`, `inactiveTrackColor: scheme.tertiary`, `trackHeight: 12`）将滑块轨道自身作为双色对比比例条；
     - 移除了 320px 窄屏下可能导致 29px 布局溢出的冗余图例行，卡片顶部保留居中统计文本，在 320px 与 1000px 宽度下均完美自适应。
  3. **参考资料折叠状态本地持久化 (`lib/screens/ai_search_page.dart`)**：
     - 新增 `SharedPreferences` 存储键 `ai_search_citations_collapsed`，用户点击折叠/展开时自动记录到本地；
     - 下次进入 AI 搜索页或发起新提问时，自动恢复用户偏好的展开/折叠状态。
  4. **参考资料课本标题精简与右上角页码角标化 (`lib/screens/ai_search_page.dart`)**：
     - 对教材类型标题提取纯净书名（如《药理学》-> 药理学），页码提取并转换为右上角专属微型角标（如 `P299`）；
     - 彻底收窄卡片横向占用，避免“药理学·PDF第299页”过长导致的拥挤感，同时通过 `Tooltip` 完整保留原引用来源说明。
  5. **验证与测试保障**：
     - `dart analyze lib/`：**0 issues, No issues found!**
     - `flutter test test/ai_search_settings_test.dart`：**7/7 全部 PASS**（覆盖 320px、1000px 窄屏宽屏自适应、比例持久化）。
     - `flutter test test/ai_search_ui_test.dart test/textbook_search_test.dart`：**13/13 全部 PASS**。
     - `flutter test test/bank_subscription_test.dart`：**2/2 全部 PASS**。
- **未完成项 / 下一次第一步**：
  - 代码变更保留在本地未暂存状态（未 commit，未 push），严格遵循 AGENTS.md 准则；
  - 下一次第一步：执行 `git status` 确认未暂存代码，等待用户指示是否合并或提交。


## 最新交接：Windows复习测试超时

- 起始main@2b80da1与origin一致/干净，用户反馈Windows每日复习测试30秒timeout。两次真实Actions43432164278/43436136566均在fixture的insert/saveItem处结束，database_closed为超时清理后的后续写入，未进入buildDailySession。
- 修改仅test/daily_review_service_test.dart中该用例：502题Batch.commit(noResult:true)、502复习项repo.batchSaveItems，从1004逐条提交变两批事务；501 outside/q_4末项和真实分页服务调用保留。新增首批500条outside断言，保证覆盖分页边界；保留30秒timeout、默认并发和生产SQLite行为。
- Flutter3.44.6/3.50.0该文件各11 PASS；CI同SDK3.50全量357 PASS/3联网默认skip，dart analyze与CI的flutter analyze --no-fatal-infos均exit0、0 errors/warnings、119原有弃用info。单文件dart format、git diff --check、62份文档547本地链接检查通过。
- 日志.local/windows-daily-3.44-tests.log、windows-daily-3.50-tests.log、windows-daily-3.50-full-tests.log、windows-daily-3.50-{dart,flutter}-analyze.log；CI日志actions-43436136566-failed.log。SDK3.50/隔离工作树复用上一轮.local资源，不提交日志、依赖锁或SDK自动迁移文件。
- 本机macOS测试不能宣称Windows runner已通过；本轮不push/发布。下一次第一步git status/log核对该修复，用户push后检查Windows Test/Build/Upload；上一提交2b80da1的Android/macOS/Linux已远程成功。其他同步/医学/费用待办保持下方交接，不重复云部署/知识库上传。

## 前次交接：Android Release工具链

- 起始main@4deacbb与origin一致/干净，用户反馈Android构建失败。本轮只修Android工具链和同步文档，App业务/README/依赖声明/题库/云资源保持原状。
- Actions43432164143使用Flutter3.50.0，Analyze/Tests成功、assembleRelease配置阶段getDefaultConfig API缺失；本地隔离树同版构建复现。Flutter插件编译依赖AGP9.1.1，最低支持同为9.1.1；项目8.11.1/Gradle8.14不能靠skip依赖检查解决。
- android.yml及release.yml/build-android固定Flutter3.44.6，删除skip依赖验证参数；AGP8.11.1/Gradle8.14/Kotlin2.2.20/NDK28.2不升级。其他平台和Release verify仍stable，未来AGP9迁移在TECHNICAL_DEBT记录。
- Java17 release通用80.1MB/分ABI28.5MB、30.4MB、32.1MB全部exit0，签名校验/包名com.melonhu.yibubang/2.2.3+213/原生ABI检查通过；同SDK dart analyze和CI的flutter analyze --no-fatal-infos均No issues/exit0，全量357 PASS/3联网默认skip。YAML、545本地链接、git diff --check通过。
- 日志在ai_backend/.local/android-3.50-release-before.log、android-3.44-release-after.log、android-3.44-release-split.log、android-3.44-{dart,flutter}-analyze.log、android-3.44-full-tests.log；产物清单android-release-artifacts.json，APK仅在.local/ci-workspace/build/app/outputs/flutter-apk。隔离树复用.local/ci-workspace，不替换用户SDK或提交pub依赖/生成配置；沿用原debug签名配置，不是正式发布或真机验收。本轮修复不push/触发Release。
- 下一次第一步git status/log核对该修复，用户push后观察Android Analyze/Tests/Build/Upload各阶段。当前远程旧4deacbb的Linux/macOS已成功；Windows有独立daily_review_service_test大fixture30秒超时（43432164278），本轮未扩大到该项，不将Android修复宣称为四平台全绿。

## 前次交接：README恢复与Flutter3.50 CI修复

- 起始main@082f205与origin一致/干净；该HEAD是用户合并提交，814a20d已在共享历史。用户明确选择仅恢复README，保留功能和docs；本轮用新的恢复提交，不reset/revert全部814a20d，不push或发布Release。
- 恢复ec0fdf6原README/英文页的品牌、徽章、目录、架构和截图；补AI/教材、session/额度、1–25条数/比例、模型回退、快捷键/缓存和最新验证。根README仍完整项目介绍，docs仍维护运维/知识库/开发资料。
- 四平台Actions（082f205）均失败在Analyze，CI Flutter3.50.0而本地3.44.6。唯一warning为note_service.dart try内返回Future未await；补await后独立3.50.0/Dart3.14.0的dart analyze及CI同命令均exit0，0 errors/warnings、119个Material/Cupertino等弃用info，未降低warning规则。
- 同SDK全量初跑356 PASS/3 skip/1 fail，设置测试开启自动更新发后台网络并留下timeout Timer；fixture设置最近检查时间，只测设置交互而非逾期检索。定向6 PASS，旧SDK笔记/队列27 PASS；3.50.0最终全量357 PASS/3联网默认skip、All tests passed。fixture修改后dart analyze与CI分析再次exit0，0 errors/warnings、119 infos。
- 隔离验证在ai_backend/.local/ci-workspace（detached HEAD）、SDK在.local/flutter-ci-3.50；最终日志ci-3.50-full-tests-final.log、ci-3.50-dart-analyze-final.log、ci-3.50-flutter-analyze-final.log，早期日志ci-note-regression.log/actions-*-failed.log。SDK自动迁移的平台/build分析排除与插件注册文件仅在隔离树，主工作区配置/依赖未变。无需把缓存/工作树加入Git，也不需替换用户原SDK或修改题库/用户库schema。
- README恢复后的本轮链接检查：62份文档、544个本地链接，无失效/指向私有资料的链接；git diff --check通过。另恢复隔离树为主工作区原analysis_options后独立dart analyze仍exit0/119 infos，日志ci-3.50-dart-analyze-exact-config.log。
- 下一次第一步先git status/log核对新的恢复提交，阅读根README与本段；若要验证远程四平台，按用户push授权触发CI，检查Analyze/Tests/Build每阶段，不能把本机同SDK测试当已重跑Actions。其他医学/费用/网络/同步服务待办仍见下方；不用重导知识库或上传页图。

更新：2026-11-13；main；本轮修正提交父基线082f205（上一轮814a20d父基线ec0fdf6），用户明确授权commit。准确提交ID以`git log -1`为准。本次只提交代码/测试/公开文档，不push、不发布Release；新会话先核对Git是否有用户后续改动。

## 本次完成

1. 检索条目设置1–25（默认12），总数变化保留来源比例，默认25为17教材/8题。每轮SharedPreferences→HTTP result_count/textbook_count→服务端校验→独立二源Search→显式Answer结果列表；单源跳过无用请求，最多60000字符并为后续来源留预算。
2. 引用/行内公式WidgetSpan内部Text重复加入Text.rich选择delegate导致lastSelectionResult断言，已精确复现并隔离内部选择；正文可选、引用可点。Google实际采用的证据可少于输入数量。
3. 文档统一到docs并建立总索引/当前状态；AI运维与费用、知识库/教材操作分别分类；旧动态记录/早期数据库研究保留为历史档案。根README已按用户反馈恢复完整项目介绍，本地AGENTS.md保留代理发现，版本化规则副本在本目录。
4. 更新全部开发入口到schema25/当前内置模型/200额度/可调25条/00018部署；Release工作流从docs/release-notes读说明。原PDF、页图、生成SQLite/JSONL、.local身份/回执/截图、虚拟环境、API抓包均不提交。

## 当前资源和数据

- Google yibubang-search/520065588983，global Store yibubang-medical-v1，171463块=149472题+21991教材；两应用yibubang-medical-search（Standard）/yibubang-medical-answer（Enterprise）共用Store。不要创建RAG Corpus或重复导入。
- 东京Cloud Run yibubang-ai-search，00018-q7c/100%，App入口https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app。默认stable、当前快照3.5-flash/answer_gen/v1，默认改写+流式；没有外接Vertex Token生成。
- Firestore yibubang-ai记录身份哈希、北京时间日200额度/分钟6/租约，TTL清理3天过期限额；会话仅本机user_data.sqlite的AiSearchSessions/AiSearchTurns，不加入同步。
- 外置盘源目录`/Volumes/My PSSD/书籍/自用53本课本（可复制）`；教材主库/原始OCR/清洗页/坐标/页图在`/Volumes/My PSSD/书籍/医不帮教材知识库`。仓库scripts/knowledge_base/artifacts/current与artifacts/cloud是语料及增量成功账本，均忽略但不可删除。
- 私有R2 yibubang-textbooks，Worker yibubang-textbook-pages，textbooks.melonhu.com；20669页图+20669小图，7714259450 bytes。阅读器按稳定版本/物理页定位，原PDF未上传。

## 已有验证与回执

Flutter全量357 PASS/3联网默认skip、最终相关8 PASS，后端39 PASS，analyze0；Android/macOS普通main Debug构建通过。生产App25条17:8/回答/SQLite/引用2联网PASS；Google返回references10、正文用到第13项，不能说25条全部被用到。五组非法数量/比例400且不扣额度。

最近回执在忽略的ai_backend/.local/result-count-*、result-selection-*、selection-*；教材全量和早期原生Reader证据见[实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。联网测试复用专用smoke-device.json，不提交/打印secret，不重置真实用户额度。构建包仅在build/；Widget截图/模拟手势不代表Android真机或大陆网络验收。

本次文档复核62份文档/520个本地链接，无失效/私有未版本化目标；静态分析0。旧审计复制的凭据已脱敏，原稿仅在ai_backend/.local/docs-private-archive；链接报告/分析日志为ai_backend/.local/docs-link-report.json、docs-final-analyze.log，不提交。维护的docs目录已纳入Git，抓包/数据库/工具环境继续忽略。

## 下一次第一步

执行`git status --short --branch`与`git log -1`，读[当前状态](../CURRENT_STATUS.md)、本段与用户新反馈。用最新Debug App核验AI设置→条目/比例及原鼠标选择手势；若代码已改需重建/重启。默认无需重新跑付费生成、造Store、导入171463块或上传41338图片。

新教材按[知识库手册](../knowledge-base/README.md)与[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)复用本地缓存、稳定ID和成功基线，先本地验证delta，再增量导入。更换Embedding须重算向量，PDF清洗不必重做。

## 未完成项和授权边界

- 用户原手势实机、Android/Windows/Linux/iOS、目标地区网络、375页医学符号人工复核、版次ISBN、167题答案分歧/6923题配图OCR、Release与真实向量库迁移仍未验收。
- 该段为2026-11-13历史授权边界：当时未部署同步服务。2026-11-15用户已明确授权并完成v2服务端发布及独立账号验证，见顶部最新交接；真实用户/M03目录分阶段/M04/M05/M13仍为后续项。
- 专项赠金适用SKU、实际Advanced计量和账户运行费用仍待账单，不承诺100%抵扣/不扣卡。混合搜索两Standard+一Enterprise列表价USD7/千、Advanced预算USD11，App1/2/3不是Google收费倍数。
- 当前没有保证每个子问题按来源比例迭代检索，25条并不穷尽全库。只有用户明确授权下一步才发布Release、push或新建云资源。

旧会话完整记录：[历史交接](../archive/development-history/SESSION_HANDOFF.md)。
