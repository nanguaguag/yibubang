# 医不帮题库制作规范

> 2026-11-13整理：本文保留对应专项的详细规范/历史基线。当前项目schema25、内置AI与最新部署/验证以[当前进度](../CURRENT_STATUS.md)和[交接](SESSION_HANDOFF.md)为准；未经重新核查不套用历史行号。

> 文档版本：1.1；初始核查基线：`324b3a3`；实施更新：2026-11-07。
> 当前已实现订阅、导入合并/覆盖、完整树创建、实时进度、详情时间轴和导出。第 1.1 节保留初始基线审计，第 1.3、5 节说明本轮实际实现；原生文件选择器与真实账号抓取仍待实机验收。

## 1. 现有同步实现与作用范围

### 1.1 初始基线客户端调用链（324b3a3，历史记录）

课程页 `CourseSyncButtons` → `CourseSyncActions.run` → 从 `activeBankId` 查出当前题库 → 调用下列服务 → `QuestionBankRepository.importFile` → 校验暂存文件、备份和替换正式题库、登记用户库 `QuestionBank`。操作结束由课程按钮的 `onCompleted` 刷新课程树。

| 项目 | 智能增量 `YkbBankSmartSyncService.run` | 全量重建 `YkbBankSyncService.syncBank` |
| :--- | :--- | :--- |
| 范围 | 可显式传入 `bank`；省略则解析当前题库；要求已安装 | 必须显式传入一个 `bank` |
| 现有 UI | 课程页传入当前题库；启动后台省略 `bank`，也只处理当前题库 | 课程页传入当前题库，有确认弹窗 |
| 远端目录 | `subjectV2` 找到根，再请求直接子入口的 `chapter` 目录 | 同样找到根，再请求直接子入口的 `chapter` 目录 |
| 选章策略 | 对比章节数量、更新时间和已保存状态；必要时拉取题目并比对 SHA-256 | 遍历所收集章节并拉取所有题目 |
| 章节漂移 | 已保存映射、同 ID 与标题、归一化标题、同科目标题相似度、题目 ID 重合度 | 无智能映射，使用远端目录重新建立关系 |
| 内容更新 | 保留本地额外题目与关系；新增远端题，更新同 ID 的变更内容 | 新建临时 SQLite，以新文件替换旧包；旧包独有内容不保留 |
| 文件写入 | 复制正式只读库为独立 `.delta-*.sqlite` 暂存文件，在副本内应用增量 | 在系统临时目录新建 `ykb_sync_*.sqlite` |
| 请求与续传 | 默认每批 12 章，课程页手动指定 16 章；每轮预算 28 次请求，目录也占预算；目录/队列缓存 24 小时 | 逐章拉取；非 203 错误重试一次后仍失败则跳过；无持久化续传队列 |
| 失败处理 | 题目列表数量必须匹配章节声明；失败留队重试，203 权限不足按周复查，失败退避 | 203 或重试失败可跳过章节；当前不能据成功安装推断全科完整 |
| 状态存放 | 用户库 `BankSyncState`、`ChapterSyncState`，成功安装后登记章节状态 | 无对应持久化构建任务状态 |
| 版本 | `基础版本+delta.秒时间戳`，基础解析失败使用 `3.0.0` | `sync-毫秒时间戳` |
| 进度 | 返回批次结果摘要；尚无实时题量回调 | 阶段文案与章节 `done/total` 回调；UI 使用不定进度条 |
| 用户数据 | 不覆盖用户作答、笔记、收藏、斩题和流水 | 不覆盖用户库；但当前题目字段转换仍携带 API 的 `user_answer` / `cut_question` |

启动 `_silentBankSmartSync` 先等待 15～34 秒；有剩余章节或错误时约四分钟后再次调度。每轮重新解析当前题库，切换题库后不会固定续传此前题库。手动智能同步只执行一批，不保证一次点击完成全部队列。

**结论：现有入口都针对当前使用的一个题库，服务本身并非只能处理当前题库；目前也没有遍历所有已安装题库同步的入口。** 两个服务都可复用请求与安装能力，但不能直接作为任意深度身份树的完整构建器。

### 1.2 与 `docs/yikaobang/` 生产工具比较

本轮只比较仓库内可读的 Python 源码副本，没有访问 private 仓库的远端 HEAD，因此不声明与 private 项目最新版一致。

