# 医不帮使用与构建说明

2026-11-13 · [English](README_EN.md) · [文档总目录](../README.md) · [当前进度](../CURRENT_STATUS.md)

医不帮面向医学生，提供离线题库、练习/测试/背题、收藏错题、笔记、每日复习与学习统计。独立题库按需安装，个人作答在本地用户库保存；同一题目跨题库共享状态。

## AI搜索与教材

底栏默认顺序为课程→每日计划→AI搜索→统计→我的；可在导航设置重排或隐藏。AI搜索支持流式回答、追问、修改重试、停止和本机会话管理。题目引用打开已安装的原题；教材引用打开对应版本/PDF物理页。

设置→通用下方「AI搜索」提供回答模型、问题改写、流式输出、检索条目数和教材/题目比例。默认改写/流式开启，条数12、教材8/题目4；条数可调1–25。每日200额度，基础1/改写2/流式3；默认最多66次完整高级提问，余2可换模式使用。

教材检索入口在AI页面右上书本按钮。支持书名筛选、关键词高亮/缩略图、原页缩放/翻页/跳页与缓存离线阅读。桌面Shift+Enter发送问题，阅读器左右键翻页。AI生成需要联网；本机会话和已缓存页可离线查看。教材OCR/符号与医学回答仍需对照原文核实。

[AI手册](../ai-search/README.md) · [检索数量](../ai-search/RETRIEVAL_LIMITS.md) · [模型和费用](../ai-search/COSTS_AND_BUILTIN_MODELS.md) · [教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)

## 平台与下载

支持Android、macOS、Windows、Linux，iOS适配中。当前源码版本2.2.4+214；AI/教材改动已完成Debug构建和独立后端部署，详见 [v2.2.4 发布说明](../release-notes/v2.2.4.md)。

[GitHub Releases](https://github.com/nanguaguag/yibubang/releases) · [Gitee镜像](https://gitee.com/pumpkin_melon/yibubang/releases)

## 从源码构建

要求以[pubspec.yaml](../../pubspec.yaml)为准：Flutter≥3.32.0、Dart≥3.8.0且<4.0.0。以下命令从仓库根目录执行：

```sh
flutter pub get
flutter run -d macos
flutter build apk --debug
```

其他平台安装相应Flutter工具链后使用标准flutter build命令。默认AI endpoint已内置；部署自己的服务可用`--dart-define=AI_SEARCH_ENDPOINT=https://你的服务地址`覆盖。Google凭据仅服务端保存，不写入App。

## 数据和协作

用户库schema25，题库schema1。题库文件只读，用户状态单独保存；AI会话不加入现有跨设备同步。同步协议v2服务端发布/真实账号验证仍待独立处理；不要把已实现客户端等同于已完成线上同步验收。

[开发交接](../antigravity/SESSION_HANDOFF.md) · [架构](../antigravity/ARCHITECTURE.md) · [数据库](../antigravity/database_current.md) · [测试](../antigravity/TESTING_STRATEGY.md)

[Telegram社区](https://t.me/yibubang) · [MIT License](../../LICENSE)
