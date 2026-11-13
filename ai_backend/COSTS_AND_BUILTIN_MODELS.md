# 内置模型、计费条目与运行费用（2026-11-13）

## 2026-11-13 后续更新：默认高级与200次额度

用户改为体验优先，默认问题改写+流式输出。设置在通用下方AI搜索组，模型选择移入同组。流式API必须1步改写，不能关闭；开关联动。App每安装每天200额度，基础1/仅改写2/改写+流式3，由Firestore事务核算；历史计数保留。因此默认可完整提问66次，剩余2次可改模式使用，不是每天200次高级请求。IP/分钟/全站仍按真实请求数计。

3倍是App额度策略，不是Google收费比例。当前仍两次Standard检索+一次Enterprise Answer/streamAnswer：基础列表价USD7/千App问题，另计Advanced时USD11/千。Google的生成计费来自Discovery Engine，无独立Vertex模型Token入口；本赠金实际SKU/免费分配/抵扣仍没有账户合同或账单证明，不把“Discovery Engine原生”直接等同“任何费用100%由本赠金抵扣”。用户所引USD8/千是单Enterprise+Advanced的列表价，不含本项目两个独立Standard检索。

模型目录由后端获取，App不直连Google官网。现在App与后端均附带2026-11-13四模型已核对快照；App优先本机缓存、立即显示，联网刷新短超时，失败保留可选目录；后端冷启动立即回快照并后台更新，官方缓存最多24小时后改回标记的快照，不伪称最新。离线可保存选择，搜索本身仍需Cloud Run可达。无需通过付费生成枚举模型。

Firestore TTL是托管到期删除规则：当前清理ai_request_limits/ai_registration_limits的3天过期记录，不删除本地会话或设备身份。搜索/零点刷新不依赖TTL，停用会累积旧记录；TTL删除另计、无普通免费删除额度。保持原规则，没有部署新的清理服务。单纯搜索+推理只走App→Cloud Run→Discovery Engine；Cloudflare Worker仅用于R2教材图片鉴权/缓存。

以下基础方案与费率/运行费估算保留为上一阶段记录；普通服务免费额度未因本次切换改变。最新部署与验证见SESSION_HANDOFF/VALIDATION。

用户选择：优先省钱，基础Answer返回后逐行平滑渐入；不使用streamAnswer。本文件列出公开费率与按源码操作次数的估算，不是已支付账单。美元价格不含税；JPY结算以Google账单转换为准。

## SKU与赠金

SKU是具体的计费条目编号；一个服务有多个SKU。例如Search Standard查询BADA-EE26-7BDA、Enterprise查询93D6-7280-CF05、高级生成C232-DC00-D993。https://cloud.google.com/skus 可查SKU与价格；用赠金名称“Trial credit for GenAI App Builder”过滤不会列出它的抵扣范围，因为赠金不是SKU。赠金详情里的促销条款/适用SKU组才决定抵扣范围；官方公开SKU组不能直接与用户的赠金ID关联。该赠金范围仍未获得账户条款，不能承诺所有运行费用抵扣。

## 本次回答架构

- Cloud Run仍是Google Cloud东京asia-northeast1的yibubang-ai-search，保存Google服务账号凭据、设备认证、北京时间100次/天及额外限额、私有页图签名，不存云端聊天。
- 原yibubang-medical-search保持Standard，两次并行检索：最多8教材+4题，教材优先。
- 新yibubang-medical-answer为Enterprise，复用原yibubang-medical-v1 Data Store，不复制或重新导入171463条数据。调用discoveryengine.googleapis.com的:answer，传searchSpec.searchResultList及选择的/answer_gen/v1模型；不调用aiplatform.googleapis.com生成。
- 基础Answer请求禁用queryRephraserSpec、relatedQuestionsSpec，无Google session参数。历史追问仍是本地会话传来的有界上下文，当前新话题检索不拼旧主题。App收到完整回答后按行显示、Markdown块/列表项渐入；这是本地展示动画，不是真实Token流。
- 实测Enterprise且searchAddOns为空时，包括最小仅query请求在内均返回400“only available when Large Language Model add-on is enabled”。所以只在新Answer应用启用SEARCH_ADD_ON_LLM必要生成开关。请求禁用高级行为不等于账单已证明无附加费；原Standard应用没有升级或开启这个开关。
- 官方基本Enterprise USD4/1000、Standard USD1.50/1000、Advanced附加USD4/1000。两Standard+一Enterprise按列表价约USD7/1000次App提问；若Answer计入附加生成费，则保守USD11/1000。不把三次API调用当一次USD4；输入自选结果的实际计量、免费查询分配与赠金抵扣仍须SKU账单确认。

