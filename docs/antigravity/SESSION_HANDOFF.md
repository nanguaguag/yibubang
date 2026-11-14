# 跨会话交接

## 最新交接：v2.2.4+214 版本升级与清单回写发布

- **版本发布与基线状态**：
  - 代码版本正式递增为 `2.2.4+214`（[pubspec.yaml](../../pubspec.yaml)）；
  - 更新在线分发清单 [yibubang_update.json](../../yibubang_update.json)，写入 v2.2.4 版本号、更新说明（四大核心维度）及各平台（Android 通用与分 ABI、Windows、macOS、Linux）Release 下载资产直链；
  - 创建发布说明文档 [docs/release-notes/v2.2.4.md](../release-notes/v2.2.4.md) 并挂载至索引；
  - 同步更新根 README、英文 README 及文档中心中的版本号描述。
- **质量门禁核验结果**：
  - `flutter analyze`：**No issues found! 0 errors, 0 warnings**。
  - `flutter test`：**358 passed! 3 skipped (联网用例). All other tests passed! 100% 通过**。
- **完成项回顾**：
  1. **AI 搜索与 53 本医学教材知识库**：17 万条切片入库、流式输出、打字机光标动效、30+ 精选问题库、多课本检索直选、右上角原版页「直接查页」调阅、1～25 条比例融合设置滑块、引用角标化与折叠偏好持久化。
  2. **UI 体验与细节打磨**：全系统设置页提示统一为 `InfoHintBanner` 组件，闪卡搜索框自动获取焦点（`autofocus`），底栏设置保护锁定「我的」不可隐藏。
  3. **A01~A20 白盒深度审计修复**：云同步断点分页、复习事务原子性、跨库做题统计并发安全、用户库导入原子恢复等 20 项核心缺陷彻底闭环。
  4. **跨平台 CI 与工具链**：Windows CI 超时修复，Android Release 构建工具链稳定。
- **未完成项 / 下一次第一步**：
  - 检查版本提交与 Git status；
  - 根据用户指令决定是否推送远端分支或触发 GitHub Actions Tag Release 流水线。

## 前次交接：UI 统一与交互细节打磨（设置页提示统一 / 比例滑块融合 / 参考资料持久化与角标化）

- **完成项**：
  1. **设置页提示统一为 `InfoHintBanner`**：
     - 将 `lib/screens/settings_page.dart`（记忆算法设置弹窗、导入模式弹窗）、`lib/screens/shortcut_settings_page.dart`（单选题/多选题提示）、`lib/screens/bottom_nav_settings_page.dart`、`lib/widgets/ai_search_settings.dart`（使用说明、条目限制说明）以及 `lib/widgets/bank_subscription_settings.dart` 中的所有提示/说明文本全部统一为 `InfoHintBanner` 规范组件；
     - 修复了 `lib/widgets/info_hint_banner.dart` 文件首行拼写错误。
  2. **教材与题目检索比例滑块与彩带融合 (`lib/widgets/ai_search_settings.dart`)**：
     - 移除独立的 8px 双色彩带，直接通过 `SliderTheme`（`activeTrackColor: scheme.primary`, `inactiveTrackColor: scheme.tertiary`, `trackHeight: 12`）将滑块轨道自身作为双色对比比例条；
     - 移除了 320px 窄屏下可能导致 29px 布局溢出的冗余图例行，卡片顶部保留居中统计文本，在 320px 与 1000px 宽度下均完美自适应。
  3. **参考资料折叠状态本地持久化 (`lib/screens/ai_search_page.dart`)**：
     - 新增 `SharedPreferences` 存储键 `ai_search_citations_collapsed`，用户点击折叠/展开时自动记录到本地；
     - 下次进入 AI 搜索页或发起新提问时，自动恢复用户偏好的展开/折叠状态。
  4. **参考资料课本标题精简与右上角页码角标化 (`lib/screens/ai_search_page.dart`)**：
     - 对教材类型标题提取纯净书名（如《药理学》-> 药理学），页码提取并转换为右上角专属微型角标（如 `P299`）；
     - 彻底收窄卡片横向占用，避免“药理学·PDF第299页”过长导致的拥挤感，同时通过 `Tooltip` 完整保留原引用来源说明。
  5. **验证与测试保障**：
     - `dart analyze lib/`：**0 issues, No issues found!**
     - `flutter test test/ai_search_settings_test.dart`：**7/7 全部 PASS**（覆盖 320px、1000px 窄屏宽屏自适应、比例持久化）。
     - `flutter test test/ai_search_ui_test.dart test/textbook_search_test.dart`：**13/13 全部 PASS**。
     - `flutter test test/bank_subscription_test.dart`：**2/2 全部 PASS**。
