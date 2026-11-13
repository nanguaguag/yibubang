# yibubang 题库数据库架构最终实现说明

> 本文记录当前工作区已经实现并验证过的题库架构、生产产物、客户端管理、老用户迁移、文件导入、远程下载更新和界面行为。
>
> 本文不是最初的升级计划。`docs/gpt/upgrade_database.md` 描述的是目标方案；本文以当前 Dart、Python、SQLite 产物和 `yibubang_update.json` 的实际实现为准。
>
> 记录日期：2026-08-11

## 1. 实现状态和设计结论

当前版本已经从“一个合并题库文件”升级为：

```text
题库生产端
  └── 三个独立 SQLite 题库文件

客户端
  ├── QuestionBank/<bank_id>/<bank_id>.sqlite   只读题库内容
  └── user_data.sqlite                          可写用户状态、统计和题库目录
```

已经落地的核心能力包括：

- 口腔、临床、护理三套独立题库。
- 每个题库独立存储、独立校验、独立下载和独立更新。
- 题库可以启用、禁用和切换；当前题库不能在没有替代题库时被禁用。
- 支持导入 `.sqlite`、`.db` 和 `.zip` 文件。
- 支持远程 ZIP 流式下载、下载进度、ZIP 大小校验和 ZIP SHA-256 校验。
- 支持 SQLite schema、元数据、外键和完整性校验。
- 使用 staging 文件、`.bak` 备份和失败恢复，避免更新失败时破坏旧题库。
- 保留旧版 `question_data.sqlite` 作为只读兼容回退，迁移失败时仍可继续刷题。
- 老用户的 `user_data.Question` 题目状态继续按全局 `question_id` 保存，不因拆库而复制或丢失。
- 课程和章节统计按 `bank_id` 隔离；同一道题在多个题库出现时，用户题目状态仍然共享。
- 远程清单同时兼容原有 App 更新字段和新增的多题库清单。
- 应用更新检查与题库更新检查已经解耦。

当前正式内置题库只有以下三个：

```text
30401 → dental_final  → 口腔期末
20101 → clinical_final → 临床期末
11070 → nursing_final  → 护理期末
```

`dental_license` 等最初升级计划中的第四题库尚未登记到当前客户端，也不属于当前正式题库集合。

## 2. 最终目录和数据边界

### 2.1 生产端产物

题库生产脚本位于 `docs/yikaobang/src/`。以合并源库为输入后，`split_question_banks.py` 输出：

```text
docs/yikaobang/data/question_banks/
├── manifest.json
├── dental_final/
│   └── dental_final.sqlite
├── clinical_final/
│   └── clinical_final.sqlite
└── nursing_final/
    └── nursing_final.sqlite
```

发布到 Gitee 时，SQLite 文件分别压缩为：

```text
dental_final.sqlite.zip
clinical_final.sqlite.zip
nursing_final.sqlite.zip
```

ZIP 是交付格式；客户端安装后会从 ZIP 中取出 SQLite 文件，并将其复制到应用数据库目录下的规范路径。

### 2.2 客户端实际路径

客户端使用 `sqflite` 的 `getDatabasesPath()` 作为数据库根目录。独立题库路径固定为：

```text
<databasesPath>/QuestionBank/<bank_id>/<bank_id>.sqlite
```

例如：

```text
<databasesPath>/QuestionBank/dental_final/dental_final.sqlite
<databasesPath>/QuestionBank/clinical_final/clinical_final.sqlite
<databasesPath>/QuestionBank/nursing_final/nursing_final.sqlite
```

用户数据库路径为：

```text
<databasesPath>/user_data.sqlite
```

旧版合并题库路径为：

```text
<databasesPath>/question_data.sqlite
```

迁移备份目录为：

```text
<databasesPath>/migration_backup/
```

题库数据库与用户数据库的边界如下：

| 数据类型 | 所在位置 | 是否可写 | 说明 |
| --- | --- | --- | --- |
| 题干、选项、正确答案、解析、课程、章节 | 独立题库 SQLite | 客户端只读 | 更新时替换整个题库文件 |
| 题目答案历史、作答状态、收藏、斩题 | `user_data.sqlite` | 可写 | 以全局 `Question.id` 为主键 |
| 课程/章节正确错误统计 | `user_data.sqlite` | 可写 | 以 `bank_id` 隔离 |
| 题库目录、版本、哈希、启用状态 | `user_data.sqlite.QuestionBank` | 可写 | 记录本地安装状态 |
| 当前题库选择 | `SharedPreferences.activeBankId` | 可写 | 选择题库文件，不再只依赖 identity |
| 旧版合并题库 | `question_data.sqlite` | 只读 | 迁移失败或新库不可用时兼容回退 |

题库 SQLite 不保存运行时用户状态的权威版本。虽然拆分产物中的 `Question` 仍保留历史字段 `cut_question` 和 `user_answer`，但客户端运行时的答案、收藏和斩题状态以 `user_data.sqlite.Question` 为准。

## 3. 三套题库和实际产物统计

`docs/yikaobang/data/question_banks/manifest.json` 当前记录的三套题库如下：

