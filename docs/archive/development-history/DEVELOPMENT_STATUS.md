> 历史快照：归档于2026-11-13，包含各阶段当时状态。当前状态见[开发状态](../../antigravity/DEVELOPMENT_STATUS.md)，不要据本文旧版本/未提交描述判断当前实现。

# DEVELOPMENT_STATUS.md - 医不帮开发状态盘点与排期规划

<!-- AI_RESULT_COUNT_SELECTION -->
## 2026-11-13 检索条目设置与文本选择断言（实现/部署/联网验收完成）

- 起始main@ec0fdf6干净；本目标为检索数量问答及lastSelectionResult断言。新增设置→AI搜索→检索条目数1–25，默认12；总数调整按当前比例分配，默认8:4→25条17:8，比例弹窗随总数变化。旧设置/旧请求仍默认12/8:4，每轮重读本机并传result_count。
- 后端严格整数1–25、教材0–total校验在扣额度前；二源独立过滤Search、单源跳过、来源内去重后分配字符预算，≤12沿用28000、大于12最多60000，避免后面题目无预算。显式searchResultList完整传入内置回答，没有使用Google自动maxReturnResults字段；条数不改变App1/2/3扣额。
- 段尾引用/行内公式WidgetSpan内部Text重复加入Text.rich选择delegate，已精确复现用户段落选择断言；隔离控件内部选择后同事件/鼠标三击/正文选择/引用点击PASS，保留正文SelectionArea。
- 最终Cloud Run00018-q7c/100%；线上health max_result_count25，0/26/bool/string/来源超总数400且额度不变PASS。生产App真实25证据=17教材+8题，内置模型回答/SQLite持久化/引用回调2项联网PASS。Google最终references10，正文引用含第13项；不把25张参考卡片等同于模型使用全部25条或穷尽索引。
- Flutter全量357 PASS/3联网默认skip，最后选择/设置8 PASS；后端最终39 PASS，静态分析0。320/1000px新设置截图已查看；Android/macOS普通main Debug构建通过。原PDF/Google数据/R2页图/题库与用户库schema未改。
- 官方Answer自动搜索默认10/最高25，摘要DOCUMENTS10/CHUNKS50与Search普通数据pageSize100分别核实；赠金条款/SKU仍待账单。[数量说明](../../ai-search/RETRIEVAL_LIMITS.md)。本轮未commit/push/Release，之前提交授权不复用于新改动。
<!-- /AI_RESULT_COUNT_SELECTION -->

<!-- AI_SEARCH_COMMIT -->
## 2026-11-13 用户授权提交 AI 搜索与教材功能

- 提交范围：此前本地处理53本教材/增量上传工具、私有R2页图Worker、教材检索/引用/缓存阅读器、Search内置Answer与模型本机回退、高级流式与200额度，以及最新Markdown/设置一致性/缩放/快捷键/默认Tab/检索比例六项修订；保留先前实现，不拆出缺少依赖的客户端或服务端。
- 验证：沿用同一源码Flutter355 PASS/3联网默认skip、后端36 PASS、静态0、Android/macOS Debug构建通过、生产App6:6联网2 PASS。提交前补充知识库Python18 PASS和Worker鉴权/过期/路径/散列/缓存PASS，Git差异与文件清单复核。
- 只提交源代码、公开目录元数据、回归测试和文档；.local凭据/日志/截图、外置盘PDF/页图、知识库生成产物、虚拟环境、APK/App保持忽略。用户仅授权commit，本次不push或发布Release。
- 下一次第一步：git log -1与git status核对提交，再读最新六项交接，按用户实机反馈验证Android缩放/大陆网络。待验收边界仍为375页符号公式人工医学复核、版次ISBN、其他平台真机及赠金实际SKU账单。
<!-- /AI_SEARCH_COMMIT -->


<!-- AI_SEARCH_FEEDBACK -->
## 2026-11-13 AI 搜索六项反馈修订（实现/部署/回归与 App 联网验收完成）

- Markdown 紧凑列表按连续行内节点合并，嵌套列表不再把粗体标题/冒号拆成两个段落；定向扩展中文括号紧邻粗体边界，保留普通 CommonMark、代码、转义、未闭合流式语法和引用。用户原文回归验证粗体字号权重与正文保留。
- AI 设置整组改用现有 InfoCard/IconTile/Switch：模型、改写、流式、教材与题目比例、使用说明。长说明仅进入 Material 弹窗；模型单选使用自适应抽屉/桌面 Dialog，保留本机目录与后台刷新。320px/1000px 真实字体/图标截图已人工查看；窄屏稳定版标签缩短、比例弹窗两按钮。
- 阅读器 PhotoViewGestureDetectorScope 协调 PageView 的横向拖动，双指缩放优先、放大后拖动及边缘翻页保留；读取本机稳定缓存不变。桌面阅读器方向键覆盖全页，跳转弹窗/文本编辑/组合键不拦截；AI 输入 Shift+Enter 发送、普通 Enter 不发送、输入法组词/长按重复不提交。
- 默认导航为课程→每日计划→AI 搜索→统计→我的；已有五项用户排序保留，旧四项补入 AI 的默认邻居位置。恢复默认采用新顺序。
- 客户端可选教材 0–12 条，题目 12−教材；默认 8:4。每轮重读 SharedPreferences，服务端严格 int 验证、在扣额前拒绝越界；二源仍独立检索，单源跳过无用请求、统一去重编号、总证据 28000 字上限，不自动挤占来源。纯教材检索/1–3 额度策略保持。
- Flutter 全量 355 PASS / 3 联网默认 skip；后端 36 PASS。Android 模拟触摸双指缩放/双击、macOS 模拟按键边界与按钮后焦点、Markdown 用户原文、设置持久化/新旧导航回归均通过。最终静态分析0；Android/macOS Debug构建成功；Cloud Run00016-lbf/100%，生产App实际6教材+6题、引用打开与SQLite持久化2项联网PASS，越界400且不扣额PASS。未宣称 Android 真机已验收。
- 本目标未 commit/push；不重导文本、不上传 PDF/页图、不改题库/用户库 schema。延续既有全部未提交改动。
<!-- /AI_SEARCH_FEEDBACK -->


<!-- ADVANCED_AI_SETTINGS -->
## 2026-11-13 AI设置、高级流式与200额度（实施/部署/联网验收完成）

- 用户覆盖基础省钱偏好，改为默认问题改写+streamAnswer。设置→通用下方新增AI搜索组，回答模型移入同组；开流式自动开改写，关改写同时关流式。客户端每次提问重读本机设置，现有AI页也生效。
- 每安装/北京时间日200额度：基础1、仅改写2、改写+流式3，服务端事务核算，余额不足拒绝；保留原已用值，IP/分钟/全站仍计真实请求数。App显示服务端limit，教材纯检索每次1；默认最多66次高级完整提问，余2可换模式使用。3倍是App额度策略，不是Google3倍收费。
- 解析Google增量JSON数组并转SSE片段，最终全文不重复追加；迟到引用按最终UTF-8偏移/原URI校正，客户端先平滑显示已收片段再校正。本机缓存/共用随App和Docker附带的4模型目录可即时选择；后端冷启动快照立即返回、后台官网刷新/4秒超时/60秒节流，旧目录明确标记，无客户端直连Google官网。
- 后端00015-rlt/100%，health默认双开/200；33后端、Flutter全量348 PASS/3联网默认skip、最终analyze0；真实App联网2项PASS，线上基础/默认流式/仅改写扣1/3/2，12证据含8教材，模型查询不扣额度。默认流式6delta/首2.8s/总3.7s仅当前样本；Android/macOS Debug通过，线上200日额/分钟/并发/重放/错误凭据五项PASS，专用测试字段已恢复。
- TTL保留现有3天过期限额记录清理，非额外后端/非零点刷新依赖，删除另计。文本检索生成仅App→Cloud Run→Discovery Engine；Cloudflare Worker仅教材图片签名鉴权/缓存。赠金SKU实际映射仍待账单，未声称100%抵扣；无独立Vertex Token入口、无重导数据/schema变化/commit/push/Release。
<!-- /ADVANCED_AI_SETTINGS -->

<!-- BUILTIN_ANSWER_MODELS -->
## 2026-11-13 内置Answer与模型选择（已部署，赠金抵扣待账单）

