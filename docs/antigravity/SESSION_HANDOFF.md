# SESSION_HANDOFF.md - 跨会话开发交接记录

<!-- AI_SEARCH_COMMIT -->
## 2026-11-13 用户授权提交 AI 搜索与教材功能

- 提交范围：此前本地处理53本教材/增量上传工具、私有R2页图Worker、教材检索/引用/缓存阅读器、Search内置Answer与模型本机回退、高级流式与200额度，以及最新Markdown/设置一致性/缩放/快捷键/默认Tab/检索比例六项修订；保留先前实现，不拆出缺少依赖的客户端或服务端。
- 验证：沿用同一源码Flutter355 PASS/3联网默认skip、后端36 PASS、静态0、Android/macOS Debug构建通过、生产App6:6联网2 PASS。提交前补充知识库Python18 PASS和Worker鉴权/过期/路径/散列/缓存PASS，Git差异与文件清单复核。
- 只提交源代码、公开目录元数据、回归测试和文档；.local凭据/日志/截图、外置盘PDF/页图、知识库生成产物、虚拟环境、APK/App保持忽略。用户仅授权commit，本次不push或发布Release。
- 下一次第一步：git log -1与git status核对提交，再读最新六项交接，按用户实机反馈验证Android缩放/大陆网络。待验收边界仍为375页符号公式人工医学复核、版次ISBN、其他平台真机及赠金实际SKU账单。
<!-- /AI_SEARCH_COMMIT -->


<!-- AI_SEARCH_FEEDBACK -->
## 最新交接：2026-11-13 AI 搜索六项反馈

- 用户当前要求：修复嵌套列表/中文括号粗体、AI 设置 UI 全组重写且说明弹窗、Android 教材缩放、桌面 Shift+Enter/方向键翻页、默认 AI Tab 位于每日计划和统计之间、客户端教材/题目比例可设置。
- 完成：AiAnswerText 行内连续段落合并 + 中文粗体括号边界扩展；标准解析其余内容保留。AiSearchSettingsGroup 全部沿用 InfoCard/IconTile/Switch，模型单选自适应弹层、说明仅弹窗、比例 0–12 Slider+保存/取消，稳定版短标签。320/1000px 真字体图标截图已人工查看，最新回执 .local/screenshots/feedback-*。
- PhotoViewGestureDetectorScope(axis:horizontal) 优先双指并保留拖动/边缘翻页；阅读器全页 Focus 支持方向键，路由/输入框/组合键保护。AI 桌面 Shift+Enter 会发送，普通 Enter/输入法组词/KeyRepeat 不提交。真实 FileImage+临时缓存+双触点测试通过，未触及本机正式缓存。
- BottomNavConfig 默认 subjects/daily_plan/ai_search/statistics/profile；已有五项排序/隐藏状态保留，旧四项补到默认邻居前。测试改为用 ID 定位，避免对旧索引产生假验收。
- options.textbookCount SharedPreferences 保存，每次 Search payload textbook_count 重读；服务端校验 int0–12 后预扣原有额度，retrieve 默认 8+4/可选0+12或12+0，一种来源0时不发送其请求、总证据/统一编号/不足来源独立保留。未改 Google Store、数据、计费入口和每日200/1–3额度。
- 当前已部署东京 Cloud Run 00016-lbf/100%，使用现有配置/账号与 Search 内置 Answer。后端 36 PASS；Flutter 全量 355 PASS/3 默认 skip，所有新增交互回归通过。最终flutter analyze0，Android/macOS Debug构建成功。生产App6:6请求→Cloud Run→Google内置Answer→本地SQLite→引用Widget2项联网PASS，12证据正好6教材/6题；错误比例4项400且余额不变PASS。新增模型离线单选UI在320/1000px仍可选/保存PASS，新9项设置/模型回归通过。
- 回执：ai_backend/.local/feedback-{full-tests,backend-tests,reader-tests,gestures-tests,settings-visual-tests,app-live,final-analyze,deploy,android-build,macos-build}.log；feedback-app-live.json / feedback-online-check.json及screenshots/feedback-*。App联网只使用既有专用smoke设备，花3次App额度，没有重置真实用户计数。macOS已打开最新Debug；AndroidAPK已构建，真机待用户安装确认。
- main@02ea2ba，起始大量此前教材/Markdown/高级设置未提交变更全部保留。本目标不 commit/push/Release，没有用户库 schema/题库写入或重复上传。
- 本次闭环完成：最终分析、生产 App 6:6 核验、新 Debug 构建、文档/范围复核；无待处理构建或部署进程。下一次第一步核对 Git、本段和 .local/feedback-*.log，使用最新 Debug App 依用户真机反馈处理，勿重复导入知识库。375页人工医学校对、Windows/Linux/iOS/Android真机和大陆网络、专项赠金 SKU 账单仍属此前未验收项。
<!-- /AI_SEARCH_FEEDBACK -->


<!-- ADVANCED_AI_SETTINGS -->
## 最新交接：2026-11-13 默认高级、AI设置与200额度

