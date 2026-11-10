# FEATURE_MATRIX.md - 医不帮功能实现与验证状态矩阵

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A10 / 已修复**。复习流水统一毫秒并补权威题库/课程/章节来源，复习作答进入总统计与明细，自评与斩卡不计答题；评分/斩题事件持久化、按当日首次新学属性去重，Again/Good/Cram不重分类。用户库v21，旧三类复习秒记录定向幂等转换，云拉取同样规范化。新增3项事件/单位/历史回归，相关35/35、analyze 0 issues；commit：修复 A10 复习流水单位与每日事件统计。升级前无事件的学习分类仍保留原估算，ReviewEvents目前为本地日志。下一步A11斩题与删除后的旧会话保护。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v21；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：按照清单继续尚未完成问题，补充对应正确性回归；历史缺陷探针不再用于判定修复通过。保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
<!-- /A01_A20_REPAIR_STATUS -->


> **题库专项更新**：2026-11-07，Commit efc2e55（Bot 清单回写；v2.2.2 tag 为 bd6a7a0），分析 0 issues、135/135 测试；第 1 节为当前状态，后续原审计与切片按历史基线保留。  
> **状态定义规范**：
> - `NOT_STARTED`：未开始开发。
> - `IN_PROGRESS`：开发中，存在半成品。
> - `IMPLEMENTED`：代码已实现，但尚未经过完整运行时与自动化测试。
> - `TESTED`：已有自动化测试（单元/部件）覆盖。
> - `VERIFIED`：经过实际代码审计并证实调用链完整闭环。
> - `PARTIAL`：部分实现，存在已知截断或未闭环环节。
> - `BROKEN`：功能存在严重逻辑阻塞或运行时必现缺陷。
> - `UNKNOWN`：现有证据不足，无法确认状态。

---

## 1. 题库核心管理体系

| 功能 | 状态 | 当前源码入口 | 验证与边界 |
| --- | --- | --- | --- |
| 多题库只读/全局共享题目状态 | VERIFIED / TESTED | lib/db/question_bank_manager.dart openBank；lib/repositories/question_bank_repository.dart importFile | 正式库 readOnly，用户库独立，ATTACH 聚合；真实安装/全局答案共享回归 |
| 元数据/完整性校验与原子安装 | TESTED | QuestionBankRepository.validatePath / importFile | 暂存校验、安装互斥、文件/登记/履历/基线/统计回滚；显式完整性检查零网络 |
| Material 管理/详情/来源 | TESTED | QuestionBankPage._bankCard；BankDetailPage；BankSubscriptionsPage | 标题同行强调色当前使用/紧凑状态 tag、详情右侧学科号/文件大小/三项统计、点击卡片进详情、原位进度与相邻动作；390px/1000px 部件与截图复核，用户视觉待验收 |
| 来源配置/去重/主候选来源 | TESTED | BankSubscriptionService.addSource / editSource / proposeBankSource / selectSource | 保存零网络，候选不抢占主来源，新地址待验证，失败隔离、删除归档、学科保护 |
| 轻量检查更新 | TESTED | BankSubscriptionService.check；BankSubscriptionLoader.check | 全局入口在订阅页，单库入口在管理卡片；同流程、不安装；JSON/HEAD/304/无验证器需下载确认 |
| 受控下载/缓存/链接导入 | TESTED | BankArtifactCache.acquire；BankSubscriptionService.importLink / install | 持久化 256 MiB LRU、摘要复核、lease、取消/半包清理、任务内单次下载；无持久化下载断点协议 |
| 上游版本与本地补充 | TESTED | BankContentState；BankUpdateInfo.compare；QuestionBankFileService.diff | v13 迁移；同发布不再合并、同版本变更/回退显式确认、ATTACH 差异、基线事务回滚 |
| 自动检查/安装设置与后台状态 | TESTED | BankSubscriptionSettings；BankSubscriptionService.checkAutomatically | 默认仅检查、安装双开关、可调 1～10080 分钟，仅安全版本自动安装，当前页面即时刷新；应用关闭不运行 |
| 同库导入合并/覆盖 | TESTED | QuestionBankRepository.importFile；QuestionBankFileService.merge | 保留本地独有题/关系，同 ID 采用新包，用户答案不变；RISK-01 ZIP 整包内存仍暂缓 |
| 删除本地题库 | TESTED | QuestionBankRepository.deleteBank；BankSubscriptionService.deleteBank；BankDetailPage | 路径保护/互斥/关闭连接/事务失败还原；保留个人数据与选课，来源和内置库可重新下载 |
| 创建页大目录选择性能 | TESTED | BankIdentitySelection；BankIdentityTree；BankCreationPage | 可见行懒加载、子树/祖先局部通知、开始按钮独立更新；4,380 节点父/叶/滚动后勾选 105/23/14ms，父子全选/半选与去重保持；本机 debug 部件数据 |
| 创建题库与版本递增 | TESTED | BankCreationPage；BankCreationService；YkbBankSmartSyncService | 父子全选/半选/数字小标签，创建前风险与会员确认；深层学科/共享题、忽略/忽略全部/终止、报告与取消；真实账号待验收 |
| 官方全量重建/DES 解密 | TESTED | YkbBankSyncService.syncBank → BankCreationService.build | 暂存完整构建、失败保留、选课迁移、版本递增；真实账号全科待验收 |
| API 智能同步 | PARTIAL | YkbBankSmartSyncService.run | 旧章节算法保持；完整树分支全快照检查再合并，无深层持久化章节断点 |
| 创建/同步/下载进度 | TESTED | BankProgressView；CourseSyncActions；BankDownloadTask / BankActionButton / BankActionProgress | 按钮原位无文字圆环，阶段/章数/题数保留；字节进度与取消，原子安装禁取消；R2 下载/导入/304 已实测 |
| 详情覆盖课程与时间轴 | TESTED | BankDetailPage._identity / _history；用户库 BankHistory | 空学科隐藏、DISTINCT 题量、真实新增题数；旧历史不补造，不随内容包导出 |
| SQLite/ZIP 全量导出 | TESTED | BankExportService；BankExportButton | 副本账号值清理、源文件不变、旧多学科导出、ZIP 往返、防覆盖/别名；原生文件选择器待实机验收 |
| 制作规范与现有机制汇报 | VERIFIED（文档） | docs/antigravity/QUESTION_BANK_SPEC.md v1.1 | schema v1、原始 ID、manifest、只读/ATTACH、本地 Python 对照；private 远端未访问 |
| 旧单体库回退/题库切换 | VERIFIED / TESTED | DatabaseHelper._initDB；QuestionBankRepository.selectBank / setEnabled | 既有逻辑保持，管理导航回归 |

