# 医不帮 App AI 搜索

已接入现有医学 Search Data Store，独立 Cloud Run 服务已上线。重新构建 App 后，底栏/桌面侧栏出现「AI 搜索」，默认位于「每日计划」和「统计」之间；可在原导航设置中重排或隐藏。

更新2026-11-13：Cloud Run00018-q7c/100%，每日200额度、默认改写/流式、检索1–25条/默认12和来源比例可调。[当前状态](../CURRENT_STATUS.md) · [交接](../antigravity/SESSION_HANDOFF.md)。本手册命令均从仓库根目录执行；服务代码仍在ai_backend/。

## 使用

- 输入医学问题，页面依次显示检索、整理资料和回答。默认开启问题改写与streamAnswer，收到Google文字片段后立即逐字平滑显示；Google最终全文/引用只作校正，不重复追加。关闭流式时使用基础Answer全文返回后的逐行渐入。星芒呼吸动画、等待骨架、Markdown块/列表项淡入；支持深色模式和小屏/大字体，比较表格可横向滑动。
- 设置→通用下方“AI 搜索”：选择回答模型、问题改写、流式输出，后两项默认开启。流式必须改写；开启流式自动开改写，关闭改写同时关流式。设置保存在本机，下次提问生效，已打开的AI页也会读取最新设置。
- 模型选择先显示本机缓存或随App附带的已核对备用目录，后台向Cloud Run刷新，不从App直连Google官网。后端同样有即时备用目录、官网刷新4秒超时及60秒节流，过期目录明确标记。离线仍可选择/保存模型；实际搜索仍需Cloud Run可达。查询不扣搜索额度，来源与回退见[模型与费用](COSTS_AND_BUILTIN_MODELS.md)。
- 点回答内 `[1]` 或组合编号引用及「参考资料」卡片，教材打开源版本/物理页，题目按全局 `question_id` 打开原题并带上已有作答。对应独立题库必须已在本机安装、启用；缺失时给出下载提示。既有全局查询不包含兼容回退的旧合并题库 `legacy_combined`，旧库需先迁移为独立题库。
- 底部继续输入即可追问；铅笔修改问题后重新生成，该问题以后的分支被替换。「重新回答」也会替换后续分支。停止按钮保留已收到的内容。
- 右上角历史按钮切换/删除会话，旁边加号开启新会话。生成期间先停止，再切换或删除。
- 会话写入 `user_data.sqlite` 的 `AiSearchSessions` / `AiSearchTurns`，约每 700 ms 保存一次，结束时再保存。异常退出后显示「回答已停止，内容已保留」。用户库升级 v24→v25；不改题库或 Question 主键。
- 对话不加入现有跨设备同步。已有整库 SQLite 备份包含这些本地表；删除会话不重置搜索额度。

## 已部署资源

