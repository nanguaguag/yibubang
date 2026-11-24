# 已知问题与验证边界

## 2026-11-15 已解决：云服务协议 v2 / D1 schema 未发布

正式D1迁移与Worker发布完成，protocol2和精确ACK线上可用，原数据/口令保留；后端11/11、Flutter相关18/18，独立账号HTTP及实际客户端临时SQLite联网通过。详见[发布记录](audits/SYNC_V2_DEPLOYMENT.md)。D1本次迁移77813行计费，不意味着免费额度问题消失；真实用户/国内网络及全天计费仍待核验。

更新2026-11-13；[旧问题账本](../archive/development-history/KNOWN_ISSUES.md)保留原始证据，旧“未修”不得覆盖后续修复结果。

## 最近已解决

| 问题 | 状态与验证 |
| --- | --- |
| GitHub Actions 自动化发布 APK 签名漂移，各版本无法覆盖升级 | 已修复；根因为 `android/app/build.gradle` 依赖 `signingConfigs.debug`，在 GitHub 临时 Ubuntu 虚拟机中每次动态生成不同的调试证书；已生成 50 年官方长期正式密钥库 `yibubang-release.jks` 并通过 GitHub Secrets 注入 CI/CD，配置 `signingConfigs.release` 自动注入与本地优雅降级；使用正式密钥对 `v2.2.5` 全量 4 个 APK 救火重签并通过 `gh release upload --clobber` 覆盖更新；`apksigner verify` 确认 SHA-256 证书指纹 100% 对齐 |
| 云同步万题上传单批 500 耗时 43s 报 HTTP 500 | 已修复；重构 `sync_v2.ts` 为并发幂等查重 + 多行 `ON CONFLICT DO UPDATE`（严格 $\le 91$ 参数守住 D1 100 参数上限），500 题耗时由 43s 降至 4.3s；客户端增加 >16KB 自动 GZip 压缩（压缩率 ~95%）、中间分片 `push_only` 及 500/超时自动缩减批次降级；MockClient 15/15 PASS，Worker 已上线 |
| 云同步第 ~3400 条后稳定报黑盒 500 (Internal Server Error) | 已修复；Hono 原先缺失 `app.onError` 导致 D1 报错（如远程 D1 未执行最新 `schema.sql` 建表 `sync_flashcards`/`sync_spaced_items`）或旧迁移题目 `user_answer: null` 校验异常均被吞成 `"Internal Server Error"`；现已补全全局异常透传与历史 `NULL` 字段兼容默认值 |
| AppMarkdown 图片加载时居中、加载后闪跳至左侧 | 已修复；`AppNetworkImage` 默认占位无尺寸导致加载时撑满全宽、加载后缩回配合 `Alignment.centerLeft` 闪跳；已改为 `Center` 居中与 `200×140` 固定占位尺寸，10/10 PASS |
| 每日复习卡片主入口绕过已配置算法 (M13) | 已修复；`DailyReviewCard` 动态感知并加载设置中的算法引擎（如 `fsrs_lite`），`DailyReviewService` 提供 `createConfigured` 工厂，探针及 Widget 12/12 测试通过 |
| 云同步 Worker pushMutations 串行处理 500 变动性能瓶颈 | 已修复；按 25 条切片批量查询 `seenMap` 并在单 D1 batch 事务中聚合提交，彻底消除 CPU 耗尽与子请求超限风险；后端 11/11 测试通过 |
| Windows每日复习测试fixture超30秒/database_closed | 502题+502复习项逐条提交耗尽准备时间，timeout清理后写入已关闭库；改两批事务、保留501过滤/500首批与q_4翻页断言。3.44/3.50该文件各11 PASS，3.50全量357 PASS/3 skip；Windows runner修复后尚未重跑 |
| Flutter3.50 Android getDefaultConfig API不匹配 | 本地复现；该SDK要求AGP>=9.1.1，项目8.11.1。Android日常/Release固定Flutter3.44.6并恢复依赖检查；Java17通用及3分ABI release APK通过，分析0、全量357 PASS/3 skip；修复后远程尚未重跑 |
| Flutter3.50 CI分析warning | syncNotesForQuestion的try内getLocalNotes返回补await；独立CI同版SDK的dart analyze/CI命令exit0，0 errors/warnings；119弃用info仍保留，不扩大迁移 |
| 新SDK设置测试残留Timer | 开启自动检查原会发无关网络，fixture设最近检查时间，定向6 PASS、3.50全量357 PASS/3 skip；产品定时/超时逻辑未因此关闭 |
| 段落选择lastSelectionResult断言 | 已修复；WidgetSpan引用/行内公式内部Text隔离选择，精确修前/修后事件、三击、正文可选和引用点击PASS |
| 固定12证据/题库挤教材 | 已部署00018；总数1–25、独立来源比例、显式结果列表；线上25条17教材/8题和SQLite/引用PASS |
| 紧凑列表粗体/冒号分行、CREB星号 | AST连续行内合并及中文边界修订，用户原文/转义/代码/流式回归PASS |
| 组合编号引用纯文本 | 拆为每个真实编号可点，代码/无效编号不导航 |
| 独立新话题继承旧检索词 | 仅明确省略追问补前问；慢阻肺独立/肝硬化后证据一致并有定义 |
| 流式最终全文重复/迟到引用 | 增量与最终全文分开、UTF-8引用校正，真实App与模拟边界通过 |
| 模型官网故障阻塞选择 | App/后端快照即时回退、后台有界刷新；旧目录标备用，不宣称永久可用 |
| Android页图缩放手势竞争 | PhotoView/PageView轴向协调，模拟双指/双击PASS；Android真机未宣称通过 |
| 教材needs_review字段导入回执成功但未生效 | 407条仅补structData，逐条GET/实际Search核验通过，未重传正文 |

A01–A20源码已修复并独立提交，见[修复日志](audits/A01_A20_REPAIR_LOG.md)；M01/M02和M03隐藏Tab切片已修，见[启动日志](audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。

## 未解决/待核验

- Windows原Actions43432164278/43436136566的每日复习fixture超时已修复并本机复核；修复后Windows原生Test/Build仍需push重跑，不能用macOS同SDK通过代替。2b80da1的Android/macOS/Linux远程成功。
- 同步v2/schema已发布及独立账号闭环通过；真实用户、官方ID/幂等边界、国内网络及D1全天计费/熔断仍待验证，迁移回执77813 rows_written已记录。
- 教材375页符号/公式、239稀疏页候选、36无文本页的人工质量判断、版次ISBN；167题答案分歧、6923题配图未OCR。所有页图可读不等于全部文字医学正确。
- 最新原生实机、Android/Windows/Linux/iOS、目标地区网络及Release；模拟手势/Debug构建不作实机性能保证。
- 专项赠金抵扣/Advanced实际SKU、Worker订阅和整账号共享免费额度，没有完整账单证明。
- 25条仍为选中片段上限；Google实际引用可少于输入，当前无保证每个子问题来源比例的迭代覆盖。
- 安装凭据不是硬件身份证，重装/换IP/脚本滥用仍有边界；新增LB/CDN须重审可信代理链。

其他维护范围见[技术债](TECHNICAL_DEBT.md)，本次未顺手修复无关模块。
