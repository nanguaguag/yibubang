# 医不帮文档目录

更新时间：2026-11-13。先读[当前进度](CURRENT_STATUS.md)，开发会话再读[开发状态](antigravity/DEVELOPMENT_STATUS.md)与[交接清单](antigravity/SESSION_HANDOFF.md)。当前代码/线上验证与历史审计分开维护，历史报告里的旧版本、费用入口和未实现描述不能作为现在的状态。

| 目录/入口 | 内容 |
| --- | --- |
| [中文使用说明](project/README.md) / [English](project/README_EN.md) | 功能、平台、安装、构建与使用边界 |
| [AI 搜索手册](ai-search/README.md) | App 操作、部署、配额、防滥用和本地会话 |
| [检索数量](ai-search/RETRIEVAL_LIMITS.md) | 1–25条证据、来源比例、Google参数和覆盖边界 |
| [模型与费用](ai-search/COSTS_AND_BUILTIN_MODELS.md) | 内置模型、专项赠金、Cloud Run/Firestore/R2/Worker估算 |
| [AI 验证记录](ai-search/VALIDATION.md) | 最新357项Flutter/39项后端、线上25条与构建证据 |
| [知识库手册](knowledge-base/README.md) | 本地构建、增量导入Google、Embedding/向量库迁移 |
| [教材实施](knowledge-base/TEXTBOOK_EXECUTION.md) | 53本处理/上传结果、数据质量、增量运维与复核 |
| [教材原方案](knowledge-base/TEXTBOOK_PLAN.md) / [知识库验证](knowledge-base/VALIDATION.md) | 方案依据和分阶段导入证据；当前状态由实施记录覆盖 |
| [开发知识库](antigravity/README.md) | 系统契约、架构、功能、问题、决策和测试 |
| [发布说明](release-notes/README.md) | 历史已发布版本；不是本次Release发布记录 |
| [历史档案](archive/README.md) / [审计记录](antigravity/audits/README.md) | 原文保留，区分审计时发现与后来修复 |

## 维护方式

操作命令均从仓库根目录执行；移动文档不移动脚本、配置、数据或凭据。[根README](../README.md)保留原品牌页、功能章节、架构和截图，并维护最新App介绍；[英文README](../README_EN.md)保留对应介绍。project目录提供简要使用/构建说明，AI/知识库和开发文档仍分类维护。开发规则的版本化副本见[AGENT_RULES](antigravity/AGENT_RULES.md)，本机原AGENTS.md仍供代理发现。

本地历史工具 `docs/yikaobang/`、网站 `docs/Bugaoshan-Web/` 与 API 抓包 `docs/api-req-resp/` 保持现有位置和忽略规则，不属于本次版本化文档。原PDF、页图、SQLite、生成语料、.local回执、虚拟环境与构建安装包不加入Git。

更新功能后同步当前进度、开发状态、功能矩阵和交接；修复问题再更新问题账本。费率是公开价格/估算，实际支出和赠金抵扣以账单为准。