| bank_id | 名称 | 根 identity | 题库版本 | schema_version | 题目数 | 课程数 | 章节数 | 关系数 | SQLite 大小 | SQLite SHA-256 |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `dental_final` | 口腔期末 | `30401` | `1.0.0` | 1 | 78,310 | 45 | 1,132 | 78,310 | 176,340,992 bytes | `574aaa4cb8e443f25661581594272a92e6b997199afd19f5faf90ffe247ce536` |
| `clinical_final` | 临床期末 | `20101` | `1.0.0` | 1 | 57,346 | 40 | 1,137 | 57,346 | 138,215,424 bytes | `893100264187b49a57a802cba3933b02b121f566378f43c5f5625df380ff5eb2` |
| `nursing_final` | 护理期末 | `11070` | 1.0.0 | 1 | 69,591 | 50 | 928 | 69,591 | 125,919,232 bytes | `e0b0b5ab40f7d6f9718c1962282c36b479161112ec0bb77fe330acfedd0384f8` |

这里的“关系数”是 `IdentityQuestion` 行数。当前三库中关系数与题目数相同，但这不是 schema 的通用约束；同一道题如果在一个题库中属于多个课程或章节，可以存在多条关系，而仍然只对应一个 `Question` 行。

需要区分两个版本概念：

- SQLite `BankMeta.version` 和本地 `manifest.json` 中的 `version` 为 `1.0.0`，表示当前生成产物的内容版本。
- 远程发布清单将当前 Gitee ZIP 发布版本标为 `3.0.0`，表示发布包/远程题库版本。
- 两者不是同一个字段，不能仅凭 `1.0.0` 和 `3.0.0` 判断内容是否不同。客户端优先使用 SQLite 内容 SHA-256 判断更新。

三套 SQLite 均由生成脚本执行并通过：

```sql
PRAGMA integrity_check;
PRAGMA foreign_key_check;
```

当前结果分别为 `ok` 和空结果集。

## 4. 独立题库 SQLite schema

题库 schema 版本当前为 `1`。由 `docs/yikaobang/src/split_question_banks.py` 生成的必需表为：

```text
BankMeta
Identity
Subject
Chapter
Question
IdentitySubject
IdentityChapter
IdentityQuestion
```

另外保留 `Comment` 表，当前拆分脚本创建的是空的简化表；Flutter 当前评论页面主要通过网络接口读取评论，不依赖本地 Comment 表。

### 4.1 `BankMeta`

每个独立 SQLite 文件只有一行 `BankMeta`：

```sql
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
```

字段用途：

- `bank_id`：独立题库的稳定 ID，必须与目标安装目录和远程清单一致。
- `name`：题库显示名称。
- `version`：题库内容版本，当前生成产物为 `1.0.0`。
- `schema_version`：SQLite 结构版本，当前支持版本为 `1`。
- `generated_at`：生成时间戳。
- `source`：生成来源说明。
- `*_count`：题目、课程、章节和题目关系的声明数量，安装校验时会与实际 SQL 统计对比。

### 4.2 内容表

#### `Identity`

```sql
Identity(
    id TEXT PRIMARY KEY,
    parent_id TEXT,
    name TEXT NOT NULL
)
```

每个独立题库以对应根 identity 为边界。拆分后，根 identity 的 `parent_id` 被设置为 `'-1'`，每个独立库必须且只能有一个 `parent_id = '-1'` 的根节点。

#### `Subject` 和 `Chapter`

```sql
Subject(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
)

Chapter(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
)
```

课程和章节通过关系表与 identity 关联。`Chapter` 本身不依赖一列 `subject_id` 表达课程边界，课程/章节/题目的上下文以关系表为准。

#### `Question`

`Question.id` 是全局稳定题目 ID。题库内容表包含题干、选项、答案、解析、图片、题型、来源、排序、章节和历史字段等，主要字段包括：

```text
id
year / unit / number / public_number
 title / public_title / title_img
restore / restore_img / explain / explain_img
answer / option / score / score_describe
native_app_id / native_identity_id / app_id / identity_id
chapter_id / chapter_parent_id
type / type_str / origin_type / filter_type
part_id / part_parent_id / sort*
outlines* / am_pm
high_frequency / is_collection_question / is_real_question / is_new
cases_id / cases_parent_id / sort_cases*
source / source_filter / show_number / created_at
cut_question / user_answer
```

`option` 在 SQLite 中保存为 JSON 字符串，Flutter 详情页读取后再 `json.decode()`。题库文件中的 `cut_question`、`user_answer` 是历史生产字段，不是当前用户库状态的权威来源。

### 4.3 关系表和主键

当前关系表的主键是完整上下文键：

```sql
IdentitySubject(
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identity_id, subject_id)
)

IdentityChapter(
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    chapter_id TEXT NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identity_id, subject_id, chapter_id)
)

IdentityQuestion(
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    chapter_id TEXT NOT NULL,
    question_id TEXT NOT NULL,
    PRIMARY KEY (identity_id, subject_id, chapter_id, question_id)
)
```

三张关系表都声明了到相应字典表的外键。`IdentityQuestion` 额外建立：

```sql
CREATE INDEX idx_identity_question_question
    ON IdentityQuestion(question_id);

CREATE INDEX idx_identity_question_chapter
    ON IdentityQuestion(identity_id, subject_id, chapter_id);
```

拆分边界不是简单地按 `Question.identity_id` 或 `Question.chapter_id` 过滤，而是：

1. 从指定根 identity 递归收集完整 identity 子树。
2. 从该子树的 `IdentityQuestion` 关系收集 subject、chapter 和 question ID。
3. 按这些 ID 复制内容表。
4. 复制完整的 `IdentitySubject`、`IdentityChapter` 和 `IdentityQuestion` 关系。
5. 重算课程和章节的 `total`。

这样可以保留共享题目在多个课程/章节中的出现关系，避免因 `Question` 行中的单个归属字段被最后一次导入覆盖而错误划分题库。

