# 当前数据库契约

更新2026-11-13。用户库schema25，题库schema1；准确DDL由[database_helper.dart](../../lib/db/database_helper.dart)及各install方法定义。[旧详细设计](../archive/development-history/database_current.md)记录v13阶段，不再作为当前完整字段清单。

## 物理隔离和版本

正式QuestionBank/<bank_id>/<bank_id>.sqlite只读；Question全局单列id；跨库共享用户状态，所有答题/收藏/Activities/笔记写user_data.sqlite。聚合采用[data_transfer.dart](../../lib/db/data_transfer.dart)的ATTACH规范。制作/更新只写独立暂存文件，不向正式题库执行DDL/DML。

schema25在v24基础上仅增加AI会话表；本轮检索条目/选择修复没有schema变化。此前CloudOutbox、DurableSyncQueue、NoteSyncStore、QuestionProjection、ReviewEvents的升级顺序/索引以各install与_onUpgrade为准，不复制过期字段清单。

## 本地AI表

DDL来源：[AiSearchStore.install](../../lib/db/ai_search_store.dart)。

| 表 | 主键/字段与约束 |
| --- | --- |
| AiSearchSessions | id TEXT PRIMARY KEY；title TEXT NOT NULL；created_at/updated_at INTEGER NOT NULL；updated_at索引用于历史排序 |
| AiSearchTurns | id TEXT PRIMARY KEY；session_id TEXT NOT NULL；position INTEGER NOT NULL；payload TEXT NOT NULL；session_id外键ON DELETE CASCADE；UNIQUE(session_id,position) |

payload为AiTurn JSON（问题/回答/状态/模型/引用等）。save回合与session标题/更新时间在同事务；truncate删除某位置以后分支；delete事务删除会话/回合；读取pending/streaming标interrupted。整库本地备份包含这两表，但现有跨设备同步不含AI会话。

## 其他存储不混用

- SharedPreferences：AI模型/改写/流式/result_count/textbook_count与导航等本机设置，按每轮重读；不记录可信服务端余额。
- Firestore yibubang-ai：身份哈希、服务端限额/租约；TTL仅过期限额；不保存云端会话/页图。
- 本地知识库corpus.sqlite及外置盘textbooks.sqlite：来源内容、原始OCR、清洗块/版本/坐标/页号；独立于个人用户库。
- R2：独立WebP/缩略图对象；Google：清洗检索文本/来源，不存原PDF或页图BLOB。

数据/续传路径见[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md)。历史生产工具docs/yikaobang/data包含本地研究数据，继续忽略；不得将user_data.sqlite、账号配置或个人笔记作为医学语料。
