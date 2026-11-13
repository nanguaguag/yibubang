> 历史阶段记录：2026-11-13归档，当前状态见[项目进度](../../CURRENT_STATUS.md)。旧部署/外接模型/未提交描述仅属当时。

# 医学知识库构建与验证记录

日期：2026-11-12；项目工作区基线 `main@d862099`。开始已有首页优化的产品/测试/文档改动，本任务只新增 `scripts/knowledge_base/` 并补充项目知识库，没有提交Git。

## 本地实际数据

| 来源 | 原始题目行数 |
| --- | ---: |
| legacy_combined | 142,071 |
| clinical_final | 57,346 |
| dental_final | 78,310 |
| nursing_final | 69,591 |
| clinial_exam | 18,806 |

按全局question_id合并后 **149,448题**，输出 **149,472块**；无空正文。五份源SQLite均只读打开；`validate.py`重新计算来源SHA256，与构建前记录一致。`user_data.sqlite`未导入。

正文168,458,152字节（约160.65MiB）；Google完整Document JSONL共8个分片、约507.4MiB。完整本地缓存和两个快照占数GiB，包含原始/规范版本及关系，不能拿这个大小作为Google计费索引量。

11,348题有跨来源差异；84题答案字母不同，按对应选项正文比较发现1题仅为选项重排。再把“字母相同、对应选项正文不同”计入，共167题答案内容有差异。所有167题加来源分歧提示；未医学审核，未声称所选来源一定正确。6,923题带配图引用，本轮没有图像OCR。没有找到53本教材PDF，未声称已导入教材。

快照：`artifacts/current/manifest.json`；本次Google上传build ID `afa21b3daf36f0b386056d55`。随后无变化重建build ID `a7e0d3733eab8ad43cdbff15`，全部来源缓存复用，新增/修改0块、删除0块，完整Google导出内容保持。构建第二轮复用全部五个来源的清洗缓存，重新生成规范文档/块并添加167题提示；本地delta167块。Google同步依据云端成功基线，不受这个本地delta数量限制。

## 验证命令与结果

```bash
python3 scripts/knowledge_base/validate.py
python3 -m unittest discover -s scripts/knowledge_base -p 'test_*.py' -v
```

- 真实数据校验：PASS；149,448文档、149,472块、5份来源散列、3个医学内容探针。
- Python集成/回归：14/14通过；只读不改源、共享题合并/版本/来源、用户库拒绝、HTML及医学符号、长文缩短删块、失败保留快照、缓存无变化delta为零、教材页码与空页、同字母答案正文差异、Embedding响应校验、跨多次离线构建的云基线、部分成功计数拒绝ACK、完成任务中断后的恢复、恢复计数不一致拒绝ACK、并发导入锁。
- Embedding API/Qdrant未实际调用或部署；PDF路径使用逐页JSONL夹具验证，未对真实教材版面或扫描OCR作验收。
- 本任务没有修改Flutter；没有把既有Flutter314/314历史基线冒充本轮重跑结果。

## Google实际状态

项目 `yibubang-search`（520065588983）ACTIVE，结算已启用；Discovery Engine/Storage API已启用。实际创建并通过GET复核：

- Data Store：`global/yibubang-medical-v1`，`CONTENT_REQUIRED`，Digital parser，无Layout/OCR自动处理。
- Engine：`global/yibubang-medical-search`，`SEARCH_TIER_STANDARD`，关联上述Data Store，无LLM add-on。
- 私有GCS：`gs://yibubang-search-kb-520065588983`，ASIA-NORTHEAST1；统一bucket权限、禁止公开访问；Search service agent仅授予该bucket objectViewer。
- Schema已通过真实API提交；Google数组注解应在items内，最初放在array层的请求被拒绝，已经修正。

小样本Cloud Storage Document JSONL真实导入：**12/12成功、0失败**。

Operation：`projects/520065588983/locations/global/collections/default_collection/dataStores/yibubang-medical-v1/branches/0/operations/import-documents-15530931304614803546`；2026-11-12 11:13:17 UTC完成。原始回执保存在 `artifacts/cloud/pilot-result.json`。

全量剩余149,460块：**149,460/149,460成功、0失败**。加上pilot12块，总计149,472块。Operation：`projects/520065588983/locations/global/collections/default_collection/dataStores/yibubang-medical-v1/branches/0/operations/import-documents-7963806848407866694`；2026-11-12 11:38:00 UTC创建，12:04:20 UTC完成（约26分钟）。最终回执保存在 `artifacts/cloud/import-result.json`。

真实试导入题干搜索：Top1命中question_id=1435967（肢体能在床面上移动但不能抬起），返回完整正文、B/2级及教材依据、两个来源ID。报告保存在artifacts/cloud/pilot-search.json。

全量完成后真实固定查询 **3/3通过**：

| 查询 | 预期题目ID | 实际排名 |
| --- | --- | ---: |
| 属于营养必需氨基酸的是 | 1637905 | 5 |
| 能够为人CD8 T细胞提呈抗原肽的分子 | 1637906 | 1 |
| 心室肌细胞静息电位和动作电位平台期均发挥作用的离子流 | 1084839 | 1 |

报告：`artifacts/cloud/search-test.json`。这三条只证明简单检索可用，不构成完整医学检索质量benchmark或生成答案医学审核。

自然语言改写查询“哪类HLA分子负责把抗原肽展示给CD8阳性T淋巴细胞？”Top1命中1637906；返回5个相关知识块，全部有完整正文、来源ID和引用标识。报告：`artifacts/cloud/rag-search.json`，含可交给任意LLM的证据提示词；本轮没有付费调用生成模型。

全量完成后再次执行 `cloud.py sync`：**新增/修改0、删除0**，无上传/导入请求。云端成功基线已记录149,472个ID及各自export_hash，独立于上一次本地build。无变化本地build也已验证0新增/修改/删除；五库清洗缓存全部复用。

最终汇总：`artifacts/cloud/final-summary.json`。原先全量处理中首次搜索1/3、第二次2/3的中间报告已被最终结果更新；CD8文档当时确实尚未入库，最终已建立索引并命中。

专项15万日元credit的SKU、有效期和实际抵扣未从结算控制台确认；本轮仅核对公开Search定价和项目结算状态，不声称Cloud Storage/其他模型API全部可抵扣。

## 控制台位置复核（2026-11-12）

用户打开RAG Engine Corpus与Agent Retrieval Collection页面未看到变化；这两者不是本次Search Data Store管理页。重新在线核对Data Store、Engine、原import operation、文档列表及一次CD8自然语言查询，均成功：原全量149460成功、done=true，样例文档有indexTime，查询Top1为1637906。结果保存为 `artifacts/cloud/resource-location-check.json`。

已启用Discovery Engine API，未启用独立的 `vectorsearch.googleapis.com`；Search查询不依赖后者。本次未新建RAG Corpus或Agent Retrieval Collection，未重复上传。Search控制台入口及三个产品的资源映射已补入README。
