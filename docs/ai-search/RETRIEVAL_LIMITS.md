# 检索条目数与教材/题目比例

2026-11-13，按官方指南、v1 Discovery schema与本项目实际请求核实。

## 官方限制

| 接口/方式 | 数量规则 |
| --- | --- |
| `:answer` / `:streamAnswer` 的自动搜索参数 | `searchSpec.searchParams.maxReturnResults` 默认10，最多25，见 [Answer指南](https://docs.cloud.google.com/generative-ai-app-builder/docs/answer) |
| `:search` 的 `summarySpec.summaryResultCount` | 文档模式 `DOCUMENTS` 最多10；检索块模式 `CHUNKS` 最多50，见 [v1 schema](https://discoveryengine.googleapis.com/$discovery/rest?version=v1)。指南示例设5，不将示例误写成通用默认值。 |
| `:search` 的 `pageSize` | 普通结构化/非结构化搜索单页最多100；基础网站25，高级网站50，支持pageToken翻页，见同一schema。 |

摘要与Answer使用不同字段，不能混用限制。纯搜索返回100条也不意味着生成模型自动阅读全部100条。

## 本项目的实现

原来的12是App为响应时间、证据长度和来源覆盖选择的策略，不是Google的12条硬限制。现可在「设置→AI搜索→检索条目数」选择1–25，默认12；来源比例在相邻设置调整。

每轮请求链为：本机设置 → `AiSearchClient`发送`result_count`/`textbook_count` → Cloud Run校验 → 两类独立Search → 来源内去重/截取/统一编号 → 内置Answer或streamAnswer → App引用和本地SQLite会话。

- 教材Search过滤 `kind: ANY("textbook")`；题目Search过滤 `kind: ANY("question")`，两请求并行执行。
- 每类先取比目标数更多的候选，按Search的排序挑选；最终最多教材n条、题目total−n条，不用混合排序让题库挤掉教材。
- 默认12条为8教材/4题；调整25条后默认比例为17教材/8题。改总数尽量保留当前比例，再允许手动调整来源。单源为0时跳过该Search；不足不拿另一来源填满。
- 传给内置回答的是 `searchSpec.searchResultList.searchResults` 的显式证据列表，**当前没有使用 `searchParams.maxReturnResults` 自动搜索**。不能把我们实现的双源配额说成Google原生支持的来源比例参数。
- 每条是教材片段或题目片段，最多2500/2000字符；≤12条沿用28000字符总预算，更大总数上限60000，并给后面来源留预算。App「参考资料」展示传入证据；正文仅引用其中实际用到的条目，模型不保证用到全部证据。
- 所有请求校验都在扣额前进行。增加条数不改变App基础1/改写2/流式3的额度策略；可能增加生成等待与Cloud Run运行时间。

## 数据库很大时会不会遗漏

Search在整个已建立的索引中寻找匹配内容，返回当次排序靠前的证据。没有选入本次证据列表的资料不会供本次回答使用；库很大、问题很宽泛时确实可能遗漏。提高条数可以增加覆盖，也可能引入重复或较弱资料，不能保证穷尽所有相关结果。

具体问题、指定教材/章节、把复杂对比拆成数问，通常比单纯增加条数更有效。当前streamAnswer强制1步改写（[官方限制](https://docs.cloud.google.com/generative-ai-app-builder/docs/stream-answer)），未实现保证覆盖全部章节的迭代检索，不能声称每个子问题都会自动按我们指定的来源比例再查一遍。

## 生成与赠金边界

当前回答使用Discovery Engine内置生成，不调用独立Vertex AI模型Token接口。官方[定价](https://cloud.google.com/generative-ai-app-builder/pricing)：Standard搜索USD1.50/千次，Enterprise含Core回答USD4/千次，Advanced另加USD4/千次；每月10000免费查询不包含Advanced。

当前一次混合来源App提问包含两次Standard Search和一次Enterprise内置回答，列表价约USD7/千次App提问；若另计Advanced则按USD11/千次预算。单源省一次Standard Search。不能直接套用“每次App请求只有USD4或USD8”。本次增加条目数保持相同API调用数量，但不把它当作账单金额不变的保证。

Search原生计费与这笔专项赠金的适用范围是两项事实；是否抵扣以赠金条款和实际账单SKU为准，未核实前不能保证100%抵扣或不扣绑定付款方式。[完整费用说明](COSTS_AND_BUILTIN_MODELS.md)。
