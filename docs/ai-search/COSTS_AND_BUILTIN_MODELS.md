# 内置模型、SKU与运行费用

更新2026-11-13，公开美元价格/估算均不含税，不是实际账单；日元换算、免费分配和赠金抵扣以账户账单为准。[当前状态](../CURRENT_STATUS.md) · [旧核查原文](../archive/ai-search/COSTS_AND_BUILTIN_MODELS.md)

## 当前入口与模型

独立Cloud Run（Google Cloud东京）做凭据、限额和页图签名，文本回答走Discovery Engine内置Answer/streamAnswer；没有外接Vertex模型Token调用。混合来源两次Standard Search的显式结果送Enterprise Answer，Store共用，无重导数据。

设置→AI搜索选择内置模型，默认stable。Google公开v1无内置枚举API；后端读取官方Answer模型表，App/后端先用共享快照或本机缓存，后台有界刷新，旧目录标备用。App不直连Google官网；离线可保存模型但生成仍需Cloud Run可达。查询不扣搜索额度，无付费生成枚举。

| 内置版本（2026-11-13核对快照） | 状态 |
| --- | --- |
| stable | 当前指向gemini-3.5-flash/answer_gen/v1，Google可能更新 |
| gemini-3.5-flash/answer_gen/v1 | 固定版本，真实200/SUCCEEDED |
| gemini-3-flash-preview/answer_gen/v1 | 预览版，真实200/SUCCEEDED |
| gemini-3.1-pro-preview/answer_gen/v1 | Pro预览版，真实200/SUCCEEDED |

官方四者上下文128K；实际证据仍受App1–25片段/60000字符预算限制。预览版本退役不保证永久可用，不偷偷改为外接付费模型。

## Search计费与赠金

SKU是计费条目编号，赠金不是SKU。公开查询地址https://cloud.google.com/skus；按赠金名称过滤不能得出抵扣范围，需促销条款/适用SKU组与实际报表。

| Search条目 | 公开价格 | SKU线索 |
| --- | --- | --- |
| Standard搜索 | USD1.50/1000查询 | BADA-EE26-7BDA |
| Enterprise含Core生成 | USD4/1000查询 | 93D6-7280-CF05 |
| Advanced生成附加 | +USD4/1000查询 | C232-DC00-D993 |

每结算账号每月10000免费Search查询不含Advanced。高级能力包括问题改写/简化、拆解/多步、托管多轮、推荐追问和Google回答图片/图表；App点击R2原页不等于Google多模态生成。streamAnswer强制1步改写；实际输入显式列表的Advanced计量仍需SKU账单验证。

混合一次App提问=两Standard Search+一Enterprise Answer：列表价USD7/千App问题，若另计Advanced按USD11预算；单源省一次Standard请求。不能直接套单Enterprise的USD4/8。App日200、基础1/改写2/改写流式3是用量限制策略，非Google收费倍数；调整条数不变API数量/App扣额，但可能增加运行时间。

用户赠金Trial credit for GenAI App Builder，156515 JPY，2026-03-25至2027-03-25，CSV只说明特定使用范围，没有实际SKU映射。余额未变可能与免费查询/账单延迟有关，不能据此承诺100%抵扣或不会由绑定付款方式结算。旧官方SKU组/论坛转述不能代替本赠金合同。

## 基础服务免费额度和超额价

| 服务 | 免费额度 | 公开超额价/当前条件 |
| --- | --- | --- |
| Cloud Run请求计费 | 每月180000 vCPU秒、360000 GiB秒、200万请求，结算账号跨项目共享 | 东京Tier1：CPU USD0.000024/vCPU秒，RAM USD0.0000025/GiB秒，请求USD0.40/百万；当前1vCPU/512MiB、min0/max2、并发16 |
| Firestore Standard | 1GiB存储、50000读/天、20000写/天、20000删/天、10GiB出站/月；一项目一库，太平洋日重置 | 本库GET freeTier=true；东京读USD0.038/10万、写USD0.115/10万、删USD0.013/10万 |
| R2 Standard | 每月10GB-month、100万Class A、1000万Class B，账号共享；互联网出网免费 | USD0.015/GB-month、A USD4.50/百万、B USD0.36/百万；超额计费单位向上取整；当前教材7714259450 bytes=7.714GB≈7.184GiB |
| Cloudflare Worker | Free：100000请求/天、10ms CPU/请求 | Paid至少USD5/月，含1000万请求/3000万CPU毫秒；超额USD0.30/百万请求、USD0.02/百万CPU毫秒。实际订阅未核实，未新开Paid |

不是所有费用都免费：东京Cloud Run公网出站不直接享有仅北美1GiB网络免费项；TTL删除不在Firestore普通免费删除额度；Worker缓存HIT也算Worker请求；账号其他桶/服务会共享并占用额度。Cloud Build、Artifact Registry、Secret Manager等附属服务另计。

Firestore TTL是expires_at到期后的异步托管删除，当前约3天清理限额集合，不删本机会话/设备身份；零点额度按服务器日期刷新，与TTL无关。可停用，但旧记录累积；东京删除估算USD0.013/10万，非额外部署后端。

## 按源码操作数估算

一次正常AI请求约6读4写Firestore（含认证/事务/释放/App额度查询），一次图片签名1读1写；本机签名缓存命中不请求，边缘缓存不取消已发签名。注册/目录/模型查询和事务重试另计。

假设30天/月，每AI后端请求10秒、图片签名0.2秒、额度查询0.05秒；实例时间按请求求和，未扣并发共享，免费额度未被其他项目占用。这是场景估算，不是实测月账单。

| 每日全站AI请求 | 每日签名 | Cloud Run计算/请求月费 | Firestore普通月费 | 本教材R2月费 |
| --- | --- | --- | --- | --- |
| 100 | 200 | USD0 | USD0（800读/600写每天） | USD0 |
| 2000 | 4000 | 约USD10.73 | USD0（16000读/12000写每天） | USD0 |
| 2000 | 20000 | 约USD13.04 | 约USD0.276（32000读/28000写每天） | USD0 |

不含Search/Answer、TTL、互联网出网、Worker订阅或部署附属服务。每安装日200额度、全站日2000请求是请求限制，非现金硬上限。

## 官方依据

- [Search定价](https://cloud.google.com/generative-ai-app-builder/pricing)
- [内置模型](https://docs.cloud.google.com/generative-ai-app-builder/docs/answer-generation-models)
- [streamAnswer限制](https://docs.cloud.google.com/generative-ai-app-builder/docs/stream-answer)
- [Cloud Run](https://cloud.google.com/run/pricing)
- [Firestore配额](https://docs.cloud.google.com/firestore/quotas) / [定价](https://cloud.google.com/firestore/pricing)
- [R2](https://developers.cloudflare.com/r2/pricing/) / [Worker](https://developers.cloudflare.com/workers/platform/pricing/)
- [UI Bakery介绍](https://uibakery.io/blog/vertex-ai-agent-builder)：产品概览，其Model Garden模型数不是Search内置模型目录，也不是赠金合同。

官网/云状态/实际响应只在ai_backend/.local保存，未提交凭据。最新验收见[VALIDATION](VALIDATION.md)，旧四模型/费用抓取原文已归档。