统一管理方案最终调用链和逐条测试证据见 [QUESTION_BANK_MANAGEMENT_DESIGN.md](QUESTION_BANK_MANAGEMENT_DESIGN.md) 第 9 节。下列第 2～6 节是历史审计，缺陷状态请以 DEVELOPMENT_STATUS / KNOWN_ISSUES 当前状态为准。

---

## 2. 刷题与答题业务体系

| 功能名称 | 状态 | 实现代码位置 | 核心依赖 | 测试覆盖情况 | 未完成事项 / 关联问题 |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **题目详情页跨章节顺滑切章（Issue #22）** | **VERIFIED** | `question_detail_page.dart:185`, `chapter_cross_indicator.dart` | `Listener`, `BouncingScrollPhysics`, `HapticFeedback` | `test/cross_chapter_navigation_test.dart` (14项测试通过) | 首末题持续滑动蓄能、纯图标双箭头跳变、macOS 触控板释放适配 |
| **章节九宫格页上下滑跨章节切换（Issue #22）** | **VERIFIED** | `question_grid_page.dart:110`, `chapter_cross_indicator.dart` | `ChapterCrossIndicator(axis: vertical)`, `ScrollNotification` | `test/cross_chapter_navigation_test.dart` (14项测试通过) | 顶部下拉上一章、底部上拉下一章、全约束防塌陷、双向路由同步 |
| **全局刷题快捷键绑定系统** | **VERIFIED** | `shortcut_config.dart`, `shortcut_settings_page.dart` | `HardwareKeyboard`, `LogicalKeyboardKey` | `test/shortcut_config_test.dart` (6项测试通过) | 支持单键/组合键、冲突迁移与滚动步长配置 |
| **刷题页键盘切题与防误触** | **VERIFIED** | `question_detail_page.dart:130` | `FocusNode`, `ModalRoute` | `test/question_shortcuts_test.dart` (4项测试通过) | 覆盖路由/输入框焦点自动退避 |
| **题目网格筛选原始题号映射** | **VERIFIED** | `question_grid_page.dart:129, 636` | `_chapterQuestionNumbers` | 单元回归证实 | 筛选后保留章节原始题号 |
| **Windows Win32 原生 F11 全屏** | **VERIFIED** | `flutter_window.cpp:68`, `app_fullscreen_shortcut.dart` | `MethodChannel`, Win32 API | `test/course_actions_fullscreen_test.dart` 通过 | 退出全屏精确恢复原窗口大小坐标；移动端沉浸 |
| **单选题作答与即时判分** | **VERIFIED** | `question_options_view.dart:121` | `QuestionDetailController` | 单元测试 & UI 交互证实 | 无 |
| **多选题作答与提交** | **VERIFIED** | `question_options_view.dart:142` | `QuestionDetailController` | UI 交互证实 | 无 |
| **快刷模式（答对切题）**| **VERIFIED** | `question_detail_controller.dart:212`| `PageController` | 控制器逻辑证实 | 无 |
| **测试模式（模拟考试）**| **VERIFIED** | `question_test_bar.dart:25`, `question_grid_page.dart:211`| `UserQuestion.status=4` | 交卷与批量判分逻辑证实 | 无 |
| **背题模式（直显答案）**| **VERIFIED** | `question_options_view.dart:54` | `QuestionDetailController` | 只读高亮逻辑证实 | 无 |
| **主观非选择题（题型3~7）**| **BROKEN** | `question_options_view.dart:170` | 暂无主观题渲染器 | 审计证实界面显示“未知题型” | **BUG-05**：护理近万道主观题死锁，提交直接判错 |
| **题目斩题与内容遮罩** | **VERIFIED** | `question_page_item.dart:88` | `UserQuestion.isCut` | `test/question_cut_test.dart` 自动化测试通过 | 斩题遮罩、一键放回题库 |
| **题目收藏与取消** | **VERIFIED** | `question_detail_controller.dart:219`| `UserQuestion.collection` | 跨库读写证实 | 无 |
| **全部重做 / 重做错题** | **VERIFIED** | `question_grid_page.dart:257-390` | `updateQuestion`, `Activities`| 状态重置与流水追加证实 | 循环等待存在批处理优化空间 |
| **四维条件过滤筛选** | **PARTIAL** | `question_grid_page.dart:128-140` | `cutType`, `mode`, 等 | 内存过滤逻辑证实 | **BUG-01**：筛选持久化保存时序倒置，重启失效 |
| **自动恢复上次做题进度** | **PARTIAL** | `choosed_subjects_page.dart:75-178`| `SharedPreferences` | 跳转调用链证实 | 存在 `containsKey` 保护过度风险 |

---

## 3. 数据同步与备份系统