- 用户省钱优先/逐行渐入：已迁移Discovery Engine基础:answer；新Enterprise应用yibubang-medical-answer共用原Store，无重复导入。原Standard应用继续教材/题库各搜一次、最多8教材+4题。新应用实测须启用SEARCH_ADD_ON_LLM，否则最小Answer请求亦400；请求禁用改写/推荐追问，无Google托管session，不承诺实际Advanced计量已核实。
- Cloud Run最终00014-dlq/100%东京；默认stable当前gemini-3.5-flash/answer_gen/v1。旧Gemini环境变量/预测权限移除；仅Search+Answer推理权限。App右上回答模型查询/刷新/选择，SharedPreferences保存选择，每轮turn payload保存模型。官方4项版本均真实200/SUCCEEDED。
- 官方目录1小时缓存/60秒刷新节流，官网失败最多24小时回退，过期在节流内仍503。当前后端27、模型/Markdown/会话Flutter18、analyze0通过；接续阶段全量344与Android/macOS Debug记录保留。生产App client/controller→Cloud Run→Answer→SQLite→引用Widget PASS，最终health/目录/匿名401/查询不扣搜索次数再次PASS。
- 两Standard+一Enterprise列表价USD7/千App提问；若另计Advanced保守USD11，实际SKU/免费分配及本笔赠金映射待账单。三项运行费/共享免费/TTL/出网/Worker边界见[费用说明](../../ai-search/COSTS_AND_BUILTIN_MODELS.md)。原生缩略图系统确认、四平台真机/大陆网络/Release仍未验收；未commit/push，既有教材/Markdown改动保留。
<!-- /BUILTIN_ANSWER_MODELS -->

<!-- SEARCH_BILLING_REVIEW -->
## 2026-11-13 Search赠金与生成入口核查（核查完成，赠金SKU范围/迁移未完成）

- 当前线上是Cloud Run代理+两次Search+独立Vertex AI gemini-3.8-flash生成；ADC服务账号OAuth，费用进入绑定JPY结算账号，未抵扣部分可能由付款方式结算，没有实际扣卡证明。
- 官方确认Search Enterprise USD4/1000含Core生成，Advanced另加USD4/1000，免费10000不含Advanced；内置Answer模型stable当前3.5-flash/answer_gen/v1。当前Engine只读GET仍STANDARD，未切换内置生成或部署。
- 官方v1 Answer支持searchSpec.searchResultList，可评估复用两源汇总与引用，无需重建/导入。streamAnswer强制一次rephrase，实际Core/Advanced与多请求计量需核对，不能承诺流式全包仅一次USD4。
- 找到社区转述Support指向的两组官方SKU，但当前均标废弃且范围不同；其中Offer组含部分Vertex模型，不能将其套用为本赠金条款。已向用户请求本笔赠金适用SKU/条款，余额不变不是模型免费证据。
- 本轮仅只读云核查、官网/schema及文档追加；保留全部教材/Markdown等未提交改动，无commit/push/产品测试或付费生成调用。详见ai_backend/SEARCH_IMPROVEMENTS.md新增复核段。
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
## 2026-11-12 完成提交与53本教材方案研究（未处理/上传教材）

- 按用户commit授权完成三项主题提交：c911b06首页优化、71e9241可迁移知识库、105c942 App AI搜索；没有push。原先未提交状态为历史记录，以上提交为最新状态。
- 用户提供本地目录，自用53本可复制PDF；只读元信息53份/16.283GiB/20669页，11本22页文字层抽检；诊断/内科/外科确认双OCR层重复，普通文字提取不可直接当干净语料。
- [教材方案](../../knowledge-base/TEXTBOOK_PLAN.md)：本地复用OCR并选择/去重，页级来源/坐标主库；Google只导文本，私有R2/GCS独立页图，教材纯检索不调用Gemini，异常页才补OCR。现App引用类型/页图阅读器需后续扩展。
- 本轮遵守先说方案：未批量OCR/渲染/提取语料/压缩页图、未改知识库来源、未导入教材或部署新功能。原产品验证Flutter334/334、Python11/11保留，本轮只文档与只读研究。
<!-- /TEXTBOOK_PLAN_REVIEW -->


<!-- APP_AI_SEARCH -->
## 2026-11-12 App AI 搜索（实现、独立后端部署与验收完成）

- 新增Gemini星芒底栏/桌面Rail，独立Material页面，检索骨架/呼吸与阶段淡入淡出/平滑流式字输出、比较表格，追问/修改重试/停止/复制。引用按全局question_id打开只读题库原题及共享作答；未装库给提示。
- 本地session新建/切换/删除与中断恢复，用户库schema v24→v25仅新增AiSearchSessions/AiSearchTurns。不加入现有同步，不改题库/Question主键，保留已有首页延迟挂载优化。
- 用户明确授权独立Cloud Run配置部署：yibubang-search/东京/yibubang-ai-search，最终修订00003-cl2，100%流量；Firestore专用yibubang-ai，运行账号最小推理权限+数据库条件IAM；复用原Search Engine/Data Store，Gemini 3.8 Flash global/LOW，Google凭据仅服务端ADC。
- Firestore事务执行北京时间100次/安装/天、6次/分钟、单并发租约，另有IP/全站搜索及注册上限、请求体/上下文/tokens上限；失败/取消/重试已受理亦计数，客户端不能改额度。
- 最终Flutter334/334、Python11/11、analyze 0 issues；两轮真实搜索/追问PASS，最终修订首文字3.04s/2.58s、quota98→96；线上五项限额/凭据拒绝PASS且恢复测试设备计数。Android/macOS Debug构建成功；六张真实字体截图检查。
- 未commit/push/发布Release；Windows/Linux/iOS/Android真机与国内可达性未实测。安装凭据不能替代硬件证明，专项credit抵扣新服务费用仍待账单确认；PDF尚未导入/页码阅读器未实现。详见[手册](../../ai-search/README.md)与[验收](../../ai-search/VALIDATION.md)。
<!-- /APP_AI_SEARCH -->


<!-- MEDICAL_KNOWLEDGE_BASE -->
## 2026-11-12 可迁移医学知识库（本地构建/云导入/搜索验收完成）

- 新增独立 `scripts/knowledge_base/`：五份内容SQLite只读导出，149,448唯一题/149,472块；标准JSONL、来源缓存、稳定ID、差异审计、Google增量导入、RAG证据、PDF/逐页OCR接口及未来Embedding→Qdrant适配，详细中文手册。
- Google项目yibubang-search已建global Data Store/Standard Engine/私有GCS；pilot12/12、全量149460/149460成功、0失败，真实三题搜索3/3、自然语言CD8改写Top1；再次sync新增/修改0、删除0。
- 真实来源散列/全产物/3医学探针PASS，Python14/14；无变化build全部缓存复用、0新增/修改/删除。167题答案内容分歧已提示待医学审核；6923题配图未OCR，53本真实PDF尚未提供，Embedding/Qdrant未真实部署。
- 控制台入口澄清完成：Search Data Store位于gen-app-builder，与RAG Engine Corpus/Agent Retrieval Collection独立；在线GET及CD8查询再次确认已导入资源存在，README已补入口/API对照，未创建重复库。
- 未改Flutter/依赖/题库schema；开始已有首页优化改动全部保留，不commit/push。[验证记录](../../knowledge-base/VALIDATION.md)、[操作手册](../../knowledge-base/README.md)。专项creditSKU/有效期、预算及实际账单仍需结算控制台核对。
<!-- /MEDICAL_KNOWLEDGE_BASE -->


<!-- HOME_STARTUP_OPTIMIZATION -->
## 2026-11-11 首页启动优化（完成）

M02投影真实路径统一、M01提交数据精准刷新、M03宽屏隐藏Tab延迟挂载完成；每项最小修改与独立回归，最终Flutter314/314、后端8/8/tsc通过、analyze 0 issues。十万题路径别名10次热读取2ms且0行写入（原1.52–1.54秒/2000010次变更）；不代表实机启动耗时。

只变更5个产品文件及16项新增测试/辅助文件，schema/依赖/题库校验迁移/后台队列流程保持；开始已有4份文档改动已保留。详见[逐项记录](../../antigravity/audits/HOME_STARTUP_OPTIMIZATION_LOG.md)。未commit/push/部署；M03目录分阶段初始化、M04/M05、协议后端发布/M13配置入口仍为独立后续项。真机启动profile和400px真实字体布局待测。
<!-- /HOME_STARTUP_OPTIMIZATION -->

<!-- POST_A20_MAINTENANCE_AUDIT -->
## 2026-11-11 启动/协议错误与长期维护审计（完成，优化待实施）