## 5. 用户数据库 `user_data.sqlite` schema version 4

`UserDBHelper` 当前通过：

```dart
openDatabase(path, version: 4, onCreate: _onCreate, onUpgrade: _onUpgrade)
```

打开 `user_data.sqlite`。用户数据库可写，保存用户状态、统计、活动记录、题库目录和迁移状态。

### 5.1 课程和章节统计

```sql
IdentitySubject(
    bank_id TEXT NOT NULL,
    identity_id TEXT,
    subject_id TEXT,
    correct INTEGER NOT NULL DEFAULT 0,
    incorrect INTEGER NOT NULL DEFAULT 0,
    selected INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bank_id, identity_id, subject_id)
)
```

```sql
IdentityChapter(
    bank_id TEXT NOT NULL,
    identity_id TEXT,
    subject_id TEXT,
    chapter_id TEXT,
    correct INTEGER NOT NULL DEFAULT 0,
    incorrect INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bank_id, identity_id, subject_id, chapter_id)
)
```

`bank_id` 是统计边界，`subject_id` 也进入章节主键。因此同一章节 ID 出现在不同课程或题库时，不会直接共用同一条统计缓存。

### 5.2 全局用户题目状态

```sql
Question(
    id TEXT PRIMARY KEY,
    chapter_id TEXT,
    chapter_parent_id TEXT,
    cut_question TEXT NOT NULL DEFAULT '',
    user_answer TEXT NOT NULL DEFAULT '',
    status INTEGER NOT NULL DEFAULT 0,
    collection INTEGER NOT NULL DEFAULT 0
)
```

用户题目表故意没有 `bank_id`，因为产品决策是：同一个稳定的全局 `question_id` 表示同一道题，用户只保存一份答案、收藏、斩题和作答状态。

常用状态含义：

- `status = 0`：未作答。
- `status = 1`：答对。
- `status = 2`：答错。
- `status = 4`：测试模式已作答。
- `collection`：是否收藏。
- `cut_question`：是否斩题，运行时主要使用空字符串或 `cutted`。
- `user_answer`：保存答案历史，最后一段表示当前答案。

这意味着：

```text
题库 A 和题库 B 都有 question_id = 100
用户在 A 作答
切换到 B 后，B 读取同一条 user_data.Question
```

题库统计仍然按各自 `IdentityQuestion` 关系和 `bank_id` 独立计算。

### 5.3 `Activities`

当前活动表保留历史通用字段，并增加结构化题库字段：

```sql
Activities(
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    bank_id TEXT,
    question_id TEXT,
    identity_id TEXT,
    subject_id TEXT,
    chapter_id TEXT,
    is_right TEXT
)
```

答题时会写入题库、题目、identity、课程、章节和是否正确等信息。旧的 `description` JSON 字符串仍然保留，用于兼容历史活动数据。

### 5.4 `QuestionBank` 题库目录

题库目录和题库文件内容分离，当前表结构为：

```sql
QuestionBank(
    bank_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    version TEXT NOT NULL DEFAULT '0.0.0',
    schema_version INTEGER NOT NULL DEFAULT 0,
    local_path TEXT NOT NULL DEFAULT '',
    content_hash TEXT NOT NULL DEFAULT '',
    size INTEGER NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1,
    built_in INTEGER NOT NULL DEFAULT 0,
    update_enabled INTEGER NOT NULL DEFAULT 1,
    install_state TEXT NOT NULL DEFAULT 'available',
    remote_url TEXT,
    identity_id TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
)
```

字段说明：

- `bank_id`：题库稳定 ID。
- `local_path`：已安装 SQLite 的规范路径。
- `content_hash`：本地 SQLite 文件 SHA-256，不是 ZIP SHA-256。
- `size`：本地 SQLite 文件大小。
- `enabled`：是否允许题库参与选择和运行。
- `built_in`：是否为客户端登记的内置题库。
- `update_enabled`：该题库是否允许检查官方远程更新。
- `install_state`：例如 `available`、`installed`、`broken`。
- `remote_url`：最近一次清单提供的下载地址。
- `identity_id`：题库根 identity。

`update_enabled` 是后续增加的字段，`UserDBHelper` 从 version 3 升级到 version 4 时通过 `ALTER TABLE` 补建，默认值为 `1`。

### 5.5 `MigrationState`

```sql
MigrationState(
    migration_id TEXT PRIMARY KEY,
    from_version INTEGER NOT NULL,
    to_version INTEGER NOT NULL,
    state TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    finished_at INTEGER NOT NULL DEFAULT 0,
    error TEXT NOT NULL DEFAULT ''
)
```

该表用于记录题库目录迁移和完成状态，便于诊断迁移失败。当前 `UserDBHelper` 的实际 SQLite schema 版本是 `4`；初始化目录时写入的 `question_bank_catalog_v1` 记录仍使用 `to_version = 3`，这是当前实现中需要后续统一的版本记录细节，不影响 SQLite version 4 本身的打开和升级逻辑。

### 5.6 其他用户表

用户库还保留：

- `Notes`：用户笔记。
- `Cards`：卡片数据。
- `Activities`：答题活动和历史上传结构。

这些表不存储题库正文。题库更新不会覆盖它们。

## 6. 题库打开和完整性校验

### 6.1 `QuestionBankDatabaseManager`

`QuestionBankDatabaseManager` 负责题库路径、打开、关闭和校验：