- 本段覆盖基础省钱阶段：用户要求体验优先，已默认改写+streamAnswer。设置→通用下方AI搜索组包含回答模型、问题改写、流式输出；原AI页模型按钮移除。开关按Google限制联动；保存SharedPreferences，新请求在旧client实例上也重读最新模型/选项。
- 服务端每安装日200额度，generation_options严格bool/禁止stream=true且rephrase=false，按1/2/3在Firestore原子预扣，客户端自报扣额不能绕过；剩2拒默认高级而允许基础/仅改写。旧used值保留，无重置/用户库schema变化。分钟6/IP300/全站2000仍按真实请求。默认200额度最多66次高级，余2可选其他模式；App文字明确3倍仅指额度。
- builtin_answer.answer_packets增量JSON数组解码，处理网络/UTF-8边界与截断；STREAMING文字立即SSE，最终SUCCEEDED全文不追加第二遍，answer事件校正迟到引用，controller等显示队列完成再覆盖。Google内置模型/外部两源证据保持，无独立Vertex回退。真实Google首文本2.2s/完成2.78s，线上Cloud Run样本首2.8s/总3.7s/6delta，非性能承诺。
- 模型离线：新增ai_backend/answer_model_catalog.json为已核对4模型快照，同时Flutter asset与DockerCOPY，.dockerignore仅放行此公共JSON。App先本机缓存/快照立即展示、后台有界刷新，失败仍可选/保存；后端冷启动立即快照、后台官网刷新（4秒/60秒节流），官方缓存超过24小时标记回快照。Google官网仅后端访问；Cloud Run不可达时目录仍可选，但搜索不能离线生成。
- 最新部署00015-rlt/100%，health默认双开/200。后端33 PASS，Flutter全量348 PASS/3联网skip，最终静态0；真实App client/controller→Run→streamAnswer→SQLite与引用Widget2 PASS。线上三模式扣1/3/2、12证据含8教材与模型查询不扣额PASS。Android/macOS Debug完成；200日额/分钟6/并发/重放/错误凭据五项线上PASS，专用测试字段restored=true。两条TTL GET均ACTIVE。原生新设置/四平台真机/大陆网络/Release尚未验收，当前运行旧macOS进程需重启最新Debug。
- 忽略回执：.local/advanced-online-validation.json、advanced-run-state.json、advanced-ttl-state.json、stream-answer-probe.json、advanced-app-live.log、advanced-full-tests.log、advanced-backend-tests.log、advanced-settings-tests.log、advanced-final-analyze.log、advanced-limits-validation.log、advanced-deploy.log及advanced-*-build.log。联网测试复用专用smoke设备，未输出/提交凭据；额度实扣9（线上6+App3），限额测试只临时改此设备且完整恢复，无真实用户计数修改。
- TTL保持ai_request_limits/ai_registration_limits的expires_at，3天过期托管删除；不是另一套服务，也不是配额零点刷新条件，停用可运行但旧记录累积，删除无免费额度。仅图片走Cloudflare Worker，搜索推理直达Cloud Run/Discovery Engine。Google1/2/3次额度不等于其SKU计价；赠金具体抵扣/Advanced实际计量仍未取得账户账单，不按用户引用断言免扣卡。
- 未commit/push/Release，无重导171463文本或上传教材；main@02ea2ba，所有此前未提交教材/Markdown工作保留。下一次第一步核对Git、本段和health，启动最新Debug体验设置与流式；账单反馈按Search各SKU核赠金，不重复造库。用户若要每天200次高级请求，应另明确调整总额度到600；本次按其200额度/高级扣3要求实施。
<!-- /ADVANCED_AI_SETTINGS -->

<!-- BUILTIN_ANSWER_MODELS -->
## 最新交接：2026-11-13 内置Answer、模型选择与费用说明完成

- 本段优先于下方“尚未迁移”历史：用户选择省钱/逐行渐入后已上线内置基础Answer。东京Cloud Run最终00014-dlq/100%，ANSWER_MODEL=stable，旧Gemini环境/预测权限移除；角色仅discoveryengine.servingConfigs.search/answer，Firestore/页图Secret权限保留。
- 原Standard yibubang-medical-search保留两源检索、最多8教材+4题；新Enterprise yibubang-medical-answer共用原yibubang-medical-v1，无重新导入。新应用最小Answer实测必须SEARCH_ADD_ON_LLM，否则400；请求禁用rephrase/relatedQuestions，无托管session。基础Answer完整返回后App140ms逻辑行推进、Markdown块/列表项渐入，非真实token流；UTF-8引用字节偏移按本轮URI映射。
- /v1/models读取官方Answer模型表（Google v1无内置枚举API），缓存1小时/刷新节流60秒/失败回退最多24小时。本轮修过期在节流内被复活的问题并增加回归。App右上调节图标→回答模型→刷新/选择，SharedPreferences与AiTurn payload持久化，无schema变更。stable当前3.5 Flash，另3.5固定版、3 Flash preview、3.1 Pro preview；四项真实200/SUCCEEDED、慢阻肺气流定义PASS。
- 生产App client/controller→Cloud Run→Answer→本地SQLite实际回执及Widget引用点击PASS，12资料含8教材。当前后端27/相关Flutter18/analyze0；接续阶段全量344及Android/macOS Debug构建记录保留。最终部署后仅health/目录/匿名拒绝/不扣额度复核，不重复付费生成。忽略回执ai_backend/.local/builtin-final-online.json、builtin-run-state.json、builtin-model-validation.json、builtin-service-answer-live.json、builtin-app-live.json、screenshots/builtin-ai-live.png；最终logs为builtin-final-*。
- ai_backend/COSTS_AND_BUILTIN_MODELS.md列SKU/高级功能/三项免费及估算。两Standard+一Enterprise列表价USD7/千App问题，若附加Advanced保守USD11，不能当一API USD4。本赠金CSV只有特定范围，实际适用SKU/免费分配/Advanced计量未证实，不承诺免扣卡。Firestore实际freeTier=true；R2教材+小图7.714GB，免费账号共享；Worker实际订阅未查明。
- 未完成：上述账单与赠金映射、原生缩略图系统确认、Windows/Linux/iOS/Android真机/大陆网络、Release。当前macOS运行进程仍旧版，最新Debug已构建，重启后可体验模型选择；Widget截图不是原生新页面验收。未commit/push/Release，main@02ea2ba及已有全部教材/Markdown现场保留。
- 下一步第一项：核对Git、本段、费用说明和线上health；若有结算报表，分别核Search Standard/Enterprise/Advanced SKU及本赠金ID抵扣。产品反馈先重启最新Debug核验模型选择/缩略图，不重复导入171463文本或上传PDF/20669页图，不凭余额不变推定免费。
<!-- /BUILTIN_ANSWER_MODELS -->