1. `spider.py::save_all_identities` 递归遍历身份树，在叶入口请求目录，按代码中的允许列表抓取章节题目并存为 JSON；其 `save_question_data` 按课程下的直接章节取题。
2. `save_data.py::insert_questions_batch` 将 JSON 导入合并库，题目与关系采用 `INSERT OR IGNORE`；重复 ID 的旧内容不会像智能同步那样按哈希更新。关系保留题目的身份归属；旧合并库有计数触发器。
3. `split_question_banks.py::_copy_bank` 按根 identity 的完整后代集合筛选 `IdentityQuestion`，复制去重题目、课程、章节与身份到独立新库；重新计算关系计数、检查外键与完整性，生成 manifest。每次重建输出文件，默认版本固定 `1.0.0`。

两侧使用同类远端接口、单列题目主键与 schema v1 关系结构，但抓取、去重、映射、失败恢复和版本策略不同。Python 副本使用旧客户端协议；其 `encrypt.py::DES_decode` 使用 ASCII IV，Dart `YkbCrypto.decrypt` 使用二进制 IV，JSON 包装/解析也不同，不能将两套解密实现认定为相同或互换。

### 1.3 当前实现与基线的差异（2026-11-07）

- `BankCreationService.build` 递归身份和课程目录，按每个叶入口抓题；同题原始 ID 去重，真实关系保留叶归属。`YkbBankSyncService.syncBank` 现在复用此构建器。权限不足、失败、题量不完整停止安装；目录题量与最终去重题量分别计数，时间统一为秒。
- 既有题库继续使用 `YkbBankSmartSyncService.run` 的章节映射/哈希/队列算法；`custom_*` 与本轮完整重建产物（`BankMeta.source = ykb-created`）采用完整快照检查后增量合并。本分支保留本地额外内容，有变化才增加 PATCH；尚无深层章节断点缓存，成功检查后六小时冷却，失败沿用退避。
- 课程页手动同步仍只处理当前库；服务允许显式指定目标；管理页首次创建独立 ID，不切换当前库。订阅自动检查只更新已安装、允许包更新的订阅题库，与 API 内容同步开关独立。
- `QuestionBankRepository.importFile` 支持合并/覆盖选择；题库登记、`BankHistory` 和原生 ATTACH 对错重算处于同一个用户库事务；异常恢复旧文件。根以校验后文件为准，远程目录不会覆盖已安装根。
- `BankProgressView` 展示阶段、章节、章数与抓题数/目录题数。创建页固定底部进度和取消区；进度中的目录题数可能包含跨章重复，最终题量使用 SQL 实数。
- 管理页详情展示身份→课程→章节及时间轴，实际新增 ID 用 ATTACH 查询；SQLite/ZIP 导出清理账号字段并 VACUUM，ZIP 含单个 SQLite 和 manifest。移动端使用系统文档保存 API，桌面端选择路径后写入，禁止覆盖正式数据库或链接别名。

当前源码入口（不依赖会随开发变动的历史行号）：

- `lib/screens/question_bank_page.dart` — 管理入口、数字圆角标签、导入选择。
- `lib/services/bank_creation_service.dart` — `BankIdentityNode`、`BankCreationService.identities/build/create`。
- `lib/services/ykb_bank_sync_service.dart` — `syncBank`、`createSchema`、`fetchChapterQuestionsResult`、`questionRow`。
- `lib/services/ykb_bank_smart_sync_service.dart` — `run`、`_fetchManifest`、`_applyToStaging`。
- `lib/services/question_bank_file_service.dart` — `merge`、`hasChanges`、`countNewQuestions`、`nextVersion`。
- `lib/services/bank_subscription_service.dart` — `save/refresh/start/parseManifest`。
- `lib/screens/bank_detail_page.dart`、`lib/services/bank_export_service.dart` — 详情、履历、安全导出。
- `lib/db/data_transfer.dart` — `rebuildQuestionCount/rebuildAttachedQuestionCount`。
- Python 副本：`docs/yikaobang/src/spider.py`、`save_data.py`、`split_question_banks.py`（未访问 private 远端）。

## 2. 存储、根身份与 ID 契约

