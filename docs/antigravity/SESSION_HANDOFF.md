# 跨会话交接

更新：2026-11-13；main；本次提交父基线ec0fdf6，用户明确授权commit。准确提交ID以`git log -1`为准。本次只提交代码/测试/公开文档，不push、不发布Release；新会话先核对Git是否有用户后续改动。

## 本次完成

1. 检索条目设置1–25（默认12），总数变化保留来源比例，默认25为17教材/8题。每轮SharedPreferences→HTTP result_count/textbook_count→服务端校验→独立二源Search→显式Answer结果列表；单源跳过无用请求，最多60000字符并为后续来源留预算。
2. 引用/行内公式WidgetSpan内部Text重复加入Text.rich选择delegate导致lastSelectionResult断言，已精确复现并隔离内部选择；正文可选、引用可点。Google实际采用的证据可少于输入数量。
3. 文档统一到docs并建立总索引/当前状态；中文英文使用指南、AI运维与费用、知识库/教材操作分别分类；旧动态记录/早期数据库研究保留为历史档案。根README保留导航，本地AGENTS.md保留代理发现，版本化规则副本在本目录。
4. 更新全部开发入口到schema25/当前内置模型/200额度/可调25条/00018部署；Release工作流从docs/release-notes读说明。原PDF、页图、生成SQLite/JSONL、.local身份/回执/截图、虚拟环境、API抓包均不提交。

## 当前资源和数据

- Google yibubang-search/520065588983，global Store yibubang-medical-v1，171463块=149472题+21991教材；两应用yibubang-medical-search（Standard）/yibubang-medical-answer（Enterprise）共用Store。不要创建RAG Corpus或重复导入。
- 东京Cloud Run yibubang-ai-search，00018-q7c/100%，App入口https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app。默认stable、当前快照3.5-flash/answer_gen/v1，默认改写+流式；没有外接Vertex Token生成。
- Firestore yibubang-ai记录身份哈希、北京时间日200额度/分钟6/租约，TTL清理3天过期限额；会话仅本机user_data.sqlite的AiSearchSessions/AiSearchTurns，不加入同步。
- 外置盘源目录`/Volumes/My PSSD/书籍/自用53本课本（可复制）`；教材主库/原始OCR/清洗页/坐标/页图在`/Volumes/My PSSD/书籍/医不帮教材知识库`。仓库scripts/knowledge_base/artifacts/current与artifacts/cloud是语料及增量成功账本，均忽略但不可删除。
- 私有R2 yibubang-textbooks，Worker yibubang-textbook-pages，textbooks.melonhu.com；20669页图+20669小图，7714259450 bytes。阅读器按稳定版本/物理页定位，原PDF未上传。

## 已有验证与回执

Flutter全量357 PASS/3联网默认skip、最终相关8 PASS，后端39 PASS，analyze0；Android/macOS普通main Debug构建通过。生产App25条17:8/回答/SQLite/引用2联网PASS；Google返回references10、正文用到第13项，不能说25条全部被用到。五组非法数量/比例400且不扣额度。

最近回执在忽略的ai_backend/.local/result-count-*、result-selection-*、selection-*；教材全量和早期原生Reader证据见[实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。联网测试复用专用smoke-device.json，不提交/打印secret，不重置真实用户额度。构建包仅在build/；Widget截图/模拟手势不代表Android真机或大陆网络验收。

本次文档复核62份文档/520个本地链接，无失效/私有未版本化目标；静态分析0。旧审计复制的凭据已脱敏，原稿仅在ai_backend/.local/docs-private-archive；链接报告/分析日志为ai_backend/.local/docs-link-report.json、docs-final-analyze.log，不提交。维护的docs目录已纳入Git，抓包/数据库/工具环境继续忽略。

## 下一次第一步

执行`git status --short --branch`与`git log -1`，读[当前状态](../CURRENT_STATUS.md)、本段与用户新反馈。用最新Debug App核验AI设置→条目/比例及原鼠标选择手势；若代码已改需重建/重启。默认无需重新跑付费生成、造Store、导入171463块或上传41338图片。

新教材按[知识库手册](../knowledge-base/README.md)与[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)复用本地缓存、稳定ID和成功基线，先本地验证delta，再增量导入。更换Embedding须重算向量，PDF清洗不必重做。

## 未完成项和授权边界

- 用户原手势实机、Android/Windows/Linux/iOS、目标地区网络、375页医学符号人工复核、版次ISBN、167题答案分歧/6923题配图OCR、Release与真实向量库迁移仍未验收。
- 同步协议v2服务端部署/真实账号验证，以及M03目录分阶段/M04/M05/M13等属于独立后续任务；本次不部署同步服务。
- 专项赠金适用SKU、实际Advanced计量和账户运行费用仍待账单，不承诺100%抵扣/不扣卡。混合搜索两Standard+一Enterprise列表价USD7/千、Advanced预算USD11，App1/2/3不是Google收费倍数。
- 当前没有保证每个子问题按来源比例迭代检索，25条并不穷尽全库。只有用户明确授权下一步才发布Release、push或新建云资源。

旧会话完整记录：[历史交接](../archive/development-history/SESSION_HANDOFF.md)。