<!-- SEARCH_BILLING_REVIEW -->
## 最新交接：2026-11-13赠金与API入口核查（尚未迁移）

- 用户质疑独立Gemini费用是否抵扣专项赠金；实际仍Cloud Run latest00011-mm9/100%，两次Discovery Engine Search后独立Vertex gemini-3.8-flash/global生成，ADC服务账号。只读GET原Engine仍SEARCH_TIER_STANDARD，原Store与数据完整保留。
- 已核实官网Search定价、Answer模型和v1 schema：Enterprise含Core生成，Advanced另计；stable当前gemini-3.5-flash/answer_gen/v1；searchSpec.searchResultList允许自选检索片段；streamAnswer不可禁用一次rephrase。迁移有功能路径但尚未测试，不能声称已上线或只收一次USD4/1000。
- 找到Google论坛用户转述Support的两组官方SKU清单，均已标废弃且范围不同，一组含部分Vertex模型。赠金CSV没有实际SKU映射，不能据旧论坛或余额不变承诺所有生成抵扣；已异步请求本赠金条款/适用SKU。独立模型未获抵扣部分可能由绑卡结算，没有实际扣卡记录。
- 本轮只追加ai_backend/SEARCH_IMPROVEMENTS.md复核段与两份交接/状态文档，官网与schema/GET回执在忽略的.local；无产品改动、重新导入、部署、commit/push或付费生成调用。此前教材/Markdown全部未提交工作保留，原生缩略图显示仍待系统签名确认。
- 下一步第一项：读取本赠金适用SKU/条款（如用户回复）与本段，区分确定的Search内置计价和仍未证实的账户赠金抵扣。用户明确要求切换后，复用原Store评估Enterprise+内置Answer/streamAnswer，保留两源教材优先、引用和本地session；避免默默回退收费Vertex模型，验证实际多API计量及Advanced功能配置后部署。不凭本轮质疑擅自改变计费SKU。
<!-- /SEARCH_BILLING_REVIEW -->

<!-- SEARCH_IMPROVEMENTS -->
## 2026-11-13 AI检索与Markdown修订（功能/部署/数据完成，原生小图显示待系统确认后验收）

- 原缺陷确认：Markdown仅子集且只识单编号；混合pageSize6遮蔽教材；前两问无条件拼接污染新话题。
- 修订CommonMark/GFM AST原生渲染引用块/列表/代码/表格和LaTeX内联/独立公式，组合引用拆分逐号点击；非法/未闭合公式回退文字、代码不转换、外部链接不能任意导航。
- 后端两次并行Search候选教材12/题8，去重后最多8教材+4题、教材在先重编号，总证据28000字符；只明确省略追问用上一问，独立新话题不污染。两种慢阻肺真实搜索12证据相同/气流定义PASS。latest00011-mm9/100%。
- textbooks.melonhu.com绑定独立页图Worker，鉴权在缓存前、稳定版本key边缘缓存。20669缩略图本地完成/上传完，377590170 bytes、全部本地/R2成功SHA一致；真实签名小图21.5KB/2.07s→HIT0.46s，不扣搜索次数。App右侧缩略图和关键词底色高亮实现。
- Flutter340全量基线/最终15相关、后端21、WorkerPASS，最新analyze0；Android/macOS Debug通过；App组件生产检索PASS，原生真实缩略图显示核验待macOS“身份不明且版本不同”签名确认（已定位系统弹窗，测试尚未启动，不能称PASS）。
- 线上模型gemini-3.8-flash/global/LOW；官方当前USD0.75输入/3.75输出含推理每百万tokens，2027-01-01起1.50/7.50；真实10770输入/204输出/0推理约USD0.00884，单独token SKU。赠金CSV仅限定使用，无法证明适用独立Gemini；Search每月10000免费查询+账单延迟最可能解释未扣赠金，JPY账号已核对，无billing export。
- 本目标未commit/push/Release；原生测试被系统新签名确认挡住未进入断言，已停止测试进程/恢复普通main Debug并open；下一步用户点“仍要打开”后实际检查AI与教材预览，或重跑integration_test/textbook_reader_test.dart。生成费用赠金条款仍待明确，不需再次处理/上传20669图。。手册ai_backend/SEARCH_IMPROVEMENTS.md；此前教材实施改动完整保留。
<!-- /SEARCH_IMPROVEMENTS -->

<!-- TEXTBOOK_IMPLEMENTATION -->
## 2026-11-13 53本教材实施（处理、Google、R2、App验收完成）