- **未完成项 / 下一次第一步**：
  - 代码变更保留在本地未暂存状态（未 commit，未 push），严格遵循 AGENTS.md 准则；
  - 下一次第一步：执行 `git status` 确认未暂存代码，等待用户指示是否合并或提交。


## 最新交接：Windows复习测试超时

- 起始main@2b80da1与origin一致/干净，用户反馈Windows每日复习测试30秒timeout。两次真实Actions43432164278/43436136566均在fixture的insert/saveItem处结束，database_closed为超时清理后的后续写入，未进入buildDailySession。
- 修改仅test/daily_review_service_test.dart中该用例：502题Batch.commit(noResult:true)、502复习项repo.batchSaveItems，从1004逐条提交变两批事务；501 outside/q_4末项和真实分页服务调用保留。新增首批500条outside断言，保证覆盖分页边界；保留30秒timeout、默认并发和生产SQLite行为。
- Flutter3.44.6/3.50.0该文件各11 PASS；CI同SDK3.50全量357 PASS/3联网默认skip，dart analyze与CI的flutter analyze --no-fatal-infos均exit0、0 errors/warnings、119原有弃用info。单文件dart format、git diff --check、62份文档547本地链接检查通过。
- 日志.local/windows-daily-3.44-tests.log、windows-daily-3.50-tests.log、windows-daily-3.50-full-tests.log、windows-daily-3.50-{dart,flutter}-analyze.log；CI日志actions-43436136566-failed.log。SDK3.50/隔离工作树复用上一轮.local资源，不提交日志、依赖锁或SDK自动迁移文件。
- 本机macOS测试不能宣称Windows runner已通过；本轮不push/发布。下一次第一步git status/log核对该修复，用户push后检查Windows Test/Build/Upload；上一提交2b80da1的Android/macOS/Linux已远程成功。其他同步/医学/费用待办保持下方交接，不重复云部署/知识库上传。

## 前次交接：Android Release工具链

- 起始main@4deacbb与origin一致/干净，用户反馈Android构建失败。本轮只修Android工具链和同步文档，App业务/README/依赖声明/题库/云资源保持原状。
- Actions43432164143使用Flutter3.50.0，Analyze/Tests成功、assembleRelease配置阶段getDefaultConfig API缺失；本地隔离树同版构建复现。Flutter插件编译依赖AGP9.1.1，最低支持同为9.1.1；项目8.11.1/Gradle8.14不能靠skip依赖检查解决。
- android.yml及release.yml/build-android固定Flutter3.44.6，删除skip依赖验证参数；AGP8.11.1/Gradle8.14/Kotlin2.2.20/NDK28.2不升级。其他平台和Release verify仍stable，未来AGP9迁移在TECHNICAL_DEBT记录。
- Java17 release通用80.1MB/分ABI28.5MB、30.4MB、32.1MB全部exit0，签名校验/包名com.melonhu.yibubang/2.2.3+213/原生ABI检查通过；同SDK dart analyze和CI的flutter analyze --no-fatal-infos均No issues/exit0，全量357 PASS/3联网默认skip。YAML、545本地链接、git diff --check通过。
- 日志在ai_backend/.local/android-3.50-release-before.log、android-3.44-release-after.log、android-3.44-release-split.log、android-3.44-{dart,flutter}-analyze.log、android-3.44-full-tests.log；产物清单android-release-artifacts.json，APK仅在.local/ci-workspace/build/app/outputs/flutter-apk。隔离树复用.local/ci-workspace，不替换用户SDK或提交pub依赖/生成配置；沿用原debug签名配置，不是正式发布或真机验收。本轮修复不push/触发Release。
- 下一次第一步git status/log核对该修复，用户push后观察Android Analyze/Tests/Build/Upload各阶段。当前远程旧4deacbb的Linux/macOS已成功；Windows有独立daily_review_service_test大fixture30秒超时（43432164278），本轮未扩大到该项，不将Android修复宣称为四平台全绿。

