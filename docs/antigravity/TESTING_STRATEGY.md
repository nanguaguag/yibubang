# 当前测试与验证策略

更新2026-11-13；[历史测试盘点](../archive/development-history/TESTING_STRATEGY.md)。当前357项Flutter通过、3联网默认skip、39后端通过、静态0，Android/macOS Debug构建通过；具体日志在本地.local，[AI记录](../ai-search/VALIDATION.md)含最新线上证据。

SDK复核：此前本地为Flutter3.44.6/Dart3.12.2，静态0不等同于新CI SDK结果。2026-11-13四平台Actions自动使用3.50.0，在note_service.dart的try中直接返回Future触发1个warning；补await后使用独立干净工作树/Flutter3.50.0/Dart3.14.0实测dart analyze与CI同一flutter analyze --no-fatal-infos均exit0，0 errors/warnings、119个弃用info。CI允许info但保留warning阻断，未改规则或大规模迁移Material导入。

同SDK全量最终357 PASS/3联网默认skip；设置交互fixture增加最近检查时间，避免自动更新的无关网络timeout Timer。定向6 PASS，旧SDK笔记/队列27 PASS。修改后两种分析命令再次通过；这是本机同版复核，远程四平台尚未重跑，历史Debug构建也不是本轮新SDK构建结果。

## 常规门禁

从仓库根目录执行，先针对变更运行相关测试；新失败/风险才扩大或重复，不为文档移动重复付费生成或处理医学数据。

Android构建使用Flutter3.44.6/Dart3.12.2，匹配AGP8.11.1/Gradle8.14/Kotlin2.2.20/Java17；android.yml和release.yml的build-android均固定此版本。其他平台和Release verify仍使用stable。Flutter3.50的Android插件需要AGP>=9.1.1，`--android-skip-build-dependency-validation`不能解决二进制API不匹配。修改Android构建配置须实际运行`flutter build apk --release`；Release分ABI还需`flutter build apk --release --split-per-abi`。保持依赖验证开启，APK成功与正式发布/真机验收分别记录。

上一轮固定SDK实际复核：上述两种构建均exit0，通用80.1MB及3分ABI APK产出，签名/版本/ABI检查通过；dart analyze与CI分析No issues/exit0，全量357 PASS/3联网默认skip。日志.local/android-3.44-*；原Flutter3.50失败复现.local/android-3.50-release-before.log。2b80da1的Android/macOS/Linux远程已成功。

Windows fixture复核：daily_review_service_test准备502题/502复习项改两批事务，使用现有batchSaveItems；首批500条均被排除，真实buildDailySession继续翻页获取q_4。保留默认30秒timeout/并发与501排除规模。3.44/3.50该文件各11 PASS，3.50全量357 PASS/3联网默认skip；同版dart analyze/CI分析均exit0、0 errors/warnings、119 infos。本机macOS，Windows修复后仍须原生CI重跑；日志.local/windows-daily-*。

```sh
dart analyze
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub --reporter expanded
ai_backend/.venv/bin/python -m unittest discover -s ai_backend -p 'test_*.py' -v
```

知识库/Worker更改时再运行其专用套件：scripts/knowledge_base/test_*.py、textbook_worker鉴权/缓存测试与真实产物校验。仅文档整理检查本地链接/路径、Git忽略边界和Release说明读取路径；不重新创建云资源。

## 最新有效回归

- [daily_review_service_test.dart](../../test/daily_review_service_test.dart)：批量fixture、首批500条无可用题仍继续翻页取得q_4；跨库范围、999参数预算、斩题/笔记/超额复习回归共11项。
- [ai_selection_test.dart](../../test/ai_selection_test.dart)：精确SelectParagraphSelectionEvent段尾断言，修前失败/修后通过；正文选中、鼠标三击和引用点击。
- [ai_search_settings_test.dart](../../test/ai_search_settings_test.dart)：旧设置、总数1–25、比例联动、保存/取消/重开、模型回退、每轮payload与最终引用校正。
- [test_retrieval.py](../../ai_backend/test_retrieval.py) / [test_builtin_answer.py](../../ai_backend/test_builtin_answer.py)：严格类型/越界、来源预算/单源/25条编号和显式列表。
- [ai_model_live_test.dart](../../test/ai_model_live_test.dart)：主动设置AI_MODEL_LIVE_TEST=1、AI_RESULT_COUNT=25、AI_TEXTBOOK_COUNT=17才调用生产生成；最近2 PASS。使用既有专用设备，每次默认扣3App额度，禁止打印secret/重置真实用户计数。

## 历史探针和实机边界

早期v2_2_3_reproduction_test.dart刻意断言旧缺陷，不能当当前CI门禁；后续修复以正常行为测试和[逐项日志](audits/A01_A20_REPAIR_LOG.md)为准。M01/M02/M03切片已有独立回归/生产SQL样本，不能外推其他设备启动耗时。

Widget截图/模拟Android手势、FFI数据库和Debug构建不能替代原生真机、旧SQLite3.22、Windows锁恢复、国内网络、断电和医学人工复核。Googleimport成功还需GET/Search验证新字段；25输入证据不等于模型使用25。赠金/费用通过账单SKU核验，不用净余额不变作免费证据。
