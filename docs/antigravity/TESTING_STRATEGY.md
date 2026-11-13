# 当前测试与验证策略

更新2026-11-13；[历史测试盘点](../archive/development-history/TESTING_STRATEGY.md)。当前357项Flutter通过、3联网默认skip、39后端通过、静态0，Android/macOS Debug构建通过；具体日志在本地.local，[AI记录](../ai-search/VALIDATION.md)含最新线上证据。

## 常规门禁

从仓库根目录执行，先针对变更运行相关测试；新失败/风险才扩大或重复，不为文档移动重复付费生成或处理医学数据。

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
ai_backend/.venv/bin/python -m unittest discover -s ai_backend -p 'test_*.py' -v
```

知识库/Worker更改时再运行其专用套件：scripts/knowledge_base/test_*.py、textbook_worker鉴权/缓存测试与真实产物校验。仅文档整理检查本地链接/路径、Git忽略边界和Release说明读取路径；不重新创建云资源。

## 最新有效回归

- [ai_selection_test.dart](../../test/ai_selection_test.dart)：精确SelectParagraphSelectionEvent段尾断言，修前失败/修后通过；正文选中、鼠标三击和引用点击。
- [ai_search_settings_test.dart](../../test/ai_search_settings_test.dart)：旧设置、总数1–25、比例联动、保存/取消/重开、模型回退、每轮payload与最终引用校正。
- [test_retrieval.py](../../ai_backend/test_retrieval.py) / [test_builtin_answer.py](../../ai_backend/test_builtin_answer.py)：严格类型/越界、来源预算/单源/25条编号和显式列表。
- [ai_model_live_test.dart](../../test/ai_model_live_test.dart)：主动设置AI_MODEL_LIVE_TEST=1、AI_RESULT_COUNT=25、AI_TEXTBOOK_COUNT=17才调用生产生成；最近2 PASS。使用既有专用设备，每次默认扣3App额度，禁止打印secret/重置真实用户计数。

## 历史探针和实机边界

早期v2_2_3_reproduction_test.dart刻意断言旧缺陷，不能当当前CI门禁；后续修复以正常行为测试和[逐项日志](audits/A01_A20_REPAIR_LOG.md)为准。M01/M02/M03切片已有独立回归/生产SQL样本，不能外推其他设备启动耗时。

Widget截图/模拟Android手势、FFI数据库和Debug构建不能替代原生真机、旧SQLite3.22、Windows锁恢复、国内网络、断电和医学人工复核。Googleimport成功还需GET/Search验证新字段；25输入证据不等于模型使用25。赠金/费用通过账单SKU核验，不用净余额不变作免费证据。
