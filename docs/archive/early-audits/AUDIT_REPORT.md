# AUDIT_REPORT.md - 医不帮全量技术审计与基线评估报告 (归档)

> **报告性质**：历史首期全量代码技术审计归档基线 (READ-ONLY AUDIT)
> **审计基线版本**：Commit `3c33fb9cd955e3cd4bf071b492e422e371396cef` (Branch: `main`)
> **审计时间**：2026-10-31
> **审查范围**：`yibubang` 客户端完整源码（72 个 Dart 文件，25,835 行代码）、5 个测试文件、后端 Cloudflare D1 增量同步服务、CI/CD 工作流及数据生产端 Python 脚本。

---

## 1. 审计执行摘要

医不帮（yibubang）采用解耦的“独立只读题库 SQLite + 全局共享可写用户库 `user_data.sqlite`”架构，核心业务框架健全，在离线刷题性能与多题库管理上有较好的设计考量。

经过全量代码审计与调用链追踪，发现早期技术债务文档（`improve.md`）中的诸多高危问题（如斩题状态撕裂、未捕获的图片网络请求、微秒伪随机算法哈希碰撞、1403行单体类以及 Notes 僵尸表）在近期提交中已被显著自愈与重构。同时，审计发现了 5 个新增已确认缺陷（BUG-01 ~ BUG-05）、4 个潜在隐患（RISK-01 ~ RISK-04）以及 4 项技术债务。

---

## 2. Git 与工作区基线事实

- **当前分支**：`main`
- **HEAD Commit**：`3c33fb9cd955e3cd4bf071b492e422e371396cef`
- **Commit 标题**：`feat(ui): 优化桌面端导航与自适应模态弹出内置嵌套路由`
- **远端同步状态**：本地领先 `origin/main` 3 个提交（`6392f03`、`d51a660`、`3c33fb9`）
- **工作区未暂存文件**：无（`working tree clean`）
- **未跟踪符号链接**：`yibubang-web` -> `/Users/huzongyao/WeChatProjects/yibubang-web`（不影响主项目）

---

## 3. 系统架构与核心事实

1. **内容只读与用户可写物理分离**：各专业题库文件在客户端以 `readOnly: true` 打开，禁止向题库写入任何内容；用户作答、收藏、斩题、做题用时（`duration`）、作答流水（`Activities`）与笔记一律写入 `user_data.sqlite`。
2. **全局 `question_id` 契约**：同道题目跨题库共享同一份作答与收藏状态，`Question` 表主键唯一。
3. **文件指纹持久化加速**：采用 `size:modifiedMilliseconds` 指纹缓存，冷启动跳过整库扫描，耗时低于 5ms。
4. **ATTACH DATABASE 跨库重算**：使用 SQLite 原生 `ATTACH` 完成进度自愈，避免 Dart 内存多重循环卡顿。

---

## 4. 全量文件审计清单 (72/72 VERIFIED)

工作区共 72 个 Dart 文件，行数总计 25,835 行，全部完成逐行与调用链审查：
- 入口：`lib/main.dart` (169行)
- 通用基础设施：`lib/common/` (10 个文件，844 行)
- 数据与存储：`lib/db/` (5 个文件，1,626 行)
- 业务模型：`lib/models/` (11 个文件，2,284 行)
- 业务仓储：`lib/repositories/` (2 个文件，1,262 行)
- 核心服务：`lib/services/` (5 个文件，2,628 行)
- 通用组件：`lib/widgets/` (7 个文件，893 行)
- 页面层：`lib/screens/` (15 个主页面文件 + 9 个详情子视图，16,129 行)

---

## 5. 缺陷与风险汇总

### 5.1 已确认缺陷 (Confirmed Bugs)
1. **[BUG-01 | HIGH]** `question_grid_page.dart:741-775` 筛选抽屉菜单中，`saveSettings()` 先于变量赋值执行，导致用户筛选偏好无法保存至 `SharedPreferences`。
2. **[BUG-02 | HIGH]** `statistics_page.dart:1120-1123` 日统计详情弹窗在调用 `Navigator.pop(context)` 后立即使用失活的 `context` 进行路由跳转，抛出 Element 树失活异常。
3. **[BUG-03 | MEDIUM]** `platform_adaptive.dart:172-178` 桌面端自适应模态弹出弹窗关闭时未向外层传递返回值，导致子页面回传数据丢失（恒为 null）。
4. **[BUG-04 | MEDIUM]** `settings_page.dart:214-220` 本地做题记录导入（替换/合并）后未触发 `rebuildQuestionCount()`，界面进度数字未刷新。
5. **[BUG-05 | MEDIUM]** `question_options_view.dart:170` 护理期末等主观题（填空/名词解释/简答等）显示“未知的题目类型”，且点击提交直接判错。

### 5.2 潜在风险清单 (Potential Risks)
1. **[RISK-01 | MEDIUM]** `question_bank_repository.dart:383` 导入题库时 `readAsBytes()` 一次性读入 176MB 文件，低配手机面临 OOM 风险。
2. **[RISK-02 | LOW]** `comment_page.dart:86-94` 评论接口 309 错误比对类型不严谨，缺少 null 转换防御。
3. **[RISK-03 | LOW]** `question_search_repository.dart:156` 全库搜索无 FTS 全文索引，关键词包含 `%` 时扫描较重。
4. **[RISK-04 | LOW]** `choosed_subjects_page.dart:106` `_saveLastProgress` 包含 `containsKey` 保护过度，缓存重置时可能无法写入最后进度。

### 5.3 技术债务清单 (Technical Debt)
1. **[DEBT-01]** `Cards` 表为未被任何业务使用的僵尸表。
2. **[DEBT-02]** `database_helper.dart:266` 在 `oldVersion < 2` 内部误粘了 `oldVersion < 10` 的逻辑。
3. **[DEBT-03]** `home_page.dart:147` 与第 68 行存在重复的题目对错重算逻辑。
4. **[DEBT-04]** `flutter analyze` 报告了 7 处 linter 警告（弃用的 Radio 参数与私有类型暴露）。

---

## 6. 测试体系评估

- 现有有效测试：主键防碰撞测试、版本对比测试、斩题交互测试、云同步模型测试、检索模型测试。
- 现有失效测试：`widget_test.dart`（未维护）。
- CI 缺口：GitHub Actions 工作流完全未集成静态检查与单元测试。

---

## 7. 审计结论与工作区安全确认

本次代码技术审计严格在只读模式下执行，确认工作区完全保持 clean，未修改任何业务源码与依赖配置。全量审计结果已完整归档至本项目知识库中。
