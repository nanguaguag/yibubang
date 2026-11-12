# 医不帮可迁移医学知识库

这个目录包含独立的本地构建、Google 导入、检索验证及向量迁移工具；不修改 Flutter 应用或原始题库。默认 Project ID 为 `yibubang-search`。

## 在哪个控制台查看已导入的数据

**本次数据导入到 Vertex AI Search / Agent Search 的 Data Store。** 打开 [Search控制台](https://console.cloud.google.com/gen-app-builder/?project=yibubang-search&hl=zh-cn)，在左侧选择 **Data Stores / 数据存储区**，查找显示名称 **医不帮医学知识库 v1**、ID `yibubang-medical-v1`，位置为 **global**。点进去查看 **Data / 数据** 和 **Activity / 活动**。

也可尝试 [数据存储区列表](https://console.cloud.google.com/gen-app-builder/data-stores?project=yibubang-search&hl=zh-cn) 和 [搜索应用列表](https://console.cloud.google.com/gen-app-builder/engines?project=yibubang-search&hl=zh-cn)。如果控制台更新导致列表URL重定向，从上面的Search控制台入口进入，再选左侧菜单。应用显示名称是 **医不帮医学搜索**，ID `yibubang-medical-search`；在该应用的Preview / 预览中测试查询。

| Google产品/页面 | 资源类型 | API | 本次状态 |
| --- | --- | --- | --- |
| Vertex AI Search / Agent Search，`gen-app-builder` | Data Store和Search Engine | `discoveryengine.googleapis.com` | 已建库、导入149472块并查询验证 |
| RAG Engine，`agent-platform/rag/corpus` | RAG Corpus | `aiplatform.googleapis.com` | 本次未创建Corpus，此页面为空不代表Search导入失败 |
| Agent Retrieval（原Vector Search 2.0），`agent-platform/agent-retrieval/collections` | Collection / Data Objects | `vectorsearch.googleapis.com` | 本次未创建Collection，也未启用此API |

这三类资源属于同一个项目中的不同产品，**不会自动互相展示或复制数据**。Search服务内部提供语义索引，使用它无需启用独立的Vector Search API。RAG是“检索资料供模型回答”的方法；用Search检索正文并交给模型就能组成RAG流程，不必创建RAG Engine Corpus。

2026-11-12针对控制台位置疑问重新核对在线GET：Data Store/Standard Engine均存在；全量import仍为done=true、149460成功（另有pilot12成功）；文档列表能返回已索引题目，CD8自然语言搜索再次Top1命中1637906。回执在 `artifacts/cloud/resource-location-check.json`。官方当前[创建Data Store文档](https://cloud.google.com/generative-ai-app-builder/docs/create-data-store-es)也使用 `gen-app-builder` 控制台入口。

## 设计与迁移边界

知识库主副本保存在本地：来源 SQLite/PDF → 文本清洗 → 按全局题目 ID 合并 → 标准文档/检索块 → Google Search 或任意 Embedding + 向量数据库。

Google 的内部向量不作为可迁移资产。以后换 Embedding 模型需计算新向量，**不需要重新读取、清洗或切分题库/PDF**；换模型后查询和文档必须采用相同模型及维度。向量不能跨模型直接混用。

| 文件 | 用途 |
| --- | --- |
| `config.json` | 来源清单、版本优先级、切分参数、Google 配置；路径相对本配置文件 |
| `build.py` | 全程离线构建；源库 `mode=ro` + `query_only`；复用未变化来源的清洗缓存 |
| `validate.py` | 校验真实产物、所有来源散列、Google 格式及三个医学内容探针 |
| `cloud.py` | 设置、12块试导入、按云端成功基线增量导入、搜索测试及 RAG 证据检索 |
| `embed.py` | 以后调用兼容 Embedding API，缓存向量，导出 Qdrant 可用点数据 |
| `artifacts/current/` | 本次成功的知识库；`previous/` 保留上一个成功快照 |
| `artifacts/cloud/` | 云任务记录、导入基线、测试报告；增量同步依赖这些记录 |

默认读取仓库内旧合并库和四个拆分库；旧库独有题也会保留。**不读取 `user_data.sqlite`、账号配置、作答、收藏、斩题、个人笔记或流水。** ZIP 请先在本地解压，将其中内容 SQLite 加入来源清单；不要同时添加一个文件的 ZIP 和解压副本。

同一题目只保留一个全局文档，所有库的权威 `IdentityQuestion` 关系仍保留。来源优先级是**选择版本的规则，不代表医学正确性审定**：临床执业库20，期末拆分库10，旧合并库0；同优先级按 source ID 字典序决定，结果可复现。`corpus.sqlite` 的 `variants` 保留每个来源的内容字段及原文，`conflicts.jsonl` 记录差异。答案内容存在分歧时，检索正文和每个块都携带提示及所选来源；完整备选答案在本地文档中。

清洗使用 NFC，保留 CD8⁺、HLA-Ⅰ、单位和不等号；选项 JSON 转成有字母的文本，题干、共用病例、答案、解析、教材依据一起入库。配图仅保留引用，**没有识别图内文字**。本地1800字符切分、160字符重叠，不是1800模型tokens；短题保持完整，长题每段附带题干摘要和来源答案。

## 一、本地构建和验证

在仓库根目录执行；题库不需要额外 Python 依赖，建议 Python 3.10+：

```bash
python3 scripts/knowledge_base/build.py
python3 scripts/knowledge_base/validate.py
python3 -m unittest discover -s scripts/knowledge_base -p 'test_*.py' -v
```

主要产物：

```text
artifacts/current/
  corpus.sqlite          来源缓存、版本、关系、规范文档和检索块
  documents.jsonl        完整规范文档
  chunks.jsonl           后端无关的检索块，含稳定ID、正文、内容散列、来源、页码
  conflicts.jsonl        跨来源差异审计
  deleted_ids.jsonl      相对上一次本地构建的删除清单
  manifest.json          题量、差异、来源SHA256、产物SHA256和大小
  google_schema.json     Google字段Schema
  google/full-*.jsonl    完整Google Document格式，64MiB分片
  google/delta-*.jsonl   相对上一次本地构建的新增/修改
```

本地ID为 `question:<原始ID>`，Google ID为其稳定散列加块序号。即使内容修改，ID仍稳定。Google文件把已经清洗的HTML以 `content.rawBytes` 的base64形式装入Document JSONL，因此不需要上传十几万个单独HTML或SQLite文件。Google `structData` 保留可过滤的学科、来源、题目ID，以及可检索/可返回的正文。

构建产生的完整缓存、JSONL和前一快照可能占数GiB，本地缓存大小不是Google计费索引大小。产物在本目录的 `.gitignore` 中排除；脚本和配置正常保留。不要提交医学原始数据或凭据。构建失败保留上次成功快照；构建锁仅在确认进程已退出后才可手动删除。

## 二、Google Cloud 控制台要设置什么

进入 [项目控制台](https://console.cloud.google.com/home/dashboard?project=yibubang-search)，确认顶部选中 `yibubang-search`。

1. **Billing → Credits / 优惠额度**：打开 `Trial credit for GenAI App Builder` 条目，查看有效期、剩余额度、适用产品/SKU和绑定的结算账号。15万日元专项额度不能视为所有Google产品通用余额；Cloud Storage、其他Embedding API、独立Gemini API是否被抵扣，以此条目为准。
2. **Billing → Budgets & alerts**：给该项目设置小额日元预算，例如先设每月1,000日元，50%/90%/100%实际支出提醒及预测提醒。预算提醒不是硬性停机限额；看报表时同时查看费用和促销credit，避免净额为零掩盖额度消耗。
3. **API & Services**：启用 Discovery Engine API (`discoveryengine.googleapis.com`) 与 Cloud Storage。创建题库搜索不需要 Vertex AI Vector Search 集群、GPU、BigQuery 或 Cloud Healthcare/FHIR。
4. **AI Applications / Agent Search / Vertex AI Search**：当前官方文档正将 Vertex AI Search 改名 Agent Search，控制台也可能仍显示旧名。创建 **Custom Search / Search** 应用，业务类型用 **Generic**，按量 **General pricing** + **Standard**；开始时关闭高级生成/LLM add-on、个性化、订阅式 Configurable pricing。
5. **Data Store**：用非结构化内容/Cloud Storage数据源，位置 **global**，手动导入。数据已经在本地分块，默认数字文本解析（Digital parser），关闭Google Layout/OCR处理及额外自动切分。不要选择网页爬取或上传SQLite作为文档。
6. **Cloud Storage**：暂存bucket使用 Standard、统一bucket权限、禁止公开访问。这里默认GCS区域 `ASIA-NORTHEAST1`；它与Search数据位置 `global` 是两个独立设置。若需US/EU数据驻留，应在首次创建前一起修改配置并使用对应Search API端点。
7. **IAM**：操作者需要创建/管理Search资源和上传bucket文件的权限。工具给Search服务代理 `service-520065588983@gcp-sa-discoveryengine.iam.gserviceaccount.com` 仅在此bucket授予 `roles/storage.objectViewer`。正常搜索服务端使用专用服务账号及 `roles/discoveryengine.user`；生产端进一步限制最小权限，不在Flutter中打包gcloud凭据或管理员密钥。

本工具已自动化第3–7项中的资源创建/关联和导入权限。运行 `setup` 即可复现，不用控制台重复创建同名库。预算和专项credit条款需要在你的结算控制台查看。

实际默认资源：

| 配置 | 值 |
| --- | --- |
| Project ID / Number | `yibubang-search` / `520065588983` |
| Search location | `global` |
| Data Store ID | `yibubang-medical-v1` |
| Engine ID | `yibubang-medical-search` |
| Serving config | `default_search` |
| GCS bucket | `gs://yibubang-search-kb-520065588983` |

## 三、导入与测试命令

本机先在**自己的终端**登录；不要将访问token复制到文档或聊天中：

```bash
gcloud auth login
gcloud config set project yibubang-search
python3 scripts/knowledge_base/cloud.py inspect
python3 scripts/knowledge_base/cloud.py setup
python3 scripts/knowledge_base/cloud.py pilot
python3 scripts/knowledge_base/cloud.py sync
python3 scripts/knowledge_base/cloud.py test
```

脚本会自动发现PATH中的gcloud，或使用本机 `~/google-cloud-sdk/bin/gcloud`；也可加 `--gcloud /绝对路径/gcloud`。没有更改你的默认gcloud项目的必要，实际资源命令已经明确指定项目。

`pilot` 用12个块通过真正的Cloud Storage `dataSchema=document`导入，验证base64内容及Schema。成功后 `sync` 上传剩余新增/修改块，并等待Import operation结束。`INCREMENTAL` 保持未变化的文档；不启用Google自动生成ID，不用 `FULL` 导入delta。一次Import最多1000个JSONL分片；当前数据远低于此限制。

**云端增量基线以最后成功的Google导入为准**，不是上一次本地构建：即使先后本地构建多次而没上传，也不会漏掉中间修改。`deleted_ids.jsonl` 是可移植辅助清单；Google工具根据已成功导入的ID与当前快照比较并逐项删除。部分失败、HTTP错误或任务未结束，不推进基线。稳定ID使重试执行upsert，不增加重复文档。

测试默认只发3次搜索，不调用生成模型。对三个真实题目检查Top10是否包含对应全局ID；完整结果写入 `artifacts/cloud/search-test.json`。导入任务成功不意味着搜索索引已就绪，若第一次未命中，检查控制台Data Store → Activity和文档索引状态（也可运行 `cloud.py status`），过几分钟后重跑：

```bash
python3 scripts/knowledge_base/cloud.py test --attempts 3
```

`--attempts 3` 最多9次搜索。长任务的operation完整名称写入 `artifacts/cloud/*-operation.json`。进程超时后先查询原任务，避免反复提交：

```bash
python3 scripts/knowledge_base/cloud.py wait --operation 'projects/项目号/locations/global/collections/default_collection/dataStores/库ID/branches/0/operations/任务ID'
```

Cloud Shell也可运行同样命令，但**本地题库不会自动出现在Cloud Shell**。优先在本机完成清洗，再从本机将 `google/full-*.jsonl` 上传到私有bucket。在Cloud Shell使用OAuth登录后的gcloud进行API导入；无需上传原始SQLite、用户库或完整本地缓存。

如果用控制台手动导入：Data Store → Import data → Cloud Storage → **有metadata的非结构化Document JSONL**（`dataSchema=document`），路径只选同一次快照的 `full-*.jsonl`，不要指向混有pilot/sync/旧快照的整个bucket根目录。提供自定义Schema并应用 `google_schema.json`；自动推断后确认 `title`/`uri`映射、正文 `text`可搜索/返回、数组注解位于`items`。本轮格式使用rawBytes已通过API试导入验证；如控制台向导强制要求独立文件URI，使用本脚本API路径导入。

## 四、检索与RAG

```bash
python3 scripts/knowledge_base/cloud.py query \
  --query '为什么HLAⅠ类分子向CD8阳性T细胞提呈抗原？' \
  --output /tmp/yibubang-rag-evidence.json
```

返回5个知识块、来源标识及适合交给任意LLM的带编号证据提示词；查询一步只有Search费用，没有生成费用。用户流程可以是 Flutter → 自己的后端 → Search → 任意LLM → 带引用回答；未来将Search替换为自建向量检索，输入/输出知识块格式保持。此轮未改Flutter或发布应用后端。

`yibubang://question/...`、`yibubang://book/...` 是本工具的来源标识，可映射回本地原题/教材页码；**当前Flutter尚未实现这些deep link路由**。图片题要回原始内容看图。

若以后使用Google原生生成答案，可以在Search应用里改用Enterprise和合适的生成选项；独立API/高级生成可能有单独费用。当前本地块作为独立非结构化文档导入，满足基于检索文档的RAG；没有依赖Google专有chunk ID。Google还有原生自动切分/Bring-your-own-chunks选项，如果改为另一种索引策略，应使用新Data Store先比较，避免破坏本地稳定ID及已有同步基线。

## 五、持续扩展题库和53本教材

新增题库：把SQLite文件放到自己管理的目录，往 `config.json.sources` 添加具有稳定id的条目，然后重新 `build` → `validate` → `cloud sync`。来源路径可以是绝对路径；已有来源更新文件，保留id，改来源版本优先级或路径即可。不要为了新增题库改动既有题目全局ID。

教材PDF：将 `pdf-source.example.json` 的一个条目加入 `sources`，设置实际文件路径、书名、版次和稳定id。不同版次使用不同id，保留历史引用。`printed_page_offset` 是“PDF页码加多少等于书上页码”，例如PDF第19页为印刷第1页时是-18；目录/前言页可能得到负页码，实际引用仍保留准确PDF页码。

题库构建无依赖。需要PDF时才创建独立环境：

```bash
python3 -m venv scripts/knowledge_base/.venv
scripts/knowledge_base/.venv/bin/python -m pip install pypdf
scripts/knowledge_base/.venv/bin/python scripts/knowledge_base/build.py
```

先用1本试点，检查抽取的中文、双栏阅读顺序、表格、上下标、页码和重复页眉，再批量加入其余52本。`pypdf` 提取文字层，不是OCR；全无文本的扫描PDF会拒绝构建，部分空白页会记录在manifest，必须人工区分空白页和漏识别页。

扫描本可先用本地OCRmyPDF/Tesseract `chi_sim+eng` 处理，再导入带文字层副本；双栏/表格复杂时应使用本地版面工具人工抽查。工具也接受 `type: "pages_jsonl"`，逐行格式为 `{"page":1,"text":"本页识别文本"}`，用于接入自选OCR/版面解析器。页码必须为正且唯一，版本独立保存。所有PDF/OCR工作在本地完成，这条路径不会产生Google Layout/OCR解析费。

新增/更新可复用源清洗缓存和向量缓存。不要在构建/导入中途替换源文件或并行运行同目标导入；来源有WAL/journal时先关闭应用或使用一致的导出快照。

## 六、额度结束后迁移到自建向量库

继续使用 `artifacts/current/chunks.jsonl` 或 `corpus.sqlite`，选择所需中文医学检索Embedding模型，并确认其输入tokens上限。供应商如果提供兼容的 `/embeddings` 接口，可运行：

```bash
export EMBEDDING_API_KEY='在自己的终端设置'
python3 scripts/knowledge_base/embed.py \
  --endpoint 'https://你的Embedding供应商/v1/embeddings' \
  --model '所选模型名称' \
  --model-revision '固定版本号' \
  --batch-size 16
```

密钥只从环境变量读取。供应商不支持兼容格式时，只需替换API适配器，知识库格式无需变更。模型需要`passage:`等文档前缀时设置`--document-prefix`，查询使用对应query前缀。默认不传dimensions，避免不支持该参数的供应商报错；支持时可指定 `--dimensions`。

工具按 endpoint/model/revision/dimensions/文档前缀隔离缓存，再按文本内容SHA256复用向量；中断后已完成批次保留。相同文本只付一次Embedding费；元数据更新无需重新计算向量。模型版本变化必须换revision，避免混用旧向量。

输出 `artifacts/embeddings/*-qdrant.jsonl`，每行是 `{"id":"稳定UUID","vector":[...],"payload":{完整知识块}}`；伴随manifest给出维度及Cosine collection配置。使用Qdrant客户端分批读取并 `upsert` 即可；REST方式需把多行包装成 `{"points":[...]}` 后提交 `PUT /collections/<collection>/points?wait=true`，不能把原JSONL直接发给该REST端点。同样可导入pgvector/Milvus，保留chunk ID和引用元数据。

后续删块时，将 `deleted_ids.jsonl` 的id按 `uuid.uuid5(uuid.NAMESPACE_URL, 'yibubang:chunk:' + id)` 映射到Qdrant ID进行删除。生产向量同步应像Google工具一样保留自己的“最后成功上传基线”，避免把跨多个离线构建的删除事件漏掉。不同模型建议用不同collection并切换查询后端；新collection验收通过后再移除旧collection。

不用提前付费计算另一套Embedding来“预防迁移”；知识库主副本已独立于Google。离开Google时，停止发Search/生成请求，并按迁移计划删除Data Store/引擎及不再需要的暂存对象；**仅停止查询并不会停止超过免费额的索引存储费用**。保留本地知识库、云任务记录和向量缓存。

## 七、费用与官方资料

2026-11-12核对的General按量定价：Standard每1000次查询1.50美元；Enterprise每1000次4美元；Advanced Generative Answers额外每1000次4美元。索引存储免费额为每月10GiB、跨Agent Search共享，超出约5美元/GiB/月；按原始数据量采样计费，数据刷新不另收费。官方另列每账号每月10,000次搜索试用查询，是否与该账号现有使用叠加请查看控制台。

本库检索文本约161MiB，远低于10GiB，但它不是精确账单预测：上传Document元数据、HTML和账号内其他Data Store都需纳入。GCS暂存、请求/流量和以后独立生成/Embedding接口是另外的计费项。Google提供的自动Embedding成本在Search产品定价中体现，无需再自行调用Vertex Embedding API；本工具也没有这样调用。

只把清洗后的Document分片传Google，不传原始数百MiB SQLite、重复ZIP、用户数据或教材原PDF；只对变更块同步，先小样本测试，先不启用Layout/OCR/高级生成/订阅承诺。索引建好后从控制台Billing按服务/SKU检查真实花费和credit消耗。为了避免自动删除还在使用的导入文件，本工具不擅自配置bucket对象到期删除；完成导入和后续检索验证后，可按自己的保留周期设置生命周期规则。

- [准备导入数据与Document JSONL](https://cloud.google.com/generative-ai-app-builder/docs/prepare-data)
- [Document字段及rawBytes的1MB限制](https://cloud.google.com/generative-ai-app-builder/docs/reference/rest/v1/projects.locations.collections.dataStores.branches.documents)
- [创建Data Store](https://cloud.google.com/generative-ai-app-builder/docs/create-data-store-es)
- [Schema与字段注解](https://cloud.google.com/generative-ai-app-builder/docs/provide-schema)
- [Import API与增量/FULL语义](https://cloud.google.com/generative-ai-app-builder/docs/reference/rest/v1/projects.locations.collections.dataStores.branches.documents/import)
- [解析/自动切分/自带切分](https://cloud.google.com/generative-ai-app-builder/docs/parse-chunk-documents)
- [自带Embedding及当前维度限制](https://cloud.google.com/generative-ai-app-builder/docs/bring-embeddings)
- [官方Search定价](https://cloud.google.com/generative-ai-app-builder/pricing)

云端实际导入/搜索结果及本轮验证见 [VALIDATION.md](VALIDATION.md)。