- 基线 `main@d862099`，用户库 v24；本轮分析用户反馈的首页偶发圆环、同步协议 v2 异常并写入[完整报告](../../antigravity/audits/POST_A20_STARTUP_SYNC_MAINTENANCE_AUDIT.md)，包含15项优先级、源码位置、最小方案与验收。
- 已复现：云服务仅初始化通知就让课程页重载并隐藏旧内容；macOS `/var` 与 `/private/var` 投影指纹不一致导致反复全库重建；正常每日计划卡片入口绕过fsrs设置；后端固定seq上界返回同题最新投影而非历史快照。
- 协议错误是缺明确ACK时保留pending的保护，本次同步未成功；后端schema/Worker尚未部署是最强解释，匿名health无protocol信息，不能确认线上协议版本。未部署、未向线上同步接口写真实账号数据。
- 当前现状探针Flutter3/3、后端2/2；相关Flutter34/34、后端8/8、tsc通过，最终analyze 0 issues；上轮298/298全量基线保留，本轮未重跑全量/实机。
- 本轮仅文档与隔离探针，未修改产品代码或commit/push。新报告与探针/TECHNICAL_DEBT受docs忽略规则影响，保存在本地；已跟踪知识库有正常Git差异。
- 下一步先取实机慢启动日志/核对实际后端发布，再独立认领M02（投影路径）、M01（刷新）、M13（配置入口）最小修复；后端部署按发布流程推进。A01–A20历史提交不改。
<!-- /POST_A20_MAINTENANCE_AUDIT -->

<!-- A01_A20_REPAIR_STATUS -->
## 2026-11-11 A01–A20 修复进展

最新处理：**A20 / 已修复**。Notes自愈finally恢复原外键状态，失败保留旧表并拒绝继续开库，修订号无损复制；闪卡/核心索引独立补齐。从Git提取13个历史版本DDL夹具（v1、v4–v15），新增17项跳跃升级/坏行/重试/回滚/索引回归；相关26/26，最终Flutter全量298/298、后端8/8、analyze 0 issues、tsc通过；commit：修复 A20 数据库自愈外键恢复与历史迁移验证。未找到独立v2/v3历史快照，未冒充全历史真实用户脏数据或Android旧SQLite实机验收。

逐项状态与验证见 [A01_A20_REPAIR_LOG.md](../../antigravity/audits/A01_A20_REPAIR_LOG.md)。用户已授权每项中文 commit；未授权 push / 部署。A01 增加事务内 outbox 和后端 v2 字段变更协议；当前用户库 schema v24；A05 持久化队列账号、退避及发包状态，A06 笔记修订号，A08 每题测试用时，A12 跨库关系投影与原子计数；后端需应用 schema.sql 并部署，旧协议请求明确提示升级，待上传数据保留。后续未完成项按逐项清单继续处理；不能把代码测试通过视为线上已部署验证。

下一步：A01–A20源码修复均已独立中文提交，无未提交产品改动；下一会话先核对Git，再按发布授权部署后端schema/Worker并做真实账号及跨平台验收。未授权push/部署，本轮不执行。 保持题库物理只读、Question 单列主键与 SQLite 3.22 SQL 契约。
<!-- /A01_A20_REPAIR_STATUS -->


> **分支**：main；最新已提交 `1800362`。
> **应用版本**：2.2.3+213；用户数据库 schema v15；题库 schema v1 不变。
> **更新时间**：2026-11-10；全面闭环【Issue #23 低版本宿主 SQLite 兼容性缺陷（BUG-19）】——重构全库 8 处 `ON CONFLICT` 语法为向下兼容的原子标准 SQL（彻底消除 `near "ON": syntax error` 错误），引入 `sqlite3_flutter_libs`，实现启动期 `sqlite_version()` 输出；跨章节切换实现 100% 满额停顿 1 秒蓄力防误触；全量自动化测试 **205/205** 全部通过、代码分析 **0 issues**。
> **下一阶段焦点**：v2.2.3 白盒审计已完成，先认领同步完整性与数据丢失路径修复；富文本/Markdown 闪卡与外部 Anki 导入导出保持后续规划。

## 2026-11-10 v2.2.3 白盒审计（完成；修复待认领）

- 实际基线 `main@aa0a2d9`，用户库 v15、应用 2.2.3+213；开始时工作区干净。
- 完整报告：[audits/V2_2_3_WHITE_BOX_AUDIT.md](../../antigravity/audits/V2_2_3_WHITE_BOX_AUDIT.md)，20项发现，按P0/P1/P2区分，包含代码位置、场景、根因、最小方案及长期演进。
- 首要问题：Push/Pull时间游标混用导致漏传、Pull 10000上限无续页、失败响应/第五次失败删除队列、笔记与旧页面快照覆盖答案、用户库未验证导入直接覆盖。
- 17/17隔离生产调用探针复现；原始后端SQL证实10441题恢复遗漏441题；相关既有测试38/38通过。发布前205/205基线保留，未在本轮重复全量测试。
- 最终`flutter analyze --no-pub` 0 issues；审计文档位于被.gitignore忽略的docs目录，Git status/diff仍为空。
- 本轮只更新审计材料/知识库，未改产品代码、依赖、schema，未修复上述发现，未commit或部署；后端结论基于仓库源码，线上部署版本待对照。
- 已更正旧线索：ATTACH路径已转义；HTTP4xx/5xx已停止备用节点重试；EF下限不构成1天死循环；busy_timeout并非所有用户写连接都已有3000～5000配置。
- 下一步先实现A01/A02同步完整性闭环（本地outbox、独立游标、服务器分页/变更序号），再处理P0数据丢失路径；保持题库只读、全局Question.id与ATTACH、旧SQLite语法契约。

## 1. 当前开发状态

历史 BUG-01～09、BUG-13～19 清零基线保持。最新代码分析 **0 issues**、全测 **204/204**。