| 功能名称 | 状态 | 实现代码位置 | 核心依赖 | 测试覆盖情况 | 未完成事项 / 关联问题 |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **本地记录导出 ZIP** | **VERIFIED** | `record_sync_service.dart:31` | `archive`, `file_picker` | 平台分流导出代码证实 | 无 |
| **本地记录导入（替换）**| **VERIFIED** | `record_sync_service.dart:84` | WAL 清理, `UserDBHelper` | 物理覆盖与升级代码证实 | 无 |
| **本地记录导入（合并）**| **PARTIAL** | `record_sync_service.dart:104` | LWW 题目合并, 流水追加 | 内存合并逻辑证实 | **BUG-04**：导入后未触发 `rebuildQuestionCount()` |
| **Cloudflare D1 增量同步**| **VERIFIED** | `cloud_sync_service.dart:350-520`| `Hono`, D1, LWW SQL | `test/cloud_sync_service_test.dart` 模型测试 | 包含配对码互联、自动容灾双端点 |
| **医考帮斩题离线同步** | **VERIFIED** | `ykb_sync_service.dart:204` | `YkbSyncQueue` | 队列入队与重试证实 | 无 |
| **医考帮作答流水同步** | **VERIFIED** | `ykb_sync_service.dart:278` | `YkbSyncQueue` | 队列消费证实 | 无 |
| **医考帮章节重做同步** | **VERIFIED** | `ykb_sync_service.dart:400` | `YkbSyncQueue` | 队列消费证实 | 无 |
| **医考帮做题记录按叶子拉取合并**| **VERIFIED** | `ykb_pull_service.dart:55`, `course_sync_actions.dart` | `basicReq`, `rebuildQuestionCount` | `test/course_actions_fullscreen_test.dart` 测试 | 本地已作答优先保留；支持跳过原因明细统计 |
| **CI 多端自动化门禁系统** | **VERIFIED** | `.github/workflows/release.yml`, `*.yml` | GitHub Actions | 40/40 项测试与 analyze 门禁覆盖 | 彻底阻断破坏性构建带病发布 |

---

## 4. 社交互动与用户系统

| 功能名称 | 状态 | 实现代码位置 | 核心依赖 | 测试覆盖情况 | 未完成事项 / 关联问题 |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **账号密码登录** | **VERIFIED** | `lib/common/request.dart:93` | DES 加密, MD5 签名 | 凭据持久化证实 | 无 |
| **账号状态自检守护** | **VERIFIED** | `lib/services/auth_service.dart:39` | `getUserInfo`, 309 拦截 | 启动守护逻辑证实 | 弹窗防抖 15 秒 |
| **官方评论区浏览** | **PARTIAL** | `screens/comment_page.dart:77` | 医考帮官方接口 | 分页流式加载证实 | **RISK-02**：309 整型比对与 null 转换异常隐患 |
| **评论点赞** | **VERIFIED** | `screens/comment_page.dart:200` | `/Comment/Main/praise` | 接口调用链证实 | 无 |
| **本地富文本多图笔记** | **VERIFIED** | `lib/services/note_service.dart:61` | `file_picker`, 应用沙盒目录 | 增删改查逻辑证实 | 图片沙盒持久拷贝 |
| **笔记离线同步与裁决** | **VERIFIED** | `lib/services/note_service.dart:240`| `NoteSyncQueue`, LWW | 队列消费证实 | 自动同步到医考帮 |

---

## 5. 搜索与学习数据统计

| 功能名称 | 状态 | 实现代码位置 | 核心依赖 | 测试覆盖情况 | 未完成事项 / 关联问题 |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **全库跨题库并发搜索** | **VERIFIED** | `question_search_repository.dart:142`| SQLite 并发读连接 | `test/my_page_test.dart` 模型测试通过 | **RISK-03**：未建立 FTS5，通配符全表扫描较重 |
| **单题耗时追踪 (`duration`)**| **VERIFIED** | `models/question.dart:615` | `Activities` 表 | 毫秒级时间戳落库证实 | 无 |
| **GitHub 年度热力格子墙** | **VERIFIED** | `screens/statistics_page.dart:78`| `DailyStat`, 热力色块阶梯 | 算法与渲染证实 | 无 |
| **日/周/月周期指标卡** | **VERIFIED** | `screens/statistics_page.dart:228`| `PeriodStats` | 聚合查询证实 | 无 |
| **答题趋势双轴图表** | **VERIFIED** | `screens/statistics_page.dart:450`| `fl_chart: ^0.70.2` | 动态动画与坐标映射证实 | 无 |
| **单日答题明细弹窗** | **BROKEN** | `screens/statistics_page.dart:1120`| `pushAdaptiveModalPage` | 代码审计证实 context 失活 | **BUG-02**：`Navigator.pop` 后立即跳转导致崩溃 |

---

## 6. 跨平台特化与自适应

| 功能名称 | 状态 | 实现代码位置 | 核心依赖 | 测试覆盖情况 | 未完成事项 / 关联问题 |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **桌面端横屏自适应模态** | **PARTIAL** | `common/platform_adaptive.dart:268`| `showDialog`, 居中卡片 | 桌面自适应证实 | **BUG-03**：内置 Navigator 退出未向外传返回值 |
| **桌面端左侧边栏导航** | **VERIFIED** | `screens/home_page.dart:176` | `NavigationRail`, `IndexedStack`| 瞬时切换证实 | 无 |
| **应用内增量检测与更新**| **VERIFIED** | `services/app_update_service.dart:22`| GitHub 镜像代理, `open_filex`| `test/version_utils_test.dart` 比较测试通过 | Android APK 拉起安装 |

## 2026-11-06 Goal 增量记录

- 文件导入合并/覆盖：IMPLEMENTED + 核心合并 TESTED；51 项回归通过。以 bank_id 检测同库，保留用户状态；订阅部分仍待实现。

### 切片 2：订阅清单管理

- 已接入多个 HTTPS JSON 订阅地址编辑、删除、手动检查、缓存；可开启启动和运行期间每六小时检查并更新已安装且允许更新的订阅题库。应用关闭后不执行系统后台任务。
- 清单要求下载 SHA-256、合法 bank_id；拒绝重复 ID、非 HTTPS、嵌入凭据。保留已安装文件的根 identity。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 53/53。未连接真实远端订阅实测。
- 下一切片：根身份树选择与完整暂存构建。

### 切片 3：完整身份树创建题库

- 登录后可递归选择身份，父子重叠去重，每个根生成独立 custom ID 与 1.0.0 版本；保持原始题目 ID 和叶入口关系。
- 复用 YkbBankSyncService schema/请求解密/字段转换及既有安装；暂存生成、SQL 实数统计、清除账号字段、失败/权限不足/取消不安装。进度显示目录/抓题/题数/章节/校验/安装。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 55/55，含深层树、共享题和权限/取消真实 SQLite 测试。
- 未做真实账号抓取；下一切片：自建增量版本与智能同步进度，之后详情/历史和导出。

### 切片 4：同步实时进度与自建更新版本