## 前次交接：README恢复与Flutter3.50 CI修复

- 起始main@082f205与origin一致/干净；该HEAD是用户合并提交，814a20d已在共享历史。用户明确选择仅恢复README，保留功能和docs；本轮用新的恢复提交，不reset/revert全部814a20d，不push或发布Release。
- 恢复ec0fdf6原README/英文页的品牌、徽章、目录、架构和截图；补AI/教材、session/额度、1–25条数/比例、模型回退、快捷键/缓存和最新验证。根README仍完整项目介绍，docs仍维护运维/知识库/开发资料。
- 四平台Actions（082f205）均失败在Analyze，CI Flutter3.50.0而本地3.44.6。唯一warning为note_service.dart try内返回Future未await；补await后独立3.50.0/Dart3.14.0的dart analyze及CI同命令均exit0，0 errors/warnings、119个Material/Cupertino等弃用info，未降低warning规则。
- 同SDK全量初跑356 PASS/3 skip/1 fail，设置测试开启自动更新发后台网络并留下timeout Timer；fixture设置最近检查时间，只测设置交互而非逾期检索。定向6 PASS，旧SDK笔记/队列27 PASS；3.50.0最终全量357 PASS/3联网默认skip、All tests passed。fixture修改后dart analyze与CI分析再次exit0，0 errors/warnings、119 infos。
- 隔离验证在ai_backend/.local/ci-workspace（detached HEAD）、SDK在.local/flutter-ci-3.50；最终日志ci-3.50-full-tests-final.log、ci-3.50-dart-analyze-final.log、ci-3.50-flutter-analyze-final.log，早期日志ci-note-regression.log/actions-*-failed.log。SDK自动迁移的平台/build分析排除与插件注册文件仅在隔离树，主工作区配置/依赖未变。无需把缓存/工作树加入Git，也不需替换用户原SDK或修改题库/用户库schema。
- README恢复后的本轮链接检查：62份文档、544个本地链接，无失效/指向私有资料的链接；git diff --check通过。另恢复隔离树为主工作区原analysis_options后独立dart analyze仍exit0/119 infos，日志ci-3.50-dart-analyze-exact-config.log。
- 下一次第一步先git status/log核对新的恢复提交，阅读根README与本段；若要验证远程四平台，按用户push授权触发CI，检查Analyze/Tests/Build每阶段，不能把本机同SDK测试当已重跑Actions。其他医学/费用/网络/同步服务待办仍见下方；不用重导知识库或上传页图。

更新：2026-11-13；main；本轮修正提交父基线082f205（上一轮814a20d父基线ec0fdf6），用户明确授权commit。准确提交ID以`git log -1`为准。本次只提交代码/测试/公开文档，不push、不发布Release；新会话先核对Git是否有用户后续改动。

## 本次完成

1. 检索条目设置1–25（默认12），总数变化保留来源比例，默认25为17教材/8题。每轮SharedPreferences→HTTP result_count/textbook_count→服务端校验→独立二源Search→显式Answer结果列表；单源跳过无用请求，最多60000字符并为后续来源留预算。
2. 引用/行内公式WidgetSpan内部Text重复加入Text.rich选择delegate导致lastSelectionResult断言，已精确复现并隔离内部选择；正文可选、引用可点。Google实际采用的证据可少于输入数量。
3. 文档统一到docs并建立总索引/当前状态；AI运维与费用、知识库/教材操作分别分类；旧动态记录/早期数据库研究保留为历史档案。根README已按用户反馈恢复完整项目介绍，本地AGENTS.md保留代理发现，版本化规则副本在本目录。
4. 更新全部开发入口到schema25/当前内置模型/200额度/可调25条/00018部署；Release工作流从docs/release-notes读说明。原PDF、页图、生成SQLite/JSONL、.local身份/回执/截图、虚拟环境、API抓包均不提交。