- 用户已明确授权按方案处理/上传/开发，覆盖上一轮先讨论约束。main@02ea2ba开始干净；本目标没有commit/push/Release发布。
- 原PDF留本地；53本20669页复用OCR，2991页双层去重（原始序列0交错），16558书页标签候选。36页无索引文字、239稀疏候选、375页符号/公式待人工复核，版次/ISBN未人工确认。
- 外置盘可迁移主库/原始OCR/清洗JSONL/坐标与20669张WebP完整保存；R2私有桶yibubang-textbooks全量上传完成，7336669280 bytes=6.833GiB。53原PDF与20669本地页图重新计算SHA，全部R2成功SHA回执匹配，页图manifest无漏页/重复；verify_textbook_release.py PASS。
- Google yibubang-medical-v1/原Engine：21991教材块+原149472题块，删除0，171463导出hash全部有成功回执。407复核标记增量任务8079863690164527043全成功；在线GET/Search发现新字段仍缺失，随后仅PATCH structData补齐（1试点+406），407条逐项GET核验PASS，未重传正文。真实Search及Cloud Run教材检索返回needs_review=true PASS。
- Cloud Run最新00008-hj6/100%；独立Worker短时阅读签名/上传密钥分离，Google运行账号仅指定Secret accessor。全部上传进程已正常结束，无待续传任务；三个教材末页通过正式鉴权签名接口下载、SHA一致且不扣搜索次数。
- App入口：AI搜索右上书本→教材检索/书名筛选/关键词预览→原页；题目/教材引用兼容旧本地会话，源版本+物理页定位。缩放/翻页/跳转/重试、160页稳定键缓存与离线阅读。AI/教材共用每日100搜索；图片独立1000/天、60/分钟。
- 验证：337全量Flutter PASS（联网1项默认skip），相关22 PASS；最新客户端缓存后相关14、analyze0、管线18/后端18/Worker PASS。真实App→Cloud Run→Google检索、混合AI引用与图片安全测试PASS；macOS原生引用→放大→翻页101→跳转125→离线缓存PASS。最新Android/macOS正常main Debug构建成功，恢复产品入口；测试回执/截图仅保存在被忽略的.local/artifacts。
- 本次最后操作：更新操作记录、功能矩阵与交接，Git范围/diff检查；启动最新macOS Debug App。下一会话第一步：先核对Git与scripts/knowledge_base/TEXTBOOK_EXECUTION.md，再按实机反馈处理；增加教材复用本地管线、原Store和增量成功账本，不重复导入原题或上传PDF。
- 未验收：375页医学符号/公式人工校对、版次/ISBN确认、Windows/Linux/iOS/Android真机及目标地区网络、Release发布。Google专项credit实际SKU抵扣/账单仍未确认，不宣称这些已完成。
<!-- /TEXTBOOK_IMPLEMENTATION -->


<!-- TEXTBOOK_PLAN_REVIEW -->
## 最新交接：2026-11-12 三项commit与53本PDF方案（禁止直接开始处理）

- 用户授权commit；已分别提交c911b06首页优化、71e9241知识库工具、105c942 AI搜索。暂未push。被忽略的.local凭据、知识库artifacts、教材和构建产物未纳入提交；技术债文档依旧为本地被忽略文件。
- 新用户约束：尽量本地、省钱、不上传整本PDF；文字搜索定位页面并在线打开图片；当前只说方案，不批量处理或上传。
- 来源为/Volumes/My PSSD/书籍/自用53本课本（可复制）；53份PDF/16.283GiB/20669页/224–982页，元信息全部可读。11本22页只读抽检扫描图+隐藏OCR；诊断345/内科492/外科426页有HiddenHorzOCR旧组和SimSun组重叠，正文重复。妇产类似producer但正文未抽检，不冒充全书质量验收。
- 方案已写[TEXTBOOK_PLAN.md](../../scripts/knowledge_base/TEXTBOOK_PLAN.md)：本地读已有OCR、选择层/坐标去重与医学符号质检，异常才补OCR；SQLite/JSONL主库，Google仅清洗文本，独立私有R2页图（GCS备选），PDF物理页唯一定位、版次/源版本明确，教材纯查页不调用Gemini。R2/Google价格有官方链接，页图体积仅假设未压缩测试。
- 当前构建器只有页文本，App引用只认question_id；需后续扩展页/坐标主库、书籍字段、教材引用类型、鉴权图片接口和阅读器。没有本轮产品/schema/cloud配置变更或教材导入。
- 下一次第一步：核对Git并读方案与用户最新反馈；用户没有要求实施前继续方案讨论。不要把文件路径提供或当前commit授权解释为教材批量OCR/渲染/上传授权，不直接运行knowledge_base build/config改源或cloud sync。
<!-- /TEXTBOOK_PLAN_REVIEW -->


<!-- APP_AI_SEARCH -->
## 最新交接：2026-11-12 App AI 搜索与Cloud Run完成

- **用户授权**：独立Cloud Run由代理配置并部署；本目标无commit/push/Release发布授权。
- **完成**：7个新Flutter文件（模型/本地store/HTTP SSE client/controller/页面/星芒/Markdown引用），首页/导航/schema最小接入；本地会话与编辑追问、停止/恢复、引用原题、Material动效/表格；独立ai_backend（FastAPI策略/SSE/部署/探针/11项测试/中文手册）。
- **线上**：project yibubang-search，Tokyo Cloud Run yibubang-ai-search/00003-cl2/100%；URL https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app 已写默认客户端；Firestore yibubang-ai，runtime SA最小2项推理权限+数据库IAM条件。原Search yibubang-medical-search未重新导入，Gemini gemini-3.8-flash/global/LOW。
- **限额**：100/安装/北京自然日、6/分钟、1并发租约180秒；IP300/天、全站2000/天、注册IP3/全站100；正文64KB、历史3、token2048，已受理失败/停止/重试计数。检索+生成总超时165秒。代理IP键与线上remoteIp哈希核对一致，以后加LB/CDN需重审。
- **验证**：最终Flutter334/334、analyze0、Python11/11；两轮真实搜索+追问，最终修订首字3.04s/2.58s、98→96额度，401/409符合；线上日额100、分钟6、并发429、重放409/错凭据401通过，专用测试设备字段已恢复。AndroidDebug APK和macOSDebug App均成功；真实字体/图标六张截图在ai_backend/.local/screenshots。凭据/回执.local被忽略且不输出令牌。
- **工作区**：main@d862099；开始已有首页优化5个产品文件/3测试/文档与knowledge_base完整保留，不擅自提交；本轮只AI相关新增/改动和知识库更新。KNOWN_ISSUES既有改动不归本轮。
- **边界/未完成**：Play Integrity/App Attest、账号/边缘防护未接（安装ID可重置）；专项Search credit对生成/Run/Firestore的抵扣未验账；Windows/Linux/iOS/Android真机和国内网络未验证；Release未发布。53PDF未提供/教材页码阅读器未实现；本地会话不跨设备同步。
- **下次第一步**：核对Git现场并读[ai_backend/README.md](../../ai_backend/README.md)/[VALIDATION.md](../../ai_backend/VALIDATION.md)，运行新构建体验AI栏，按用户实机反馈处理；不要重复创建Store或导入149448题。需要改后端时gcloud run deploy --source=ai_backend并重跑探针；不修改测试设备以外的线上计数，不把.local凭据加入版本控制。
<!-- /APP_AI_SEARCH -->