- 智能同步与全量课程操作接入统一进度组件；自建更新递归抓取目标根，合并保留本地额外题，有变化才安装并递增 PATCH；无变化不增版本。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 56/56，新增 SQLite 无变更判断测试。
- 下一步：用户库安装履历、题库详情树与时间轴；随后安全导出。

### 切片 5：题库详情与安装时间轴（2026-11-07）

- 用户库升级至 v12，新 BankHistory 表记录创建/导入、替换和增量安装，新增题量按 ATTACH 查询新题 ID，不用净题量差猜测。
- 管理卡片详情入口展示题量、版本、来源、订阅地址、覆盖 identity/课程/章节树和变更时间轴。旧履历不补造。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 57/57，包含 v11->v12 保留用户记录迁移测试。
- 下一步：SQLite/ZIP 安全导出与最终整体验证。

### 切片 6：安全 SQLite/ZIP 导出（2026-11-07）

- 详情页可选导出 SQLite/ZIP；桌面使用保存路径，移动端保存外部/文档目录；取消不写文件。
- 正式库只读，副本清除账号字段并 VACUUM，校验后打包；ZIP 包含一个标准 SQLite 与 manifest。旧多根合并库按选定根生成独立标准题库再导出。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 59/59；测试覆盖标准/旧库导出关系完整、校验通过、原文件不变。
- 下一步：最终审查目标覆盖与安装失败/订阅删除一致性、知识库同步。

### 收尾切片 7：安装事务与订阅清理（2026-11-07）

- 题库安装在冲突选择前加互斥锁；登记、时间轴和 ATTACH 统计重算使用同一用户库事务。发生异常恢复旧文件，取消后释放锁。
- 删除订阅/清单条目同步清理下载元数据，保留已安装文件和仍有效缓存；强化根 identity/版本/schema/hash 校验。旧合并库详情通过独立只读连接读取。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 62/62；新增真实 SQLite 安装、故障注入回滚与并发取消测试。
- 下一步：完整重建复用深层构建、自建自动检查节奏、进度终态与导出路径保护。

### 收尾切片 8：完整重建与持续进度（2026-11-07）

- 课程全量重建复用递归完整构建；原始 ID、真实叶归属、去重计数、秒时间和账号字段清理保持规范。失败/无权限不替换旧库，重建递增 PATCH，关闭包覆盖更新。
- 旧根课程迁移到叶 identity 时，以 ATTACH SQL 保留消失归属的选课状态。重建后的完整树题库走安全构建/合并分支；自动检查成功后六小时冷却，失败继续现有退避。
- 创建页固定进度/取消区；目录/题目请求设置超时，错误结果重试一次，非选择分组保留有效后代。同步无变化、权限/重试与批次完成提供终态。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 63/63，增加端到端全量重建/权限保留/选课迁移 SQLite 验证。
- 实现界限：完整树题库更新采用完整快照检查再增量合并，尚未实现深层树章节缓存/断点续传；原有题库保留既有章节智能算法。下一步导出路径保护和最终文档更新。

### 收尾切片 9：导出防覆盖与移动端文档保存（2026-11-07）

- 拒绝导出到应用数据库目录、正式库/用户库及其符号链接/硬链接别名；新文件也解析父目录链接，暂存不得覆盖已有文件。
- 移动端使用已安装 file_picker 8.1.7 的 saveFile(bytes) 系统文档 API；桌面端依旧路径返回后复制。移动返回可能为 content URI，不按本地路径写入。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 64/64，新增正式文件及目录链接拒绝测试；未做原生文件选择器实机验证。
- 下一步：修复管理页创建/订阅入口错位，补导航测试，统一最新文档状态。

### 收尾切片 10：管理入口可达与返回刷新（2026-11-07）

- 修正创建/订阅按钮错误位于导入冲突弹窗的问题，移入管理页 AppBar；冲突弹窗只保留取消/覆盖/合并。
- 创建/订阅页返回总是刷新目录和缓存，涵盖多库部分完成后取消、订阅保存后检查失败。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 66/66。390px/1000px 部件测试验证标签样式、创建登录提示、订阅导航和返回刷新，无布局异常。
- 下一步：最终产物一致性/导入往返检查和文档交接；没有原生实机抓取/文件选择器测试。

### 切片 11：订阅产物一致性与可移植往返（2026-11-07）

- 下载除下载包 SHA-256 外，校验解压后 SQLite 的可选 SHA-256 和根 identity；拒绝清单更改已安装根。
- 真实 SQLite 导出 ZIP→重新导入验证通过；根/hash 不符拒绝安装、原文件与历史不受影响。
- 最终 flutter analyze --no-pub 0 issues；flutter test --no-pub 67/67。所有代码切片分别提交；知识库已本地同步，真实账号/原生选择器验收为下一步。

## 2026-11-07 用户反馈切片 A：订阅格式与更新设置

- 支持 HTTPS ZIP/SQLite 直链和 JSON 清单，按响应文件头识别，解决二进制被 UTF-8 JSON 解码导致的异常；已下载用户 Gitee 临床题库真实 ZIP 并通过只读完整性/根信息检查。
- 订阅列表可以修改地址；单库订阅来源可独立覆盖，不影响共享清单的其他库。自动更新移至设置，检查间隔支持预设与自定义 1～10080 分钟，修改后重设计时器。
- 验证更正：f86db66 提交时实际为 1 条 lint、71 通过 / 1 失败（设置测试遗留 Timer），此前记录的全绿不准确。后续补全大括号并在测试结束前停止应用定时器；本次重新验证 flutter analyze --no-pub 0 issues、flutter test --no-pub 72/72。真实 Gitee 响应由前一切片临时探针检查，未纳入仓库。
- 下一切片：详情视觉重做、学科/去重题数/空节点隐藏、管理页详情旁更新/导出图标。

## 2026-11-07 用户反馈切片 B：详情与管理动作