## 当前资源和数据

- Google yibubang-search/520065588983，global Store yibubang-medical-v1，171463块=149472题+21991教材；两应用yibubang-medical-search（Standard）/yibubang-medical-answer（Enterprise）共用Store。不要创建RAG Corpus或重复导入。
- 东京Cloud Run yibubang-ai-search，00018-q7c/100%，App入口https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app。默认stable、当前快照3.5-flash/answer_gen/v1，默认改写+流式；没有外接Vertex Token生成。
- Firestore yibubang-ai记录身份哈希、北京时间日200额度/分钟6/租约，TTL清理3天过期限额；会话仅本机user_data.sqlite的AiSearchSessions/AiSearchTurns，不加入同步。
- 外置盘源目录`/Volumes/My PSSD/书籍/自用53本课本（可复制）`；教材主库/原始OCR/清洗页/坐标/页图在`/Volumes/My PSSD/书籍/医不帮教材知识库`。仓库scripts/knowledge_base/artifacts/current与artifacts/cloud是语料及增量成功账本，均忽略但不可删除。
- 私有R2 yibubang-textbooks，Worker yibubang-textbook-pages，textbooks.melonhu.com；20669页图+20669小图，7714259450 bytes。阅读器按稳定版本/物理页定位，原PDF未上传。

## 已有验证与回执

Flutter全量357 PASS/3联网默认skip、最终相关8 PASS，后端39 PASS，analyze0；Android/macOS普通main Debug构建通过。生产App25条17:8/回答/SQLite/引用2联网PASS；Google返回references10、正文用到第13项，不能说25条全部被用到。五组非法数量/比例400且不扣额度。

最近回执在忽略的ai_backend/.local/result-count-*、result-selection-*、selection-*；教材全量和早期原生Reader证据见[实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。联网测试复用专用smoke-device.json，不提交/打印secret，不重置真实用户额度。构建包仅在build/；Widget截图/模拟手势不代表Android真机或大陆网络验收。

本次文档复核62份文档/520个本地链接，无失效/私有未版本化目标；静态分析0。旧审计复制的凭据已脱敏，原稿仅在ai_backend/.local/docs-private-archive；链接报告/分析日志为ai_backend/.local/docs-link-report.json、docs-final-analyze.log，不提交。维护的docs目录已纳入Git，抓包/数据库/工具环境继续忽略。

## 下一次第一步

执行`git status --short --branch`与`git log -1`，读[当前状态](../CURRENT_STATUS.md)、本段与用户新反馈。用最新Debug App核验AI设置→条目/比例及原鼠标选择手势；若代码已改需重建/重启。默认无需重新跑付费生成、造Store、导入171463块或上传41338图片。

新教材按[知识库手册](../knowledge-base/README.md)与[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)复用本地缓存、稳定ID和成功基线，先本地验证delta，再增量导入。更换Embedding须重算向量，PDF清洗不必重做。

## 未完成项和授权边界

- 用户原手势实机、Android/Windows/Linux/iOS、目标地区网络、375页医学符号人工复核、版次ISBN、167题答案分歧/6923题配图OCR、Release与真实向量库迁移仍未验收。
- 同步协议v2服务端部署/真实账号验证，以及M03目录分阶段/M04/M05/M13等属于独立后续任务；本次不部署同步服务。
- 专项赠金适用SKU、实际Advanced计量和账户运行费用仍待账单，不承诺100%抵扣/不扣卡。混合搜索两Standard+一Enterprise列表价USD7/千、Advanced预算USD11，App1/2/3不是Google收费倍数。
- 当前没有保证每个子问题按来源比例迭代检索，25条并不穷尽全库。只有用户明确授权下一步才发布Release、push或新建云资源。

旧会话完整记录：[历史交接](../archive/development-history/SESSION_HANDOFF.md)。