| 资源 | 配置 / 控制台 |
| --- | --- |
| 项目 | `yibubang-search` / `520065588983` |
| Cloud Run | [yibubang-ai-search，东京](https://console.cloud.google.com/run/detail/asia-northeast1/yibubang-ai-search/revisions?project=yibubang-search) |
| App API | `https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app` |
| Search | 既有 `global/yibubang-medical-search`，Standard；教材/题库独立检索，默认8教材+4题，可选总数1–25和来源比例；原Data Store `yibubang-medical-v1`，171463块 |
| 内置Answer | `global/yibubang-medical-answer`，Enterprise，共用原Store；仅此应用开启API要求的LLM生成开关，默认streamAnswer/1步改写，无需再导入知识库 |
| 限额数据库 | [Firestore：yibubang-ai](https://console.cloud.google.com/firestore/databases?project=yibubang-search)，Native/Standard，东京 |
| 回答模型 | Search内置 `stable`（当前官方快照指向gemini-3.5-flash/answer_gen/v1），可选择其他官方内置版本；只调Discovery Engine :answer/:streamAnswer，无独立Vertex Token调用 |
| 容器 | CPU 1 / 512 MiB；min 0 / max 2；concurrency 16；Cloud Run 请求上限 180 秒，检索+生成总上限 165 秒 |

运行账号 `yibubang-ai-runtime@yibubang-search.iam.gserviceaccount.com` 的自定义推理角色只包含 `discoveryengine.servingConfigs.search` 和 `discoveryengine.servingConfigs.answer`；移除旧Vertex预测权限。`roles/datastore.user` 通过 IAM condition 限定 `projects/yibubang-search/databases/yibubang-ai`。Google 凭据来自运行账号 ADC，不写入 App。Cloud Run 对外可访问，搜索/模型接口另验安装凭据；匿名请求返回 401。

部署需要API：Cloud Run、Cloud Build、Artifact Registry、Firestore和原有Discovery Engine。旧Vertex API开关没有擅自禁用，但本后端已不调用独立模型。没有创建重复知识库，也不需要启用Vector Search API。

Firestore 仅保存设备凭据哈希、服务端计数和并发租约；两个按日计数集合的 `expires_at` 已设置 TTL，约三天后异步清理。TTL是Firestore托管删除规则，不是另一套后端部署；可停用而不影响搜索，但过期限额记录会累积。TTL删除不享受普通免费删除额度。零点配额由服务器日期判断刷新，不依赖TTL准点删除。设备凭据记录保留以免重新注册重置额度。**当前问题与最多三轮已完成历史会经服务端发给 Google，用于本次回答**，服务端不持久化对话，也不主动记录问题、回答、凭据。Cloud Run 自动请求日志仍有连接信息和 URL。

## 限额与防滥用

| 规则 | 默认值 |
| --- | --- |
| 每安装/天 | 200 次额度，北京时间 0 点刷新，使用服务器时间 |
| 每次AI扣额 | 基础1、仅改写2、改写+流式3；200额度最多200次基础或66次默认高级，余2次可选非流式模式 |
| 每安装/分钟 | 6 次 |
| 每安装并发 | 1 个，180 秒租约；正常结束/失败/断连释放，崩溃自动过期 |
| 每 IP/天 | 300 次 |
| 全站/天 | 2,000 次 |
| 每 IP 新注册/天 | 3 个安装 |
| 全站新注册/天 | 100 个安装 |
| 输入 | 问题 2,000 字，最多三轮历史，实际请求体 64 KB；App 根据 UTF-8 字节数裁掉过长的最早历史 |
| 上游输出 | 基础Answer不暴露maxOutputTokens；返回超过12000字符拒绝显示并提示缩小问题范围，失败/无证据明确标记 |

计数在Firestore事务中先按服务端核定的1/2/3权重扣额度再检索和生成；余额不足3次时拒绝默认高级请求，允许剩余额度对应的基础/仅改写模式。客户端自报quota_cost、时钟或余额不能绕过。已受理的重试、修改、上游失败和取消也扣本次权重；校验/限额拒绝不扣。最近同一请求ID重放返回409。IP/全站/分钟限额仍按实际请求数计，未重置已有计数。客户端停止保留已显示内容，已受理上游请求不保证退款。模型目录不发付费生成探针。

安装凭据不是不可伪造的硬件身份证；清 App 数据、复制安装凭据、换 IP/批量脚本仍是边界。当前 IP 取直接 Cloud Run 入口追加的最右地址哈希，线上已对照请求日志 remoteIp 验证；如果以后加负载均衡器/CDN，必须重审可信代理链，不能直接沿用该规则。

正式大规模发布建议下一步接 Android Play Integrity、iOS App Attest，以及桌面账号/一次性人机验证；按账号叠加限额并配 Cloud Armor 入口速率限制。IP 限制可能影响校园/医院共享出口，当前值适合控制试用成本，用户增长后按实际情况调整。随机安装 ID、IP 和全站配额只能降低滥用，不能替代平台证明或边缘防护。

### 调整与停用

Cloud Run 控制台「修改并部署新修订版本」→变量与密钥，可调整：

- `GLOBAL_DAILY_LIMIT`：全站总搜索，默认 2000；设为 `0` 可立即停止新搜索（需发布新修订）。
- `IP_DAILY_LIMIT`：共享网络每日总搜索，默认 300。
- `ANSWER_MODEL`：默认内置回答模型，默认stable；用户在App选择的官方有效版本优先。
- `SEARCH_ENGINE`：标准检索引擎；`ANSWER_ENGINE`：内置生成引擎。设备200额度/天、6请求/分钟及注册限额在policy.py/app.py中修改并重新部署。

App的1+1+1=3是用户要求的额度策略，不表示Google一定按3倍收费。内置生成归Search费用，无独立Vertex模型Token调用；当前两Standard+一Enterprise列表价约USD7/千次App提问，若另计Advanced按USD11/千次预算。专项赠金的实际适用SKU/免费分配/抵扣以条款和账单为准。Cloud Run请求/Firestore即使拒绝也可能有成本。全站次数不是现金硬上限。[模型与费用](COSTS_AND_BUILTIN_MODELS.md)。

单纯搜索+生成不经过Cloudflare Worker：App→Cloud Run→Discovery Engine。Worker仅服务教材页图/缩略图的短时签名鉴权和边缘缓存，图片流量不经Cloud Run转发。与原有同步Worker独立。

## 构建与重新部署

App 已内置线上 URL，正常 `flutter run -d macos` 或 `flutter run -d <设备>` 即可。更换地址：

```sh
flutter run -d macos --dart-define=AI_SEARCH_ENDPOINT=https://你的服务地址
```

部署脚本会复用同名数据库/账号/角色，配置 TTL，并部署独立服务：

```sh
ai_backend/.venv/bin/python ai_backend/deploy.py --project yibubang-search --gcloud /path/to/google-cloud-sdk/bin/gcloud
```

已经 provision 后仅部署代码：

```sh
gcloud run deploy yibubang-ai-search --source=ai_backend --region=asia-northeast1 --project=yibubang-search
```

本地依赖和检查：

```sh
python3 -m venv ai_backend/.venv
ai_backend/.venv/bin/pip install -r ai_backend/requirements.txt
ai_backend/.venv/bin/python -m unittest discover -s ai_backend -p 'test_*.py' -v
flutter analyze --no-pub
flutter test --no-pub
```

线上完整探针（每次消耗两次检索/生成）：

```sh
ai_backend/.venv/bin/python ai_backend/smoke.py
```

只检查注册、health、额度与匿名拒绝，不调用模型：

```sh
ai_backend/.venv/bin/python ai_backend/smoke.py --check-only
```

探针凭据首次随机生成，保存于忽略的 `ai_backend/.local/smoke-device.json`，权限 0600。不要把它加入版本控制。完整探针会验证流式终止、引用、追问、请求重放和额度准确减少。管理员限额验收脚本 `smoke_limits.py` 只临时设置专用探针设备的计数并在 finally 恢复，不动全站/IP计数或用户安装：

```sh
ai_backend/.venv/bin/python ai_backend/smoke_limits.py --gcloud /path/to/gcloud
```

## 后续知识库迁移

当前服务读取原有 Search Engine，新增题库仍按 [知识库手册](../knowledge-base/README.md) 本地 build/validate→增量 sync，App 无需重建本地会话。额度结束迁到自建向量库时，用原有标准 JSONL、稳定 chunk ID 和全局 question ID 替换服务端检索适配，继续保留 SSE 协议、引用字段与 App 会话表，不必重新清洗源数据。

53本教材已本地处理并导入清洗文本；页图和缩略图在私有R2，经textbooks.melonhu.com短时签名访问。App支持教材引用、逐页阅读/缩放/跳页/离线缓存；原PDF仍在本地。新增教材按既有本地增量管线，不把PDF引用当原题ID。

[验证记录](VALIDATION.md) · [页面源码](../../lib/screens/ai_search_page.dart) · [客户端](../../lib/services/ai_search_client.dart) · [服务端](../../ai_backend/app.py)


### 可调整检索条目与比例（2026-11-13）

设置 → AI 搜索 → 检索条目数，可选总数 1–25，默认 12。调整总数按当前比例四舍五入分配教材/题目（默认8:4改为25条时为17:8）。再进入「教材与题目比例」可选择教材 0–总条数；题目上限为总数减去教材条数。条数指提供给内置回答的检索片段，不保证每次足量命中，也不代表读取整本书或全部题库。

`/v1/search` 可选 `result_count`（严格整数1–25，省略12）和 `textbook_count`（严格整数0–总数，省略约2/3教材）；校验在扣额度前完成。旧客户端仍默认8:4。只有一种来源时跳过另一来源的 Search 请求，不自动拿另一来源填满不足结果；教材在前统一编号。总数≤12沿用28000字符预算；更大总数按条数增长至最多60000字符，并为后续题目保留预算。纯教材检索不受此设置影响，每日200和基础/改写/流式1/2/3使用额度不变。

客户端每轮重读本机设置，保留内置 Answer 模型与本地会话。此次只更新应用/独立 Cloud Run，不导入数据或上传页图。

Google默认/最大条数、当前两源检索与显式证据列表的区别、费用边界见[检索数量说明](RETRIEVAL_LIMITS.md)。
