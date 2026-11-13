# 当前开发状态

## 2026-11-13 Windows复习测试超时修复

起始main@2b80da1与origin一致/干净。Windows Actions43432164278与43436136566均在daily_review_service_test的数据准备阶段超30秒：502题+502复习项逐条自动提交，timeout后tearDown关闭库，未完成insert报database_closed；尚未调用buildDailySession。

仅该用例改为题目Batch和现有repo.batchSaveItems两批事务；保留501条不在覆盖范围的到期题与最后q_4，增加首批500条均为outside的断言，继续通过真实服务验证翻页找到q_4。保留默认30秒门禁，不改生产服务/SQLite配置/CI并发或SDK。

Flutter3.44.6与Windows CI同版3.50.0的该文件均11 PASS；3.50全量357 PASS/3联网默认skip。dart analyze与CI分析均exit0、0 errors/warnings、119弃用info，单文件格式/diff及62份文档547链接通过。本机为macOS，Windows runner修复后仍需push重跑；上一提交2b80da1的Android/macOS/Linux远程已成功。

## 2026-11-13 Android Release工具链修复

起始main@4deacbb/工作区干净。该提交的Android Actions已通过Analyze/Tests，但release构建报ApplicationExtension.getDefaultConfig不存在；Flutter3.50.0要求AGP>=9.1.1，项目AGP8.11.1/Gradle8.14不兼容，本机同SDK复现原报错。

Android日常与Release build-android固定Flutter3.44.6，保留现有Gradle/AGP/Kotlin配置，移除跳过依赖检查参数。隔离工作树Java17实际release通用80.1MB、armeabi-v7a28.5MB、arm64-v8a30.4MB、x86_64 32.1MB均exit0；APK签名/包名/版本/ABI检查通过。同SDK dart analyze和CI分析均No issues/exit0，全量357 PASS/3联网默认skip。YAML解析、本地545链接与diff检查通过。

其他平台和Release verify继续stable。新修复尚未推送或触发Release，未改App业务代码/README或云资源；旧4deacbb的Linux/macOS已成功，Windows独立测试timeout待处理，见问题账本。

## 2026-11-13 README恢复与新版CI分析修复

用户选择仅撤销814a20d对README的精简改写，保留1–25检索/选择修复与docs整理。当前父基线082f205（用户已合并/同步远端），不reset或改写共享历史；恢复ec0fdf6的品牌页/徽章/章节/截图并补最新App功能，英文同步恢复。

四平台Actions在Analyze阶段因Flutter自动更新至3.50.0而失败，本地此前3.44.6静态0不能代替该SDK。修复note_service.syncNotesForQuestion中try内返回Future缺await；3.50.0/Dart3.14.0独立工作树实际dart analyze与CI的flutter analyze --no-fatal-infos均exit0、0 errors/warnings、119弃用info。新版全量首次暴露设置测试触发后台网络的Timer，fixture补最近检查时间，避免无关网络；定向6 PASS，旧SDK笔记/队列27 PASS。同版SDK最终全量357 PASS/3联网默认skip，修改后两种分析命令再次exit0。

不升级现有本机SDK、不修改CI warning阻断规则、不迁移全项目Material导入；3.50源码/缓存/隔离工作树/日志仅在ai_backend/.local。没有云重新部署或数据上传，远程Actions尚未重新运行。

恢复后62份文档/544个本地链接检查通过，git diff --check通过；用原analysis_options的同版dart analyze仍exit0/119 infos。主工作区未引入SDK自动迁移或依赖配置变化。

更新：2026-11-13；main；本轮修正提交父基线082f205，上一轮814a20d父基线ec0fdf6。用户已授权恢复README并保留功能修复和docs整理；本次不push或发布Release。准确HEAD以`git log -1`为准。

[当前进度](../CURRENT_STATUS.md)是完整状态入口，[交接](SESSION_HANDOFF.md)列下一步。此前各阶段记录已完整保留在[历史状态](../archive/development-history/DEVELOPMENT_STATUS.md)，其中“未提交/未实现/旧模型”等描述仅属于对应阶段。

## 已完成

- A01–A20源码修复独立提交；M01精准刷新、M02投影真实路径、M03隐藏Tab延迟挂载切片完成，后续维护范围没有顺手扩大。
- 149472题块+21991教材块已导入原Google Store；53本/20669页复用OCR，原PDF留本地；全部页图/小图在私有R2，自定义域和鉴权缓存完成。
- 独立Cloud Run内置Answer/streamAnswer、模型本机目录回退、200额度/1–2–3规则、本地session、教材引用/缩放/缓存/键盘和默认Tab完成。
- 最新证据数量可调1–25/默认12，来源比例随总数变化；后台二源独立检索、严格扣额前校验、预算保留。25条默认17教材/8题；增加条数不保证模型全部使用。
- lastSelectionResult段落选择断言精确复现并修复，正文选择/引用点击仍可用。
- 项目说明移至docs/project、AI手册至docs/ai-search、数据手册至docs/knowledge-base；旧入口原文归档，链接与Release说明路径更新；文档纳入Git，私有本地资料继续忽略。

## 验证与部署

当前Cloud Run00018-q7c/100%。Flutter357 PASS/3联网默认skip、最终相关8 PASS、后端39 PASS、analyze0、Android/macOS Debug构建通过；App真实25条17:8→内置回答→SQLite→引用2联网PASS，非法输入400且额度不变。[详细记录](../ai-search/VALIDATION.md)。文档整理后再检查链接、静态分析和Git范围，不无理由重复付费生成或数据上传。

文档整理复核：62份Markdown/HTML引用共520个本地链接通过，无失效或指向未版本化私有文件的链接；静态分析0。旧审计凭据示例已脱敏；最终暂存范围只含本轮源码/测试、文档及必要的忽略/Release说明路径调整。

## 独立待完成

同步服务协议v2/schema发布与真实账号验收；M03目录阶段化、M04/M05、M13算法入口等维护；375页医学符号/公式与版次ISBN、167题答案冲突；Android/Windows/Linux/iOS实机、目标地区网络、Release发布；专项赠金SKU/Advanced实际账单；真正Embedding/向量库迁移。[问题账本](KNOWN_ISSUES.md)和[技术债](TECHNICAL_DEBT.md)保留边界。
