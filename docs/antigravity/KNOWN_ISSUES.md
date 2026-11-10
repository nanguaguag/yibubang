# KNOWN_ISSUES.md - 医不帮已知缺陷、潜在风险与问题总账

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A11 / 已修复**。斩题/斩卡保存主动归档原因，事务内重查斩题、暂停和实体删除；自制卡片删除墓碑防止旧会话兜底创建孤儿，显式恢复/重建才解除。UI清除当前及尾部所有同ID副本，失效评分提示并跳过；原题与关联闪卡保持独立。用户库v22；新增2项服务回归及1项重复副本部件测试，相关51/51、analyze 0 issues；commit：修复 A11 斩题队列残留与删除闪卡复活。下一步A13抽题续页及A14全库范围。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v22；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：按照清单继续尚未完成问题，补充对应正确性回归；历史缺陷探针不再用于判定修复通过。保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
<!-- /A01_A20_REPAIR_STATUS -->


> **当前专项基线**：093f4ef；2026-11-07；analyze 0 issues、135/135 测试。下方旧审计以原 Commit 3c33fb9 为历史背景，BUG-01～09 已清零。  
> **分类标准**：
> - **已确认缺陷 (Confirmed Bugs)**：在代码中有完整错误逻辑证据，可确定触发异常或逻辑错误。
> - **潜在风险 (Potential Risks)**：在特定边界条件（大文件、断网、特定输入）下可能引发崩溃或性能劣化。
> - **待验证问题 (To-be-verified)**：存在设计坏味道，但暂无直接证据表明其必定触发运行时崩溃。

---

## 1. 已确认缺陷 (Confirmed Bugs)

### [BUG-19] Android 10 (SQLite 3.22) 及旧宿主下同步写库语法报错 near "ON": syntax error (Issue #23)
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`CloudSyncService`、`Question`、`DataTransfer`、`DailyReviewService`、`QuestionBankFileService`
- **代码文件与行号**：
  - [`lib/services/cloud_sync_service.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/cloud_sync_service.dart)
  - [`lib/models/question.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/models/question.dart)
  - [`lib/db/data_transfer.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/data_transfer.dart)
  - [`lib/services/daily_review_service.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/daily_review_service.dart)
  - [`lib/services/question_bank_file_service.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/question_bank_file_service.dart)
  - [`lib/repositories/question_bank_repository.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/repositories/question_bank_repository.dart)
- **触发条件**：在系统自带 SQLite < 3.24 的宿主设备（如 Android 10/EMUI，系统 `/system/lib64/libsqlite.so` 版本为 3.22）中执行云端同步、日常复习提交、做题计数累加或题库安装。
- **根本原因**：
  1. SQLite 官方在 3.24.0 (2018-06-04) 始支持 PostgreSQL 风格的 `ON CONFLICT (...) DO UPDATE / DO NOTHING` 语法；
  2. 原代码在云端多端同步仲裁、做题计数、复习提交流水等 8 处直接硬编码了 `UPSERT` 语法；
  3. `pubspec.yaml` 缺失内嵌 `sqlite3_flutter_libs`，运行期直接调用宿主系统旧版动态库抛出语法错误。
- **当前状态**：`RESOLVED` (采用「方案 3：双保险深度防御」——引入 `sqlite3_flutter_libs` 随包分发现代 SQLite 库；将全部 8 处 `ON CONFLICT` 彻底重构为 `INSERT OR IGNORE` + 针对性原子 `UPDATE` / `INSERT OR REPLACE`，消除语法版本门槛；启动期输出 `sqlite_version()` 诊断日志；全测 204/204 通过)。

---

