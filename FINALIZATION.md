# 2.1.0+210 收尾记录（2026-10-31）

## 来源与保全

- 基线：`9d6ca62`，main 保持原位置。
- 工作分支：`codex/finalize-smart-sync`。
- 仓库原有快捷键、记录拉取、鉴权和题号修复先保存为 `345525f`。
- 智能同步来源：桌面 `yibubang-src-smart-sync.zip`。
- 源码快照 SHA-256：`982730342fef8245f8b5ae61d371c5b40063201b2cbc74355cc66ff4bd10a381`。
- 原设计与当时手工实测见 `SMART_SYNC_DESIGN.md`；其中实测数据属于 10-30 的独立开发线，不代表本次执行了线上同步。
- 旧根目录构建包已归档移出源码树，源码仓库忽略 `*.zip`。

## 合流结果

- 保留快捷键配置、设置页、输入框和弹窗防误触、原始章节题号、斩题内容显隐。
- 保留登录资料可缺失、旧账号字段清理和请求日志降噪。
- 导入 DES/CBC 解密、全量题库重建、智能增量同步和笔记外键兜底。
- 用户库升级到 v11；从 v9 升级先补 v10 队列字段，再建 v11 两张状态表。
- 做题记录只保留一套合并实现，提供单例入口及显式题库入口；按叶子身份一次请求全部记录，不逐章拉取。
- 自动拉取遵守设置；手动拉取可绕过自动开关及节流；登录触发只绕过节流。
- 拉取节流按账号、题库隔离，部分请求失败不会更新成功时间；已有本地答案优先。
- 启动时鉴权通过后再执行自动拉取和智能同步；智能同步失败后可定时续传并遵守退避。
- 目录请求失败直接中止，不保存成空目录；目录请求同样受请求预算限制。
- 每轮增量题库版本从基础版本生成，避免反复叠加 `+delta` 后缀。

## 验证

- 全量 `flutter test`：36 项通过。
- 智能同步专项：9 项通过，覆盖 ID 漂移映射、新章节隔离、已保存映射、题目重合度、内容哈希、续传顺序、损坏队列恢复，以及 v9/v10→v11 数据保留。
- `flutter analyze --no-fatal-infos`：通过，0 error / 0 warning；保留 8 条原有 info（旧页面 State 类型、key、Radio API 弃用及 forEach 风格）。
- Android Release：已尝试，因本机没有 Android SDK 而失败，尚未验证。现有 Android CI 已补静态检查和全量测试，提交 PR 后可在 CI 构建 APK。
- Windows Release：构建成功；产物版本 2.1.0+210。发布包、源码归档、依赖锁和验证日志位于构建产物输出目录。

## 本地复现

Flutter SDK 环境要求：3.47.x / Dart 3.13.x。

```powershell
# 确保 flutter 命令位于系统 PATH 中
flutter --no-version-check pub get
flutter --no-version-check analyze --no-fatal-infos
flutter --no-version-check test
flutter --no-version-check build windows --release
# 需先安装并配置 Android SDK / Java：
flutter --no-version-check build apk --release --android-skip-build-dependency-validation
```

本次没有执行线上题库同步，也未触碰实际用户数据。发布清单 `yibubang_update.json` 保留已发布的 v2.0.5 链接；等新版本资产正式发布后由发布流水线更新，避免产生不可下载的升级链接。