- 正式题库位于通过 `p.join(rootPath, bankId, '$bankId.sqlite')` 构造的路径，始终以 `readOnly: true` 打开。制作/同步只写独立暂存产物，关闭写连接、校验后通过既有安装流程替换；严禁向正式文件执行 SQL 写入。
- 用户答案、收藏、斩题、用时、流水和笔记只存 `user_data.sqlite`。共享题库不打包该文件、账号凭据、离线队列或设备配置。
- `bank_id` 稳定且匹配 `^[A-Za-z0-9_-]+$`，文件版本变化不改变 ID；同一根可有多个不同题库 ID。自建题库不得复用内置题库 ID。
- `Question.id` 始终是单列主键，保留医考帮原始全局题目 ID，转换为字符串。同题跨库复用相同 ID，不能前缀拼接 `bank_id` 或按章节重新编号。本阶段自建指从该来源制作题库；人工题目、多来源 ID 分配另行设计。
- 每个 schema v1 独立库必须且只能有一个 `Identity.parent_id = '-1'` 的根。其 ID 是题库目录/manifest 的 `identity_id`。其余身份父节点须存在，无环，全部可从根到达；原始上级在制作时裁剪，选定根改为 `-1`。
- 保留根以下身份树及真实的叶入口归属，不能把大一～大四的所有课程强制挂到根。`IdentityQuestion` 才是权威归属；`Question.identity_id/chapter_id/chapter_parent_id` 仅为兼容提示，同题可有多组关系。
- 若用户选择多个互不隶属的根，每个根生成一个独立题库。单根内可选多个后代，去除父子重叠选择；完整根制作默认覆盖全部可用后代。不引入虚假总根来绕过现有单根校验。
- 根 identity 名称必须来自实际身份树/文件，不能仅凭数字或题库显示名推断。当前内置映射为口腔期末 `30401`、临床期末 `20101`、护理期末 `11070`；示例中的其他身份需要实际目录确认。
- 跨题库与用户库对错重算必须复用 `rebuildQuestionCount(bankId: ...)` 的 SQLite `ATTACH DATABASE` / SQL 聚合 / `DETACH`，不得以 Dart 多重循环替代。

## 3. Schema v1 的规范 DDL