- 详情采用与设置/个人页相同的 InfoCard、TileIcon、主题字体/颜色与分区间距；更新记录显示简洁日期与实际新增题数。
- 覆盖课程仅显示直接拥有课程的学科；隐藏空分组时保留下级有效学科。课程/章节题量由 SQLite COUNT(DISTINCT question_id) 得出，文案改为“道题”。
- 已安装且有订阅/下载链接的题库始终显示手动更新图标，与详情、导出图标同一行；详情返回刷新订阅配置。单库订阅链接可在详情修改，保持共享清单其他题库的来源。
- 导出动作在管理卡片和详情 AppBar 共用组件，支持取消、ZIP/SQLite；管理页导出期间禁用冲突操作。
- 新增 390px/1000px 真实 SQLite 部件验证：空学科过滤、跨章共享题去重、编辑地址预填、相邻图标与导出取消。
- 下一步：创建过程逐项错误选择与成功/失败报告；最终再验证直链手动更新完整安装路径。

切片 B 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 76/76。

## 2026-11-07 用户反馈切片 C：创建错误决策与报告

- 创建过程课程目录、章节、题量不完整、字段/事务错误弹出“忽略 / 忽略全部 / 终止”；203 明确提示账号无查看权限，其他错误显示简洁原因与错误码。忽略全部限定本次创建，并跨多个所选学科生效。
- 被忽略的章节整章跳过，事务异常回滚；完成后按成功/失败分页列出条目、原因、已保存题库与实际去重题量。失败条目不写入内容包；所有条目都失败时不生成空题库。
- 终止删除当前未完成暂存文件，先前已完成题库保留；页面关闭触发取消。同步/全量重建未传交互处理器，仍严格遇错不安装。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 84/84。新增真 SQLite 忽略目录/章节、错误事务回滚、跨题库忽略全部、取消/终止清理和全失败无产物；390px/1000px 创建→弹窗决策→部分安装→报告部件测试。
- 下一步：最后统一“学科”错误文本，验证 Gitee 真实 ZIP 从订阅识别到安装/手动更新的调用链，再更新最新基线与交接。

## 2026-11-07 用户反馈切片 D：最终回归

- 题库校验、订阅匹配和增量合并错误统一使用“学科”，不再向用户显示“根 identity”。
- 新增真实 SQLite 手动订阅更新回归：自动检查跳过被冻结内容，单库手动检查刷新来源并新增题目；全局个人答案保留，ATTACH 重算课程对错数，重复检查不再安装、不新增履历。
- 实际下载用户 Gitee 临床期末 ZIP（25,939,926 字节，SHA-256 3db37a844ec0f8ac3688a7fcf7967de1a8adf8f787a3e4801dd1276893383061），57,346 题、40 课程、1,137 章节、学科 20101。只读完整性检查通过；用原始响应文件字节运行 Flutter 临时探针，验证订阅识别→注册→安装→手动检查，保留发布版本 3.0.0，未出现 UTF-8 异常。临时探针已删除，不作为常规测试依赖。
- 实际最终验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 85/85。真实 Gitee 下载/安装探针额外 1/1 通过。
- 用户 9 项反馈实现完成；下一步是用户视觉验收与真实账号创建（含 203 弹窗）、平台原生文件保存验收。

## 2026-11-07 统一管理方案：切片 1

- 持续 Goal 已切换为完整实现 QUESTION_BANK_MANAGEMENT_DESIGN.md。
- 已落地来源目录/主来源/候选来源，保存无网络；来源失败隔离；全局与单库共用只检查不安装流程；JSON 条件请求，直链 HEAD/条件 GET 不接收整包、显示需下载确认。
- 新来源待检查；修改单库来源先保留旧绑定，检查匹配后切换。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 89/89。
- 尚未完成：持久化下载缓存、链接导入、上游基线/本地修订、安全更新处理、独立自动安装设置及完整状态 UI。旧 refresh/install API 暂保留，后续切片统一移除。
- 下一步：缓存产物并接通从链接导入，再处理上游基线与本地补充。每片验证后 commit，不 push。

## 2026-11-07 统一管理方案：切片 2

- 新增持久化有界下载缓存（默认 256 MiB），保存已校验包与来源/摘要/HTTP 验证器；复用前核对字节摘要，活动租约防清理、超限 LRU，损坏重下载。
- 从链接导入 ZIP/SQLite，支持订阅以后更新；注册/安装复用本次下载，不重复来源。来源操作提供检查/显式下载确认；确认后安装复用包。管理页包安装改走缓存任务。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 94/94。新增 5 项真 SQLite 缓存/请求次数/损坏/租约/一致性测试，390px/1000px 链接导入弹窗可达。
- 未完成：上游基线与本地修订、安全合并/替换与重复发布判断；自动安装独立开关；完整来源与详情状态 UI、完整性/重新下载。下一步从用户库基线元数据与安装事务开始。

## 2026-11-07 统一管理方案：切片 3

- 用户库 v13 新 BankContentState；已处理上游发布标识/版本/摘要和本地修订独立保存，和安装履历/ATTACH 统计同事务回滚；题库 schema v1 不变。
- 同一上游发布重复检查/安装不再合并；本地改动保留基线，新上游需要显式合并/替换/暂缓；同版本内容变更/回退和旧库未知基线不自动覆盖。下载后用 ATTACH 展示新增/不同/本地独有题量，ZIP 比较复用缓存。
- 自动检查与自动安装分离，默认仅检查；自动安装限定已知基线、无本地补充、可自动更新且版本前进的库。移除旧混合 refresh/setBankSource 路径，来源读取统一目录。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 101/101。新增 7 项真 SQLite 基线/合并/回退/回滚/缺少 SQLite 摘要/旧库迁移/自动安装测试；设置双开关验证。
- 未完成：完整 Material 管理页/来源/详情状态呈现、候选来源与待检查编辑、显式本地完整性与重新下载、任务进度/取消以及边界审查。下一步完成 UI 与对应交互测试。

## 2026-11-07 统一管理方案：切片 4（完成）