- `pathFor(bankId)` 生成规范文件路径。
- `openBank(bankId)` 先校验文件，再以 `readOnly: true` 打开。
- `closeBank(bankId)` 关闭指定题库连接。
- `closeAll()` 关闭所有缓存连接。
- `validateFile(filePath, expectedBankId:)` 执行安装前和打开前校验。

题库数据库只读打开，客户端不会直接在题库 SQLite 中写入答案或统计。

### 6.2 校验内容

安装或打开题库时，`validateFile` 按以下顺序检查：

1. 文件存在。
2. 必要数据表齐全：
   `BankMeta`、`Identity`、`Subject`、`Chapter`、`Question`、`IdentitySubject`、`IdentityChapter`、`IdentityQuestion`。
3. `BankMeta` 恰有一行。
4. `BankMeta.bank_id` 非空，并且在指定题库安装时与 `expectedBankId` 相同。
5. `schema_version` 当前必须为 `1`。
6. `PRAGMA integrity_check` 返回 `ok`。
7. `Identity` 中 `parent_id = '-1'` 的根 identity 恰有一个。
8. `PRAGMA foreign_key_check` 没有错误。
9. 实际 `Question`、`IdentityQuestion`、`Subject`、`Chapter` 行数与 `BankMeta` 声明数量一致。
10. 题目数量和关系数量不能为零。

校验失败的文件不会被安装为正式题库，也不会覆盖原来的可用文件。

## 7. 启动、迁移和旧库兼容回退

### 7.1 启动初始化

应用启动时，`main.dart` 完成基础设置后，由 `QuestionBankRepository.initialize()` 初始化题库目录：

1. 创建 `migration_backup` 目录。
2. 首次启动时备份已有 `user_data.sqlite` 和 `question_data.sqlite`。
3. 检查三个内置题库的正式文件和 `.bak` 文件。
4. 正式文件不存在时尝试恢复 `.bak`。
5. 正式文件存在但校验失败时，若 `.bak` 有效则恢复 `.bak`。
6. 在用户库 `QuestionBank` 表登记三个内置题库。
7. 如果旧 `question_data.sqlite` 存在，登记为 `legacy_combined`。
8. 启动过程中单个题库初始化失败时，保留目录记录和旧库回退能力，不主动删除旧数据。

### 7.2 老用户数据迁移

旧版本用户的关键用户状态仍在 `user_data.sqlite.Question` 中，且 `Question.id` 已经是全局题目 ID。因此迁移不需要将用户题目状态复制到三套题库中。

迁移重点是：

- 为课程和章节统计增加 `bank_id`。
- 创建 `QuestionBank` 目录表。
- 创建 `MigrationState`。
- 为 `Activities` 增加结构化字段。
- 增加 `update_enabled`。
- 根据新题库关系重建统计。
- 备份旧用户库和旧题库。

`UserDBHelper._onUpgrade()` 的迁移分支为：

```text
oldVersion < 2
  ├── 将旧 IdentitySubject/IdentityChapter 迁移到带 bank_id 的表
  ├── 根据 identity_id 映射 dental_final / clinical_final / nursing_final
  ├── 创建 QuestionBank
  └── 创建 MigrationState

oldVersion < 3
  ├── 给 Activities 增加 bank_id、question_id、identity_id
  │   subject_id、chapter_id、is_right
  └── 创建活动索引

oldVersion < 4
  └── 给 QuestionBank 增加 update_enabled
```

迁移在 SQLite transaction 中执行，原数据库文件在迁移前进入 `migration_backup`。

迁移后，`rebuildQuestionCount({String? bankId})` 可以通过当前题库的 `IdentityQuestion` 关系和全局用户 `Question.status` 重建课程/章节统计。统计重建只写用户库，不修改题库内容。

### 7.3 旧版合并题库回退规则

旧版 `question_data.sqlite` 不会因为新架构上线而立即删除。它以 `legacy_combined` 目录记录存在，特点是：

- 只读。
- `update_enabled = 0`。
- 不是新的普通题库候选。
- 主要用于拆分失败、独立题库缺失或老用户兼容。

如果当前独立题库文件不存在或校验失败，`DatabaseHelper` 会检查旧库是否存在，并检查 `QuestionBank.enabled`：

- 没有明确禁用旧库时，可以回退打开旧合并题库。
- 用户在题库管理页面明确关闭旧库后，不再静默回退到旧库。
- 关闭当前题库时，如果存在其他已安装且启用的题库，先切换到替代题库。
- 如果没有任何替代题库，则拒绝禁用，保证至少有一个可用题库。

这修复了旧版“兼容回退按钮永远显示开启、点击关闭仍反复提示已切换”的行为：启用状态现在保存于 `QuestionBank.enabled`，并参与实际回退判断。

## 8. 导入、安装、下载和回滚

### 8.1 文件导入

题库管理页面允许选择：

```text
.sqlite
.db
.zip
```

导入流程如下：

```text
选择文件
  ↓
如果是 ZIP，寻找其中第一个 .sqlite 文件
  ↓
解压到 QuestionBank/.import-<timestamp>.sqlite
  ↓
validateFile()
  ↓
计算 SQLite SHA-256
  ↓
写入 staging 文件
  ↓
关闭题库连接
  ↓
旧正式文件改名为 .bak
  ↓
staging 改名为正式 <bank_id>.sqlite
  ↓
写入/替换 QuestionBank 目录记录
  ↓
删除临时文件
```

临时题库根目录会自动递归创建，因此导入和下载不会因为 `QuestionBank` 目录尚不存在而失败。此前出现的：

