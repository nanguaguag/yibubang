# AI检索、Markdown与教材预览修订（2026-11-13）

已完成实现、独立Cloud Run部署和验证。最新修订yibubang-ai-search-00011-mm9/100%；macOS与Android Debug构建通过，未commit/push/发布Release。

## 检索与上下文

原实现混合检索pageSize=6，所有前两轮问题直接拼入检索词，因此新话题可能被旧疾病干扰。修订为教材/题库并行两次Search：分别取12/8条候选，同页或同题去重后最多8教材页+4题，教材在先，全局重新编号1–12。证据正文预算总28000字符（教材每条2500、题目2000）；只明确省略式追问使用上一问题，独立新问题仅检索当前主题，并展开慢阻肺→慢性阻塞性肺疾病/COPD。历史对话仍用于生成，但当前问题与本轮证据优先。每次用户提问仍扣1次本地服务额度，Google Search会产生2个查询；两个源都失败报告错误，单源失败保留另一源并提示。

## 显示与页图

Markdown由CommonMark/GFM AST原生渲染，支持引用块、列表、粗斜体、删除线、代码、表格；LaTeX $...$/$$...$$及\(...\)/\[...\]原生公式，非法或未闭合流式内容显示原文。合并编号[3, 4, 5, 6]拆成逐个可点击来源；没有实际引用编号保持文字，代码不转换，外部模型链接不能跳转。

textbooks.melonhu.com绑定原页图Worker，自定义域名不会迁移R2或开放桶；HMAC鉴权在边缘缓存命中前执行。缓存键使用版本化对象键，短期签名不影响复用，浏览器仍private/max-age300。缩略图从现有WebP本地制作（长边480、quality65），独立thumbnails路径，仅可视结果懒加载，最近300缩略图本地缓存；不把完整页图当缩略图下载。

## 模型、价格和赠金证据

已读线上Cloud Run GEMINI_MODEL=gemini-3.8-flash、GEMINI_LOCATION=global，thinkingLevel=LOW、maxOutputTokens=2048；直接调用aiplatform.googleapis.com的streamGenerateContent，不是Search内置生成。Google Cloud结算账号币种已核对JPY。

用户提供赠金CSV：Trial credit for GenAI App Builder；156515 JPY、100%，2026-03-25至2027-03-25；范围仅“特定使用情况；请查看促销活动条款了解详情”。这些字段未证明独立Gemini、Cloud Run、Firestore适用。Cloud Billing公开API没有该条赠金SKU范围/实时余额接口，当前项目也没有BigQuery billing export可核对SKU抵扣。不能据余额不变宣称生成免费或已抵扣。生成按单独Vertex模型token SKU计费，若促销条款未明确包含，应按不涵盖估算。

2026-11-13官方页面：Search每结算账号每月10000查询免费（不含Advanced Generative Answers）；Standard超出为USD1.50/1000查询。官方示例使用10GB免费索引空间，但实际索引计费占用需结算核对。查询几十次且免费查询尚未耗尽时无需消耗专项赠金；账单成本通常一天内可见，也可能超过24小时。该免费查询最有可能解释当前Search余额未动，不据此解释Gemini成本。

Gemini 3.8 Flash Standard/global截至2026-12-31：输入USD0.75/百万tokens，输出（含推理）USD3.75/百万tokens；2027-01-01起输入USD1.50、输出USD7.50/百万tokens。按实际token及日本结算转换为JPY；示例每次10000输入+2000输出/推理共USD0.015，30次USD0.45，非实际账单。增加教材证据提高输入token，LOW仍有计费推理token。源码记录不含问题/回答的model+usageMetadata计数，以便核算。Cloud Run/Firestore/R2/Worker另按各服务规则；专项赠金是否抵扣需用户条款或SKU账单证明。

官方来源：
- https://cloud.google.com/generative-ai-app-builder/pricing
- https://cloud.google.com/model-garden/pricing
- https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-flash
- https://docs.cloud.google.com/billing/docs/how-to/reports
- 赠金控制台：https://console.cloud.google.com/billing/01B815-069E99-72B4B3/credits
- 费用控制台：https://console.cloud.google.com/billing/01B815-069E99-72B4B3/reports

## 2026-11-13赠金与API入口复核（未迁移或部署）

本次按用户质疑重新查官方文档与线上配置。自部署的是Cloud Run代理、鉴权与限额服务；模型由Google托管。当前代码两次调用Discovery Engine Search，然后另行调用Vertex AI `gemini-3.8-flash:streamGenerateContent`。凭据来自Cloud Run运行服务账号的ADC/OAuth，不是购买的第三方API或AI Studio免费Key。费用进入项目绑定的JPY结算账号01B815-069E99-72B4B3；未获抵扣的费用可能按该账号付款方式结算。未取得实际净费用/扣卡记录，不把usage日志等同账单。

官方已确认Search Enterprise包含Core Generative Answers：USD4/1000查询；Standard USD1.50/1000；Advanced在基础上加USD4/1000用户输入查询；每账号每月10000免费查询不含Advanced。内置Answer/summary生成属于对应Search计价，不需要另发Vertex模型生成请求。查询按API请求计，不能把教材Search+题库Search+Answer合并宣称只收一次USD4/1000；输入自选检索结果时的实际计量也需要按最终配置核对。当前线上Engine只读GET确认`SEARCH_TIER_STANDARD`，没有已启用内置生成的证据。