- 管理、来源、详情统一 Material Design：复用 InfoCard/TileIcon、主题形状与字体，宽屏内容限制 760px；数字学科标签与状态同行，详情/更新/导出相邻，更新图标由检查/下载确认/下载并更新状态驱动。
- 来源添加/编辑即时保存且不联网；显示官方来源、重复提示、待检查的新来源、候选来源及显式切换。原绑定在新来源匹配前继续可用；移除提示解绑影响，保留已安装内容、个人数据和来源归档。
- 详情提供订阅状态、最新版本、最近检查时间与本地补充；仅在不同版本或本地补充时显示已应用订阅版本。覆盖课程隐藏空学科，课程/章节按 DISTINCT 全局题目 ID 计数；本地完整性检查和重新下载收进更多菜单。
- 新 BankDownloadTask 提供阶段、字节进度、取消与半包清理；原子安装开始后不允许取消。缓存复用、重新下载及超限包在同一任务内持有租约，避免确认后再次下载。轻量检查显示“检查中”，下载任务只显示一组进度。
- 删除无人调用的旧 checkRemoteManifest/downloadBank/hasUpdate 网络与判断路径；保留 GitHub 代理，HTTP 验证器只在同一实际传输地址复用。
- 配置/检查/确认/来源切换/安装使用 ChangeNotifier 通知页面，后台检查结果即时刷新。修复详情保存链接的 setState 返回 Future 断言；拒绝远端更改已安装学科，并保留原文件、登记和履历。
- 最终代码实际验证：flutter analyze --no-pub **0 issues**；flutter test --no-pub **113/113**。新增 12 项缓存/取消/超限单次下载、学科保护及 390px/1000px 管理/详情/来源交互与后台刷新回归。
- 已对 390px/1000px 使用真实中文字体与 MaterialIcons 的截图进行视觉检查。用户视觉验收、真实医考帮账号抓取和各平台原生文件选择器仍未实机验收。
- 完整统一管理方案已实施并通过上述代码审查与自动化验证；切片提交后不 push。下次先核对 Git 与本文，再按用户反馈做实机验收，无需重做已完成切片。

## 2026-11-07 用户追加反馈：切片 1（错误诊断与页面安全）

- GitHub 下载镜像仅用于 GitHub/GitHubusercontent 域名，Gitee、R2 和签名订阅地址保持原样。用户给定的 Gitee 临床 ZIP 与 R2 口腔 ZIP，在配置 gh-proxy.com 后均通过实际 Flutter HEAD 探测（HTTP 200 / 需下载确认），未下载整包。
- 检查输出 [bank-check] 请求方法/公开地址/HTTP 状态及异常堆栈；来源失败仍独立保存。全局、单库、来源和候选检查通过共同弹窗展示失败来源与实际原因，不改变已安装内容。
- 复现订阅展开 bool 转 double 的异常：ExpansionTile 与 SelectableText 内部滚动共用 PageStorage 键。给链接文本和订阅列表独立命名空间，重复展开回归通过。
- 课程页 _refreshData / 异步恢复进度 / 管理返回检查 mounted，覆盖管理未关闭而原课程路由已移除的生命周期测试。
- 保留工作区将“官方题库”改为“内置题库”的既有命名修改，相关 UI 测试同步更新。
- 实际验证：flutter analyze --no-pub 0 issues，flutter test --no-pub 117/117；真实链接轻量探测额外 1/1。提交后不 push。
- 未完成：用户追加的详情三项统计、点击卡片进详情、所有题库操作按钮内圆形进度；下一切片完成这些 UI 反馈。


## 2026-11-07 用户追加反馈：切片 2（详情统计与按钮进度，完成）

- 详情名称/描述/数字学科标签下方同行显示课程总数、章节总数、题目总数；标准库使用校验过的 BankMeta，旧合并库用只读 SQL COUNT，未安装且缺少元数据时显示“—”。跨章共享题仍按独立题目计数。
- 点击管理卡片进入详情；切换当前刷题题库通过独立“使用此题库”按钮执行，保留启用开关及相邻详情/更新/导出图标。
- BankActionButton / BankActionProgress 统一 20px、2px 描边的 Material 圆形进度，不在环内放文字。全局检查、单库检查/下载、内置/订阅来源检查、候选来源确认、导入、导出、创建与课程同步均在发起按钮原位显示；移除页面底部/卡片外的重复进度。下载阶段按字节显示确定进度，其他阶段为不确定进度；取消仍可通过进度按钮执行，原子安装禁取消。
- 页面刷新保留旧内容，避免按钮因 FutureBuilder 重新加载而消失。FFI 回归将异步操作放在 tester.runAsync 的真实时钟中，并等待页面的 SQLite Future，避免跨测试共享配置队列或关闭数据库时仍有加载。
- 新增 6 项阻塞请求交互测试，覆盖全局、普通/内置来源、单库、详情“待比较”、候选来源的原位圆环及无中心文字；390px/1000px 验证详情三项统计、卡片导航不更改当前题库及跨章共享题去重。真实中文字体与 MaterialIcons 截图已复核。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 全量 123/123。R2 临时联网探针额外 1/1：用户口腔 ZIP（38,029,760 字节）下载、导入、只读完整性、订阅绑定成功；版本 1.0.0、学科 30401、77,189 题、44 课程、1,182 章节。配置 gh-proxy.com 仍直接访问 R2；再次检查为 HEAD HTTP 304，没有重新下载、安装或增加履历。探针不加入常规测试，临时脚本已清理。
- 本次追加的 5 项反馈已实现；真实账号创建/203 现场与各平台原生文件选择器仍待实机验收，用户视觉验收待反馈。保持正式库只读、用户库隔离、全局 question_id 和 ATTACH 契约。按既有授权验证后提交，不 push。


## 2026-11-07 追加六项需求：切片 A（删除与更新语义，完成）