### [BUG-18] QuestionGridPage 布局松约束与极端约束下断言 crossAxisCount > 0 失败及页面白屏
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`QuestionGridPage` 章节九宫格 / `LayoutBuilder`
- **代码文件与行号**：[`lib/screens/question_grid_page.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_grid_page.dart)
- **触发条件**：窗口调整、转场过渡或在非紧约束容器下首次挂载九宫格。
- **根本原因**：
  1. `count = ((width + 24) / (btnSize + 24)).floor()` 在 `width == 0` 时算得 0，导致 `SliverGridDelegateWithFixedCrossAxisCount` 断言 `crossAxisCount > 0` 失败；
  2. 若简单返回 `SizedBox.shrink()`，在 `AnimatedSwitcher` 的松约束（`StackFit.loose`）下会导致子树永久折叠为 0x0 纯白屏。
- **当前状态**：`RESOLVED` (移除干扰宽高的 `AnimatedSwitcher`，使用 `Column` + `Expanded` 传递稳定紧约束，并以 `math.max(1, count)` 与 `math.max(1, crossAxisCount)` 严格兜底)。

---

### [BUG-17] 跨章节滑动切章在 Bouncing 弹性回弹与 macOS 触控板下松手弹回原位
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`QuestionDetailPage`、`QuestionGridPage`、`ChapterCrossIndicator`
- **代码文件与行号**：[`lib/screens/question_grid_page.dart:110-180`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_grid_page.dart#L110)、[`lib/screens/question_detail_page.dart:185-265`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_detail_page.dart#L185)
- **触发条件**：在题目页左右滑或章节页上下滑达标 55px 后松手；尤其在 macOS 端使用触控板双指滑动。
- **根本原因**：
  1. Flutter 物理引擎 `BouncingScrollSimulation` 在抬手瞬间先于 `ScrollEndNotification` 将位移回弹归零，原逻辑在位移下降时提前清空了 `_canTriggerChapter`；
  2. macOS 触控板双指滑动在 Flutter 中发射 `PointerPanZoomStart/Update/EndEvent`，不发射 `PointerUpEvent`，导致原本针对抬手的监听被完全穿透。
- **当前状态**：`RESOLVED` (为 `Listener` 挂载 `onPointerPanZoomEnd`；联合 `UserScrollNotification(direction: idle)` 与 `ScrollEndNotification` 实现多路即时触发；回弹期间保持就绪状态不被擦除)。

---

### [BUG-16] 错题或收藏加入记忆复习后因 status 改变在到期队列中被误过滤消失
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`DailyReviewService._fetchDueReviewQueue` / 百词斩抽题队列
- **代码文件与行号**：[`lib/services/daily_review_service.dart:650-675`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/daily_review_service.dart#L650)
- **触发条件**：用户做错题目（status = 2）进入记忆曲线后，在后续复习中答对（status 变更为 1）；当下一次到达复习间隔再次到期（Due）时。
- **根本原因**：`_fetchDueReviewQueue` 对已经加入记忆系统（`SpacedReviewItem`）且到期的题目，再次执行了原始来源判定（`matchesSource = selectedSources.contains('wrong') && uq?.isWrong == true`）。由于题目做对后 `isWrong` 已变为 false，该题目被直接 `continue` 跳过，导致到期题目永远无法复习，打卡时提示“暂无待刷题目”。
- **当前状态**：`RESOLVED` (移除到期队列中对动态做题对错状态的二次过滤，题目一旦进入间隔记忆曲线，只要未斩卡且在覆盖学科内，均作为到期题目如期调度复习)。

---

### [BUG-15] 桌面端缩放窗口触发横竖屏自适应时 Tab 状态丢失跳回课程页
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`HomePage` 布局自适应 / `PageView` 控制器生命周期
- **代码文件与行号**：[`lib/screens/home_page.dart:92-120`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/home_page.dart#L92)
- **触发条件**：在 macOS 桌面端横屏（>=640px）处于“每日计划”、“统计”或“我的”页面时，横向缩放窗口至竖屏模式（<640px）。
- **根本原因**：桌面宽屏采用 `IndexedStack` 挂载各 Tab，`_pageController` 未挂载并保持 `initialPage: 0`；切回竖屏时 `PageView` 挂载瞬间触发 `onPageChanged(0)`，将 `_selectedIndex` 错误覆盖为 0。
- **当前状态**：`RESOLVED` (在 `HomePage` 构建流程中加入 `_ensurePageController` 动态同步 `initialPage` 与 `jumpToPage`，保证任何尺寸切换下 Tab 均无损保留)。

---

### [BUG-14] Notes 表历史外键指向复数 questions(id) 导致笔记保存失败 no such table: main.questions
- **严重程度**：CRITICAL
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`UserDBHelper` / `NoteService` / SQLite 外键约束
- **代码文件与行号**：[`lib/db/database_helper.dart:255,783`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/database_helper.dart#L255)
- **触发条件**：老数据库升级开启 `PRAGMA foreign_keys = ON` 后，用户在题目详情页或评论页保存任何笔记。
- **根本原因**：老版本 `Notes` 建表语句曾定义为 `FOREIGN KEY (question_id) REFERENCES questions(id)`（指向不存在的复数表名）。当外键开启时，prepare 语句触发 SQLite 报错 `no such table: main.questions`。
- **当前状态**：`RESOLVED` (在 `UserDBHelper.onOpen` 加入 `_repairNotesForeignKey`，自动检测并在事务内重建表外键指向正确的 `Question(id)`，完整无损迁移用户所有笔记)。

---

### [BUG-13] CustomFlashcards 旧库缺失 question_id 列导致闪卡保存失败
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`UserDBHelper` / `SpacedReviewRepository` / `FlashcardEditDialog`
- **代码文件与行号**：[`lib/db/database_helper.dart:262,618`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/database_helper.dart#L262)
- **触发条件**：已生成过旧版 `user_data.sqlite` 的用户在制作新闪卡时。
- **根本原因**：`CustomFlashcards` 增加 `question_id` 时未在 `onOpen` 中对已处于当前版本的用户库做增量补列。
- **当前状态**：`RESOLVED` (在 `UserDBHelper.onOpen` 中加入 `_repairCustomFlashcards` 自愈补齐字段与索引)。

---

### [BUG-12] DailyReviewPage 异步加载完成遗漏 setState 导致界面永久停留在转圈加载
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`DailyReviewPage` 记忆曲线刷题页面
- **代码文件与行号**：[`lib/screens/daily_review_page.dart:91`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/daily_review_page.dart#L91)
- **触发条件**：从每日计划 Tab 或首页卡片点击“开始今日打卡”进入 `DailyReviewPage`。
- **根本原因**：`_loadDailySession` 异步构建刷题会话完成后调用了 `_applySession(session)`，在修改内部变量 `_loading = false` 时遗漏了 `setState(...)` 调用，导致 Flutter 框架未触发重新 build，页面一直处于 initState 初始的 `CircularProgressIndicator` 转圈骨架。
- **当前状态**：`RESOLVED` (已在 `_applySession` 中增加 `if (mounted) setState(...)` 确保状态即时刷新)。

---

### [BUG-11] ReviewPlans 扩展字段未递增用户数据库版本号导致保存计划抛出 SQL logic error
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`UserDBHelper` / `SpacedReviewRepository` / `DailyReviewPlanDialog`
- **代码文件与行号**：
  - [`lib/db/database_helper.dart:240,418`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/database_helper.dart#L240)
  - [`lib/repositories/spaced_review_repository.dart:83`](file:///Users/huzongyao/flutterProjects/yibubang/lib/repositories/spaced_review_repository.dart#L83)
- **触发条件**：已升级到 v14 的旧数据库用户在“计划设置”弹窗点击“保存计划”。
- **根本原因**：`source_types` 与 `covered_subjects` 列在 v14 发布后追加，但数据库版本仍保持为 14；由于 SQLite 仅在当前版本大于原版本时触发 `onUpgrade`，导致已处于 v14 的老库无法执行 `ALTER TABLE ADD COLUMN`。
- **当前状态**：`RESOLVED` (用户库升至 v15 并由 `_onUpgrade` 执行增量迁移；同时在 `onOpen` 与 `savePlan` 增加双重热自愈拦截，发现缺失字段自动补齐)。

---

### [BUG-10] macOS App Sandbox 下多连接打开只读题库引发 SqliteException(6922) disk I/O error
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`DailyReviewService` / macOS 沙盒题库读取
- **代码文件与行号**：
  - [`lib/services/daily_review_service.dart:553`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/daily_review_service.dart#L553)
  - [`lib/db/question_bank_manager.dart:27`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/question_bank_manager.dart#L27)
- **触发条件**：
  1. 用户在 macOS 桌面端运行应用；
  2. 首页已通过 `QuestionBankDatabaseManager` 打开活动题库（如 `dental_final.sqlite`）；
  3. 用户进入“每日计划”Tab 并点击“开始今日打卡”加载题目。
- **根本原因**：
  macOS App Sandbox 在默认非 WAL 模式（`journal_mode = delete`）下，对沙盒容器内的 SQLite 文件施加严格的 POSIX 文件锁（`fcntl(F_SETLK)`）。
  `DailyReviewService` 内部曾绕过 `QuestionBankDatabaseManager`，直接调用底层 `openDatabase(bankPath, readOnly: true)` 打开了同一个题库文件，导致同一进程内创建了两个不同文件描述符的连接（id 2 与 id 3）。
  当新连接执行 `SELECT * FROM Question WHERE id IN (...)` 请求 POSIX 建议共享读锁时，与已持锁的连接发生竞争冲突，内核抛出 SQLite 扩展错误码 `6922` (`0x1B0A` = `SQLITE_IOERR_LOCK`)。
- **实际影响**：进入打卡页面报错打不开，报错信息提示 `disk I/O error (code 6922)`。
- **当前状态**：`RESOLVED`（已在 `QuestionBankDatabaseManager.openBank` 中支持 `validate = false` 快速通道，`DailyReviewService` 全面改用单例连接池复用，杜绝同一文件多句柄打开）。

---

### [BUG-07] 历史配置键 sync_question_bank 跨领域抢占导致三大同步互相踩踏
- **严重程度**：CRITICAL
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`SettingsPage` / `UserDBHelper` 设置初始化 / `YkbSyncService` / `YkbBankSmartSyncService`
- **代码文件与行号**：
  - [`lib/screens/settings_page.dart:675,791`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/settings_page.dart#L675)
  - [`lib/db/settings.dart:70,87`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/settings.dart#L70)
  - [`lib/main.dart:108`](file:///Users/huzongyao/flutterProjects/yibubang/lib/main.dart#L108)
- **触发条件**：
  1. 新安装应用启动初始化设置；或
  2. 用户在设置页切换“做题同步到医考帮”或“启动后自动增量同步题库”。
- **根本原因**：
  历史键名 `sync_question_bank` 原本指代题库管理页进入时是否检查清单（默认 `false`）。
  后来被错误重用：在“做题同步到医考帮”（同步 2）与“启动后自动增量同步题库”（同步 1）中均作为旧键 fallback 或同时覆盖写回。
  导致：
  1. 在 `settings.dart` 初始化时，`sync_question_bank` 的 `false` 污染了 `sync_answers_to_ykb`，导致新设备上做题记录上报医考帮被误初始化为禁用；
  2. 在 `main.dart` 中，静默题库智能同步因 fallback 到该 `false` 而无法自动启动；
  3. 用户修改做题同步或题库同步任意一个开关，会强行将另一个开关的历史 fallback 覆盖。
- **实际影响**：静默题库增量同步无法执行、做题记录无法同步医考帮。
- **当前状态**：`RESOLVED` (已在 `settings.dart`、`settings_page.dart`、`main.dart`、`ykb_bank_smart_sync_service.dart` 中彻底解耦键命名空间，切断交叉污染)

---

### [BUG-06] Android 端 SQLite execute 执行 PRAGMA journal_mode 导致启动崩溃
- **严重程度**：CRITICAL
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`UserDBHelper.onConfigure` / 全局数据库初始化
- **代码文件与行号**：[`lib/db/database_helper.dart:243`](file:///Users/huzongyao/flutterProjects/yibubang/lib/db/database_helper.dart#L243)
- **触发条件**：旧版本（2.0.5）升级至 2.1.1 后在 Android 设备上首次打开应用。
- **根本原因**：
  在 Android 原生端，`SQLiteDatabase.execSQL` 会判定 `PRAGMA journal_mode = WAL`（返回当前模式字符串）为 `STATEMENT_SELECT`，抛出 `Queries can be performed using SQLiteDatabase query or rawQuery methods only` 异常；桌面端（基于 C FFI）无此拦截，导致该问题逃逸出桌面测试。
- **实际影响**：Android 设备升级后首次进入应用崩溃，首页与课程列表白屏无法打开。
- **当前状态**：`RESOLVED` (已通过 Commit `4c116c8` 修复，改为 `rawQuery` 并加上异常防护)

---

### [BUG-01] 题目方格页筛选菜单保存时序倒置，导致筛选配置无法持久化
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`QuestionGridPage`（筛选抽屉）
- **代码文件与行号**：[`lib/screens/question_grid_page.dart:741-775`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_grid_page.dart#L741-L775)
- **触发条件**：用户在题目方格页点击筛选抽屉，切换“斩题”（全部/已斩/未斩）、“题型”或“分类”。
- **根本原因**：
  在筛选选项点击回调中，`saveSettings()` 被调用的位置在 `setState` 赋值**之前**：
  ```dart
  (value) {
    saveSettings(); // 此处异步读取类成员变量 cutType，此时 cutType 仍为旧值！
    setState(() {
      cutType = cutTypes.indexOf(value); // 此时才赋新值！
    });
  }
  ```
  `saveSettings()` 读取了旧变量，将上一次的状态异步写入了 `SharedPreferences`。
- **实际影响**：用户切换了筛选条件后，一旦返回上一页或重新进入，筛选条件立即回退到上一次的旧状态，造成用户严重困惑。
- **关联 Sprint**：Sprint 1 (P0)
- **当前状态**：`RESOLVED` (已将 `setState` 调整至 `saveSettings()` 之前执行，确保读取最新赋值)

---

### [BUG-02] 单日统计详情弹窗在 Context 销毁后调用路由跳转引发崩溃
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`StatisticsPage`（日统计明细弹窗 `_DailyStatsDetailDialog` / `_DayDetailSheet`）
- **代码文件与行号**：[`lib/screens/statistics_page.dart:1120-1123`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/statistics_page.dart#L1120-L1123)
- **触发条件**：用户在学习统计看板点击热力格子墙的某一天，在弹出的统计详情卡片中点击“查看全部题目”。
- **根本原因**：
  ```dart
  onPressed: () {
    Navigator.pop(context); // 立即将当前弹窗出栈，导致该 context 的 Element 树被停用 (deactivated)
    pushAdaptiveModalPage(
      context, // 使用已失活的 context 执行路由查找与主题解析！
      builder: (_) => AnsweredRecordsPage(...),
    );
  }
  ```
- **实际影响**：在 Debug 模式或较严格的 Flutter 运行时抛出 `Looking up a deactivated widget's ancestor is unsafe` 异常或红屏，页面无法正常跳转。
- **关联 Sprint**：Sprint 1 (P0)
- **当前状态**：`RESOLVED` (在 `_DayDetailSheet` 增加 `onViewAll` 回调，由持有有效上下文的外层负责 `pushAdaptiveModalPage`，并加入 `mounted` 保护)

---

### [BUG-03] 桌面端自适应模态弹出弹窗（`pushAdaptiveModalPage`）丢失子页面返回值
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`platform_adaptive.dart`（桌面端自适应路由）
- **代码文件与行号**：[`lib/common/platform_adaptive.dart:172-178, 204-208`](file:///Users/huzongyao/flutterProjects/yibubang/lib/common/platform_adaptive.dart#L172-L178)
- **触发条件**：在桌面端/宽屏环境下通过 `final res = await pushAdaptiveModalPage<T>(...)` 推入子页面，子页面使用 `Navigator.of(context).pop(result)` 返回业务结果。
- **根本原因**：
  `_AdaptiveModalContainerState` 内部的 `_AdaptiveModalNavigatorObserver` 在检测到内部首个页面被关闭时：
  ```dart
  _observer = _AdaptiveModalNavigatorObserver(
    onDismissModal: () {
      if (mounted && Navigator.of(widget.dialogContext).canPop()) {
        Navigator.of(widget.dialogContext).pop(); // 未将子路由的 result 传递给外层 Dialog
      }
    },
  );
  ```
  外层 `Dialog` 直接无参 `pop()`，导致 `pushAdaptiveModalPage` 的 Future 始终完成为 `null`。
- **实际影响**：破坏了跨平台契约一致性，移动端可获取到返回值，桌面端返回值全部丢失。
- **关联 Sprint**：Sprint 1 (P0)
- **当前状态**：`RESOLVED` (在 observer 中提取 `route.currentResult` 并冒泡传递给 `onDismissModal(result)`，外层 `Dialog` 及 `PopScope` 均正确带参 `pop(result)`)

---

### [BUG-04] 本地做题记录导入后未联动重算章节统计，界面对错计数失真
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`settings_page.dart` / `record_sync_service.dart`
- **代码文件与行号**：[`lib/screens/settings_page.dart:214-220`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/settings_page.dart#L214-L220)
- **触发条件**：用户在设置页点击“导入做题记录（替换或合并）”。
- **根本原因**：`RecordSyncService.importMerge` 仅合并了 `Question` 与 `Activities` 表。而存储科目/章节做对做错总数的 `IdentitySubject` 与 `IdentityChapter` 表未被重新计算。CloudSync 服务中显式调用了 `rebuildQuestionCount()`，而本地导入被遗漏。
- **实际影响**：导入成功后，题目网格内状态已变，但目录与章节树的完成度百分比和对错题数依然停留在旧值，除非用户手动去开发者页面点击“重新统计刷题数量”。
- **关联 Sprint**：Sprint 1 (P0)
- **当前状态**：`RESOLVED` (在 `importMerge` 与 `importReplace` 执行完毕后自动调用 `await rebuildQuestionCount()`，并带有异常保护)

---

### [BUG-05] 护理期末等主观题（填空/名词解释/简答等）不可答且被强制判错
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`QuestionOptionsView` / `QuestionDetailController` / `QuestionHeaderView` / `QuestionExplainView`
- **代码文件与行号**：[`lib/screens/question_detail/question_options_view.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_detail/question_options_view.dart)、[`question_detail_controller.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_detail/question_detail_controller.dart)
- **触发条件**：在护理期末或跨库搜索中打开题型为 3~7 的非选择题（护理题库包含近万道主观题）。
- **根本原因**：`QuestionOptionsView` 遇到非 '1'、'2' 题型直接渲染 `Text('未知的题目类型')`，没有提供文本输入或记忆模式视图；用户点击提交后，因 `question.answer` 为空字符串，系统直接将 `userQuestion.status` 标记为 2（回答错误）。
- **实际影响**：近 15% 的护理专业题库处于死锁不可用状态。
- **关联 Sprint**：Sprint 2
- **当前状态**：`RESOLVED` (已在 `Question` 模型中识别主观题与题型中文映射；在 `QuestionOptionsView` 中实现参考答案核对与自评模式【已掌握/未掌握】；在 `QuestionHeaderView` 对填空题进行智能挖空；在所有页面的筛选 UI 中同步新增了填空题、名词解释、简答题、论述题、病例分析等题型支持；并在交卷判定中切断了强制判错)

---

### [BUG-08] 统计接口 500 异常未打印响应原始 Body 且 appId 空值导致异常
- **严重程度**：MEDIUM
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`request.dart` / `QuestionStatView`
- **代码文件与行号**：
  - [`lib/common/request.dart:69-77`](file:///Users/huzongyao/flutterProjects/yibubang/lib/common/request.dart#L69-L77)
  - [`lib/screens/question_detail/question_stat_view.dart:18-25`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/question_detail/question_stat_view.dart#L18-L25)
- **触发条件**：题目 `appId` 为空时加载题目统计或服务端返回 500 空响应体。
- **根本原因**：
  1. `basicReq` 中 `app_id` 为空时未正确 fallback，且 GET 查询参数将 `null` 转成了字符串 `"null"`，导致服务端无法识别返回 500；
  2. 500 时服务端返回空 Body，`json.decode("")` 抛出 `FormatException: Unexpected end of input`，且 catch 块未打印原始 Body 与状态码详情；
  3. `QuestionStatView` 未校验 `response['data']` 是否为 `Map` 即强行解析。
- **当前状态**：`RESOLVED` (已在 `basicReq` 补充非 200 与解析异常的 raw body 调试日志输出、安全空响应兜底，且在 `QuestionStatView` 补充了 `appId` 降级与 Map 类型保护)

---

### [BUG-09] GitHub 镜像站因 Cloudflare 防护或失效返回 HTTP 403 与更新中断
- **严重程度**：HIGH
- **置信度**：HIGH (VERIFIED)
- **受影响模块**：`GitHubProxyConfig` / `AppUpdateService` / `QuestionBankRepository`
- **代码文件与行号**：
  - [`lib/common/github_proxy.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/common/github_proxy.dart)
  - [`lib/services/app_update_service.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/services/app_update_service.dart)
  - [`lib/repositories/question_bank_repository.dart`](file:///Users/huzongyao/flutterProjects/yibubang/lib/repositories/question_bank_repository.dart)
- **触发条件**：国内网络环境下检查软件更新或题库更新。
- **根本原因**：
  1. `ghps.cc` 开启了 Cloudflare 5 秒盾与 Turnstile 质询，客户端非浏览器请求 100% 返回 HTTP 403；
  2. `mirror.ghproxy.com` 证书失效断开；`ghproxy.net` 在部分运营商网络下受限；
  3. `AppUpdateService` 的 GET 请求不合规地附加了 `Content-Type: application/json` 请求头且缺少标准 User-Agent，极易触发 CDN/WAF 的爬虫拦截；
  4. 缺少多源自动候选轮询机制，任一镜像站异常即阻断流程。
- **当前状态**：`RESOLVED` (移除了失效镜像源，新增当前高可用的 `gh-proxy.com`，自动迁移旧配置；规范了 `User-Agent` 与 `Accept` 请求头；构建了“用户选定源 -> 推荐镜像 -> jsDelivr CDN -> 官方直连”多级自动兜底降级链)

---

## 2. 潜在风险清单 (Potential Risks)

### [RISK-01] 题库安装导入阶段整文件读入内存存在 OOM 隐患
- **严重程度**：MEDIUM
- **置信度**：HIGH (OBSERVED)
- **代码位置**：[`lib/repositories/question_bank_repository.dart:383`](file:///Users/huzongyao/flutterProjects/yibubang/lib/repositories/question_bank_repository.dart#L383)
- **风险描述**：`final bytes = await sourceFile.readAsBytes()` 将 176MB 的 SQLite 文件一次性加载至连续的内存数组中。低端 Android 设备（2GB~3GB RAM）面临瞬间 OOM Crash 风险。
- **建议**：改用流式散列计算（`crypto` 流式 Chunk 处理）与流式拷贝。
- **关联 Sprint**：Sprint 2

### [RISK-02] 评论接口错误响应处理缺乏类型防护
- **严重程度**：LOW
- **置信度**：MEDIUM (OBSERVED)
- **代码位置**：[`lib/screens/comment_page.dart:86-94`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/comment_page.dart#L86-L94)
- **风险描述**：`if (response['code'] == 309)` 仅检查整型，若返回 String `'309'` 或遭遇非 200 网络异常时，`response['data']` 为 `null`，执行 `CommentData.fromJson(response['data'])` 会抛出空类型转换异常。
- **关联 Sprint**：Sprint 2
- **当前状态**：`RESOLVED` (已对 code == 309 与 '309' 增加双类型判定，并对 response['data'] 进行了严格 Map 类型与 null 保护)

### [RISK-03] 全库搜索无全文索引（FTS），大数据量下存在线性卡顿风险
- **严重程度**：LOW
- **置信度**：MEDIUM (OBSERVED)
- **代码位置**：[`lib/repositories/question_search_repository.dart:156-175`](file:///Users/huzongyao/flutterProjects/yibubang/lib/repositories/question_search_repository.dart#L156-L175)
- **风险描述**：跨多题库并发执行 5 列文本的 `LIKE '%...%'` 全表扫描。当用户输入 `%` 等通配符时，扫描耗时急剧上升。
- **关联 Sprint**：Sprint 4 (后续复杂演进，暂缓处理)

### [RISK-04] 新设备首次运行可能因 `containsKey` 保护过度导致无法保存最后进度
- **严重程度**：LOW
- **置信度**：MEDIUM (OBSERVED)
- **代码位置**：[`lib/screens/choosed_subjects_page.dart:106-115`](file:///Users/huzongyao/flutterProjects/yibubang/lib/screens/choosed_subjects_page.dart#L106-L115)
- **风险描述**：`_saveLastProgress` 包含 `if (prefs.containsKey('lastSubjectId'))`。一旦缓存被外部清空导致 key 不存在，将永远无法重新创建该 key。
- **关联 Sprint**：Sprint 1 协同优化
- **当前状态**：`RESOLVED` (已移除包含性拦截，改为直接写入持久化)

## 2026-11-07 用户反馈切片 A：订阅格式与更新设置

- 支持 HTTPS ZIP/SQLite 直链和 JSON 清单，按响应文件头识别，解决二进制被 UTF-8 JSON 解码导致的异常；已下载用户 Gitee 临床题库真实 ZIP 并通过只读完整性/根信息检查。
- 订阅列表可以修改地址；单库订阅来源可独立覆盖，不影响共享清单的其他库。自动更新移至设置，检查间隔支持预设与自定义 1～10080 分钟，修改后重设计时器。
- 验证更正：f86db66 提交时实际为 1 条 lint、71 通过 / 1 失败（设置测试遗留 Timer），此前记录的全绿不准确。后续补全大括号并在测试结束前停止应用定时器；本次重新验证 flutter analyze --no-pub 0 issues、flutter test --no-pub 72/72。真实 Gitee 响应由前一切片临时探针检查，未纳入仓库。
- 下一切片：详情视觉重做、学科/去重题数/空节点隐藏、管理页详情旁更新/导出图标。

## 2026-11-07 用户反馈切片 D：最终回归

- 题库校验、订阅匹配和增量合并错误统一使用“学科”，不再向用户显示“根 identity”。
- 新增真实 SQLite 手动订阅更新回归：自动检查跳过被冻结内容，单库手动检查刷新来源并新增题目；全局个人答案保留，ATTACH 重算课程对错数，重复检查不再安装、不新增履历。
- 实际下载用户 Gitee 临床期末 ZIP（25,939,926 字节，SHA-256 3db37a844ec0f8ac3688a7fcf7967de1a8adf8f787a3e4801dd1276893383061），57,346 题、40 课程、1,137 章节、学科 20101。只读完整性检查通过；用原始响应文件字节运行 Flutter 临时探针，验证订阅识别→注册→安装→手动检查，保留发布版本 3.0.0，未出现 UTF-8 异常。临时探针已删除，不作为常规测试依赖。
- 实际最终验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 85/85。真实 Gitee 下载/安装探针额外 1/1 通过。
- 用户 9 项反馈实现完成；下一步是用户视觉验收与真实账号创建（含 203 弹窗）、平台原生文件保存验收。

## 2026-11-07 统一题库管理修复（已解决）

| 编号 | 原问题与影响 | 最终处理 | 验证 |
| --- | --- | --- | --- |
| QBM-FIX-01 | 订阅保存触发所有来源下载，检查/安装与完整性混杂；不同 URL 同 bank_id 阻断刷新 | 配置零网络，check 只检查，confirmSource/安装独立；主/候选模型与失败隔离 | bank_source_catalog_test、bank_management_flow_test 请求计数与真实 UI 操作 |
| QBM-FIX-02 | 临时包销毁导致重复下载；同一任务的超限缓存可能提前清理 | 持久化有界缓存、摘要复核、活动 lease，同一安装/确认任务保持租约；半包取消清理 | bank_artifact_cache_test：并发/持久化/损坏/超限单次下载/取消 |
| QBM-FIX-03 | 本地合并 hash 与上游 hash 不同被误认为新发布，重复要求合并；自动覆盖有风险 | BankContentState 独立发布基线/本地修订；相同发布不安装，同版本变更/回退显式确认 | bank_release_state_test：重复发布、回退、缺摘要、旧库基线、自动保护/事务回滚 |
| QBM-FIX-04 | 详情保存新链接时 setState 闭包返回 _load() Future，引发 Flutter 断言 | setState 使用同步 block；页面绑定服务负责来源选择与通知，保存不联网 | bank_management_flow_test 390px/1000px 保存/检查/显式切换全过程 |
| QBM-FIX-05 | 远端同 bank_id 可更改已安装学科，引发内容归属错误 | selectSource / install 在下载前及冲突回调拒绝不匹配学科 | bank_release_state_test：无新增下载、原 hash/学科/履历保持 |
| QBM-FIX-06 | 自动检查结束后打开的管理页仍显示旧状态 | 服务 ChangeNotifier，管理/详情/来源页订阅并在 dispose 移除 | bank_management_flow_test：独立后台检查即时更新可见状态 |

上述均为 RESOLVED + TESTED；未新增未解决缺陷。既有 RISK-01 大 ZIP 内存、FTS、真实账号与原生文件选择器实机验收边界继续保留。

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


### QBM-PERF-01：创建页每次勾选数秒卡顿（RESOLVED / TESTED）

完整树递归挂载、保留全部 ExpansionTile 状态及整页刷新导致大目录卡顿；改为可见行懒加载与预索引/局部通知。测试覆盖 4,380 节点、无关兄弟不重建、父子联动与滚动后选择，最新 105/23/14ms；性能提交 3d6287b。
