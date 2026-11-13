# 医不帮 (yibubang) AI 编程代理工作规则与行动准则

> **适用范围**：所有接入本项目进行代码理解、Bug 修复、需求开发、性能优化和技术重构的 AI 编程代理（Antigravity Agent）。
> **基准知识库索引**：[docs/antigravity/README.md](README.md)

---

## 1. 启动任务前的强制阅读流程

在接收任何用户指令后，**禁止直接盲目搜索或直接修改代码**。必须严格遵循以下阶段化阅读规范：

1. **查阅当前开发基线与交接状态**：
   - 必读文件：[`docs/antigravity/DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) 与 [`docs/antigravity/SESSION_HANDOFF.md`](SESSION_HANDOFF.md)。
   - 明确当前所处阶段（例如当前为：审计完成，知识库已建立，Sprint 1 待开始）、已分配的 Bug ID / Sprint 范围。
2. **按任务类型精准定向读取知识库**（禁止每次无差别全量加载所有文档以浪费上下文）：
   - **涉及架构、数据流与生命周期**：查阅 [`docs/antigravity/ARCHITECTURE.md`](ARCHITECTURE.md)。
   - **涉及功能实现状态与业务逻辑**：查阅 [`docs/antigravity/FEATURE_MATRIX.md`](FEATURE_MATRIX.md)。
   - **涉及 Bug 修复与排障**：查阅 [`docs/antigravity/KNOWN_ISSUES.md`](KNOWN_ISSUES.md)。
   - **涉及技术决策背景与约束**：查阅 [`docs/antigravity/DECISIONS.md`](DECISIONS.md)。
   - **涉及自动化测试与验证**：查阅 [`docs/antigravity/TESTING_STRATEGY.md`](TESTING_STRATEGY.md)。
   - **涉及数据库底层细节**：参考 [`docs/antigravity/database_current.md`](database_current.md)。

---

## 2. 代码理解与事实核查准则

1. **以实际源码与运行时调用链为唯一事实依据**：
   - README、注释、TODO、Git 提交信息以及历史讨论只能作为辅助推断证据。
   - **严禁将 IMPLEMENTED 视为 VERIFIED**：代码中存在某个方法、按钮或类，不等于业务链条已闭环。必须追踪“用户操作 -> UI -> Controller -> Repository -> SQLite / Network”完整链路。
2. **严禁编造任何行号与类名**：
   - 引用代码必须提供确切文件路径（如 `lib/screens/question_grid_page.dart:741`）与函数名，并在输出前再次校验。

---

## 3. 工作区保护与修改边界铁律

1. **Git 现场保护原则**：
   - 开始任何写操作前，必须执行只读命令检查当前 Git 分支、HEAD commit 和未暂存修改。
   - **严禁擅自执行 `git checkout .`、`git reset` 或丢弃用户的任何未提交变更**。
   - 未经用户明确授权，**严禁自动提交 Git commit**。
2. **禁止擅自扩大修改范围**：
   - 一次修改只针对当前指定的单一目标（如单个 Bug ID）。
   - 禁止在修复 Bug 时“顺手重构无关模块”、“格式化整个目录”或“自动升级 pub 依赖”。
   - 未经用户明确书面授权，严禁进行架构级大规模重构。
3. **保持既有注释与文档的完整性**：
   - 除非特定注释与修改内容直接冲突，否则必须保留原有业务注释与 Docstrings。

---

## 4. 医不帮核心业务与底层架构铁律

所有涉及代码编写的会话，必须无条件遵守以下系统契约：

1. **只读题库与可写用户数据物理隔离**：
   - 所有题库文件（`QuestionBank/<bank_id>/<bank_id>.sqlite`）在客户端**只能以只读方式（`readOnly: true`）打开**。严禁编写任何向题库文件执行 `INSERT`、`UPDATE`、`DELETE` 或 DDL 变更的代码。
   - 用户的所有作答、收藏、斩题、用时（`duration`）、做题流水（`Activities`）与笔记一律落入 `user_data.sqlite`。
2. **全局 `question_id` 跨库唯一与共享契约**：
   - 题目 ID 在全系统唯一。同一题目出现在不同题库中时，共享同一份用户状态。
   - `Question` 表的主键永远是单列 `id`，禁止擅自将其改为 `(bank_id, id)` 联合主键。
3. **跨库数据聚合必须遵循 ATTACH 规范**：
   - 跨题库与用户库的对错总数重算，必须使用 SQLite 原生 `ATTACH DATABASE`（参考 `lib/db/data_transfer.dart` 中的 `rebuildQuestionCount`），严禁在 Dart 内存中进行低效的多重循环拼接。
4. **Context 与路由生命周期安全性**：
   - 严禁在 `Navigator.pop(context)` 后继续使用该失活的 `context` 执行跳转（如 `pushAdaptiveModalPage`）。
   - 桌面端模态弹窗（`pushAdaptiveModalPage`）若包含子路由交互，必须确保返回值能正确冒泡至外层 Dialog 调用方。

---

## 5. 跨平台兼容性规范

项目原生支持 Android、macOS、Windows、Linux（iOS 适配中）：
1. **文件路径处理**：严禁硬编码 `/` 或 `\`，必须统一使用 `path` 包的 `p.join(...)`。
2. **本地文件选择与存储**：
   - 导出与导入 zip 时，注意移动端（外部存储目录/SAF）与桌面端（`FilePicker.saveFile` 仅返回路径）的平台差异。
3. **布局自适应契约**：
   - 桌面宽屏（>=640px）：优先采用居中卡片 Dialog、NavigationRail 侧栏。
   - 移动窄屏：保持底部抽屉（BottomSheet）与底部导航栏（NavigationBar）。

---

## 6. 会话结束与交接要求

在每次开发会话结束或上下文即将达到上限时，AI 代理必须完成以下闭环动作：
1. **复核实际修改**：执行 `git status` 与 `git diff`，确认变更仅限于当前任务范围。
2. **同步更新知识库文档**：
   - 若完成了任务：更新 [`docs/antigravity/DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) 中的任务状态。
   - 若修复了 Bug：更新 [`docs/antigravity/KNOWN_ISSUES.md`](KNOWN_ISSUES.md) 的状态与验证记录。
   - 若改变了功能行为：更新 [`docs/antigravity/FEATURE_MATRIX.md`](FEATURE_MATRIX.md)。
   - 若发现新技术债：记录至 [`docs/antigravity/TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md)。
   - **必填输出**：更新 [`docs/antigravity/SESSION_HANDOFF.md`](SESSION_HANDOFF.md)，明确写明本次完成项、未完成项与下一次会话的第一步操作。
