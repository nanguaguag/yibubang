# 已知问题与验证边界

更新2026-11-13；[旧问题账本](../archive/development-history/KNOWN_ISSUES.md)保留原始证据，旧“未修”不得覆盖后续修复结果。

## 最近已解决

| 问题 | 状态与验证 |
| --- | --- |
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

- 4deacbb的Windows Actions43432164278：daily_review_service_test大fixture插入超30秒，355 PASS/1 fail/4 skip；数据库关闭是测试timeout后tearDown的后续报错。与Android AGP问题独立，本轮仅记录，未扩大修复。
- 同步协议v2服务端/schema部署、真实账号、官方ID/幂等边界与D1实际rows_written；客户端完成不证明线上同步闭环。
- 教材375页符号/公式、239稀疏页候选、36无文本页的人工质量判断、版次ISBN；167题答案分歧、6923题配图未OCR。所有页图可读不等于全部文字医学正确。
- 最新原生实机、Android/Windows/Linux/iOS、目标地区网络及Release；模拟手势/Debug构建不作实机性能保证。
- 专项赠金抵扣/Advanced实际SKU、Worker订阅和整账号共享免费额度，没有完整账单证明。
- 25条仍为选中片段上限；Google实际引用可少于输入，当前无保证每个子问题来源比例的迭代覆盖。
- 安装凭据不是硬件身份证，重装/换IP/脚本滥用仍有边界；新增LB/CDN须重审可信代理链。

其他维护范围见[技术债](TECHNICAL_DEBT.md)，本次未顺手修复无关模块。
