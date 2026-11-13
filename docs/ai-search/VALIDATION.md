# 当前AI搜索验收

更新2026-11-13；Cloud Run东京00018-q7c/100%。[历史分阶段验收](../archive/ai-search/VALIDATION.md)保留旧Gemini/100额度/12条/旧修订记录；当前以下状态优先。

## 最新验证

- Android工具链修复本机验收：固定Flutter3.44.6/Java17/AGP8.11.1/Gradle8.14，开启依赖检查；release通用80.1MB及3分ABI28.5MB/30.4MB/32.1MB均构建成功，包名/2.2.3+213/ABI与签名校验通过。dart analyze与CI分析No issues，全量357 PASS/3联网默认skip；日志.local/android-3.44-*，新修复尚未push或正式发布。旧4deacbb的Linux/macOS远程成功，Windows独立测试超时待处理。
- 2026-11-13 CI同版复核：Flutter3.50.0/Dart3.14.0全量357 PASS/3联网默认skip，dart analyze与CI的flutter analyze --no-fatal-infos均exit0，0 errors/warnings、119弃用info。四平台原Actions停在Analyze；补笔记try内返回await、设置fixture避免无关自动检查网络后本机通过，远程Actions尚未重跑。最终日志在.local/ci-3.50-*-final.log。
- 前一阶段Flutter3.44.6：全量357 PASS/3联网默认skip；最终选择/设置8 PASS；后端39 PASS，flutter analyze0；Android APK/macOS普通main Debug构建通过。本轮未重复后端/付费生成或新SDK原生构建。
- 生产App `AI_MODEL_LIVE_TEST=1 AI_RESULT_COUNT=25 AI_TEXTBOOK_COUNT=17 flutter test --no-pub test/ai_model_live_test.dart` 2 PASS：17教材+8题、内置gemini-3.5-flash/answer_gen/v1回答成功、SQLite保存、AiSearchPage引用回调打开教材。
- 服务端SUCCEEDED/references10/streaming=true/quota_cost3；正文含第13项。25卡片是提供的证据，不能证明模型全部使用25；实际引用由内置生成决定。
- /health default_result_count12/max25；0/26/bool/string/教材超total五组400，专用设备额度不变。校验在扣额前完成。
- 精确段尾SelectParagraphSelectionEvent在修前触发lastSelectionResult断言；引用/行内公式内部SelectionContainer.disabled后同事件、鼠标三击、正文选择、引用点击PASS。
- 320/1000px真实字体设置与条数弹窗截图人工查看；旧设置12/8:4、总数保留比例、保存/取消/重开、每轮payload、单源/预算/25编号与显式Answer列表均有回归。

回执/日志：ai_backend/.local/result-count-app-live.json、result-count-online-validation.json、result-count-online-answer.json、result-count-*、result-selection-*、selection-*与screenshots，均忽略。smoke-device身份保密，不重置真实用户计数。

## 已验证的前序能力

两源新主题不污染/慢阻肺定义、默认高级增量与最终不重复、UTF-8引用校正、模型官网故障回快照、200额度三模式扣1/2/3、分钟/并发/重放/错误凭据拒绝、R2签名和缩略图缓存、原生macOS Reader放大/翻页/跳页/离线缓存曾验证。详细阶段证据见历史验收与[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。

## 本轮文档整理验证

文档统一目录、旧记录归档，检查Markdown/HTML本地链接、Git排除私有资料及Release读取路径；静态分析复核。产品源码保持上一轮已测版本，未重复付费生成/重导数据。提交包含本轮检索/选择修复和文档；不push/发布Release。

62份文档/520个本地链接通过，无失效或私有未版本化目标；最终静态分析0。旧审计中凭据示例已脱敏；文档校验报告/分析日志保存在忽略的ai_backend/.local/docs-*。

## 尚未验收

用户原手势真机/Android/Windows/Linux/iOS/目标地区网络、Release、新版原生整体UI、375页医学符号/公式和版次ISBN；专项赠金/Advanced实际SKU账单、真实向量迁移。Widget截图/模拟触摸/FFI不能替代这些验证。[交接](../antigravity/SESSION_HANDOFF.md) · [限制与费用](RETRIEVAL_LIMITS.md)。
