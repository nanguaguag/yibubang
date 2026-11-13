# 当前技术决策

更新2026-11-13；详细早期ADR原文保留在[历史决策](../archive/development-history/DECISIONS.md)。

| 决策 | 当前选择与原因 |
| --- | --- |
| 内容/用户隔离 | 正式题库只读、用户状态独立写；Question全局单列id，跨库共享状态，ATTACH聚合 |
| 安装/更新 | 暂存校验/原子替换，来源配置/检查/下载安装分离；保持既有题库管理契约 |
| 性能 | 文件校验缓存、M02真实路径投影、M01精准刷新、M03隐藏Tab切片；不承诺所有设备毫秒冷启动 |
| AI入口 | 独立Cloud Run做凭据/限额，Search内置Answer/streamAnswer，移除外接Vertex Token生成，避免将专项赠金错误等同通用模型费用 |
| 两源检索 | 教材/题库分别过滤Search，显式汇总给内置回答；保留可调来源覆盖，代价是多一个/两个Standard查询 |
| 流式与额度 | 用户改为体验优先，默认改写+流式；Google流式强制1步改写。App日200、基础1/改写2/流式3，仅为App额度策略 |
| 可调结果数 | 原12是App策略，现1–25默认12；有限片段预算、比例联动，不保证穷尽索引或模型逐条采用 |
| 会话/模型 | 会话只本地SQLite，模型选择本机保存；共享快照/有界后台官网刷新，不让App直连Google模型文档 |
| 教材处理 | 本地复用OCR/按坐标去重；原PDF不上传，Google收清洗文本，私有R2存独立页图/小图；源版本与物理页定位 |
| 可迁移资产 | 保留本地规范文字/稳定ID/坐标/来源和云成功账本；换Embedding重算向量，不需再清洗PDF |
| 文档 | docs为唯一维护目录，根README导航，当前与历史分开；忽略私有抓包/数据库/环境。Release工作流读取docs/release-notes |

详情：[题库管理](QUESTION_BANK_MANAGEMENT_DESIGN.md)、[AI手册](../ai-search/README.md)、[检索限制](../ai-search/RETRIEVAL_LIMITS.md)、[费用](../ai-search/COSTS_AND_BUILTIN_MODELS.md)、[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。实际赠金抵扣仍待账单，不由架构选择自动保证。
