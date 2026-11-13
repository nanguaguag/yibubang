# 当前进度与验证

2026-11-13 Android CI最新修订：4deacbb的Android分析/测试已通过，但Flutter3.50与AGP8.11.1的API不匹配导致release失败，本机复现。Android日常与Release build-android固定Flutter3.44.6，依赖检查恢复开启；Java17通用和3分ABI release APK、签名/元数据、同版两种分析均通过，全量357 PASS/3 skip，见[最新交接](antigravity/SESSION_HANDOFF.md)。新修复未push；旧4deacbb的Linux/macOS已绿，Windows独立测试timeout仍待处理，不能宣称全部Actions通过。

2026-11-13最新修订：按用户选择恢复根README原品牌页/章节/截图并补当前App功能，保留docs与检索/选择修复。082f205的四平台CI使用Flutter3.50.0而先前本地3.44.6；补笔记try内返回的await后，独立3.50.0/Dart3.14.0实际dart analyze与CI命令均exit0、0 errors/warnings、119个弃用info。设置测试fixture隔离无关自动检查网络后，同版全量357 PASS/3联网默认skip，两种分析再次通过。旧“静态0”是3.44.6记录，不能等同于新SDK没有info；远程Actions尚未重新运行。[最新交接](antigravity/SESSION_HANDOFF.md)。

更新：2026-11-13；分支main；整理前最近提交ec0fdf6。本次提交包含检索条目设置、选择断言修复和文档整理，准确提交ID由`git log -1`查询。App版本仍是[pubspec.yaml](../pubspec.yaml)中的2.2.3+213，用户库schema25、题库schema1；没有发布新Release。

## 已实现与上线

| 模块 | 当前结果 |
| --- | --- |
| 题库与个人数据 | 正式题库只读，Question全局单列id，个人作答/收藏/流水/笔记进入user_data.sqlite，跨库统计用ATTACH |
| A01–A20修复 | 源码已分别提交；历史迁移、队列/ACK、笔记/作答一致性等验证见[修复记录](antigravity/audits/A01_A20_REPAIR_LOG.md)。同步协议v2服务端发布/真实账号验收仍是独立未完成项 |
| 首页性能 | M01精准失效刷新、M02真实路径投影指纹、M03隐藏Tab延迟挂载切片完成；未做目录阶段化与全面调度重构 |
| 医学知识库 | 五份题库来源149448唯一题/149472题块；53本教材20669页/21991教材块，总171463块已入原Search Store，删除0 |
| 教材主副本 | 原PDF、本地textbooks.sqlite、原始OCR/清洗文字/坐标和WebP均在本地；复用OCR，2991页去重，不上传整本PDF |
| 在线页图 | 私有R2页图20669张+缩略图20669张，总7714259450 bytes；textbooks.melonhu.com独立Worker签名鉴权后缓存 |
| AI回答 | 独立Cloud Run→两源Search→内置Answer/streamAnswer；无外接Vertex模型Token生成。模型选择/改写/流式/数量/比例放在设置→AI搜索 |
| 检索条目 | 可选1–25，默认12/8教材+4题；改总数保持比例，25默认17:8。独立Search汇总后传显式结果列表，不是Google原生来源配额字段 |
| 会话与额度 | SQLite本机会话/删除/追问/修改重试；每日200额度、基础1/改写2/流式3，服务端事务验证。模型查询不扣搜索额度 |
| App体验 | 默认Tab在每日计划和统计之间；Markdown引用块/粗体/公式/组合引用，教材预览关键词高亮/右侧小图，页图缩放/翻页/跳页/160页离线缓存 |
| 最近修复 | 引用/行内公式WidgetSpan内部Text不再重复注册选择段落，精确lastSelectionResult断言用例和正文选择/引用点击通过 |

## 当前线上资源

| 资源 | 配置 |
| --- | --- |
| Google项目 | yibubang-search / 520065588983 |
| Search Store | global/yibubang-medical-v1；171463块；不是RAG Corpus或Vector Search Collection |
| Search / Answer应用 | yibubang-medical-search（Standard） / yibubang-medical-answer（Enterprise），共用Store |
| Cloud Run | 东京asia-northeast1，yibubang-ai-search，00018-q7c/100%；[控制台](https://console.cloud.google.com/run/detail/asia-northeast1/yibubang-ai-search/revisions?project=yibubang-search) |
| App API | https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app |
| 模型 | 默认stable；最新官方快照指向gemini-3.5-flash/answer_gen/v1，用户可选官方内置版本；Google可能更新stable |
| Firestore | yibubang-ai/东京，设备认证、计数/租约；TTL仅清理过期限额，不保存云端聊天 |
| 页图 | R2 yibubang-textbooks，Worker yibubang-textbook-pages，自定义域textbooks.melonhu.com |

## 最近验证

- Flutter全量357 PASS、3个联网默认skip；最终选择/设置8 PASS，后端39 PASS，静态分析0；Android/macOS普通main Debug构建通过。
- 生产App25条=17教材/8题，内置模型回答、SQLite持久化、引用回调2联网PASS；非法数量/比例400且不扣额度。
- Google最终references10，正文用了第13项：25条是提供的证据上限，不保证模型采用每条或穷尽索引。增加条数不改变App1/2/3扣额。
- 教材全量散列/上传回执、原生macOS阅读器曾验收；最近设置和选择回归为Widget/模拟手势，不能代替Android/其他平台真机和大陆网络验证。

细节见[AI验收](ai-search/VALIDATION.md)、[教材实施](knowledge-base/TEXTBOOK_EXECUTION.md)与[交接](antigravity/SESSION_HANDOFF.md)。源码/测试与公开目录元数据入Git，.local日志/截图/身份凭据、知识库产物和安装包只在本地。

## 未完成与费用边界

375页医学符号/公式、版次ISBN、167题答案分歧仍需人工复核；6923题配图未OCR。新版原生实机/目标地区网络、其他平台和Release仍待验收。Embedding/Qdrant已有适配但未真实迁移；换Embedding须重算向量，无需重做PDF清洗。

混合一次提问含两次Standard Search和一次Enterprise内置回答，公开列表价约USD7/千次，若另计Advanced按USD11预算；不能直接套用单Enterprise的USD4/8。专项赠金是否抵扣尚无实际SKU账单证明；Cloud Run、Firestore TTL、Worker等也不能一概称免费。[费用说明](ai-search/COSTS_AND_BUILTIN_MODELS.md)。