```text
PathNotFoundException: Cannot open file .../QuestionBank/.import-<timestamp>.sqlite
```

已经通过自动创建题库根目录、临时文件父目录以及等待安装流程完成的方式修复。

安装失败时：

- 删除新正式文件或未完成的 staging 文件。
- 如果存在 `.bak`，恢复原正式文件。
- 保留旧题库可用性。
- 不修改用户题目状态。

### 8.2 手动导入题库是否检查更新

当前规则不是“所有文件导入题库都完全不检查更新”，而是根据导入内容判断：

1. 普通手动导入文件的 SQLite SHA-256 与官方清单中的 `sqlite_sha256` 不相同。
2. 这种题库写入 `update_enabled = false`。
3. 题库管理页面不会显示官方远程更新。
4. 用户导入的自定义版本不会被官方版本自动覆盖。

如果用户导入的 SQLite 内容与官方清单中的 `sqlite_sha256` 完全相同：

1. 客户端识别为官方内容。
2. 保留 `update_enabled = true`。
3. 以后可以参与官方远程更新检查。

因此，导入一个与当前官方口腔题库完全相同的文件后，正常结果应该是：

- 导入成功。
- 本地 `content_hash` 与远程 `sqlite_sha256` 相同。
- 不显示“有更新”。
- 不会重新下载同一个远程 ZIP。

只有导入文件的实际 SQLite 内容哈希与远程清单不同时，且该题库允许更新，才会显示“更新”。如果用户导入的是自定义题库，默认不会显示更新按钮。

### 8.3 下载和更新

`QuestionBankRepository.downloadBank()` 下载的是远程 ZIP，不直接写入正式 SQLite：

1. 从远程清单取得 URL、ZIP 大小、ZIP SHA-256 和 SQLite SHA-256。
2. 使用 `http.Client` 发送流式 GET。
3. 将数据写入 `QuestionBank/.download-<timestamp>.zip` 临时文件。
4. 按已接收字节数回调下载进度。
5. 检查 HTTP 状态码必须为 `200`。
6. 检查实际下载字节数是否等于清单的 `size`。
7. 计算临时 ZIP 的 SHA-256，并与清单 `sha256` 对比。
8. 通过后交给 `importFile()`，继续解压和 SQLite 校验。
9. 下载完成后删除临时 ZIP。

下载中的页面 UI 使用当前题库卡片右侧的环状进度条替换“下载”或“更新”按钮，并显示例如 `50%`、`60%`。不再把一个无关的转圈进度条固定放在页面底部。

### 8.4 ZIP SHA-256 与 SQLite SHA-256

两种 hash 用途不同：

| 字段 | 对象 | 用途 |
| --- | --- | --- |
| `sha256` | 远程 ZIP 文件 | 校验网络下载内容是否完整、是否被替换 |
| `sqlite_sha256` | ZIP 解压后的 SQLite 文件 | 判断本地题库内容是否与远程内容相同 |
| `QuestionBank.content_hash` | 本地正式 SQLite 文件 | 与远程 `sqlite_sha256` 比较更新 |

不能用 ZIP hash 直接与本地 SQLite 文件比较，因为两者不是同一文件。

当前 `downloadBank()` 会强制校验 ZIP 的 `sha256` 和可用的大小；安装阶段会计算本地 SQLite 的 `content_hash`。远程 `sqlite_sha256` 主要用于更新判断和手动导入是否属于官方内容识别。

### 8.5 更新判断算法

`QuestionBankRepository.hasUpdate(bank, remote)` 的判断顺序为：

```text
如果 bank.update_enabled == false
    → 没有更新

如果远程 sqlite_sha256 和本地 content_hash 都存在
    → 两者不同才是有更新

否则
    → 比较远程 version 与本地 version
    → 远程版本更高才是有更新
```

这比单纯比较版本号更可靠：同一个 SQLite 文件即使因发布字段或 ZIP 标签不同而版本号不同，也不会误报为更新。

当前更新策略是整个 SQLite 文件替换，不是增量 patch。更新独立题库不会覆盖其他题库，也不会改写 `user_data.sqlite`。

## 9. 远程清单 `yibubang_update.json`

原有配置可以继续使用。当前文件同时保留旧 App 更新字段：

```json
{
  "latest_app": "...",
  "latest_app_url": "...",
  "update_info": "...",
  "latest_data_url": "...",
  "latest_data_md5": "...",
  "data_for_version": {}
}
```

并新增：

```json
{
  "question_banks": {
    "manifest_version": 1,
    "schema_version": 1,
    "banks": []
  }
}
```

每个题库条目包含：

```json
{
  "bank_id": "dental_final",
  "name": "口腔期末",
  "version": "3.0.0",
  "schema_version": 1,
  "identity_id": "30401",
  "url": "https://.../dental_final.sqlite.zip",
  "size": 32563857,
  "sha256": "ZIP 的 SHA-256",
  "sqlite_sha256": "SQLite 文件的 SHA-256"
}
```

当前三个官方 ZIP 配置如下：