<!-- MEDICAL_KNOWLEDGE_BASE -->
## 最新交接：2026-11-12 可迁移医学知识库构建/导入/验证完成

- 完成：五份只读内容库→149448题/149472块、源SHA256/完整产物/3医学探针PASS、Python14/14、缓存无变化build零delta；标准文档/块/来源版本、Google工具、RAG证据、PDF接口、未来Embedding缓存/Qdrant导出、中文手册。
- 云端：yibubang-search/global/yibubang-medical-v1，Standard Engine yibubang-medical-search，私有bucket yibubang-search-kb-520065588983；pilot12/12 + 全量149460/149460成功0失败，最终12:04:20 UTC完成。三题搜索3/3（排名5/1/1），CD8自然语言改写Top1，后续sync上传/导入0、删除0。artifacts/cloud保留149472个成功ID/hash基线、import/search/rag/final-summary回执。
- 未完成的扩展：53本教材PDF未提供；6923题配图未OCR；167题来源答案正文分歧已提示、未医学审核；EmbeddingAPI/Qdrant未实际调用/部署；专项creditSKU/有效期、预算和账单未从结算控制台确认。Flutter/应用后端尚未接入这个独立检索工具，yibubang://引用标识还不是现有App deep link路由。
- Git：main@d862099；开始已有5个产品文件、首页测试和4份文档改动全部保留；本轮新增scripts/knowledge_base与知识库本段/技术债记录，不commit/push。artifacts/密钥忽略；TECHNICAL_DEBT仍受既有docs忽略规则影响。
- 控制台复核：用户打开agent-platform/rag/corpus与agent-retrieval/collections为空，实际资源是gen-app-builder下Search Data Store；已在线GET资源/导入回执/文档并查询CD8 Top1验证。README新增入口与三产品/API对照；未新建Corpus/Collection或启用vectorsearch API。回执artifacts/cloud/resource-location-check.json。
- 下一会话第一步：核对Git及[VALIDATION.md](../../scripts/knowledge_base/VALIDATION.md)/[README](../../scripts/knowledge_base/README.md)，按用户下一目标提供实际PDF路径或认领检索接入；新增来源修改config→build→validate→cloud sync即可。不重复创建同名资源，不用FULL导入delta，不重新导入本次已经成功的数据；保留artifacts/cloud成功基线。
<!-- /MEDICAL_KNOWLEDGE_BASE -->


<!-- HOME_STARTUP_OPTIMIZATION -->
## 最新交接：2026-11-11 首页启动最小优化完成

