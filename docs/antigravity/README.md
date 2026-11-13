# 开发知识库索引

当前日期：2026-11-13。App源码2.2.3+213，用户库schema25、题库schema1；AI后端00018-q7c/100%。旧3c33fb9/Sprint待开展状态已归档，不能作为现在的基线。[项目文档总目录](../README.md) · [完整当前进度](../CURRENT_STATUS.md)

| 文档 | 使用场景 |
| --- | --- |
| [DEVELOPMENT_STATUS](DEVELOPMENT_STATUS.md) / [SESSION_HANDOFF](SESSION_HANDOFF.md) | 每次启动/结束必读，当前完成项、未完成项和下一步 |
| [AGENT_RULES](AGENT_RULES.md) / [PROJECT_MEMORY](PROJECT_MEMORY.md) | 工作区保护、数据契约与跨平台约束 |
| [ARCHITECTURE](ARCHITECTURE.md) / [database_current](database_current.md) | 当前调用链、生命周期与数据库来源 |
| [FEATURE_MATRIX](FEATURE_MATRIX.md) / [KNOWN_ISSUES](KNOWN_ISSUES.md) | 功能/缺陷与实际验证范围 |
| [TECHNICAL_DEBT](TECHNICAL_DEBT.md) / [DECISIONS](DECISIONS.md) | 剩余技术债与决策依据 |
| [TESTING_STRATEGY](TESTING_STRATEGY.md) | 当前门禁、历史探针和实机边界 |
| [QUESTION_BANK_SPEC](QUESTION_BANK_SPEC.md) / [QUESTION_BANK_MANAGEMENT_DESIGN](QUESTION_BANK_MANAGEMENT_DESIGN.md) | 题库制作与订阅设计；保留明确标注的历史基线 |
| [审计与修复记录](audits/README.md) / [历史档案](../archive/README.md) | 原始问题证据与后续修复；不替代当前源码核验 |

先读状态/交接，再按任务类型定向阅读，检查Git现场后修改。沿完整UI→Controller→Repository→SQLite/Network调用链核验；源码存在不等于业务已验证。结束时更新对应文档并复核diff。只有用户授权时才commit/push/部署。