| bank_id | URL | ZIP size | ZIP SHA-256 | SQLite SHA-256 |
| --- | --- | ---: | --- | --- |
| `dental_final` | `https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/dental_final.sqlite.zip` | 32,563,857 | `cb9870e6e77e1875a0f73530ec7e9c897c4ee0a435e13d39b6543719ff33f76f` | `574aaa4cb8e443f25661581594272a92e6b997199afd19f5faf90ffe247ce536` |
| `clinical_final` | `https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/clinical_final.sqlite.zip` | 25,939,926 | `3db37a844ec0f8ac3688a7fcf7967de1a8adf8f787a3e4801dd1276893383061` | `893100264187b49a57a802cba3933b02b121f566378f43c5f5625df380ff5eb2` |
| `nursing_final` | `https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/nursing_final.sqlite.zip` | 24,184,056 | `d23ac8b8b49083fb912749d21633bccc7f79bb60213ac6e4982d189c9bf7fa33` | `e0b0b5ab40f7d6f9718c1962282c36b479161112ec0bb77fe330acfedd0384f8` |

### 9.1 清单解析兼容方式

`checkRemoteManifest()` 支持以下形式：

1. 顶层直接有 `banks` 数组。
2. 顶层有 `question_banks` 对象，内部有 `banks` 数组。
3. 顶层 `question_banks` 直接是数组。

当前远程地址为：

```text
https://files.melonhu.cn/yibubang/yibubang_update.json
```

远程清单优先；如果请求失败、HTTP 状态不正确或格式无法解析，客户端使用代码内置的三个官方题库清单作为 fallback。远程条目缺少 URL、ZIP hash 或 SQLite hash 时，会用客户端内置的已发布配置补全必要字段。

### 9.2 App 更新与题库更新解耦

旧版配置中的 `latest_app`、`latest_app_url`、`update_info` 和 `data_for_version` 仍服务于 App 版本更新兼容，不再作为新题库管理页面的唯一数据源。

题库页面从 `question_banks.banks` 读取独立题库。应用更新不需要等待旧的 `question_data.sqlite` 下载完成；题库更新也不会因为 App 更新字段缺失而阻塞。发布新的题库内容时，可以只更新 JSON 中的 `question_banks` 和对应 ZIP。

发布新版本时，需要将修改后的本地 `yibubang_update.json` 上传到上述远程地址；当前工作区文档和源码已经适配，线上文件是否已替换取决于发布操作。

## 10. `QuestionBankRepository` 的职责

`QuestionBankRepository` 是题库目录和交付流程的主要入口，关键职责如下：

| 方法 | 作用 |
| --- | --- |
| `initialize()` | 创建备份、恢复 `.bak`、登记内置题库和旧库 |
| `listBanks()` | 读取 `QuestionBank` 目录 |
| `activeBankId()` | 获取当前可用题库，必要时选择第一个已安装且启用的题库 |
| `selectBank(bankId)` | 关闭旧连接、切换数据库和 SharedPreferences |
| `setEnabled(bankId, enabled)` | 启用/禁用题库，禁止禁用最后一个可用题库 |
| `importFile(path)` | 导入 SQLite/DB/ZIP |
| `downloadBank(bankId)` | 下载、校验并安装官方 ZIP |
| `checkRemoteManifest()` | 获取并兼容解析多题库清单 |
| `hasUpdate(bank, remote)` | 按 update_enabled、SQLite hash 和版本判断更新 |
| `validatePath(path)` | 调用数据库管理器验证题库 |

题库安装时会关闭相关题库连接和 `DatabaseHelper` 连接，然后进行 staging 替换，避免正式 SQLite 被打开状态下覆盖。

## 11. 客户端 UI 和入口变化

### 11.1 题库管理页面

`QuestionBankPage` 是当前题库安装、更新和切换入口，能够：

- 展示三个内置题库和目录中的其他题库。
- 点击卡片切换当前已安装且已启用题库。
- 使用 Switch 启用或禁用已安装题库。
- 点击右上角同步按钮检查远程清单。
- 点击文件按钮导入 SQLite、DB 或 ZIP。
- 未安装题库显示“下载”。
- 已安装且没有更新时隐藏下载按钮。
- 检测到更新时显示“更新”。
- 下载或更新中，在同一张题库卡片内显示环状百分比进度。
- 卡片不再显示“已启用”或“已禁用”文字，启用状态只通过 Switch 表达。
- 默认题库不可删除；当前实现没有为自定义题库提供删除入口。

题库卡片中的状态文字主要用于“未安装”“当前使用”“有更新”和版本信息，不再重复显示启用状态文字。

### 11.2 题库图标

三个内置题库使用 Material Symbols 图标，圆形背景、背景色和图标颜色保持原有 Material UI 风格：

| 题库 | 图标 |
| --- | --- |
| 口腔期末 | `Symbols.dentistry_rounded` |
| 临床期末 | `Symbols.health_metrics` |
| 护理期末 | `Symbols.bloodtype_rounded` |

图标定义位于 `lib/models/question_bank.dart`，页面通过题库 `bank_id` 获取对应图标。

### 11.3 旧“选择题库”入口

题库管理页面已经具备切换题库、启用/禁用和下载能力，因此做题首页不再显示旧版“选择题库”入口，避免出现两个入口和旧版合并题库回退混淆。

`IdentityListPage` 文件仍保留，以尽量不删除用户原有代码和注释。对于已安装且启用的新题库，它会配合当前题库选择逻辑；未安装时若仍存在旧合并库，可以提供兼容回退提示。

## 12. 题目读取、答题和统计链路

### 12.1 课程和章节读取

课程页面读取当前只读题库中的：

```text
IdentitySubject + Subject
```

题库提供课程名称和题目总数；用户库提供当前 `bank_id` 下的 `selected`、`correct`、`incorrect`。两部分在 Dart 模型层合并。

章节页面读取：

```text
IdentityChapter + Chapter
```

同样按当前 `bank_id` 和 identity/subject 读取用户统计。

### 12.2 题目列表读取