| 模块 | 当前交付 | 验证范围 |
| --- | --- | --- |
| 低版本 SQLite 全面兼容 (Issue #23 闭环) | 1. 消除全部 8 处 SQLite ≥ 3.24 `ON CONFLICT` 语法依赖（改用 `INSERT OR IGNORE` + 针对性原子 `UPDATE` / `INSERT OR REPLACE`），在 Android 10 (SQLite 3.22) 及老宿主环境下拉取做题记录、云端同步、答题计数、复习提交与题库合并零报错；2. 依赖加入 `sqlite3_flutter_libs`；3. 启动期 `sqlite_version()` 引擎版本主动诊断输出 | 4 项真实 SQLite 兼容性专项测试（`test/sqlite_compatibility_test.dart`），覆盖 LWW 时间戳仲裁、原子计数累加、跨库聚合与版本探测 |
| 跨章节顺滑翻页 (Issue #22 闭环) | 1. 刷题详情页首题右滑/末题左滑及章节九宫格上下滑纯动效跨章节切换（ChapterCrossIndicator），动态流体胶囊抽屉展开、环形进度与双箭头高能状态；2. 差异化手感调优：章节九宫格上下滑启用 500ms 停顿（Dwell Hold）蓄能机制，满 500ms 触感振动平滑切章，中途松手或回弹立即取消，彻底根除 macOS 触控板与快速滚动的误触；题目详情页左右翻页恢复轻快即时手感（拉满 85px 阈值松手即切，无须停顿）；3. 指示器垂直方向呈现 500ms 动态充满光环，水平方向满额即高能；4. macOS 触控板三路释放监听；5. 相邻章节后台静默预取，切章 0 延迟；6. 桌面端方向键与圆圈导航联动 | 15 项自动化测试（test/cross_chapter_navigation_test.dart），覆盖章节数字 ID 排序、指示器状态流转、首末题边缘手势交互、垂直滑动手势、触控板事件与 500ms 停顿打断机制 |
| 闪卡（Flashcard）体系完整闭环 | 1. 题目详情页笔记一键转双面闪卡（自动解析正面题干/背面笔记，保持原题关联）与制作闪卡弹窗；2. 每日计划页卡片池「自制闪卡」统计与独立卡包管理弹窗（全局搜索、动态标签横向滑动筛选、编辑修改、删除与随时斩卡）；3. 百词斩复习刷题流 Matrix4 3D 物理翻牌动效（防镜像反转、轻触震动反馈）及背面揭晓后 Again/Hard/Good/Easy 4 档自评驱动，严格遵守题库隔离契约 | 4 项端到端及 7 项部件与数据层自动化测试，覆盖新建、笔记转化、卡包筛选、斩卡流转与调度评分 |
| 独立 Tab 每日计划与 Anki 抽题控制 (Phase 3 进阶) | 原首页题库布局 100% 保持；新增独立的“每日计划”Tab（DailyPlanPage）；支持自定义抽题来源（错题重点攻克、收藏难点、笔记卡片、包含新题）与课程覆盖多选（一键同步首页当前课程，学完课程取消勾选后其错题自动移出复习）；展示记忆精粹卡片池（错题/收藏/笔记/掌握）与未来 7 天到期预测 | 5 项部件测试覆盖独立 Tab 渲染、范围概览、卡片池数据、到期预测、交互刷题流与结题打卡；10 项全生命周期集成验证 |
| 每日抽题服务 DailyReviewService (Phase 2 & 优化) | 从用户自定义来源与覆盖课程抽取新题，复习优先拉取到期题目；毫秒级轻量只读直读题库，彻底杜绝全表 ATTACH ORDER BY RANDOM 导致的界面卡死；自动过滤已斩题目（isCut == true / cut_question == '1'）并自动归档；联动更新作答与 Activities 流水；提供今日概览与卡片池分布 | 4 项真实跨库 SQLite 集成测试覆盖错题/收藏/笔记来源抽样、覆盖课程严格隔离、已斩题过滤、队列优先级、记账流水闭环 |
| 记忆曲线调度引擎 (Phase 1) | 纯 Dart SM-2 算法内核（SpacedRepetitionEngine），支持 4 档评分自评与客观题秒答/对错驱动；自然日对齐计算下次到期日；提供下次间隔预测 | 10 项单元测试覆盖 Again/Hard/Good/Easy 各状态转移、EF 下限、熟练掌握归档及多内容类型（选择/填空/主观/笔记/卡片） |
| 记忆数据仓库与模式升级 (Phase 1) | 用户库 upgrade 到 v14，无损迁移原有答案与流水；新增 ReviewPlans、SpacedReviewItem、CustomFlashcards 及三项索引；SpacedReviewRepository 涵盖计划管理、到期筛选、批量保存与未来 7 天到期量分布预测 | 4 项真实 SQLite 单元测试覆盖 v13->v14 数据无损升级、完整性、计划 CRUD、到期过滤与自制卡片联动 |
| 下拉列表 UI 优化 | 全局 Theme 注入 expansionTileTheme，消除展开时的黑线/上下边界线 | 覆盖题库详情-覆盖课程及全局 ExpansionTile，无视觉割裂 |
| 应用更新智能架构匹配 | 结合 dart:ffi Abi.current() 与 split-per-abi buildNumber，智能下载 arm64-v8a / armeabi-v7a / x86_64 专用包，彻底避免 2222 vs 222 降级错误；更新弹窗显示适配架构 | 8 项单元测试覆盖架构识别、资产解析与多平台直链，全测覆盖 |
| 管理与详情 Material UI | 数字圆角学科标签与状态同行；点击卡片进详情，顶部三项统计；相邻动作原位圆环；复用 InfoCard/TileIcon，宽屏最大 760px；隐藏空学科、去重题量、更新 Timeline | 390px/1000px 部件交互与真实字体截图复核 |
| 来源管理 | 保存零网络，URL 去重，同 bank_id 主/候选来源；新来源待验证且显式切换；删除解绑并归档，不删内容与个人数据 | 零请求、失败隔离、来源候选与跨学科拒绝 |
| 检查与下载 | 全局/单库共用只检查流程；JSON/HTTP 条件请求；直链需下载确认；持久化 256 MiB LRU 缓存、lease、链接导入单次下载 | 304/HEAD 405/无验证器、损坏缓存、取消半包、超限任务单次下载 |
| 版本与安全更新 | 用户库 v13 BankContentState；上游发布基线/本地修订分离，重复发布不安装；ATTACH 差异确认合并/替换/暂缓；回退/变更需确认 | 真实 SQLite 基线/履历/统计回滚及用户答案保留、旧库迁移 |
| 自动设置与任务状态 | 自动检查/自动安装双开关，默认仅检查，可调 1～10080 分钟；仅安全版本自动安装；后台结果即时刷新，阶段/字节进度/取消 | 设置与自动保护、后台部件刷新、原子安装禁取消 |
| 创建与同步 | 登录选学科独立建库；创建异常忽略/忽略全部/终止、成功失败报告；原始题目 ID、全量重建严格失败保护 | 深层树/共享题/203/取消/事务回滚/选课迁移，真实账号待验收 |
| 完整性与全量导出 | 显式本地完整性零网络；重新下载独立操作；SQLite/ZIP + manifest 安全导出、账号字段清理、防覆盖 | 原文件不变、旧多学科导出、ZIP 往返、路径/链接别名保护 |
| 制作规范/机制汇报 | QUESTION_BANK_SPEC.md v1.1；现有智能/全量与本地 Python 副本比较 | 八表 DDL、原始全局 ID、只读/用户库/ATTACH 契约 |

保持的实现边界：完整树 API 增量仍抓完整快照后合并，无深层章节持久化断点；旧题库保留原章节算法。自动计时器仅应用打开时运行；未承诺二进制增量包协议。RISK-01 整包内存、FTS 和加密继续暂缓。真实账号全科抓取、203 现场和平台原生文件选择器仍待实机验收；视觉效果待用户验收。

---

## 2. 最近已完成的关键工作与基线

在形成当前基线前，项目已完成的核心演进：
1. **Sprint 1 P0 历史高危缺陷全面闭环**：
   - **BUG-01**：修复题目方格页筛选抽屉时序倒置，将 `setState` 置于 `saveSettings` 之前，解决筛选配置持久化失效；
   - **BUG-02**：修复单日统计详情弹窗在 `Navigator.pop` 导致 Context 销毁后调用 `pushAdaptiveModalPage` 引发红屏的问题，解耦为父级 `onViewAll` 回调配合 `mounted` 保护；
   - **BUG-03**：修复桌面端 `pushAdaptiveModalPage` 内置 Navigator Observer 丢失返回值缺陷，冒泡透传 `route.currentResult` 还原跨平台契约一致性；
   - **BUG-04**：修复本地做题记录导入后未重新统计的缺陷，在 `importMerge` 与 `importReplace` 完成后调用 `rebuildQuestionCount()` 联动重算。
2. **三大“同步”系统深度理清与配置键解耦（BUG-07）**：
   - 全面区分了“官方题库内容同步（同步 1）”、“医考帮个人数据双向同步（同步 2）”与“医不帮多设备间个人数据漫游（同步 3）”的架构边界；
   - 彻底消除了配置键 `sync_question_bank` 对做题同步上传（`sync_answers_to_ykb`）和题库智能增量同步（`sync_bank_smart_enabled`）的错误重用与跨系统覆盖；
   - 修复了新安装设备上做题记录被误设为不上传的严重历史遗留 Bug。
2. **Android 数据库升级崩溃自愈（BUG-06）**：
   - 修复旧版本升级到 2.1.1 时 Android 原生 `execSQL` 对 `PRAGMA journal_mode = WAL` 抛出 `Queries can be performed using SQLiteDatabase query or rawQuery methods only` 导致的启动崩溃。
3. **外部连贯 PR 审核、修复与正式合流（PR #17、#18、#19、#20）**：
   - **PR #17**（Commit `73c1788`）：引入刷题全局快捷键系统（`ShortcutConfig`，支持单键/组合键、冲突迁移与输入/弹窗防误触）；按叶子身份拉取医考帮答题记录并本地保留；题目网格修复筛选状态下的章节原始题号；
   - **PR #18**（Commit `9d42918`）：攻克医考帮题目加密协议（`YkbCrypto` DES/CBC 解密），实现官方题库全量重建；设计并落地**章节级智能增量同步**（Manifest 目录对比、SHA-256 题目内容哈希、ID 漂移映射、分批请求与延迟抖动）；用户库平滑升级至 `v11` 并开启 WAL 模式与外键约束；
   - **PR #19**（Commit `abcea89`）：修复 `release.yml` 及所有桌面/移动端 CI，构建前强制执行 `flutter analyze --no-fatal-infos` 与全量测试；归档源码来源；
   - **PR #20**（Commit `56a6b0a`）：课程页右上角聚合同步操作按钮（智能增量、拉取记录、全量重建带二次确认，操作完成联动刷新课程）；实现 Windows 原生 Win32 F11 全屏（精准还原窗口位置与状态）及移动端沉浸模式。
2. **桌面端横屏自适应导航与内置嵌套模态**（Commit `3c33fb9` & `d51a660`）：
   - 移除桌面端侧边栏冗余 Logo，Tab 靠左上对齐；桌面端引入 `IndexedStack` 消除横屏滑动，移动端保留原生 `PageView`；
   - 模态弹窗引入内置 `Navigator` 与 `_AdaptiveModalScope`，实现窗内连续转场平滑替换，避免多重弹窗叠加。
3. **账号状态自检守护与 Token 失效引导**（Commit `88f07b8`）：
   - 启动时自动调用 `getUserInfo` 自检，捕获 309 错误并防抖全屏提示重新登录。
4. **开发者控制台升级与接口演练场**（Commit `84c3c02`, `be3674d`, `0452a49`）：
   - 增加 API Playground，支持自动生成 DES/MD5 签名；
   - 将同步队列错误与服务端原始响应持久化至 SQLite，支持单项手动重试。
5. **历史高危 Bug 的代码级自愈**：
   - 重写了防碰撞唯一 ID 算法（`generateSimpleId`）；
   - 统一使用 `AppNetworkImage` 代替原生 `Image.network`，实现离线图片磁盘缓存；
   - 修复了 `UserQuestion.isCut` 契约撕裂；
   - 补齐了 `NoteService` 离线同步队列与 LWW 时间戳裁决。

---

## 3. 后续开发排期规划 (Sprint 1 ~ 4)

### Sprint 1：P0 紧急缺陷修复 (建议优先认领)
- **状态**：`COMPLETE` (全部修复并通过测试验证)
- **目标**：消除运行时致命红屏、配置丢失与核心界面计数失真。

| 任务编号 | 问题标题 | 涉及文件与代码位置 | 严重等级 | 状态 |
| :--- | :--- | :--- | :---: | :---: |
| **BUG-01** | 题目方格页筛选菜单保存时序倒置，导致筛选配置无法保存 | `lib/screens/question_grid_page.dart:741-775` | HIGH | `RESOLVED` |
| **BUG-02** | 单日统计详情弹窗在 Context 销毁后调用路由跳转引发崩溃 | `lib/screens/statistics_page.dart:1120-1123` | HIGH | `RESOLVED` |
| **BUG-03** | 桌面端自适应模态弹出弹窗（`pushAdaptiveModalPage`）丢失子页面返回值 | `lib/common/platform_adaptive.dart:172-178` | MEDIUM | `RESOLVED` |
| **BUG-04** | 本地做题记录导入后未联动重算章节统计，界面对错计数失真 | `lib/screens/settings_page.dart:214-220` | MEDIUM | `RESOLVED` |

---

### Sprint 2：核心体验与题库完善
- **状态**：`COMPLETE` (BUG-05 与 RISK-02 已闭环；RISK-01 按规划暂缓)
- **目标**：释放护理题库主观题做题能力，增强接口健壮性。

| 任务编号 | 问题标题 | 涉及文件与代码位置 | 严重等级 | 状态 |
| :--- | :--- | :--- | :---: | :---: |
| **BUG-05** | 护理期末等主观题（填空/名词解释/简答等）不可答且被强制判错 | `question_options_view.dart`, `question_detail_controller.dart` 等 | MEDIUM | `RESOLVED` |
| **RISK-01** | 题库安装导入阶段整文件读入内存存在 OOM 隐患 | `lib/repositories/question_bank_repository.dart:383` | MEDIUM | `DEFERRED` (暂缓) |
| **RISK-02** | 评论接口 309 错误比对类型不严谨与 null 转换隐患 | `lib/screens/comment_page.dart:86-94` | LOW | `RESOLVED` |

---

### Sprint 3：工程规范与 CI 门禁
- **状态**：`COMPLETE` (全部技术债与 Linter 告警清理完毕)
- **目标**：清理历史残留僵尸代码，实现静态分析 0 警告。

| 任务编号 | 任务说明 | 涉及文件 | 严重等级 | 状态 |
| :--- | :--- | :--- | :---: | :---: |
| **CI-01** | 在 Android 与 Release Actions 中增加 `flutter analyze` 与 `flutter test` 门禁 | `.github/workflows/android.yml`, `release.yml` | MEDIUM | `RESOLVED` (已在 PR #19 合流) |
| **DEBT-01** | 清理 `database_helper.dart` 中遗留的 `Cards` 僵尸表创建逻辑 | `lib/db/database_helper.dart` | LOW | `RESOLVED` |
| **DEBT-02** | 清理 `database_helper.dart:266` 在 `oldVersion < 2` 内部误粘的重复升级逻辑 | `lib/db/database_helper.dart` | LOW | `RESOLVED` |
| **DEBT-03** | 清理 `HomePage._checkForAppUpdate` 中重复的题目对错重算逻辑 | `lib/screens/home_page.dart` | LOW | `RESOLVED` |
| **LINT-01** | 修复 `flutter analyze` 报告的全部 linter 警告（弃用的 Radio 参数与私有类型暴露） | `question_options_view.dart`, `comment_page.dart` 等 | LOW | `RESOLVED` (实现 0 issues) |

---

### Sprint 4：回归验证与长期演进
- **状态**：`NOT_STARTED`
- **目标**：多平台构建验证、数据库迁移测试与全文检索性能专项。
- **主要内容**：
  1. 编写 `database_upgrade_test.dart`，针对 v1~v10 升级执行真实 SQLite 验证。
  2. 跨平台打包验证（macOS DMG、Android Universal APK、Windows zip、Linux AppImage）。
  3. 题库生产端（Python 脚本）探索引入 SQLite FTS5 全文索引（解决 RISK-03）。

---

## 4. 已知阻塞事项与外部依赖

1. **Git 状态**：最新本地提交 efc2e55（Bot 清单回写）；27 个题库专项切片及发布准备已 push，工作区干净；135/135、0 issues。origin/main 已同步，v2.2.2 正式发布、四平台包与文案/清单均核验通过。
2. **医考帮官方接口变动风险**：官方接口已对齐 `2801` 客户端协议版本，接口若升级加密逻辑需通过 `ApiPlaygroundPage` 重新抓包对齐。

## 2026-11-06 持续 Goal 切片记录

- 用户已授权五项功能逐一实现并每个切片 commit；Goal 已激活。
- 切片 0：identity 改为 Material Chip + StadiumBorder，只显示数字，与状态同行排列，窄屏可换行；空 identity 不显示。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 48/48。
- 下一步：题库双轨管理的订阅设置与同库导入合并/覆盖。

### 切片 1：同库文件导入合并/覆盖

- 实现：同 bank_id 已安装时可选增量合并、完全覆盖或取消；合并保留额外题/关系，导入内容优先，根 identity/父节点冲突拒绝。
- 正式题库只读，所有 SQL 修改发生于临时副本；安装后使用 ATTACH 重算用户统计，原始题目 ID 不变。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 51/51（新增 3 项真实 SQLite 测试）。
- 下一切片：远程订阅配置与定时/手动更新。

### 切片 2：订阅清单管理

- 已接入多个 HTTPS JSON 订阅地址编辑、删除、手动检查、缓存；可开启启动和运行期间每六小时检查并更新已安装且允许更新的订阅题库。应用关闭后不执行系统后台任务。
- 清单要求下载 SHA-256、合法 bank_id；拒绝重复 ID、非 HTTPS、嵌入凭据。保留已安装文件的根 identity。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 53/53。未连接真实远端订阅实测。
- 下一切片：根身份树选择与完整暂存构建。

### 切片 3：完整身份树创建题库

- 登录后可递归选择身份，父子重叠去重，每个根生成独立 custom ID 与 1.0.0 版本；保持原始题目 ID 和叶入口关系。
- 复用 YkbBankSyncService schema/请求解密/字段转换及既有安装；暂存生成、SQL 实数统计、清除账号字段、失败/权限不足/取消不安装。进度显示目录/抓题/题数/章节/校验/安装。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 55/55，含深层树、共享题和权限/取消真实 SQLite 测试。
- 未做真实账号抓取；下一切片：自建增量版本与智能同步进度，之后详情/历史和导出。

### 切片 4：同步实时进度与自建更新版本

- 智能同步与全量课程操作接入统一进度组件；自建更新递归抓取目标根，合并保留本地额外题，有变化才安装并递增 PATCH；无变化不增版本。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 56/56，新增 SQLite 无变更判断测试。
- 下一步：用户库安装履历、题库详情树与时间轴；随后安全导出。

### 切片 5：题库详情与安装时间轴（2026-11-07）

- 用户库升级至 v12，新 BankHistory 表记录创建/导入、替换和增量安装，新增题量按 ATTACH 查询新题 ID，不用净题量差猜测。
- 管理卡片详情入口展示题量、版本、来源、订阅地址、覆盖 identity/课程/章节树和变更时间轴。旧履历不补造。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 57/57，包含 v11->v12 保留用户记录迁移测试。
- 下一步：SQLite/ZIP 安全导出与最终整体验证。

### 切片 6：安全 SQLite/ZIP 导出（2026-11-07）

- 详情页可选导出 SQLite/ZIP；桌面使用保存路径，移动端保存外部/文档目录；取消不写文件。
- 正式库只读，副本清除账号字段并 VACUUM，校验后打包；ZIP 包含一个标准 SQLite 与 manifest。旧多根合并库按选定根生成独立标准题库再导出。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 59/59；测试覆盖标准/旧库导出关系完整、校验通过、原文件不变。
- 下一步：最终审查目标覆盖与安装失败/订阅删除一致性、知识库同步。

### 收尾切片 7：安装事务与订阅清理（2026-11-07）

- 题库安装在冲突选择前加互斥锁；登记、时间轴和 ATTACH 统计重算使用同一用户库事务。发生异常恢复旧文件，取消后释放锁。
- 删除订阅/清单条目同步清理下载元数据，保留已安装文件和仍有效缓存；强化根 identity/版本/schema/hash 校验。旧合并库详情通过独立只读连接读取。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 62/62；新增真实 SQLite 安装、故障注入回滚与并发取消测试。
- 下一步：完整重建复用深层构建、自建自动检查节奏、进度终态与导出路径保护。

### 收尾切片 8：完整重建与持续进度（2026-11-07）

- 课程全量重建复用递归完整构建；原始 ID、真实叶归属、去重计数、秒时间和账号字段清理保持规范。失败/无权限不替换旧库，重建递增 PATCH，关闭包覆盖更新。
- 旧根课程迁移到叶 identity 时，以 ATTACH SQL 保留消失归属的选课状态。重建后的完整树题库走安全构建/合并分支；自动检查成功后六小时冷却，失败继续现有退避。
- 创建页固定进度/取消区；目录/题目请求设置超时，错误结果重试一次，非选择分组保留有效后代。同步无变化、权限/重试与批次完成提供终态。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 63/63，增加端到端全量重建/权限保留/选课迁移 SQLite 验证。
- 实现界限：完整树题库更新采用完整快照检查再增量合并，尚未实现深层树章节缓存/断点续传；原有题库保留既有章节智能算法。下一步导出路径保护和最终文档更新。

### 收尾切片 9：导出防覆盖与移动端文档保存（2026-11-07）

- 拒绝导出到应用数据库目录、正式库/用户库及其符号链接/硬链接别名；新文件也解析父目录链接，暂存不得覆盖已有文件。
- 移动端使用已安装 file_picker 8.1.7 的 saveFile(bytes) 系统文档 API；桌面端依旧路径返回后复制。移动返回可能为 content URI，不按本地路径写入。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 64/64，新增正式文件及目录链接拒绝测试；未做原生文件选择器实机验证。
- 下一步：修复管理页创建/订阅入口错位，补导航测试，统一最新文档状态。

### 收尾切片 10：管理入口可达与返回刷新（2026-11-07）

- 修正创建/订阅按钮错误位于导入冲突弹窗的问题，移入管理页 AppBar；冲突弹窗只保留取消/覆盖/合并。
- 创建/订阅页返回总是刷新目录和缓存，涵盖多库部分完成后取消、订阅保存后检查失败。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 66/66。390px/1000px 部件测试验证标签样式、创建登录提示、订阅导航和返回刷新，无布局异常。
- 下一步：最终产物一致性/导入往返检查和文档交接；没有原生实机抓取/文件选择器测试。

### 切片 11：订阅产物一致性与可移植往返（2026-11-07）

- 下载除下载包 SHA-256 外，校验解压后 SQLite 的可选 SHA-256 和根 identity；拒绝清单更改已安装根。
- 真实 SQLite 导出 ZIP→重新导入验证通过；根/hash 不符拒绝安装、原文件与历史不受影响。
- 最终 flutter analyze --no-pub 0 issues；flutter test --no-pub 67/67。所有代码切片分别提交；知识库已本地同步，真实账号/原生选择器验收为下一步。

## 2026-11-07 用户反馈切片 A：订阅格式与更新设置

- 支持 HTTPS ZIP/SQLite 直链和 JSON 清单，按响应文件头识别，解决二进制被 UTF-8 JSON 解码导致的异常；已下载用户 Gitee 临床题库真实 ZIP 并通过只读完整性/根信息检查。
- 订阅列表可以修改地址；单库订阅来源可独立覆盖，不影响共享清单的其他库。自动更新移至设置，检查间隔支持预设与自定义 1～10080 分钟，修改后重设计时器。
- 验证更正：f86db66 提交时实际为 1 条 lint、71 通过 / 1 失败（设置测试遗留 Timer），此前记录的全绿不准确。后续补全大括号并在测试结束前停止应用定时器；本次重新验证 flutter analyze --no-pub 0 issues、flutter test --no-pub 72/72。真实 Gitee 响应由前一切片临时探针检查，未纳入仓库。
- 下一切片：详情视觉重做、学科/去重题数/空节点隐藏、管理页详情旁更新/导出图标。

## 2026-11-07 用户反馈切片 B：详情与管理动作

- 详情采用与设置/个人页相同的 InfoCard、TileIcon、主题字体/颜色与分区间距；更新记录显示简洁日期与实际新增题数。
- 覆盖课程仅显示直接拥有课程的学科；隐藏空分组时保留下级有效学科。课程/章节题量由 SQLite COUNT(DISTINCT question_id) 得出，文案改为“道题”。
- 已安装且有订阅/下载链接的题库始终显示手动更新图标，与详情、导出图标同一行；详情返回刷新订阅配置。单库订阅链接可在详情修改，保持共享清单其他题库的来源。
- 导出动作在管理卡片和详情 AppBar 共用组件，支持取消、ZIP/SQLite；管理页导出期间禁用冲突操作。
- 新增 390px/1000px 真实 SQLite 部件验证：空学科过滤、跨章共享题去重、编辑地址预填、相邻图标与导出取消。
- 下一步：创建过程逐项错误选择与成功/失败报告；最终再验证直链手动更新完整安装路径。

切片 B 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 76/76。

## 2026-11-07 用户反馈切片 C：创建错误决策与报告

- 创建过程课程目录、章节、题量不完整、字段/事务错误弹出“忽略 / 忽略全部 / 终止”；203 明确提示账号无查看权限，其他错误显示简洁原因与错误码。忽略全部限定本次创建，并跨多个所选学科生效。
- 被忽略的章节整章跳过，事务异常回滚；完成后按成功/失败分页列出条目、原因、已保存题库与实际去重题量。失败条目不写入内容包；所有条目都失败时不生成空题库。
- 终止删除当前未完成暂存文件，先前已完成题库保留；页面关闭触发取消。同步/全量重建未传交互处理器，仍严格遇错不安装。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 84/84。新增真 SQLite 忽略目录/章节、错误事务回滚、跨题库忽略全部、取消/终止清理和全失败无产物；390px/1000px 创建→弹窗决策→部分安装→报告部件测试。
- 下一步：最后统一“学科”错误文本，验证 Gitee 真实 ZIP 从订阅识别到安装/手动更新的调用链，再更新最新基线与交接。

## 2026-11-07 用户反馈切片 D：最终回归

- 题库校验、订阅匹配和增量合并错误统一使用“学科”，不再向用户显示“根 identity”。
- 新增真实 SQLite 手动订阅更新回归：自动检查跳过被冻结内容，单库手动检查刷新来源并新增题目；全局个人答案保留，ATTACH 重算课程对错数，重复检查不再安装、不新增履历。
- 实际下载用户 Gitee 临床期末 ZIP（25,939,926 字节，SHA-256 3db37a844ec0f8ac3688a7fcf7967de1a8adf8f787a3e4801dd1276893383061），57,346 题、40 课程、1,137 章节、学科 20101。只读完整性检查通过；用原始响应文件字节运行 Flutter 临时探针，验证订阅识别→注册→安装→手动检查，保留发布版本 3.0.0，未出现 UTF-8 异常。临时探针已删除，不作为常规测试依赖。
- 实际最终验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 85/85。真实 Gitee 下载/安装探针额外 1/1 通过。
- 用户 9 项反馈实现完成；下一步是用户视觉验收与真实账号创建（含 203 弹窗）、平台原生文件保存验收。

## 2026-11-07 题库管理流程统一设计（待实施）

- 用户要求先梳理保存/重复订阅/检查/下载/完整性/本地合并职责。已核对 7da98f4 实际调用链，形成 [QUESTION_BANK_MANAGEMENT_DESIGN.md](../../antigravity/QUESTION_BANK_MANAGEMENT_DESIGN.md)。
- 当前保存后遍历全部来源，直链无条件整包下载/校验并删除临时产物；顶部检查只发现版本，单库图标检查并安装；本地 hash/自动更新许可与更新判断混用。
- 提案：来源/已安装题库/更新任务独立；保存只存配置；全局/单库检查同流程且不安装；JSON/条件请求轻量发现，直链无法确认时诚实显示需下载确认；下载产物复用；同 bank_id 候选主来源；记录上游基线和本地补充，避免自动覆盖与重复合并。
- 完成项：源码审计与设计文档。未完成项：全部提案运行时实现。本轮未改应用代码，未新增提交，85/85 为上一代码基线的验证，并未针对文档重复跑测试。
- 下一步第一项：实施保存无网络、全局/单库一致检查及来源去重/失败隔离，再推进条件请求/缓存和版本基线迁移。每片分析与全测通过后按既有授权提交；保持只读/用户库/全局 ID/ATTACH 契约。

## 2026-11-07 统一管理方案：切片 1

- 持续 Goal 已切换为完整实现 QUESTION_BANK_MANAGEMENT_DESIGN.md。
- 已落地来源目录/主来源/候选来源，保存无网络；来源失败隔离；全局与单库共用只检查不安装流程；JSON 条件请求，直链 HEAD/条件 GET 不接收整包、显示需下载确认。
- 新来源待检查；修改单库来源先保留旧绑定，检查匹配后切换。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 89/89。
- 尚未完成：持久化下载缓存、链接导入、上游基线/本地修订、安全更新处理、独立自动安装设置及完整状态 UI。旧 refresh/install API 暂保留，后续切片统一移除。
- 下一步：缓存产物并接通从链接导入，再处理上游基线与本地补充。每片验证后 commit，不 push。

## 2026-11-07 统一管理方案：切片 2

- 新增持久化有界下载缓存（默认 256 MiB），保存已校验包与来源/摘要/HTTP 验证器；复用前核对字节摘要，活动租约防清理、超限 LRU，损坏重下载。
- 从链接导入 ZIP/SQLite，支持订阅以后更新；注册/安装复用本次下载，不重复来源。来源操作提供检查/显式下载确认；确认后安装复用包。管理页包安装改走缓存任务。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 94/94。新增 5 项真 SQLite 缓存/请求次数/损坏/租约/一致性测试，390px/1000px 链接导入弹窗可达。
- 未完成：上游基线与本地修订、安全合并/替换与重复发布判断；自动安装独立开关；完整来源与详情状态 UI、完整性/重新下载。下一步从用户库基线元数据与安装事务开始。

## 2026-11-07 统一管理方案：切片 3

- 用户库 v13 新 BankContentState；已处理上游发布标识/版本/摘要和本地修订独立保存，和安装履历/ATTACH 统计同事务回滚；题库 schema v1 不变。
- 同一上游发布重复检查/安装不再合并；本地改动保留基线，新上游需要显式合并/替换/暂缓；同版本内容变更/回退和旧库未知基线不自动覆盖。下载后用 ATTACH 展示新增/不同/本地独有题量，ZIP 比较复用缓存。
- 自动检查与自动安装分离，默认仅检查；自动安装限定已知基线、无本地补充、可自动更新且版本前进的库。移除旧混合 refresh/setBankSource 路径，来源读取统一目录。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 101/101。新增 7 项真 SQLite 基线/合并/回退/回滚/缺少 SQLite 摘要/旧库迁移/自动安装测试；设置双开关验证。
- 未完成：完整 Material 管理页/来源/详情状态呈现、候选来源与待检查编辑、显式本地完整性与重新下载、任务进度/取消以及边界审查。下一步完成 UI 与对应交互测试。

## 2026-11-07 统一管理方案：切片 4（完成）

- 管理、来源、详情统一 Material Design：复用 InfoCard/TileIcon、主题形状与字体，宽屏内容限制 760px；数字学科标签与状态同行，详情/更新/导出相邻，更新图标由检查/下载确认/下载并更新状态驱动。
- 来源添加/编辑即时保存且不联网；显示官方来源、重复提示、待检查的新来源、候选来源及显式切换。原绑定在新来源匹配前继续可用；移除提示解绑影响，保留已安装内容、个人数据和来源归档。
- 详情提供订阅状态、最新版本、最近检查时间与本地补充；仅在不同版本或本地补充时显示已应用订阅版本。覆盖课程隐藏空学科，课程/章节按 DISTINCT 全局题目 ID 计数；本地完整性检查和重新下载收进更多菜单。
- 新 BankDownloadTask 提供阶段、字节进度、取消与半包清理；原子安装开始后不允许取消。缓存复用、重新下载及超限包在同一任务内持有租约，避免确认后再次下载。轻量检查显示“检查中”，下载任务只显示一组进度。
- 删除无人调用的旧 checkRemoteManifest/downloadBank/hasUpdate 网络与判断路径；保留 GitHub 代理，HTTP 验证器只在同一实际传输地址复用。
- 配置/检查/确认/来源切换/安装使用 ChangeNotifier 通知页面，后台检查结果即时刷新。修复详情保存链接的 setState 返回 Future 断言；拒绝远端更改已安装学科，并保留原文件、登记和履历。
- 最终代码实际验证：flutter analyze --no-pub **0 issues**；flutter test --no-pub **113/113**。新增 12 项缓存/取消/超限单次下载、学科保护及 390px/1000px 管理/详情/来源交互与后台刷新回归。
- 已对 390px/1000px 使用真实中文字体与 MaterialIcons 的截图进行视觉检查。用户视觉验收、真实医考帮账号抓取和各平台原生文件选择器仍未实机验收。
- 完整统一管理方案已实施并通过上述代码审查与自动化验证；切片提交后不 push。下次先核对 Git 与本文，再按用户反馈做实机验收，无需重做已完成切片。

## 2026-11-07 用户追加反馈：切片 1（错误诊断与页面安全）

- GitHub 下载镜像仅用于 GitHub/GitHubusercontent 域名，Gitee、R2 和签名订阅地址保持原样。用户给定的 Gitee 临床 ZIP 与 R2 口腔 ZIP，在配置 gh-proxy.com 后均通过实际 Flutter HEAD 探测（HTTP 200 / 需下载确认），未下载整包。
- 检查输出 [bank-check] 请求方法/公开地址/HTTP 状态及异常堆栈；来源失败仍独立保存。全局、单库、来源和候选检查通过共同弹窗展示失败来源与实际原因，不改变已安装内容。
- 复现订阅展开 bool 转 double 的异常：ExpansionTile 与 SelectableText 内部滚动共用 PageStorage 键。给链接文本和订阅列表独立命名空间，重复展开回归通过。
- 课程页 _refreshData / 异步恢复进度 / 管理返回检查 mounted，覆盖管理未关闭而原课程路由已移除的生命周期测试。
- 保留工作区将“官方题库”改为“内置题库”的既有命名修改，相关 UI 测试同步更新。
- 实际验证：flutter analyze --no-pub 0 issues，flutter test --no-pub 117/117；真实链接轻量探测额外 1/1。提交后不 push。
- 未完成：用户追加的详情三项统计、点击卡片进详情、所有题库操作按钮内圆形进度；下一切片完成这些 UI 反馈。


## 2026-11-07 用户追加反馈：切片 2（详情统计与按钮进度，完成）

- 详情名称/描述/数字学科标签下方同行显示课程总数、章节总数、题目总数；标准库使用校验过的 BankMeta，旧合并库用只读 SQL COUNT，未安装且缺少元数据时显示“—”。跨章共享题仍按独立题目计数。
- 点击管理卡片进入详情；切换当前刷题题库通过独立“使用此题库”按钮执行，保留启用开关及相邻详情/更新/导出图标。
- BankActionButton / BankActionProgress 统一 20px、2px 描边的 Material 圆形进度，不在环内放文字。全局检查、单库检查/下载、内置/订阅来源检查、候选来源确认、导入、导出、创建与课程同步均在发起按钮原位显示；移除页面底部/卡片外的重复进度。下载阶段按字节显示确定进度，其他阶段为不确定进度；取消仍可通过进度按钮执行，原子安装禁取消。
- 页面刷新保留旧内容，避免按钮因 FutureBuilder 重新加载而消失。FFI 回归将异步操作放在 tester.runAsync 的真实时钟中，并等待页面的 SQLite Future，避免跨测试共享配置队列或关闭数据库时仍有加载。
- 新增 6 项阻塞请求交互测试，覆盖全局、普通/内置来源、单库、详情“待比较”、候选来源的原位圆环及无中心文字；390px/1000px 验证详情三项统计、卡片导航不更改当前题库及跨章共享题去重。真实中文字体与 MaterialIcons 截图已复核。
- 实际验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 全量 123/123。R2 临时联网探针额外 1/1：用户口腔 ZIP（38,029,760 字节）下载、导入、只读完整性、订阅绑定成功；版本 1.0.0、学科 30401、77,189 题、44 课程、1,182 章节。配置 gh-proxy.com 仍直接访问 R2；再次检查为 HEAD HTTP 304，没有重新下载、安装或增加履历。探针不加入常规测试，临时脚本已清理。
- 本次追加的 5 项反馈已实现；真实账号创建/203 现场与各平台原生文件选择器仍待实机验收，用户视觉验收待反馈。保持正式库只读、用户库隔离、全局 question_id 和 ATTACH 契约。按既有授权验证后提交，不 push。


## 2026-11-07 追加六项需求：切片 A（删除与更新语义，完成）

- 详情更多菜单增加“删除题库”及确认框：移除本地内容与备份，保留全局作答/收藏/笔记/流水、选课和履历。内置或有来源的题库保留为未安装入口，独立本地库从目录移除；来源配置不变，删除当前库后选择可用库。同步基线/章节缓存清理，防止后台任务重装刚删除的库。
- 删除仅允许应用所属路径，与安装共用互斥；先关闭连接并移动内容，用户库事务失败还原目录。只改可写用户元数据，不向正式题库执行 SQL 写入。用户库/题库 schema 均不变。
- 真实 SQLite 回归核验题目内容：合并保留 local 独有题并用上游替换相同 ID 的差异题；替换仅留下上游题。个人答案保留，重复发布不安装。更新弹窗将动作明确命名“合并更新 / 替换题库 / 暂不更新”。
- 订阅页下载确认提示与图标同一 Row，文字可换行，按钮及其进度保持右侧位置；390px/1000px 验证布局及删除确认/取消/返回刷新。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 129/129（新增删除数据层 4 项、提示布局 2 项，扩充合并/替换与删除导航回归）。切片按既有授权提交，不 push。
- 未完成本次第 4～6 项：创建前法律风险/会员权限确认、父子全选/半选、学科名称与 ID 小 tag 同行。下一步完成创建页交互并逐片分析、全测、提交。


## 2026-11-07 追加六项需求：切片 B（创建确认与学科树，完成）

- “开始创建”先显示 Material 确认框，说明自动抓取的著作权/服务协议/法律责任和会员/课程权限不足导致失败（203）。必须勾选已了解风险并确认当前账号会员与访问权限，才能“确认并开始”；取消或关闭不创建报告、不请求题库内容。会员/权限是用户确认，未声称通过 API 验证；原 203 错误选择和结果报告保持。
- 新 BankIdentityTree 选父节点递归勾选全部后代；取消部分后代时祖先为 null 半选，点击半选父节点补齐，点击全选父节点清空子树；子节点全部选中时自动归并父节点。沿用 BankIdentityNode.selectedRoots，半选父节点不会把取消的后代传给抓取器，完全选中的父子不重复建库。
- 学科名称与数字 ID 小圆角 Chip 同行；层级缩进、折叠状态和选择独立，去除展开时的深色边线，创建页最大 760px 与其他管理页一致。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 133/133。新增取消确认零请求 2 项、三层学科树联动/半选/折叠后保留/补齐/全清/去重/标签同行 2 项；原创建→确认→203 忽略/忽略全部/终止→报告真实 SQLite 流程均通过。390px/1000px 真实字体与 MaterialIcons 临时截图探针额外 2/2，并已人工复核；临时脚本已清理。
- 本次第 1～6 项全部完成；切片 A 为 032c2ea（129/129），切片 B 为 2ea7e79（133/133），不 push。真实账号会员/课程权限现场和原生文件选择器继续待实机验收。题库 schema v1、用户库 v13、正式库只读、全局 question_id 和 ATTACH 契约保持。
- 下一会话：先核对最新 Git/基线/本交接，按用户反馈做视觉或真实账号验收，不重做已完成模块。


## 2026-11-07 创建页性能 Goal：切片 1（完成）

- 原树用递归 ExpansionTile + maintainState 挂载所有 4,380 个节点，每次勾选刷新整页并遍历整树；本轮先前复现约 5 秒。
- BankIdentitySelection 首次索引树及叶节点计数，勾选只更新所选子树与祖先；每行 ValueNotifier 局部通知。BankIdentityTree 用扁平可见节点与 ListView.builder，只挂载视窗附近行，折叠/滚动不丢选择；创建页的选择状态只通知开始按钮。
- 大目录全测实测：挂载 23 行，父节点勾选 93ms、叶节点取消 18ms、滚动回来再勾选 11ms（Flutter debug widget test，本机数据不等于所有设备的保证）。无关兄弟行保持同一 widget；父子全选/半选、selectedRoots 去重与折叠保留回归通过。
- 实际 flutter analyze --no-pub 0 issues；flutter test --no-pub 135/135。按既有授权提交，不 push。正式库只读、用户库隔离、全局 question_id 与 ATTACH 契约保持。


## 2026-11-07 创建页性能与 Material UI Goal：切片 2（完成）

- 管理卡片用 BankTag（StadiumBorder、主题色、labelSmall、非交互标签）统一小标签；当前使用与题库名称紧邻同行，采用 primaryContainer/onPrimaryContainer 强调色，其余状态和学科号使用较淡背景。保留 48px 操作触控区域，不把小标签作为按钮。
- 检查全部更新集中在题库订阅 AppBar，管理卡片保留单库检查/下载/更新。仍共用 BankSubscriptionService.check，仅检查不安装；全局检查保持按钮原位无文字圆环、失败来源与 HTTP 原因弹窗。全局/单库网络契约未改变。
- 更多导入方式改用 file_download_outlined，导入进行时在同位置显示圆环；链接/文件导入保持可达。
- 详情学科号小标签移至名称与描述右侧，数字保留、悬停提示学科编号；只显示合法数字学科号。三项统计仍在头部下方；题库信息增加题库文件大小（读取已安装 SQLite 字节元数据，不含下载包与备份，也不新增网络请求）。
- 最终验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 135/135。390px/1000px 布局、标题同行标签、右侧编号/描述、标签高度、导入与订阅导航、全局原位进度/失败弹窗回归通过。使用 PingFang 与 MaterialIcons 生成并人工复核管理/详情四张截图，额外捕获运行 4/4 通过。
- 最终大目录全测实测：4,380 节点只挂载 23 行，父节点勾选 105ms、叶节点操作 23ms、滚动后再勾选 14ms；本机 Flutter debug 部件测试，设备实机数据待用户反馈。父子全选/半选、折叠/滚动保留与根去重契约继续通过。
- 性能提交 3d6287b，UI 提交 093f4ef；均不 push。用户库 schema v13、题库 schema v1、正式库只读、全局 question_id 与 SQLite ATTACH 契约保持。


## 2026-11-07 v2.2.2 发布准备与推送（完成）

- 用户明确授权打 tag 并 push，后续将目标版本从 2.0.6 更正为 2.2.2+212；此前未 push 的限制不适用于本次发布。没有创建或推送 v2.0.6。
- pubspec.yaml 版本为 2.2.2+212，构建号保持高于上一开发版本 211。对照上一正式发布 v2.0.5 的实际 Git 差异与合并 PR，编写 .github/release-notes/v2.2.2.md；明确感谢 @JMK712 的 PR #17、#18、#19、#20，包含题库/自建/同步/快捷键/主观题/桌面/稳定性变化及完整 compare 链接。
- Release workflow 优先读取目标 tag 内的专属说明文件，旧 tag 回退到该 tag 的提交信息；不再读取 main 最新提交，避免后续提交覆盖发布说明。其余平台构建与 Bot 发布流程保留。
- 验证：flutter analyze --no-pub 0 issues；flutter test --no-pub 135/135；Ruby 解析 workflow YAML。隔离 Git 仓库运行实际说明提取 shell，验证 annotated tag 内文案、后续 main 变更隔离、旧标签 fallback 与四项 PR 致谢。
- 发布准备提交 bd6a7a0；annotated tag v2.2.2 指向 bd6a7a08a555403c532f059a4bbdf087ec54f800。已原子 push main 与该 tag，远端保留全部既有提交，没有 force push、没有重写旧 tag。
- Bot 已收到 tag 并运行发布流水线：https://github.com/nanguaguag/yibubang/actions/runs/42376143828 。此条记录时仍在构建/验证，尚未确认 Release 与安装包发布成功；勿将触发流水线记为多平台构建已通过。
- 下一步第一项：查看上述 workflow 结果；成功后检查 v2.2.2 Release、安装包、专属文案及 yibubang_update.json 的 Bot 回写。若失败根据对应平台日志修复，保留已发布 tag；不要自动挪动 v2.2.2。


## 2026-11-07 v2.2.2 正式发布核验（完成）

- GitHub Release：https://github.com/nanguaguag/yibubang/releases/tag/v2.2.2 ；正式发布、非 draft、非 prerelease，GitHub latest 已指向此版本。应用版本 2.2.2+212，tag 指向 bd6a7a0。
- Release workflow 42376143828 全部 6 个 job 成功：分析测试、Android、Windows、macOS、Linux、发布与清单回写。其成功只代表 CI 构建与发布，未替代各平台实际安装/刷题现场验收。
- 8 个 Release 附件均为 uploaded 且非空：4 个 Android APK（通用 / arm64-v8a / armeabi-v7a / x86_64）、Windows ZIP、macOS ZIP、Linux tar.gz 与更新 JSON。
- 发布 body 与 .github/release-notes/v2.2.2.md 逐字规范化比较一致；包含 @JMK712 的 PR #17～#20 致谢与 v2.0.5...v2.2.2 比较链接。
- 下载 Release 附带的更新 JSON，核对与远端 main JSON 完全一致，latest_app 为 2.2.2、资产 URL 指向本次版本、update_info 与文案匹配；原有 question_banks / data_for_version / 数据 hash 配置未改变。
- Bot 回写提交 efc2e55 已 fast-forward 同步至本地 main，工作区干净；未挪动 v2.2.2 tag，未再改变已发布源码。最新源码验证仍为本次发布前 135/135、分析 0 issues；Bot 仅修改更新 JSON。
- 本次发布任务无未完成项。下一会话第一步：核对 efc2e55 / v2.2.2 与 Git 现场，根据用户安装及升级反馈处理；如需新修复，使用新提交和后续版本，不改本次发布 tag。