高级生成包括问题自动简化/改写、复杂问题拆解、多步或托管多轮查询、推荐后续问题，以及回答中返回图片和图表。普通基于证据的回答、摘要与引用属于Core。每结算账号每月10000免费Search查询不包括Advanced。App的点击教材原页图不等于调用Google多模态回答功能。

用户提供的UI Bakery文章已读，它介绍整个Agent Builder/Agent Platform、Agent Engine、Model Garden等。其200+模型并非Search Answer内置模型目录；Search具体费率以Google官方价格页为准。

## 查询和选择模型

Google Discovery Engine v1公开API没有内置Answer模型枚举方法，customModels.list是自训练模型，不能冒充内置模型查询。服务端GET /v1/models从Google官方Answer模型表解析当前列表，1小时缓存、刷新至少间隔60秒，文档暂时失败时最多用24小时缓存并标stale，过期或无有效表报错。不会通过普通Vertex模型列表拼出内置版本，也不会在每次用户刷新时发付费生成探针。

App AI页右上“回答模型”按钮打开目录、查询/刷新、选择。选择保存在SharedPreferences ai_answer_model，下次搜索传model；每个AiTurn payload保存服务端返回的模型ID，旧会话兼容，无SQLite schema变更。未知/移除版本拒绝，不偷偷切换外接付费模型；查询模型不扣每日100次，但仍有Cloud Run和一次Firestore认证读取。

当前官方目录与本次实际接口验证：

| 选择ID | 说明 | 当前知识库调用 |
| --- | --- | --- |
| stable | 当前文档指向gemini-3.5-flash/answer_gen/v1；可能随Google更新 | 200/SUCCEEDED |
| gemini-3.5-flash/answer_gen/v1 | 固定3.5 Flash版本 | 200/SUCCEEDED |
| gemini-3-flash-preview/answer_gen/v1 | 预览版 | 200/SUCCEEDED |
| gemini-3.1-pro-preview/answer_gen/v1 | Pro预览版 | 200/SUCCEEDED |

四者官方上下文128K。验证问题“名词解释：慢阻肺”均有气流受限定义，10项原始引用、4–10段引用定位；Google引用位置为UTF-8字节偏移，按引用URI映射回本轮8教材+4题编号。steps为空，未执行问题改写。仅对当前版本/当前知识库证明，不保证未来预览版本生命周期。

## 三项基础服务是否免费

| 服务 | 免费额度 | 超额公开费率/当前状态 |
| --- | --- | --- |
| Cloud Run请求计费 | 每月180000 vCPU秒、360000 GiB秒、200万请求，结算账号跨项目共享 | 东京Tier 1，CPU USD0.000024/vCPU秒、RAM USD0.0000025/GiB秒、请求USD0.40/百万；现1vCPU、512MiB、并发16、最大2实例、最小0，无常驻实例费用 |
| Firestore Standard | 1GiB存储，50000读/天、20000写/天、20000删除/天、10GiB出站/月；每天按太平洋时间重置，一项目只一库 | 真实GET yibubang-ai返回freeTier=true。东京超额读USD0.038/10万、写USD0.115/10万、删USD0.013/10万 |
| R2 Standard | 每月10GB-month，100万Class A操作，1000万Class B操作；出网流量免费，账号共享 | USD0.015/GB-month、Class A USD4.50/百万、B USD0.36/百万；超额有整计费单位向上取整。页图+小图7714259450字节=7.714GB≈7.184GiB，本教材单独占用在免费额度内 |

不能把三项组合称为完全免费：