官方Answer模型文档当前列出`stable`指向`gemini-3.5-flash/answer_gen/v1`，以及`gemini-3.1-pro-preview/answer_gen/v1`、`gemini-3-flash-preview/answer_gen/v1`，上下文128K。stable会变动。官方v1 schema有`searchSpec.searchResultList.searchResults`，支持传入文档/片段；可评估保留教材优先的两源检索、映射原题/教材引用及本地会话，不需重新导入知识库。`streamAnswer`支持分段输出，但官方明确一次rephrase步骤不可禁用；迁移时不能未经计量验证承诺流式功能一定只走Core价格。不要把另一个Grounded Generation API误认为Search内置Answer；价格页为前者另列模型输入输出费用。

赠金证据分层：用户CSV只给名称、限定使用、金额和有效期，没有SKU组映射。公开Google论坛用户转述Google Support曾指向`vertex-ai-search-and-conversation`和`vertex-genai-offer-2025`；当前这两个官方列表都已标`[Deprecate]`且范围不同，后者还列部分Vertex模型SKU。这些只能作为线索，不能充当本账号赠金合同，既不能断言所有独立Gemini都覆盖，也不能把所有同名赠金一概认定仅限Search。已请求用户提供赠金详情条款/适用SKU组；当前按独立Gemini未保证抵扣预算。此前独立Gemini方案没有充分落实优先用专项赠金、省钱的目标，应调整生成入口，但本轮仅核查，未切换模型、修改Engine、部署或停用API，也未重传教材。

官方Search SKU供费用报表核对：Standard `BADA-EE26-7BDA`、Enterprise `93D6-7280-CF05`、Advanced Generative `C232-DC00-D993`。它们出现在公开Search SKU组中，不等于已证明赠金d6296d6af675a0a0aecba7d7fa218b60323ec62cb3c15f92f2a1d4e14cdc5464适用。余额不变可由Search免费查询或账单延迟解释，不能证明独立模型免费；Cloud Run、Firestore、R2/Worker也不能按专项赠金免费处理。

依据（2026-11-13抓取，只读资源GET与schema读取；未发付费生成测试）：
- [官方Search价格](https://cloud.google.com/generative-ai-app-builder/pricing)
- [官方Answer模型](https://docs.cloud.google.com/generative-ai-app-builder/docs/answer-generation-models)
- [Answer API与前提](https://docs.cloud.google.com/generative-ai-app-builder/docs/answer)
- [流式API及限制](https://docs.cloud.google.com/generative-ai-app-builder/docs/stream-answer)
- [Answer REST参数](https://docs.cloud.google.com/generative-ai-app-builder/docs/reference/rest/v1/projects.locations.collections.engines.servingConfigs/answer)
- [官方Search SKU组（已废弃标签）](https://cloud.google.com/skus/sku-groups/deprecate-vertex-ai-search-and-conversation)
- [另一官方Offer SKU组（已废弃标签，不是本赠金已确认范围）](https://cloud.google.com/skus/sku-groups/vertex-genai-offer-2025)
- [社区转述Support，非本账号条款](https://discuss.ai.google.dev/t/no-one-is-talking-about-how-to-use-the-credits-of-trial-credit-for-genai-app-builder/101423)

本地忽略目录`.local/`保留官网正文、Engine GET和v1 discovery schema。没有凭据进入上述文档；本轮仅追加事实核查与交接，不重跑产品测试，不自动commit/push。

## 375页的含义

本地质检规则匹配[ⅡⅢⅣ]-数字（例如OCR可能把IL-2识为Ⅱ-2）或∫/∑/√，得到375物理页/407文本块。是需对照原图的候选，不是375页均已证明错误，也不涵盖全部潜在OCR问题。原OCR保留；不自动改公式、字母、上下标、单位/剂量。App引用提示核对原页，AI证据带needs_review。需要时可单独生成完整页清单，不重OCR或人工校对全部教材。

## 最终验收

- Flutter全量340 PASS（联网1默认skip），Markdown/AI/教材相关14 PASS，analyze0；后端21 PASS；Worker签名/过期/路径/上传SHA/鉴权后边缘缓存PASS。
- 真实线上“名词解释：慢阻肺”在新会话与前一问题为“肝硬化发生的原因是什么”两种情况返回完全相同12条证据（8教材+4题），回答均包含气流受限定义；总耗时5.84s/3.91s。回执.local/search-improvements-live.json。
- 线上usage日志模型gemini-3.8-flash，第一次10770输入/204输出/0推理，第二次10787输入/242输出/0推理；按当前Standard/global标价约USD0.00884/USD0.00900，非最终JPY账单。回执.local/search-generation-usage.json。
- 本地20669缩略图完成，377590170 bytes，平均18.27KB；全部本地SHA与R2成功SHA回执匹配。正式Cloud Run签缩略图链接指向textbooks.melonhu.com，示例21510 bytes/首次2.07s/边缘HIT0.46s，不扣搜索额度；本机网络数据不能推断大陆用户同速。.local/textbook-thumbnail-validation.json。
- 真App组件→生产Search联网PASS、缩略图布局截图.local/screenshots/textbook-live.png；缩略图签名与真实字节下载在服务端探针已验证；原生integration test启动被macOS新签名确认弹窗阻止，未执行断言，不宣称原生小图显示已验收；测试环境补齐path_provider/SQLite FFI宿主，未修改产品绕过缓存。Android/macOS Debug均构建成功。其他平台/大陆网络/正式Release未验收。
- 后续新教材：从现有WebP运行scripts/knowledge_base/textbook_thumbnails.py，再r2_pages.py upload --variant thumbnails。两个variant使用同一上传锁，顺序执行；普通页与缩略图使用不同对象键，共享成功SHA账本。

最终普通main Debug已恢复并打开；可能需用户在macOS弹窗点“仍要打开”。原生测试进程已停止，避免遗留测试入口；源测试保留用于系统确认后的验收。最近额外加入“正文中$$公式后的文字不丢失”回归，Markdown4与最终相关15 PASS；原全量340基线是在该额外用例前，未重跑全量以冒充341。