以下是新产物的规范结构。已有 schema v1 兼容库可有额外列、空 `Comment` 表；客户端现有校验只要求八张核心表，不会检查全部列、索引及身份树连通性，所以制作端必须执行本文的更完整验收。

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE BankMeta (
    bank_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    generated_at INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT '',
    question_count INTEGER NOT NULL DEFAULT 0,
    subject_count INTEGER NOT NULL DEFAULT 0,
    chapter_count INTEGER NOT NULL DEFAULT 0,
    relation_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE Identity (id TEXT PRIMARY KEY, parent_id TEXT, name TEXT NOT NULL);
CREATE TABLE Subject (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE Chapter (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE Question (
    id TEXT PRIMARY KEY,
    year TEXT, unit TEXT, title TEXT, public_title TEXT,
    title_img TEXT, number TEXT, public_number TEXT,
    restore TEXT, restore_img TEXT, explain TEXT, explain_img TEXT,
    answer TEXT, option TEXT, score TEXT, score_describe TEXT,
    native_app_id TEXT, native_identity_id TEXT, app_id TEXT,
    identity_id TEXT, chapter_id TEXT, chapter_parent_id TEXT,
    type TEXT, part_id TEXT, part_parent_id TEXT,
    sort_chapter TEXT, sort_chapter_am TEXT, sort_chapter_pm TEXT,
    outlines TEXT, outlines_am TEXT, outlines_pm TEXT,
    sort_part TEXT, sort_part_am TEXT, sort_part_pm TEXT, am_pm TEXT,
    high_frequency TEXT, is_collection_question TEXT, is_real_question TEXT,
    cases_id TEXT, cases_parent_id TEXT,
    sort_cases TEXT, sort_cases_am TEXT, sort_cases_pm TEXT,
    source TEXT, source_filter TEXT, show_number TEXT, created_at TEXT,
    type_str TEXT, origin_type TEXT, sort TEXT, is_new TEXT,
    outlines_mastery TEXT, filter_type TEXT, cut_question TEXT, user_answer TEXT
);
CREATE TABLE IdentitySubject (
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identity_id, subject_id),
    FOREIGN KEY (identity_id) REFERENCES Identity(id),
    FOREIGN KEY (subject_id) REFERENCES Subject(id)
);
CREATE TABLE IdentityChapter (
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    chapter_id TEXT NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identity_id, subject_id, chapter_id),
    FOREIGN KEY (identity_id) REFERENCES Identity(id),
    FOREIGN KEY (subject_id) REFERENCES Subject(id),
    FOREIGN KEY (chapter_id) REFERENCES Chapter(id)
);
CREATE TABLE IdentityQuestion (
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    chapter_id TEXT NOT NULL,
    question_id TEXT NOT NULL,
    PRIMARY KEY (identity_id, subject_id, chapter_id, question_id),
    FOREIGN KEY (identity_id) REFERENCES Identity(id),
    FOREIGN KEY (subject_id) REFERENCES Subject(id),
    FOREIGN KEY (chapter_id) REFERENCES Chapter(id),
    FOREIGN KEY (question_id) REFERENCES Question(id)
);
CREATE INDEX idx_identity_question_question ON IdentityQuestion(question_id);
CREATE INDEX idx_identity_question_chapter
    ON IdentityQuestion(identity_id, subject_id, chapter_id);
```

`BankMeta` 恰好一行，`schema_version = 1`；内容来源用 `source` 描述，允许保留既有来源字符串。结构版本独立于内容版本，不可通过把用户库版本 `11` 填入此字段升级题库格式。新结构变更需要先设计兼容与迁移。

### 3.1 字段编码与题型

| 字段 | 规范 |
| :--- | :--- |
| 各表 `id` 与关系 ID | 非空 TEXT，保留来源 ID；现有身份/章节排序有数字解析，当前制作使用来源数字字符串 |
| `name`、题干、解析等文本 | UTF-8，缺失的可选内容规范化为空字符串；不截断 Unicode，不破坏原有文本/HTML |
| `option` | JSON 数组的 TEXT，例如 `[{"key":"A","title":"选项内容"}]`；主观题使用 `[]`；不能存 Dart/Python 对象调试字符串 |
| 图片字段 | 保持来源的文本/JSON 表示与有效 URL；API 给出列表/对象时 JSON 编码；不含设备绝对路径。当前包不内嵌缓存图片，不保证图片离线可用 |
| `answer` | 选择题为选项键，多个键保持稳定排序；主观题保留参考答案，不能套用选择题判分 |
| `type` / `type_str` | 保留来源题型与名称；当前识别 1 单选、2 多选、3 填空、4 名词解释、5 简答、6 论述、7 病例分析、19 案例分析 |
| `cut_question` / `user_answer` | 为旧格式兼容保留列，新产物必须分别为 `'0'` / `''`，不携带账号状态 |
| `is_collection_question` 等来源标志 | 区分题目分类与账号收藏标志；账号专属值必须清除，不能作为用户状态导入 |
| `BankMeta.generated_at`、manifest `generated_at` | UTC Unix 秒；历史全量服务曾写毫秒，属于需修正的兼容差异，不能复制为新规范 |
| 目录 `QuestionBank.updated_at`、同步状态时间戳 | 用户库现有毫秒契约，与产物生成时间分开 |

### 3.2 去重与计数

先按完整关系键去重，再按全局题目 ID 去重。`question_count` 为 `COUNT(*) FROM Question`，`relation_count` 为 `COUNT(*) FROM IdentityQuestion`；同题跨章节时后者可能大于前者，不能用网络返回题数累加代替数据库实数。

`subject_count` / `chapter_count` 分别为对应表实数。规范沿用现有生产端的关系计数口径：`IdentitySubject.total` 是该身份与课程下的关系行数，`IdentityChapter.total` 是完整身份/课程/章节组合下的关系行数。课程中同题跨章时关系总数可能大于去重题数，UI 应区分。用户对错计数沿用 `rebuildQuestionCount` 的现有去重口径。

计数在暂存库中用 SQL 重算，不依赖旧合并库的计数触发器。每组题目关系都必须有对应的身份、课程、章节及 `IdentitySubject` / `IdentityChapter` 行；不发布孤立题目。

## 4. 包格式、manifest 与哈希

本地 `.sqlite` 必须自描述，文件名推荐 `<bank_id>.sqlite`。标准 ZIP 每包只装一个同名 SQLite；可另带 `manifest.json`，当前导入器只读取第一个 `.sqlite` 并使用其 `BankMeta`，不会读取 ZIP 内 manifest。不得把多个题库放同一 ZIP 后期待全部导入。发布前关闭写连接并合并 WAL，不依赖额外的 `-wal` / `-shm`。

远程清单支持顶层 `banks`，以及现有应用更新清单的 `question_banks` 对象/数组。新发布推荐以下独立清单形式：

```json
{
  "manifest_version": 1,
  "schema_version": 1,
  "generated_at": 1793923200,
  "banks": [
    {
      "bank_id": "custom_clinical_final",
      "name": "我的临床期末题库",
      "description": "临床期末全学年",
      "identity_id": "20101",
      "version": "1.0.0",
      "schema_version": 1,
      "generated_at": 1793923200,
      "file": "custom_clinical_final.sqlite",
      "url": "https://example.org/banks/custom_clinical_final.sqlite.zip",
      "size": 123456,
      "sha256": "<下载文件的64位小写十六进制SHA-256>",
      "sqlite_sha256": "<解压后SQLite的64位小写十六进制SHA-256>",
      "question_count": 100,
      "subject_count": 2,
      "chapter_count": 4,
      "relation_count": 120
    }
  ]
}
```

此例是字段模板，URL、大小、数量、时间和两个哈希必须替换为真实产物值，不能直接用作发布清单。

- `url` 是实际可下载的 `.zip` 或 `.sqlite` HTTPS 地址；“管理订阅”配置的是包含这些条目的 HTTPS JSON 清单地址。离线导出包内 manifest 仅描述包内文件，没有虚构远程 url，不能直接作为在线订阅。
- `size` / `sha256` 对应 **HTTP 下载文件**，若下载 ZIP 就对 ZIP 计算；`sqlite_sha256` 对解压后的 SQLite 计算。直接下载 SQLite 时两组哈希相同。
- `file` 表示包内 SQLite 文件名，仅供生产清单描述；现有下载器依赖 `url`，不会根据 `file` 自动生成地址。
- `identity_id` 必须与唯一根 ID 一致；版本与数量必须与 `BankMeta` 一致。旧官方包有内容版本 `1.0.0`、发布版本 `3.0.0` 的历史例外，新产物不要延续这种分歧。
- 计算哈希时数据库写入已全部结束，后续不能再修改 `BankMeta`；SQLite 不保存自身文件哈希，避免循环依赖。ZIP 哈希计算在最终打包后。
- 当前生产端本地 manifest 的 `file/size/sha256` 指原始 SQLite，缺少 `url`；转换为 ZIP 订阅清单时必须重算下载包大小与哈希。
- 安装目录 `QuestionBank.content_hash` 是 SQLite 文件哈希，不是 ZIP 哈希。内容哈希不证明发布者身份；若未来需要可信发布，应另行设计签名。

智能同步的题目哈希沿用 `_rowHash`：排除 `cut_question`、`user_answer`、`chapter_id`、`chapter_parent_id`、`identity_id`，其他字段名排序，拼为 `字段=值` 的换行文本（null 视为空），UTF-8 SHA-256。章节哈希按题目 ID 与题目哈希排序，带章节 ID 再计算。它们用于现有同步状态对比，不能与文件 SHA-256 混用；不自行替换为另一种 JSON 哈希算法。

## 5. 自建、增量与管理实现

1. 登录后读取 `subjectV2`，递归选择身份；父子重叠去重，每个选定根分别制作。空/0 分组不可选，但有效后代保留。
2. 初次创建分配 `custom_<identity>_<microseconds>`，初版 `1.0.0`；构建不改当前 `activeBankId`，安装也不自动切换。原始题目 ID 转为字符串，绝不按 bank 或章节重新编号。
3. 复用 schema、请求解密和字段转换；按真实叶入口请求全课程/章节，暂存产物清除 `user_answer/cut_question/is_collection_question`，SQL 计算去重题量和关系量。schema v1 的 Chapter 无父字段，深层章节路径保存在名称中，不宣称无损存储章节树。
4. 目录与抓题设超时；错误结果重试一次，203/309 不重复请求。取消在网络请求边界检查；权限不足或题量不完整不安装，失败清理暂存。创建任务没有持久化续传。
5. 校验后安装；同时在用户库登记、记录时间轴、ATTACH 聚合共享题用户状态。所有正式题库仍只读。
6. 完整树产物更新采用完整快照检查再合并；保留本地额外内容，有内容/关系变化才递增 PATCH。全量重建则用新快照替换，递增 PATCH；失败/取消不登记版本。旧章节智能分支沿用 `基础版本+delta.秒`。
7. API 制作/增量安装关闭订阅包覆盖更新，避免被旧包回退；下载订阅包启用包更新。没有混用个人做题上传或多设备漫游配置。
8. `BankHistory` 自用户库 v12 引入（当前 v13），字段为 `id/bank_id/timestamp/action/version/added/question_count`，timestamp 为毫秒；一次成功安装记录一次履历，actual added 按 incoming 中不存在于旧库的全局题目 ID 计算；不补造旧历史。时间轴不随内容包导出。
9. SQLite 导出清理账号字段与非内容表；ZIP 包含一个 SQLite 和 `manifest.json`。旧多根库选择一个根，输出完整子树标准库。移动端 `FilePicker.saveFile(bytes)` 由系统保存，返回值可能为 content URI；桌面端返回路径后复制。导出禁止写入应用数据库目录、正式库和链接别名。

进度以章数计算比例，目录未稳定时不定进度；显示当前章节、完成章数、题数与状态。目录题数可能含跨章重复，最终存储题量由 SQL 去重计数。创建的完成/取消按钮保持可见；一次旧智能同步为一个有限批次，结束时显示剩余章数与权限/重试状态，不承诺一次点击清空全部队列。

## 6. 制作验收与交付门禁

- 八张核心表、规范列与主键完整；唯一根、无环、全树连通；核心索引存在。
- `PRAGMA integrity_check` 返回 `ok`；`PRAGMA foreign_key_check` 无结果；额外检查关系组合对应的 `IdentitySubject` / `IdentityChapter`，不能只依赖单列外键。
- `BankMeta` 恰好一行，ID、schema、版本与清单一致；SQL 实际计数与声明一致，题目/关系非空；无孤立题目与空 ID。
- 字段编码、选项 JSON 与主观题格式有效；账号答案、收藏、斩题、凭据已清除；记录失败和无权限章节，完整制作必须全部成功。
- 关闭数据库并确认无未合并 WAL；对最终文件及 ZIP 分别计算正确哈希；导入后保持正式题库只读。
- 后续实现需使用临时真实 SQLite 与可控 API 响应验证：深层身份、重叠选择、同题跨章、重复导入、内容变更、请求失败/取消/权限不足、版本不误增、用户数据共享与 ATTACH 重算。
- 每个开发模块执行 `flutter analyze` 与 `flutter test`；移动窄屏、桌面宽屏与文件选择/导出还需平台实测。自动化测试全绿不等于已完成真实账号全科抓取或原生跨平台文件导出验证。

## 7. 加密边界（规划，不实现）

开源不意味着所有加密文件必然能被解密：安全性取决于密码算法与密钥是否可获得，未提供密钥的强加密文件仍可保密。但如果客户端能离线展示所有题目，且密钥随应用分发或在运行时可取得，控制设备的人通常可以提取密钥或截取明文；闭源也不能根除这一点。

当前 `YkbCrypto` 是远端接口解密，不是本地题库加密。将来如需 SQLCipher、密码导出或在线授权，要分别定义保护目标、密钥管理、平台兼容与明文导出策略；不能承诺“用户可读而永远无法提取明文”。本轮不修改加密链路。

### 2026-11-07 交互创建的部分成功产物

仅用户主动创建支持对目录/章节错误选择忽略、忽略全部或终止。忽略后只保存完整成功章节，题量与关系数由暂存 SQLite 实数重算，禁止用远程预计题量作为 BankMeta 的实际题量。整章字段/事务失败须回滚，不得遗留半章关系或孤立题。所有章节失败时不得安装空题库。创建报告在本次会话展示成功/失败条目，不写入题库，不夹带账号信息；没有交互处理器的智能同步和全量重建继续遇错不替换。

### 统一管理元数据边界（2026-11-07）

题库 schema v1 和 manifest 内容规范保持。来源目录/检查状态保存在应用 SharedPreferences，BankContentState 上游发布基线/本地修订保存在用户库 v13，下载缓存位于独立 BankDownloads 可写目录；这些不属于题库内容包。题库制作/导出不能把订阅私有地址、账号、个人记录或设备履历写入标准 SQLite。发布包更新检查与医考帮 API 抓题是不同操作，详见 QUESTION_BANK_MANAGEMENT_DESIGN.md。