- Cloud Run东京向互联网发送回答/签名链接仍可能有出网费；其网页列的1GiB免费网络额度限北美，并不直接适用本东京服务。图片字节由R2/Worker直接发送，Cloud Run只发签名链接。
- Firestore自动TTL删除不在免费删除额度里。目前两个限额集合启用TTL，按东京USD0.013/10万次TTL删除估算。文档的旧“named databases无免费额度”段与最新配额规则有差异；本库实际freeTier=true与最新“首个数据库获得额度”规则一致，不据旧段误判。
- R2免费10GB是整个Cloudflare账号共享；其他桶占用、重试/上传/HEAD/LIST等也计入相应操作。页图和缩略图共41338对象的首次PUT远低于100万，但不能据此声称整账号账单为0。
- 私有页图经过Cloudflare Worker：Free计划100000请求/天、10ms CPU/请求；Paid计划最低USD5/月，含1000万请求及3000万CPU毫秒/月，超额USD0.30/百万请求、USD0.02/百万CPU毫秒。缓存HIT仍调用Worker，但可减少R2读取。R2免费出网不等于Worker所有计划免费。本轮现有OAuth查询账户计划返回401，未证实用户实际订阅，未新开Paid计划。
- Cloud Build、Artifact Registry镜像、Secret Manager等部署附属服务另计，不混入这三项免费额度。

## 按当前代码操作数估算

一次正常AI提问：6次Firestore读取（验证1、预留事务3、释放1、App刷新额度1）与4次写入（预留3、释放1）。一次页图/缩略图签名：1读1写；签名本地缓存命中不请求，Cloudflare边缘命中不减少已经发起的签名请求。注册、查询模型/教材目录等额外操作不包含在下表。

假设30天/月，每次AI后端请求10秒、每次图片签名0.2秒、每次额度查询0.05秒；实例时间按各请求求和，未扣并发共享，所以是保守计算，不代表实测延迟。免费额度未被同账号其他项目消耗，图片访问按全部缓存未命中估算：

| 每日全站AI提问 | 每日图片签名 | Cloud Run计算/请求 月费 | Firestore普通文档月费 | 本教材R2存储/读取月费 |
| --- | --- | --- | --- | --- |
| 100 | 200 | USD0 | USD0（800读/600写每天） | USD0 |
| 2000 | 4000 | 约USD10.73 | USD0（16000读/12000写每天） | USD0 |
| 2000 | 20000 | 约USD13.04 | 约USD0.276（32000读/28000写每天） | USD0 |

不包含Search/Answer查询、TTL、互联网出网、Worker订阅及其他部署附属服务。没有用户实际月均时长/完整账单数据，不能把估算写成已支付金额。全站搜索现有2000/天上限，100/天是每安装设备额度，不是全站总免费额度。

## 官方依据与验收回执

- https://uibakery.io/blog/vertex-ai-agent-builder （第三方概述，不作赠金合同）
- https://docs.cloud.google.com/generative-ai-app-builder/docs/answer-generation-models
- https://cloud.google.com/generative-ai-app-builder/pricing
- https://docs.cloud.google.com/generative-ai-app-builder/docs/about-advanced-features
- https://docs.cloud.google.com/generative-ai-app-builder/docs/advanced-llm
- https://cloud.google.com/run/pricing
- https://docs.cloud.google.com/firestore/quotas
- https://cloud.google.com/firestore/pricing （Tokyo region表）
- https://developers.cloudflare.com/r2/pricing/
- https://developers.cloudflare.com/workers/platform/pricing/

忽略目录.local保存官网正文、run-billing-state.json（迁移前）、builtin-run-state.json（最新）、firestore-billing-state.json、operating-cost-estimates.json、builtin-model-validation.json与四模型实际响应；不包含在Docker部署上下文或Git提交。接续阶段记录Flutter全量344 PASS/联网1默认skip、相关29 PASS及Android/macOS Debug构建；最终后端27 PASS、相关Flutter18 PASS、analyze0。Cloud Run最终00014-dlq/100%，线上health/模型目录/匿名401/查询不扣搜索次数再次PASS；真实App client/controller→Cloud Run→Answer→本地SQLite与Widget引用点击PASS。原生/四平台真机与实际账单边界见SESSION_HANDOFF。