- 详情更多菜单增加“删除题库”及确认框：移除本地内容与备份，保留全局作答/收藏/笔记/流水、选课和履历。内置或有来源的题库保留为未安装入口，独立本地库从目录移除；来源配置不变，删除当前库后选择可用库。同步基线/章节缓存清理，防止后台任务重装刚删除的库。
- 删除仅允许应用所属路径，与安装共用互斥；先关闭连接并移动内容，用户库事务失败还原目录。只改可写用户元数据，不向正式题库执行 SQL 写入。用户库/题库 schema 均不变。
- 真实 SQLite 回归核验题目内容：合并保留 local 独有题并用上游替换相同 ID 的差异题；替换仅留下上游题。个人答案保留，重复发布不安装。更新弹窗将动作明确命名“合并更新 / 替换题库 / 暂不更新”。
- 订阅页下载确认提示与图标同一 Row，文字可换行，按钮及其进度保持右侧位置；390px/1000px 验证布局及删除确认/取消/返回刷新。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 129/129（新增删除数据层 4 项、提示布局 2 项，扩充合并/替换与删除导航回归）。切片按既有授权提交，不 push。
- 未完成本次第 4～6 项：创建前法律风险/会员权限确认、父子全选/半选、学科名称与 ID 小 tag 同行。下一步完成创建页交互并逐片分析、全测、提交。


## 2026-11-07 追加六项需求：切片 B（创建确认与学科树，完成）

- “开始创建”先显示 Material 确认框，说明自动抓取的著作权/服务协议/法律责任和会员/课程权限不足导致失败（203）。必须勾选已了解风险并确认当前账号会员与访问权限，才能“确认并开始”；取消或关闭不创建报告、不请求题库内容。会员/权限是用户确认，未声称通过 API 验证；原 203 错误选择和结果报告保持。
- 新 BankIdentityTree 选父节点递归勾选全部后代；取消部分后代时祖先为 null 半选，点击半选父节点补齐，点击全选父节点清空子树；子节点全部选中时自动归并父节点。沿用 BankIdentityNode.selectedRoots，半选父节点不会把取消的后代传给抓取器，完全选中的父子不重复建库。
- 学科名称与数字 ID 小圆角 Chip 同行；层级缩进、折叠状态和选择独立，去除展开时的深色边线，创建页最大 760px 与其他管理页一致。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 133/133。新增取消确认零请求 2 项、三层学科树联动/半选/折叠后保留/补齐/全清/去重/标签同行 2 项；原创建→确认→203 忽略/忽略全部/终止→报告真实 SQLite 流程均通过。390px/1000px 真实字体与 MaterialIcons 临时截图探针额外 2/2，并已人工复核；临时脚本已清理。
- 本次第 1～6 项全部完成；切片 A 为 032c2ea（129/129），切片 B 为 2ea7e79（133/133），不 push。真实账号会员/课程权限现场和原生文件选择器继续待实机验收。题库 schema v1、用户库 v13、正式库只读、全局 question_id 和 ATTACH 契约保持。
- 下一会话：先核对最新 Git/基线/本交接，按用户反馈做视觉或真实账号验收，不重做已完成模块。


## 2026-11-07 创建页性能 Goal：切片 1（完成）

- 原树用递归 ExpansionTile + maintainState 挂载所有 4,380 个节点，每次勾选刷新整页并遍历整树；本轮先前复现约 5 秒。
- BankIdentitySelection 首次索引树及叶节点计数，勾选只更新所选子树与祖先；每行 ValueNotifier 局部通知。BankIdentityTree 用扁平可见节点与 ListView.builder，只挂载视窗附近行，折叠/滚动不丢选择；创建页的选择状态只通知开始按钮。
- 大目录全测实测：挂载 23 行，父节点勾选 93ms、叶节点取消 18ms、滚动回来再勾选 11ms（Flutter debug widget test，本机数据不等于所有设备的保证）。无关兄弟行保持同一 widget；父子全选/半选、selectedRoots 去重与折叠保留回归通过。
- 实际 flutter analyze --no-pub 0 issues；flutter test --no-pub 135/135。按既有授权提交，不 push。正式库只读、用户库隔离、全局 question_id 与 ATTACH 契约保持。


## 2026-11-07 创建页性能与 Material UI Goal：切片 2（完成）

- 管理卡片用 BankTag（StadiumBorder、主题色、labelSmall、非交互标签）统一小标签；当前使用与题库名称紧邻同行，采用 primaryContainer/onPrimaryContainer 强调色，其余状态和学科号使用较淡背景。保留 48px 操作触控区域，不把小标签作为按钮。
- 检查全部更新集中在题库订阅 AppBar，管理卡片保留单库检查/下载/更新。仍共用 BankSubscriptionService.check，仅检查不安装；全局检查保持按钮原位无文字圆环、失败来源与 HTTP 原因弹窗。全局/单库网络契约未改变。
- 更多导入方式改用 file_download_outlined，导入进行时在同位置显示圆环；链接/文件导入保持可达。
- 详情学科号小标签移至名称与描述右侧，数字保留、悬停提示学科编号；只显示合法数字学科号。三项统计仍在头部下方；题库信息增加题库文件大小（读取已安装 SQLite 字节元数据，不含下载包与备份，也不新增网络请求）。
- 最终验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 135/135。390px/1000px 布局、标题同行标签、右侧编号/描述、标签高度、导入与订阅导航、全局原位进度/失败弹窗回归通过。使用 PingFang 与 MaterialIcons 生成并人工复核管理/详情四张截图，额外捕获运行 4/4 通过。
- 最终大目录全测实测：4,380 节点只挂载 23 行，父节点勾选 105ms、叶节点操作 23ms、滚动后再勾选 14ms；本机 Flutter debug 部件测试，设备实机数据待用户反馈。父子全选/半选、折叠/滚动保留与根去重契约继续通过。
- 性能提交 3d6287b，UI 提交 093f4ef；均不 push。用户库 schema v13、题库 schema v1、正式库只读、全局 question_id 与 SQLite ATTACH 契约保持。


## v2.2.2 发布记录（2026-11-07）

版本 2.2.2+212；annotated tag 与 main 已 push，Bot 发布运行 42376143828；发布说明从 tag 内文件读取并感谢 @JMK712 的四项 PR。135/135、0 issues；多平台构建与实际包发布待 workflow 确认。


## 2026-11-07 v2.2.2 正式发布核验（完成）