当前章节题目通过完整关系读取：

```sql
SELECT q.*
FROM Question AS q
JOIN IdentityQuestion AS iq ON q.id = iq.question_id
WHERE iq.identity_id = ?
  AND iq.subject_id = ?
  AND iq.chapter_id = ?
ORDER BY q.id
```

题目内容来自当前题库；用户状态再按全局 `q.id` 批量查询 `user_data.Question`。

当某道题第一次进入用户状态表时，客户端懒插入默认状态：

```text
status = 0
collection = 0
cut_question = ''
user_answer = ''
```

安装新题库不会为全部题目预创建用户状态，因此不会因为下载题库而大幅膨胀用户库。

### 12.3 收藏、斩题和答题

收藏和斩题只更新用户库 `Question`。

普通答题流程会：

1. 从当前题库 `IdentityQuestion` 查询题目出现的全部关系。
2. 按当前题库、identity、subject、chapter 更新课程和章节统计。
3. 更新全局用户 `Question` 的 `status`、答案历史、收藏和斩题字段。
4. 在 `Activities` 写入题库和题目上下文。

因此：

```text
用户题目状态：跨题库共享
课程/章节统计：按 bank_id 隔离
题目出现关系：由当前题库 IdentityQuestion 决定
```

### 12.4 统计重建

`rebuildQuestionCount({String? bankId})` 用于修复或重新计算统计：

1. 打开指定题库或当前题库。
2. 将该 `bank_id` 的课程、章节正确错误计数清零。
3. 将用户库 `Question` 与题库 `IdentityQuestion` 连接。
4. 只聚合 `status = 1` 和 `status = 2`。
5. 按 `bank_id`、identity、subject、chapter 写回统计。

共享题目如果同时存在于多个题库，重建每个题库时会根据各自关系计入各自的课程/章节统计，但用户状态仍然只有一条。

## 13. 旧代码和兼容边界

### 13.1 HomePage 的旧下载链路

`lib/screens/home_page.dart` 中仍保留旧的 `_needToDownload()` 和 `_downloadAndExtractZip()` 代码。这条链路面向旧版：

```text
data_for_version
  └── question_data.sqlite.zip
  └── 旧 MD5
  └── 合并 question_data.sqlite
```

当前启动流程不再把它作为新三题库管理的实际下载入口；新题库由 `QuestionBankRepository` 和题库管理页面处理。保留旧代码是为了兼容历史配置和尽量不删除用户原有代码。

### 13.2 `data_transfer.dart` 的旧迁移函数

`transferData()`、`checkTransferScuess()` 是旧架构残留实现，假设用户库存在旧的 Subject/Chapter 表或题库与用户库混合 schema；当前工作区没有发现它们被新启动流程调用。实际迁移使用 `UserDBHelper.onUpgrade`、`QuestionBankRepository.initialize` 和统计重建链路。

维护时不要把这些旧函数误认为当前题库安装或用户迁移的唯一入口。

### 13.3 生产端和当前正式题库边界

生产端仍以已有合并源库为输入，再由 `split_question_banks.py` 按白名单根 identity 拆分。当前白名单是：

```python
BANKS = (
    BankConfig("dental_final", "口腔期末", "30401"),
    BankConfig("clinical_final", "临床期末", "20101"),
    BankConfig("nursing_final", "护理期末", "11070"),
)
```

工作区中可能存在其他历史目录或拼写不同的输出（例如 `clinial_exam`），但未进入上述白名单、客户端默认题库集合或远程清单，因此不能视为当前正式题库。

## 14. 验证结果

本次架构修改已经执行并通过以下验证：

### 14.1 Dart 格式化

```bash
dart format ...
```

结果：通过。

### 14.2 JSON 校验

对 `yibubang_update.json` 执行 Python JSON 解析校验。

结果：通过。

### 14.3 Flutter 测试

```bash
flutter test --no-pub
```

结果：通过。

### 14.4 静态分析

```bash
flutter analyze --no-pub --no-fatal-infos
```

结果：无 error，共 37 条既有 info/lint 提示；这些提示不是本次题库架构修改引入的编译错误。

### 14.5 macOS 构建

```bash
flutter build macos --no-pub
```

结果：构建通过。CocoaPods/Swift Package Manager 迁移提示属于环境提示，不是构建错误。

### 14.6 Git diff 格式检查

```bash
git diff --check
```

结果：通过。

### 14.7 SQLite 产物检查

三套生成 SQLite 已执行：

```sql
PRAGMA integrity_check;
PRAGMA foreign_key_check;
```

结果：三个题库完整性均为 `ok`，外键检查均为空；`manifest.json` 中的题目数、课程数、章节数、关系数和 SHA-256 已与当前产物记录一致。

## 15. 已知限制和后续建议

### 15.1 远程清单需要发布

本地 `yibubang_update.json` 已增加 `question_banks` 多题库字段，但线上：

```text
https://files.melonhu.cn/yibubang/yibubang_update.json
```

是否已经替换为最新文件，取决于最终上传操作。客户端在远程文件不可用时有内置清单 fallback，但正式发布仍应上传最新 JSON。

### 15.2 没有增量更新

当前每次更新下载整个题库 ZIP。优点是校验、回滚和发布简单；题库文件继续增大后，可以再设计带 `base_version`、`patch_url` 和 `patch_hash` 的增量协议，但必须先重建完整 SQLite，再执行同样的 schema、hash 和完整性校验。

### 15.3 自动化测试覆盖有限

当前没有专门覆盖以下场景的自动化 fixture：

