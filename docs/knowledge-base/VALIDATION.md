# 知识库当前验证

更新2026-11-13；[最初题库导入验证](../archive/knowledge-base/VALIDATION.md)保留原149472块/Standard/无生成阶段证据。

- 五份只读内容源149448唯一题、149472题块；53本20669页、21991教材块。Google原yibubang-medical-v1总171463块，原题保留、删除0；成功ID/export_hash账本匹配。
- 题库12块pilot、149460全量成功；CD8等固定医学检索及无变化增量0上传验证通过。教材全量导入和needs_review407条实际GET/Search核验见[实施](TEXTBOOK_EXECUTION.md)。
- 原PDF保留本地，2991页OCR双层去重，36页无索引文字但所有页均有图片；375页符号/公式候选及版次ISBN未人工验收。
- 20669页WebP/20669小图全量格式/manifest/本地SHA/R2成功回执匹配；页图7336669280 bytes、小图377590170 bytes，合计7714259450。私有签名、版本化路径和Worker鉴权后缓存通过。
- 知识库Python18项在前次提交前通过，后端当前39项/Flutter357项；本次仅文档整理和原已测检索/选择修复，没有重处理/上传数据。
- 生产App最新25条17教材+8题、内置回答/本地保存/引用通过；原生macOS页图缩放/翻页/跳页/离线缓存曾验收，其他真机与目标网络仍待确认。

产物/凭据在scripts/knowledge_base/artifacts、ai_backend/.local及外置盘；均不加入Git。来源散列/页图成功账本须保留，增量续传依赖它们。167题答案分歧、6923题配图未OCR、实际Embedding/Qdrant迁移与赠金SKU抵扣未验收。

[手册](README.md) · [教材实施](TEXTBOOK_EXECUTION.md) · [当前项目进度](../CURRENT_STATUS.md) · [AI验收](../ai-search/VALIDATION.md)。