- GitHub Release：https://github.com/nanguaguag/yibubang/releases/tag/v2.2.2 ；正式发布、非 draft、非 prerelease，GitHub latest 已指向此版本。应用版本 2.2.2+212，tag 指向 bd6a7a0。
- Release workflow 42376143828 全部 6 个 job 成功：分析测试、Android、Windows、macOS、Linux、发布与清单回写。其成功只代表 CI 构建与发布，未替代各平台实际安装/刷题现场验收。
- 8 个 Release 附件均为 uploaded 且非空：4 个 Android APK（通用 / arm64-v8a / armeabi-v7a / x86_64）、Windows ZIP、macOS ZIP、Linux tar.gz 与更新 JSON。
- 发布 body 与 .github/release-notes/v2.2.2.md 逐字规范化比较一致；包含 @JMK712 的 PR #17～#20 致谢与 v2.0.5...v2.2.2 比较链接。
- 下载 Release 附带的更新 JSON，核对与远端 main JSON 完全一致，latest_app 为 2.2.2、资产 URL 指向本次版本、update_info 与文案匹配；原有 question_banks / data_for_version / 数据 hash 配置未改变。
- Bot 回写提交 efc2e55 已 fast-forward 同步至本地 main，工作区干净；未挪动 v2.2.2 tag，未再改变已发布源码。最新源码验证仍为本次发布前 135/135、分析 0 issues；Bot 仅修改更新 JSON。
- 本次发布任务无未完成项。下一会话第一步：核对 efc2e55 / v2.2.2 与 Git 现场，根据用户安装及升级反馈处理；如需新修复，使用新提交和后续版本，不改本次发布 tag。

---

## 2026-11-09 【闪卡（Flashcard）体系】完整闭环实现（完成）

- **触点 1：题目详情页笔记转化与闪卡制作（QuestionDetailPage）**：
  - `lib/widgets/flashcard_edit_dialog.dart`：构建统一自制闪卡编辑组件，支持正面题干、背面答案解析、自定义多标签（逗号/空格切分）与关联原题 ID。
  - `lib/screens/question_detail/question_note_view.dart`：头部常驻「制作闪卡」入口；在每条个人笔记卡片上新增「✨ 一键转闪卡」按钮，点击自动带入题干与笔记内容，确认入库后自动挂载调度。
- **触点 2：每日计划页卡包管理与抽题（DailyPlanPage & DailyReviewPlanDialog）**：
  - `lib/widgets/flashcard_deck_dialog.dart`：打造闪卡卡包管理控制台，具备卡片总数统计、多字段全局搜索、动态标签横向滑动 FilterChip 筛选、双面预览、编辑修改、删除与随时斩卡/取消斩卡。
  - `lib/screens/daily_plan_page.dart`：在记忆精粹卡片池新增「自制闪卡」维度 Pill（点击直达卡包管理），计划抽题来源展示支持「闪卡」。
  - `lib/widgets/daily_review_plan_dialog.dart`：支持抽题来源勾选「自制闪卡（正反速记）」(`flashcard`)。
  - `lib/services/daily_review_service.dart`：混编闪卡抽题流，到期优先与新卡抽取；`submitReviewResult` 针对闪卡走纯流水记账（Activities: 闪卡复习），严禁向题库插入 dummy 数据破坏题目隔离。
- **触点 3：百词斩复习刷题流 3D 物理翻牌与自评（DailyReviewPage）**：
  - `lib/widgets/flashcard_flip_card.dart`：基于 Matrix4 实现带真实景深（perspective: 0.001）与 Y 轴 180° 翻转动效，背面自动 counter-rotate 防镜像，轻触伴随轻微触感震动（HapticFeedback.lightImpact）。
  - `lib/screens/daily_review_page.dart`：检测到闪卡自动渲染 `FlashcardFlipCard`，正面轻触翻转揭晓背面，滑出 Again/Hard/Good/Easy 4 档自评条；自评演进完全接入既有 SM-2 / 轻量 FSRS 调度引擎；顶部 AppBar 动态切换为“今日闪卡记忆”与“熟练斩卡”。
- **测试与质量验证**：
  - `test/flashcard_system_test.dart`（6 项端到端）、`test/daily_review_ui_test.dart`（7 项交互与部件测试）、`test/spaced_review_repository_test.dart`（6 项 SQLite 存储单测）。
  - 运行 `flutter analyze --no-pub` 报 **No issues found!**（0 错误 0 警告）；全量测试套件 `flutter test --no-pub` 184/184 全部通过。

---

## 2026-11-09 闪卡交互增强、全平台自适应路由与我的页管理（完成）

- **我的页自制闪卡管理**：
  - [`lib/screens/my_page.dart`](lib/screens/my_page.dart) 新增「自制闪卡」统计卡片，实时获取当前闪卡总数，点击打开闪卡卡包管理，返回时自动更新题库与笔记统计。
  - [`lib/repositories/question_search_repository.dart`](lib/repositories/question_search_repository.dart) 的 `getUserDataCounts` 支持返回 `flashcards` 闪卡总数。
- **大弹窗移动端/桌面端自适应路由重构**：
  - 记忆计划设置（[`DailyReviewPlanDialog`](lib/widgets/daily_review_plan_dialog.dart)）、闪卡卡包管理（[`FlashcardDeckPage`](lib/widgets/flashcard_deck_dialog.dart)）、闪卡新建/编辑（[`FlashcardEditDialog`](lib/widgets/flashcard_edit_dialog.dart)）在移动端均采用全屏新页面打开，在桌面端自适应保持居中模态卡片浮窗；
  - 核心自适应组件 [`lib/common/platform_adaptive.dart`](lib/common/platform_adaptive.dart) 内置 `_AdaptiveModalPageRoute`，同步拦截 `didPop(result)` 冒泡传递，彻底解决桌面端模态弹窗关闭时返回值无法透传至外部 Future 的问题。
- **闪卡卡包列表 4 行限制与点击详情**：
  - 卡片列表项正面与背面文本严格限制展示最多 4 行并带有省略号截断（`maxLines: 4, overflow: TextOverflow.ellipsis`）；
  - 卡片支持点击唤起全屏/模态卡片详情视图（`_FlashcardDetailView`），查看完整内容、复习进度并可进行编辑/斩卡/删除。
- **多标签筛选（FilterChip）**：
  - 闪卡管理支持标签多选（`Set<String> _selectedTags`），点击“全部”查看全部，点击具体标签可多选高亮并取并集匹配。