- 题库 schema 和关系主键。
- 导入文件的 SQLite hash 识别。
- 官方/非官方题库的 `update_enabled` 行为。
- 下载中断、ZIP hash 错误和 `.bak` 回滚。
- 老用户迁移和旧库回退。
- 同一 `question_id` 跨题库共享状态。

目前依赖生成脚本校验、客户端运行时校验、Flutter 测试、静态分析和构建验证。后续可以补充最小化 SQLite fixture 和 repository 单元测试。

### 15.4 题目 ID 契约仍需生产端持续保证

共享用户状态依赖全局稳定的 `Question.id`：

- 同一道题不能在不同题库中分配不同 ID。
- 不同题目不能复用已有 ID。
- 题目内容修改通常应保留原 ID。
- 题目变成另一道题时应分配新 ID。

当前拆分脚本会复制来源 ID，但不会自动解决来源 ID 冲突、题目去重或语义等价判断；这些仍属于生产数据治理责任。

### 15.5 版本记录需要统一

当前 SQLite `BankMeta.version` 为 `1.0.0`，远程发布清单 `version` 为 `3.0.0`。两者已经由 SQLite hash 比较避免误报，但后续建议明确区分：

```text
schema_version       SQLite 结构兼容版本
content_version      题库内容版本
release_version      ZIP 发布版本
```

同时应将 `MigrationState.to_version` 从初始化时的硬编码 `3` 与当前 `UserDBHelper` version 4 的关系统一，避免运维记录产生歧义。

### 15.6 生产构建仍有人工边界

`spider.py` 获取 JSON、人工整理课程目录、`save_data.py` 导入合并源库、`split_question_banks.py` 拆分输出之间尚未完全变成一个可复现的 CI 发布流程。正式发布前仍应人工确认：

- 根 identity 映射正确。
- 题目和关系数量符合预期。
- 全局 question ID 没有冲突。
- ZIP 和 SQLite hash 已重新计算并同步到远程 JSON。
- 线上 ZIP 内容与 JSON 字段一致。

### 15.7 遗留逻辑应逐步隔离

旧 HomePage 下载函数、`transferData()`、旧合并题库回退和旧页面文件目前为了兼容而保留。后续可以在确认老用户升级稳定后，将它们移到明确的 legacy 层，但不应在没有迁移备份和回滚方案的情况下直接删除。

## 16. 关键文件索引

### 客户端

- `lib/db/database_helper.dart`：用户库 version 4、用户库迁移、当前题库打开和旧库回退。
- `lib/db/question_bank_manager.dart`：独立题库路径、只读打开、schema/完整性/关系校验。
- `lib/db/data_transfer.dart`：统计重建和历史迁移残留函数。
- `lib/db/settings.dart`：用户设置和题库相关偏好。
- `lib/models/question_bank.dart`：题库默认配置、bank_id、图标和目录模型。
- `lib/repositories/question_bank_repository.dart`：题库目录、导入、下载、更新、安装和回滚。
- `lib/screens/question_bank_page.dart`：题库管理页面、Switch、下载/更新按钮和环状进度。
- `lib/screens/identity_list_page.dart`：保留的旧 identity/兼容选择逻辑。
- `lib/screens/choosed_subjects_page.dart`：当前题库课程入口。
- `lib/screens/home_page.dart`：主页和保留的旧下载兼容代码。
- `lib/common/app_strings.dart`：identity 和应用字符串配置。

### 生产端和发布配置

- `docs/yikaobang/src/split_question_banks.py`：按根 identity 拆分独立题库并生成 manifest。
- `docs/yikaobang/src/save_data.py`：从生产 JSON 生成合并源 SQLite。
- `docs/yikaobang/data/question_banks/manifest.json`：当前三套产物的数量、版本、大小和 SQLite hash。
- `yibubang_update.json`：App 更新兼容字段和多题库远程清单。
- `docs/gpt/database_research.md`：旧架构研究记录。
- `docs/gpt/upgrade_database.md`：原始升级计划。
- `docs/gpt/database_updated.md`：本文，最终实现说明。

## 17. 端到端数据流总结

```text
生产 JSON / 合并源库
        │
        ▼
split_question_banks.py
        │
        ├── dental_final.sqlite
        ├── clinical_final.sqlite
        └── nursing_final.sqlite
        │
        ▼
ZIP + ZIP SHA-256 + SQLite SHA-256
        │
        ▼
yibubang_update.json.question_banks.banks
        │
        ▼
QuestionBankRepository
        ├── 下载临时 ZIP
        ├── 校验大小和 ZIP hash
        ├── 解压临时 SQLite
        ├── 校验 BankMeta / schema / integrity / foreign key / counts
        ├── staging + .bak 原子替换
        └── 写入 user_data.QuestionBank
        │
        ▼
QuestionBankDatabaseManager（只读）
        ├── 读取题库内容和 IdentityQuestion 关系
        └── 选择当前 bank_id
        │
        ▼
user_data.sqlite（可写）
        ├── 全局 Question.id 用户状态
        ├── bank_id 维度课程/章节统计
        ├── Activities
        └── 迁移状态和题库目录
```

最终架构满足：

```text
独立题库可以单独下载和更新
题库更新不会覆盖用户数据
同一 question_id 的答案、收藏、斩题状态跨题库共享
课程和章节统计按当前题库隔离
老用户迁移失败时仍有旧合并题库回退
普通手动导入题库默认不参与官方更新
官方内容相同的导入题库可以继续参与官方更新
```
