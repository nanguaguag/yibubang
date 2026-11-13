> 历史阶段记录：2026-11-13归档，当前状态见[项目进度](../../CURRENT_STATUS.md)。旧部署/外接模型/未提交描述仅属当时。

# AI 搜索验证记录（2026-11-12）

## 2026-11-13 检索条目1–25与段落选择断言（最新状态）

- Cloud Run00018-q7c/100%，health默认12/最大25；严格result_count1–25、textbook_count0–total。线上0/26/bool/string/教材超总数返回400，专用设备额度不变。
- Flutter全量357 PASS/3 opt-in联网默认skip；最终选择/设置8 PASS，后端最终39 PASS，analyze0。旧设置默认12/8:4、增总数保留来源比例、保存/取消/重开、client实时payload、25条预算/单源/完整编号与Answer显式列表25条均有回归。
- 生产App `AI_MODEL_LIVE_TEST=1 AI_RESULT_COUNT=25 AI_TEXTBOOK_COUNT=17 flutter test --no-pub test/ai_model_live_test.dart` 2 PASS；真实17教材+8题，内置gemini-3.5-flash/answer_gen/v1生成成功、SQLite保存、引用回调打开教材。Google服务端SUCCEEDED/references10/streaming=true/quota_cost3；正文包含第13项，说明不是只用原来前12。仍不能以25参考卡片宣称模型读完全部25条；实际引用由内置回答决定。
- 精确修前SelectParagraphSelectionEvent复现同一lastSelectionResult断言；引用/行内公式内部SelectionContainer.disabled后同用例、鼠标三击、正文选择、引用点击PASS。未关闭整个SelectionArea、未修改SDK或依赖。
- 320/1000px设置与条目弹窗真实字体图标截图人工查看；Android APK/macOS普通main Debug构建通过。本轮产品UI为Widget渲染与模拟鼠标测试，未冒充Android/其他平台真机或大陆网络测试。
- 回执ai_backend/.local/result-count-app-live.json、result-count-online-validation.json、result-count-online-answer.json；日志result-count-*、result-selection-*、selection-*及截图均忽略。无重导数据/页图/schema变更/commit/push/Release。[限制及费用边界](../../ai-search/RETRIEVAL_LIMITS.md)。

## 2026-11-13 默认高级/设置与200额度（最新状态）

- 东京00015-rlt/100%，默认rephrase/streaming=true，daily_limit=200，原Store及两源8教材+4题保持。
- 后端33 PASS；Flutter全量348 PASS/3联网默认skip，设置4项PASS；analyze0。开关默认/联动/本机保存/重开、缓存损坏/网络失败回快照并离线选模型、旧client实时读选项、最终全文/引用不重复持久化均覆盖。
- 三个线上模式分别扣1/3/2：默认streamAnswer 6delta、首文字2.8s、总3.7s；基础4.03s与仅改写4.74s。均12来源含8教材、内置stable，模型查询不扣额度。网络样本非延迟保证。
- 实际App client/controller→Cloud Run→streamAnswer→SQLite与Widget引用点击2 PASS；Android/macOS Debug构建PASS，最终analyze0。线上200日额/每分钟6/并发/重放/错误凭据五项PASS，专用设备字段完整恢复；两个TTL规则只读GET均ACTIVE。截图是Widget渲染，原生新设置/四平台真机尚未验收。
- 公共4模型JSON随App和Docker共用，不含凭据；后端冷启动不等官网、后台刷新4秒节流60秒，App不直连官网，网络失败仍有标记的备用目录。Google实际文本分片/最终完整答案/迟到引用已通过真实响应核查。
- TTL和图片Worker保留原职责；3倍仅App额度，不把配置开关当已证实Google3倍费用或赠金100%抵扣。日志与回执均忽略的.local/advanced-*；没有重导数据/schema变化/commit/push/Release。

## 2026-11-13 内置Answer与模型选择（当前状态优先）

- 最终东京修订00014-dlq/100%，health provider=search_answer、generation_mode=basic_answer。运行推理角色只有Search/Answer两项权限，旧Vertex环境/预测权限移除。
- 四个官方内置模型真实200/SUCCEEDED；生产App客户端/控制器→Cloud Run→Answer→本地SQLite与引用Widget实际PASS，12资料含8教材。UTF-8引用偏移映射按本轮来源URI；模型选择持久化/重开参数与逐行完成测试通过。
- 最终后端27 PASS、相关Flutter18 PASS、analyze0。模型缓存过期且失败刷新节流内的下一请求仍拒绝回归通过。接续阶段全量344与Android/macOS Debug记录保留；未重复付费四模型生成。
- 最终部署后health、官方目录4项、匿名401、模型查询前后搜索quota不变再次PASS。回执及最终测试/部署日志保存在忽略的.local/builtin-*，真实字体截图screenshots/builtin-ai-live.png为Widget渲染，非原生/手机实测。
- 原Store无重导数据，原Standard检索应用保持；新Enterprise Answer应用实测需LLM开关。请求禁用改写/推荐、无托管session，不等于已核实实际Advanced计量/专项赠金SKU抵扣。[费用说明](../../ai-search/COSTS_AND_BUILTIN_MODELS.md)。原生缩略图系统确认、四平台真机/国内网络/Release仍未验收。下方334/原独立Gemini/仅题目等描述为2026-11-12历史。

