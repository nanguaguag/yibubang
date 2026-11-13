# 当前技术债与后续验证

更新2026-11-13；原DEBT/AI/M各阶段全文在[历史技术债](../archive/development-history/TECHNICAL_DEBT.md)。A01–A20源码修复、M01/M02/M03隐藏Tab切片和教材/Markdown实现已完成；旧“尚未处理/未提供53本”不再表示当前状态。

| 范围 | 后续工作 |
| --- | --- |
| 同步M06等 | 协议v2/schema真实发布/账号验收；D1 rows_written和计费/持久冷却、payload/seq一致性模型及平台恢复 |
| 启动M03–M05 | 目录分阶段初始化、概览SQL/共享缓存、调度/FIFO观测；真实字体窄屏卡片与设备profile |
| 数据M10–M15 | 剩余IN参数预算、FTS旁挂检索、句柄单所有者、统计DST残留、M13默认算法factory、流式归档/WAL备份与平台故障验证 |
| AI滥用 | 安装凭据不能替代Play Integrity/App Attest/账号/人机验证；共享出口限额评估；未来代理入口重审可信IP链 |
| 检索覆盖 | 25片段非穷尽，Google实际采用子集；若需求变为全面比较，独立设计迭代检索/来源约束与质量benchmark |
| 模型/网络 | 官网表解析维护、退役模型与备用快照标记；Cloud Run目标地区可达性不因目录离线回退而自动解决 |
| 医学质量 | 375页公式/符号、版次ISBN、167答案分歧、6923配图文字；质量标记需GET/Search抽查，不只看成功回执 |
| 迁移 | 实际Embedding/Qdrant接口、向量成功基线与检索质量尚未验收；更换模型必须同模型/维度文档和查询 |
| 费用/发布 | 专项赠金适用SKU、Advanced实际计量、共享免费范围/Worker订阅；TTL/出网/附属服务；真机/国内网络/Release |
| CI | 历史Node/action迁移提示仍独立评估，未顺手升级依赖或改发布tag |

设计依据见[后续维护审计](audits/POST_A20_STARTUP_SYNC_MAINTENANCE_AUDIT.md)，完成记录见[A01–A20](audits/A01_A20_REPAIR_LOG.md)及[启动修复](audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。用户未授权这些后续改造时，只记录范围，不实施。