- M02查/存投影stamp统一真实路径；M01Cloud数据revision只在已提交非空拉取后递增一次（含部分失败与删除墓碑），首页/统计精确订阅，云刷新保留课程；M03宽屏KeepAlive壳首次访问才挂业务页，GlobalKey保存导航重排/当前页布局切换，窄屏PageView模式保持。
- 全量Flutter314/314（新增6+5+5），后端8/8、tsc及analyze 0 issues；修复后审计探针3/3，十万题别名10次2ms/0次SQL行变更。日志见[逐项记录](audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。不是旧SQLite或四平台真机保证。
- Git main@d862099；5个产品文件、3个测试套件/1辅助文件与文档有未提交改动，保留上轮4份已有文档现场。未commit/push/部署；docs新报告/探针仍受忽略规则影响但本地已保存。
- 未处理M03完整目录分阶段初始化、M04/M05统计调度重构、M06后端部署、M13默认算法入口；未测实机profile/国内网络/断电。新增宽窄测试覆盖1000↔600；400px默认Ahem字体发现旧每日卡片Row溢出，真实字体未验收，未在本目标改布局。
- 下一步第一项：核对git diff及逐项记录，再运行用户设备冷/热启动和答题/同步并行验收；按现场数据认领后续独立问题。不要重复运行aa0a2d9旧缺陷探针作为修复门禁。当前post_a20探针已把M01/M02转为正确行为，M13保留未修现状。
<!-- /HOME_STARTUP_OPTIMIZATION -->

<!-- POST_A20_MAINTENANCE_AUDIT -->
## 最新交接：2026-11-11 启动、同步与维护架构审计

- **完成**：用户三问源码分析；[报告](audits/POST_A20_STARTUP_SYNC_MAINTENANCE_AUDIT.md)与15项M01–M15方案；[当前Flutter探针](audits/post_a20_current_state_probe_test.dart)3/3、[后端探针](audits/post_a20_backend_probe.mjs)2/2；相关Flutter34/34、后端8/8、tsc通过、analyze 0 issues。
- **真实发现**：Cloud状态通知触发首页/统计无差别重读；投影查stamp用传入路径而写stamp用SQLite路径，macOS路径别名导致十万题10次重建1.52–1.54秒/2000010次SQL行变更，规范路径10次3ms；宽屏隐藏Tab抢用户库FIFO；正常Card→Page传默认SM2服务绕过fsrs；pull seq固定但JOIN当前实体，非固定payload快照。
- **同步错误**：客户端未收到protocol2/accepted_seqs所以拒绝ACK，pending保留；本地v2后端尚未部署高度相关。只匿名GET主域health/root均ok且无protocol，version1.0.0也为本地写死，不能确认线上版本。未登录、未发线上sync、未部署。
- **现场**：main@d862099；本轮开始干净；只写docs/探针，没有产品修改、commit、push。DEVELOPMENT_STATUS/SESSION_HANDOFF/KNOWN_ISSUES/FEATURE_MATRIX跟踪差异；新报告、探针与TECHNICAL_DEBT被gitignore忽略但本地已保存。
- **未完成**：M01–M15未实施；平台/等待时长/现场日志问题暂无用户回复；后端真实版本及D1schema验收、真实计费、旧SQLite/Windows/国内网络/断电未测。A19标记正常入口残留PARTIAL，不冒充全链已修。上轮Flutter298/298为历史基线。
- **下一步第一项**：git现场与本段核对，读取报告第1/4节；按单问题认领M02路径指纹修复，再M01精准刷新/M13默认算法factory；收集现场日志以决定启动重构深度。发布步骤先核对远端再按发布授权执行。不要把新的“断言现状缺陷”探针作为修复后必须保持的CI门禁。
<!-- /POST_A20_MAINTENANCE_AUDIT -->

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A20 / 已修复**。Notes自愈finally恢复原外键状态，失败保留旧表并拒绝继续开库，修订号无损复制；闪卡/核心索引独立补齐。从Git提取13个历史版本DDL夹具（v1、v4–v15），新增17项跳跃升级/坏行/重试/回滚/索引回归；相关26/26，最终Flutter全量298/298、后端8/8、analyze 0 issues、tsc通过；commit：修复 A20 数据库自愈外键恢复与历史迁移验证。未找到独立v2/v3历史快照，未冒充全历史真实用户脏数据或Android旧SQLite实机验收。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v24；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：A01–A20源码修复均已独立中文提交，无未提交产品改动；下一会话先核对Git，再按发布授权部署后端schema/Worker并做真实账号及跨平台验收。未授权push/部署，本轮不执行。 保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
完成项：本次继续完成 A14、A16、A17、A18、A19、A20，各项最小修复、测试及中文独立提交；之前的 A01–A13、A15 保留。
未完成的外部验证：后端协议v2及删除墓碑schema尚未部署；官方非幂等请求和真实ID、低端Android SQLite3.22/Windows锁压测、国内网络、真实断电/平台文件恢复、v2/v3独立历史DDL样本仍待验收。A17仅清本机已有记录，未下载云端记录与官方记录保留；A18采用设备本地自然日，固定计划时区仍为后续设计；实验调度不是完整FSRS。
验证：Flutter最终全量298/298；洛杉矶DST相关32/32；后端SQLite8/8；flutter analyze --no-pub 0 issues；npx tsc --noEmit通过。SQLite测试FFI3.43.2与999参数预算不能替代旧Android实机。
下一次第一步：git status/HEAD和本段核对，按用户明确发布授权推进后端schema/Worker部署及账号/跨设备同步验证；不复跑历史缺陷断言探针作为当前正确性门禁。

<!-- /A01_A20_REPAIR_STATUS -->


## 最新交接：2026-11-10 v2.2.3 白盒审计完成

- **实际Git现场**：分支main，HEAD `aa0a2d9c959128d647b5109cd447c450c150d593`；开始时干净。本轮仅有审计/知识库变更，未commit、push或部署，未改应用逻辑和依赖。
- **文件管理边界**：`.gitignore:61`忽略整个docs目录，因此Git status/diff仍为空；审计/知识库已写入本地磁盘，未强制add或修改忽略规则。下一会话读取本地文件，不可把Git无差异解释为本轮无文档更新。
- **完成项**：数据库、业务生命周期、网络/云同步、调度内核源码调用链审计；[20项完整报告](audits/V2_2_3_WHITE_BOX_AUDIT.md)，含P0/P1/P2、精确源码位置、最小复现和修复代码/长期演进；17项显式隔离生产调用探针及后端原始SQL探针；既有相关测试38/38通过。
- **关键新证据**：同步期间变动不再上传；10441题首次恢复只拿10000、剩441被游标跳过；失败批次重传500；坏HTTP200响应删除官方队列；第五次失败删除持久化任务；图片上传覆盖笔记新编辑；并行状态转移重复计数；复习多表部分提交/单位错误；固定候选前缀饥饿；坏导入先覆盖原用户库；Notes自愈失败外键OFF。
- **原交接线索校正**：当前ATTACH路径已转义，明确HTTP4xx/5xx已不降级备用；EF低下限仍增长/Easy可回升；5000timeout位于暂存题库。不要按旧行号和旧风险描述重复修复已解决路径。
- **未完成项**：A01～A20均未修复，历史v1～v8迁移夹具未补、线上D1部署未对照、低端Android/Windows锁压测及国内DNS/SNI实机未做；本轮未重复全量205项，不能把17个缺陷探针通过记作产品修复验证。
- **下一会话第一步**：读取本最新段和审计报告，核对Git未提交文档；优先认领A01/A02作为同步完整性目标，明确客户端/后端协议版本与实际部署，再实现持久化outbox、独立游标及完整分页。其他P0按单一闭环逐项修复，禁止自动commit或大规模重构。
- **复现入口**：`flutter test --no-pub --reporter expanded docs/antigravity/audits/v2_2_3_reproduction_test.dart`（刻意断言旧缺陷，非CI门禁）；`python3 docs/antigravity/audits/backend_sql_probe.py`（内存库、无D1访问）。下面v2.2.3发布交接内容保留为历史。
- **最终检查**：静态分析0 issues；局部格式化和分析修正后隔离探针再次17/17通过；相关既有测试38/38。最终Git status/diff无产品变更，审计源代码链接54处均核对文件/行存在（主体函数已人工追踪）。

> **记录时间**：2026-11-10  
> **当前分支**：`main`（HEAD: `aa0a2d9`）  
> **发布版本**：`v2.2.3`（Build: `2.2.3+213`，用户数据库 schema `v15`，题库 schema `v1`）  
> **质量基线**：`flutter analyze --no-pub` 保持 **0 warnings / 0 errors**；全量自动化测试 **205/205** 项全部通过。  
> **交接目标**：本会话已全面闭环 **Issue #22**（每日计划、闪卡系统、跨章节差异化蓄力手势）与 **Issue #23**（低版本宿主 SQLite 兼容性缺陷 BUG-19、淘汰 ON CONFLICT、万级数据切片同步）。已完成 v2.2.3 发布。现全面梳理系统在**数据库、业务逻辑、网络与云同步、算法内核**四个维度的深度排查线索，供后续交接给 Codex 开展深度系统审计。

---

## 1. 最新交付总览与版本基线

| 模块 | 核心交付内容 | 关联与状态 |
| :--- | :--- | :--- |
| **SQLite 宿主引擎兼容 (Issue #23)** | 1. 彻底淘汰全库 8 处 SQLite ≥ 3.24 `ON CONFLICT` 语法依赖，重构成 `INSERT OR IGNORE` + 条件原子 `UPDATE` / `INSERT OR REPLACE`，彻底根除 Android 10 (SQLite 3.22) 下的 `near "ON": syntax error`；<br>2. 引入 `sqlite3_flutter_libs` 内嵌现代 SQLite 动态库；<br>3. 用户库启动主动输出 `sqlite_version()` 诊断信息 | refs #23 (BUG-19) `CLOSED` |
| **云同步性能与熔断防护 (Issue #23)** | 1. `CloudSyncService.sync()` 落地 `batchChunkSize = 500` 切片推送机制，根治万级数据（如 20,850 行）打爆 Cloudflare Worker 30s 运行时限导致的超时中断；<br>2. 优化容灾降级：主域名返回 4xx/5xx 时精准抛出错误并向用户透传清晰原因，禁止盲目将大包流量重试至受限域名（如国内受阻的 `workers.dev`） | refs #23 (BUG-19) `CLOSED` |
| **滑动切章手感与蓄力 (Issue #22)** | 1. 章节九宫格上下滑（`QuestionGridPage`）启用 **500ms** 蓄力停顿（Dwell Hold），拉满 100% 保持按住满 500ms 震动并自动切章，中途松手或回弹立即取消，彻底消除触控板惯性误触；<br>2. 题目页左右滑（`QuestionDetailPage`）恢复轻快即时手感（拉满阈值后**松手即切**，无停顿等待）；<br>3. `ChapterCrossIndicator` 垂直方向启用 500ms 动态充满光环，水平方向拉满即高能 | refs #22 (BUG-17) `CLOSED` |
| **每日计划与自制闪卡 (Issue #22)** | 1. 独立 Tab「每日计划」及抽题来源多选；<br>2. 3D Matrix4 翻转闪卡百词斩刷题流；<br>3. 题目笔记一键转自制闪卡；<br>4. 卡包管理（横向标签筛选、按题干/背面模糊检索、随时斩卡） | refs #22 `CLOSED` |
| **自动化测试与基线维护** | 新增 `test/sqlite_compatibility_test.dart`（4 项）；全量更新 `test/cross_chapter_navigation_test.dart`（15 项）与 `test/daily_review_ui_test.dart`，总计 **205/205** 项测试全绿 | 质量基线已验证 |

---

## 2. 系统核心架构铁律与设计契约（不可妥协）

任何接入代码分析或修改的代理必须严格遵守以下系统架构契约：

1. **题库库只读隔离契约**：
   - 题库文件（`QuestionBank/<bank_id>/<bank_id>.sqlite`）在客户端**必须以只读方式（`readOnly: true`）打开**。严禁编写任何对题库库执行 `INSERT`、`UPDATE`、`DELETE` 或 DDL 的代码。
   - 所有用户行为（作答记录 `Question`、做题流水 `Activities`、收藏、斩题、用时、笔记、复习计划、自制闪卡）一律落入 `user_data.sqlite`。
2. **全局 `question_id` 单列唯一与跨库共享契约**：
   - `question_id` 全系统唯一。同一题目出现在不同题库中时共享同一份用户做题与复习状态。
   - `Question` 表的主键永远是单列 `id`，严禁擅自改为 `(bank_id, id)` 联合主键。
3. **跨库聚合重算必须走 SQLite 原生 `ATTACH DATABASE`**：
   - 跨题库与用户库的章节统计（对、错、未做题数）重算，必须在 `UserDBHelper` 中利用 SQLite 原生 `ATTACH DATABASE` 在 SQL 引擎层批量完成（参考 `lib/db/data_transfer.dart` 中的 `rebuildQuestionCount`），严禁在 Dart 内存中进行双重循环查询拼接。
4. **Context 与路由生命周期安全性**：
   - 严禁在 `Navigator.pop(context)` 后继续使用该失活的 `context` 执行跳转（如 `pushAdaptiveModalPage`）。桌面端模态弹窗若包含子路由交互，必须确保返回值能正确冒泡至外层调用方。

---

## 3. 供 Codex 深入排查的四大维度潜在问题清单

在当前 v2.2.3 基线上，针对系统深层隐患梳理了四大维度的重点关注领域与已知技术债务（详见 [`docs/antigravity/TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md)）：

### 维度一：数据库底层 (Database & SQLite)
1. **多线程/后台并发与锁争用 (Lock Contention & Busy Timeout)**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart`, `lib/services/ykb_sync_service.dart`, `lib/services/note_service.dart`, `lib/db/database_helper.dart`
   - **风险**：应用启动时后台并行触发多路同步队列写入 `user_data.sqlite`，若前台用户正在快速答题或重算章节统计，偶发可能抛出 `database is locked`。当前各处 `busy_timeout` 设置分散在 3000ms~5000ms，低端 Android 机存在锁争用风险（[DEBT-13]）。
2. **动态 SQL 路径拼接与特殊字符注入风险**:
   - **痛点代码**：`lib/db/data_transfer.dart:18` (`ATTACH DATABASE '$bankPath' AS ...`)
   - **风险**：若题库路径包含单引号（如 Windows 用户名或特殊目录名），字符串模板直接拼接会导致语法错误甚至安全隐患，未做 `bankPath.replaceAll("'", "''")`（[DEBT-14]）。
3. **长事务与批量更新性能**:
   - **痛点代码**：`lib/screens/question_grid_page.dart:277-291`（全部重做/错题重做）
   - **风险**：遍历题目串行 `await updateQuestion(...)`，大章节（数百道题）会触发数百次单独 SQLite 事务与 WAL 同步，导致 UI 掉帧（[DEBT-06]）。
4. **Schema 迁移无损性与历史版本兼容**:
   - **痛点代码**：`lib/db/database_helper.dart:184-280` (`_onUpgrade`)
   - **风险**：从早期版本（v1~v10）跨多版本升级到 v15 的迁移链路是否存在列缺失容错兜底？

---

### 维度二：业务逻辑与生命周期 (Logic & Lifecycle)
1. **跨学科/叶子节点切换时的目录与状态一致性**:
   - **痛点代码**：`lib/screens/subject_page.dart`, `lib/services/question_bank_manifest_service.dart`
   - **风险**：部分题库在医考帮体系下存在多层树结构与叶子入口，深层章节的父子级联选择状态是否在缓存与重算时保持全局唯一？
2. **章节翻页与 PopScope 返回拦截时序**:
   - **痛点代码**：`lib/screens/question_detail_page.dart`, `lib/screens/question_grid_page.dart`
   - **风险**：在切章、交卷、重做及快速滑动的边界情况下，路由栈退出时是否有遗漏的未保存做题时长（`duration`）或答题状态？
3. **多端 LWW (Last-Write-Wins) 冲突仲裁时序**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart:154-184`
   - **风险**：当两台设备离线答题后同时联网同步，若设备时钟存在漂移，基于 `updated_at` 的毫秒级比较是否会导致有效答案被旧数据覆盖？

---

### 维度三：网络通信与云同步 (Network & Cloud Sync)
1. **Cloudflare D1 免费版配额熔断与流控**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart`
   - **风险**：Cloudflare D1 免费版限制每日写入上限为 100,000 行。初次全量同步（如 10,441 题 + 10,409 流水 = 20,850 行写入）若遭遇网络抖动重试 4~5 次即突破限额，触发 D1 服务端抛出 `HTTP 500 (exceeded D1 free tier daily row write limit)`（[DEBT-12]）。
2. **多节点容灾降级与国内网络可用性**:
   - **痛点代码**：`lib/services/cloud_sync_service.dart:28-36`
   - **风险**：备用域名 `*.workers.dev` 在国内部分网络环境下存在 DNS 污染与 SNI 阻断；若因业务错误（如 4xx / 5xx 配额满）盲目重试备用节点，会导致请求假死超时（45s）。
3. **离线队列丢包与指数退避恢复机制**:
   - **痛点代码**：`lib/services/ykb_sync_service.dart`, `lib/services/note_service.dart`
   - **风险**：后台离线队列在遭遇连续网络失败时虽然触发了退避，但在应用杀进程重启后，队列游标与内存重试计数器是否能无损恢复？

---

### 维度四：算法内核与调度 (Algorithm & Engine)
1. **SM-2 艾宾浩斯间隔算法的自然日边界截断**:
   - **痛点代码**：`lib/utils/spaced_repetition_engine.dart:45-80`
   - **风险**：`calculateNextReviewDate` 采用自然日截断（`DateTime(now.year, now.month, now.day)`）。若用户跨时区飞行或在 23:59~00:01 临界点做题，会导致到期日出现 0 天或多算 1 天的跳变抖动（[DEBT-15]）。
2. **EF (Easiness Factor) 衰减死锁与回弹机制**:
   - **痛点代码**：`lib/utils/spaced_repetition_engine.dart:17`
   - **风险**：当极难题目多次评分为 `Again`（Grade 1）时，EF 会快速跌落至 1.3 的强制下限，导致之后即使用户答对，间隔增长也极其缓慢，缺乏长周期自适应动态回弹测试。
3. **抽题分布与随机洗牌算法公平性**:
   - **痛点代码**：`lib/services/daily_review_service.dart:180-240`
   - **风险**：混合多来源（错题、收藏、笔记、新题）且受限于每日总题量上限时，截断逻辑是否会导致后排课程或来源被永久饥饿遗忘？

---

## 4. 下一次会话交接建议

### 当前工作区状态：
- 分支：`main`（已推送 `origin/main`，Tag `v2.2.3` 已发布）
- 代码质量：`flutter analyze --no-pub` 0 warnings / 0 errors
- 自动化测试：`flutter test --no-pub` 205 项全绿通过

### 下一会话操作建议：
1. **将第四部分整理的高信息密度 Prompt 提交给 Codex** 进行四大维度的源码级扫描与审查；
2. 收集 Codex 的审查报告，对高价值的潜在漏洞与优化点归档至 [`docs/antigravity/TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) 并制定 Sprint 重构计划。