项目 `yibubang-search`，独立服务东京 `yibubang-ai-search`，最终修订 `yibubang-ai-search-00003-cl2`，100% 流量。App 默认 URL 已替换为实际线上地址。

## 自动化

- `flutter analyze --no-pub`：0 issues。
- 最终 `flutter test --no-pub --reporter expanded`：**334/334 PASS**（原基线 314，新增 20）。日志 `/tmp/ybb_ai_full_final.log`。
- Python FastAPI/策略/事务/上游模拟：**11/11 PASS**，日志 `/tmp/ybb_backend_tests.log`。
- Flutter 新覆盖：任意 UTF-8 单字节/CRLF SSE 边界、无终止帧/异常 EOF、注册阶段取消不启动搜索、追问与编辑分支截断、停止保留中文/emoji、会话持久化/重开/删除、旧日零额度不阻塞新日服务端判断、未完状态恢复、重复发送/会话操作竞态、v24→v25保留原作答和外键完整性。
- UI 新覆盖：欢迎建议、320px/1.6字号、390px、1000px深色、历史/修改/新建/删除操作、检索→输出→停止、可横滑比较表格；引用走真实 `QuestionSearchRepository`→只读已安装题库→`QuestionDetailPage`，题目 `q` 打开时携带原 `user_answer=A`。
- 真实字体 PingFang + MaterialIcons 的六张截图已检查，位于 `ai_backend/.local/screenshots/`（不提交）；手机、桌面、检索骨架、表格均未溢出。截图为部件渲染，不冒充手机实测。

## 线上

- 注册成功、quota成功，未认证搜索 401，错误凭据 401。ADC runtime 的数据库条件 IAM 与推理最小权限经实际请求验证。
- 完整 Search→Gemini SSE→引用→追问探针运行两轮，每轮两次；最终修订那轮：
  - 问题：HLA I 为什么向 CD8 T 细胞提呈抗原？首文字 **3.04s**，总 **5.32s**，12个delta。
  - 追问：与 HLA II 的区别？首文字 **2.58s**，总 **6.19s**，18个delta。
  - 两次均完成 `done`，有真实题目 ID 引用；quota准确 **98→96**，重放返回409。
  - 数值只代表当前开发网络两次样本，不是延迟承诺。模型教学事实仍需要医学审核。
- `smoke_limits.py` 只临时设置专用探针安装计数，验证 **100/天→429、6/分钟→429、活动租约→429、重复请求→409、错误凭据→401**；原字段完整恢复。未调用Google生成，未修改真实用户或全站/IP计数。
- Cloud Run 自动请求日志 remoteIp 的哈希与注册计数IP键一致；当前直接 run.app 入口符合实现假设。未来添加LB/CDN需重审代理链。
- 两个日计数集合已提交 `expires_at` TTL 配置；自动删除为异步过程，本次没有等待三天验证删除。
- 只保存脱敏回执于 `.local/smoke-result.json` / `.local/limits-result.json`，安装凭据0600且忽略，不输出Google令牌。

## 构建

- `flutter build apk --debug --no-pub`：成功，`build/app/outputs/flutter-apk/app-debug.apk`（约170MiB，多架构调试包）。现有 SDK XML/Java8 废弃警告不影响构建；未升级无关依赖。
- `flutter build macos --debug --no-pub`：成功，`build/macos/Build/Products/Debug/yibubang.app`。
- 未连接Android/iOS真机；Windows/Linux未在该macOS机器构建。未发布Release、提交或push。

## 边界

- 每设备当前指安装凭据，重装/换IP/仿造安装仍需Play Integrity/App Attest、账号或边缘限流进一步防护。
- 100次包括已受理的失败、停止和重试。全站2000/天不是货币硬预算，也不阻止公共API的网络/计数读写成本。
- 仅题目引用打开原题；教材PDF页码查看尚未实现，实际PDF尚未供入。
- Google trial credit实际SKU/有效期及是否抵扣Gemini/Cloud Run/Firestore尚未验账；新费用可能单独计费。
- 测试中的题目详情既有官方网络请求被Flutter HTTP测试环境拒绝，验证的是本地原题/作答导航，不是官方在线接口。


### 2026-11-13 六项 AI 搜索反馈修订

- Flutter全量355 PASS/3 opt-in联网默认skip，后端36 PASS；最终静态分析0。用户Markdown原文、组词/Enter/Shift+Enter/KeyRepeat、Android双触点实际FileImage缩放/双击、教材方向键与跳转弹窗/边界、模型离线单选、比例持久化及新旧导航均有回归。最新设置/模型局部9 PASS，320/1000px真实字体图标截图已查看。
- Cloud Run00016-lbf/100%，沿用全部既有配置与Store。生产App `AI_MODEL_LIVE_TEST=1 AI_TEXTBOOK_COUNT=6 flutter test --no-pub test/ai_model_live_test.dart` 2 PASS；实际6教材+6题、内置Answer生成、SQLite持久化、引用回调打开教材104页。此联网测试不等同于原生Reader真机验收。
- /health比例能力=true；错误比例-1/13/bool/string返回400，专用测试设备额度不变。只有一种来源时后端仅1Search已由mock请求计数/故障回归验证，无重新导入任何数据。
- Android APK/macOS App Debug构建通过。平台切换模拟手势不是Android真机；Windows/Linux/iOS/大陆网络与Release保持未验收。
- .local/feedback-*日志/JSON/截图不提交凭据；本次未commit/push/Release，保持此前用户工作区。
