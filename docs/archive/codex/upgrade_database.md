# yibubang 题库数据库架构升级方案

> 本文基于 `docs/gpt/database_research.md` 的代码调研结果，结合新的产品约束制定升级方案。
>
> 核心产品决策：**题目是跨题库共享的实体，`question_id` 全局唯一且稳定；同一道题出现在多个题库中时，用户只需要作答一次。** 因此，`bank_id` 不能加入用户题目状态的主键。`bank_id` 用于题库目录、独立数据库文件、下载版本和题库维度的课程/章节统计。

## 1. 目标和结论

希望从当前架构：

```text
一个 question_data.sqlite
    ├── 临床医学期末
    ├── 口腔医学期末
    └── 护理学期末
```

升级为：

```text
QuestionBank/
    ├── clinical_final.sqlite
    ├── dental_final.sqlite
    ├── nursing_final.sqlite
    └── dental_license.sqlite
```

同时满足：

1. 新增题库时不必重新下载或替换所有旧题库。
2. 可以在线发现、下载和更新题库。
3. 可以更新单个题库，不影响其他题库。
4. 题目 ID 不变时，用户答案、收藏、斩题和历史记录保持不变。
5. 章节 ID 不变时，题目在章节中的用户进度可以继续使用。
6. 同一道题出现在多个题库时，共享用户状态，不要求重复作答。
7. 现有用户可以尽量无感升级，不强制更换包名。
8. 题库文件和用户数据互相隔离，题库更新不会覆盖用户数据。

**结论：当前架构可以演进到这个目标，但不是只修改 `AppStrings.choosableIdentities` 就能完成。** 需要同时改造题库生成端、客户端数据库访问层、题库下载管理、用户库迁移和题库版本校验。

建议采用“**题库目录 + 每个题库独立 SQLite + 全局共享用户题目状态**”的架构。

## 2. 对当前架构的重新判断

### 2.1 共享题目 ID 是 feature，不是 bug

此前调研中将“用户库题目 ID 没有题库作用域”列为风险，需要根据本次产品决策修正：

当前用户库：

```sql
Question(
  id TEXT PRIMARY KEY,
  chapter_id TEXT,
  chapter_parent_id TEXT,
  cut_question TEXT,
  user_answer TEXT,
  status INTEGER,
  collection INTEGER
)
```

保留 `id` 作为全局主键是正确方向，因为它表达了：

```text
同一 question_id
    = 同一个知识题目
    = 共享同一份用户作答状态
```

例如：

```text
clinical_final.sqlite       Question.id = 123456
medical_license.sqlite      Question.id = 123456
```

如果两条记录代表同一道题，那么用户在临床题库中做过后，切换到资格考试题库时应直接看到已作答状态。

真正需要解决的不是“给用户 Question 加 bank_id”，而是建立并强制执行以下 ID 契约：

- 同一题目必须使用同一个全局 `question_id`。
- 不同题目绝不能复用同一个 `question_id`。
- 同一章节必须使用稳定的全局 `chapter_id`。
- 不同章节不能因为来自不同题库而误用相同的 `chapter_id`。
- 题库中可以重复存储同一个题目，但用户库中只能有一份共享状态。

### 2.2 `bank_id` 应该放在哪里

`bank_id` 应用于：

- 题库目录记录。
- 题库 SQLite 文件名和路径。
- 题库版本、下载地址、文件 hash。
- 题库安装/启用/禁用状态。
- 题库维度的课程和章节统计缓存。
- `Activities` 中记录答题发生在哪个题库上下文。

`bank_id` 不应加入以下共享实体的主键：

- 用户 `Question.id`。
- 全局用户答案历史。
- 全局收藏状态。
- 全局斩题状态。

## 3. 目标物理目录

平台相关的 `getDatabasesPath()` 作为应用数据根目录，建议使用以下结构：

```text
<databasesPath>/
├── user_data.sqlite
├── user_data.sqlite.bak
├── question_banks.sqlite       # 可选：题库目录独立元数据库
└── QuestionBank/
    ├── clinical_final/
    │   ├── clinical_final.sqlite
    │   ├── manifest.json
    │   └── clinical_final.sqlite.bak
    ├── dental_final/
    │   ├── dental_final.sqlite
    │   ├── manifest.json
    │   └── dental_final.sqlite.bak
    ├── nursing_final/
    │   ├── nursing_final.sqlite
    │   ├── manifest.json
    │   └── nursing_final.sqlite.bak
    └── dental_license/
        ├── dental_license.sqlite
        ├── manifest.json
        └── dental_license.sqlite.bak
```

实际实现时，可以不为每个目录保存单独的 `manifest.json`，而只使用远程 manifest 和 `QuestionBank` 表。保留本地 manifest 有助于离线诊断和恢复。

建议正式文件名始终由系统生成，不直接信任远程 ZIP 内文件名：

```text
<databasesPath>/QuestionBank/<bank_id>/<bank_id>.sqlite
```

这样可以避免路径穿越、文件名冲突以及 ZIP 内目录结构不一致的问题。

## 4. 题库目录设计

题库目录是“可安装题库”的索引，不是题目内容本身。可以放在现有 `user_data.sqlite` 中，也可以单独创建 `question_banks.sqlite`。

为了减少连接数量，第一阶段建议放入 `user_data.sqlite`：

```sql
CREATE TABLE IF NOT EXISTS QuestionBank (
    bank_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    local_path TEXT NOT NULL,
    version TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    content_hash TEXT NOT NULL,
    content_size INTEGER NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1,
    is_builtin INTEGER NOT NULL DEFAULT 0,
    install_state TEXT NOT NULL DEFAULT 'installed',
    installed_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    last_error TEXT NOT NULL DEFAULT ''
);
```

推荐的 `install_state`：

```text
available   远程可用但未安装
installing  正在下载或校验
installed   已安装
updating    正在更新
failed      最近一次安装/更新失败
removed     逻辑删除，保留历史信息
```

题库当前选择可以继续存储在 SharedPreferences：

```text
activeBankId = dental_final
```

但不要再只用：

```text
identityId = 30401
```

作为题库选择的唯一依据。identity 是题库内部的专业/学期层级，`bank_id` 才是题库文件和题库产品的唯一标识。

## 5. 每个题库 SQLite 的结构

每个题库文件都应使用同一套 schema，至少包含：

```text
BankMeta
Identity
Subject
Chapter
Question
Comment（可选）
IdentitySubject
IdentityChapter
IdentityQuestion
```

### 5.1 `BankMeta`

每个独立题库文件应包含自身元信息：

```sql
CREATE TABLE IF NOT EXISTS BankMeta (
    bank_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    generated_at INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT ''
);
```

启动时必须验证：

```text
BankMeta.bank_id == 目录中的 bank_id
BankMeta.schema_version <= 当前 App 支持的 schema_version
```

### 5.2 题库内容表

现有 `Identity`、`Subject`、`Chapter`、`Question` 的主要字段可以继续使用，但应明确以下约束：

```text
Question.id              全局稳定题目 ID
Chapter.id               全局稳定章节 ID
Subject.id               全局稳定课程 ID
Identity.id              稳定的专业/学期层级 ID
```

每个题库文件可以复制同一个共享题目：

```text
clinical_final.sqlite:
    Question.id = 123456

 dental_license.sqlite:
    Question.id = 123456
```

两边内容可以相同，也可以因为解析或来源不同而存在非关键展示字段差异，但必须仍然表示同一个 canonical question。

### 5.3 关系表的主键

当前生成端使用：

```sql
IdentityChapter PRIMARY KEY (identity_id, chapter_id)
IdentityQuestion PRIMARY KEY (identity_id, question_id)
```

如果同一个 identity 下一个题目可能出现在多个课程/章节中，建议改为：

```sql
IdentityChapter(
    identity_id TEXT,
    subject_id TEXT,
    chapter_id TEXT,
    total INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identity_id, subject_id, chapter_id)
)
```

```sql
IdentityQuestion(
    identity_id TEXT,
    subject_id TEXT,
    chapter_id TEXT,
    question_id TEXT,
    PRIMARY KEY (identity_id, subject_id, chapter_id, question_id)
)
```

这不会破坏共享题目状态。它只是在题库文件中保存“同一道题出现在哪些上下文”的完整关系；真正的用户状态仍然只有一份。

## 6. 用户库设计：共享状态和题库统计分离

### 6.1 全局共享用户题目状态

保留现有用户题目表的全局主键：

```sql
CREATE TABLE IF NOT EXISTS Question (
    id TEXT PRIMARY KEY,
    cut_question TEXT NOT NULL DEFAULT '',
    user_answer TEXT NOT NULL DEFAULT '',
    status INTEGER NOT NULL DEFAULT 0,
    collection INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
);
```

`chapter_id` 和 `chapter_parent_id` 可以保留用于快速展示，但它们不应被当作用户状态的主键，因为同一题可以出现在多个章节或题库中。更稳定的设计是：

```text
Question.id 保存共享状态
题库文件中的 IdentityQuestion 保存题目出现位置
```

### 6.2 题库维度的课程统计

由于用户题目状态是全局共享的，但课程/章节统计属于某个题库上下文，建议给统计表增加 `bank_id`：

```sql
CREATE TABLE IF NOT EXISTS IdentitySubject (
    bank_id TEXT NOT NULL,
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    correct INTEGER NOT NULL DEFAULT 0,
    incorrect INTEGER NOT NULL DEFAULT 0,
    selected INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bank_id, identity_id, subject_id)
);
```

```sql
CREATE TABLE IF NOT EXISTS IdentityChapter (
    bank_id TEXT NOT NULL,
    identity_id TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    chapter_id TEXT NOT NULL,
    correct INTEGER NOT NULL DEFAULT 0,
    incorrect INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bank_id, identity_id, subject_id, chapter_id)
);
```

这样可以同时满足：

- `Question.id` 全局共享。
- 同一题在多个题库中只做一次。
- 课程/章节页面仍然显示当前题库自己的总题数和统计。
- 不同题库内部即使使用相同 identity/subject ID，也不会污染彼此的统计。

### 6.3 共享题目的统计语义

建议明确采用以下规则：

1. 用户状态是全局的：同一道题的答案、收藏、斩题状态共享。
2. 题库统计是上下文的：当前题库的章节统计由该题库的 `IdentityQuestion` 关系与全局用户 `Question.status` 聚合得到。
3. 用户在题库 A 做过共享题目后，切换到题库 B，题目显示已作答。
4. 题库 B 的统计在重建或读取时，也可以把这道共享题计入 B 的对应章节。
5. 如果共享题目在两个题库中的章节关系不同，两个章节都可以显示同一份用户状态，但统计归属按各自题库关系计算。

推荐将统计作为可重建缓存，而不是只依赖每次答题的增量修改：

```sql
SELECT iq.identity_id,
       iq.subject_id,
       iq.chapter_id,
       SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END) AS correct,
       SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END) AS incorrect
FROM user_data.Question AS uq
JOIN active_bank.IdentityQuestion AS iq
  ON uq.id = iq.question_id
WHERE uq.status IN (1, 2)
GROUP BY iq.identity_id, iq.subject_id, iq.chapter_id;
```

这个逻辑可以保证“共享题目只保存一份状态”，同时“每个题库都能根据自己的关系展示统计”。

## 7. Flutter 代码改造方案

### 7.1 将固定 `DatabaseHelper` 改为题库连接管理器

当前 `DatabaseHelper` 固定打开：

```text
question_data.sqlite
```

目标是增加题库级别的连接管理：

```dart
class QuestionBankDatabaseManager {
  Future<Database> openBank(String bankId);
  Future<void> closeBank(String bankId);
  Future<List<String>> installedBankIds();
}
```

建议在上层封装：

```dart
class QuestionBankRepository {
  final String bankId;

  Future<List<Identity>> getIdentities();
  Future<List<Subject>> getSubjects(String identityId);
  Future<List<Chapter>> getChapters(String identityId, String subjectId);
  Future<List<Question>> getQuestions(String identityId, String subjectId, String chapterId);
}
```

调用从：

```dart
DatabaseHelper().getByRawQuery(...)
```

变成：

```dart
QuestionBankRepository(activeBankId).getQuestions(...)
```

这样页面不需要知道数据库文件路径，也不会把题库目录逻辑散落在页面代码里。

### 7.2 题库选择流程

新增题库列表页面：

```text
QuestionBankListPage
    ├── 已安装题库
    ├── 可下载题库
    ├── 检查更新
    ├── 安装
    ├── 更新
    ├── 删除
    └── 切换当前题库
```

选择题库后：

```text
SharedPreferences['activeBankId'] = bankId
```

页面数据查询全部通过当前 `bankId` 获取；题目状态仍通过全局用户库 `Question.id` 获取。

### 7.3 题目读取

新的读取流程：

```text
activeBankId
    ↓
QuestionBankDatabaseManager.openBank(activeBankId)
    ↓
activeBank.IdentityQuestion + activeBank.Question
    ↓
得到题目 ID 列表
    ↓
user_data.Question WHERE id IN (...)
    ↓
合并题目内容和全局用户状态
```

`getUserQuestions()` 仍然可以按 `id` 批量查询，不需要增加 `bank_id`。

### 7.4 答题写入

答题时：

1. 更新全局用户 `Question`。
2. 写入 `Activities`，带上 `bank_id`、identity、subject、chapter 和 question_id。
3. 重建或更新当前题库的 `IdentitySubject`、`IdentityChapter` 缓存。
4. 不要把同一个共享题目插入多条用户 `Question`。

建议 `Activities` 增加结构化字段，避免只把 JSON 拼接到 `description`：

```sql
ALTER TABLE Activities ADD COLUMN bank_id TEXT;
ALTER TABLE Activities ADD COLUMN question_id TEXT;
ALTER TABLE Activities ADD COLUMN identity_id TEXT;
ALTER TABLE Activities ADD COLUMN subject_id TEXT;
ALTER TABLE Activities ADD COLUMN chapter_id TEXT;
ALTER TABLE Activities ADD COLUMN is_right INTEGER;
```

旧的 `description` 可以继续保留，用于兼容历史记录。

### 7.5 统计重建

将当前 `rebuildQuestionCount()` 从“只 attach 一个固定 qbank”改为：

```dart
Future<void> rebuildQuestionCount(String bankId)
```

实现方式有两种：

#### 方案 A：每次只 attach 当前题库

```sql
ATTACH DATABASE '<bankPath>' AS qbank;
```

按当前 bank_id 清零并重建统计，完成后 detach。

#### 方案 B：通过 Dart 读取关系后批量写入

对于桌面、Web 或多数据库连接限制较多的平台，先从题库文件查询关系，再在用户库事务中批量更新。

推荐优先使用方案 A，但要确保：

- attach 路径来自本地已校验的题库目录。
- 事务内不 detach。
- 只更新当前 `bank_id` 的统计。
- 题库切换后可重算目标题库。

## 8. 在线题库清单和更新协议

当前 `yibubang_update.json` 是按 App 版本组织的：

```text
data_for_version[appVersion] -> 一个 ZIP
```

应改为独立题库 manifest，例如：

```json
{
  "manifest_version": 1,
  "min_app_version": "2.1.0",
  "banks": [
    {
      "bank_id": "clinical_final",
      "name": "临床医学期末",
      "version": "2026.01",
      "schema_version": 2,
      "url": "https://example.com/banks/clinical_final-2026.01.zip",
      "sha256": "...",
      "size": 123456789,
      "required": true,
      "description": "临床医学期末题库"
    },
    {
      "bank_id": "dental_license",
      "name": "口腔执业资格考试",
      "version": "2026.01",
      "schema_version": 2,
      "url": "https://example.com/banks/dental_license-2026.01.zip",
      "sha256": "...",
      "size": 98765432,
      "required": false,
      "description": "口腔执业资格考试题库"
    }
  ]
}
```

### 8.1 下载新题库

启动或用户打开题库管理页时：

```text
下载 manifest
    ↓
比较本地 QuestionBank.bank_id/version
    ↓
发现未安装的 bank_id
    ↓
显示“可安装”
    ↓
用户确认
    ↓
下载独立 ZIP
    ↓
校验 hash、大小、schema、BankMeta
    ↓
安装到 QuestionBank/<bank_id>/
    ↓
写入 QuestionBank 目录表
```

### 8.2 更新旧题库

更新必须采用临时目录和原子替换：

```text
<bank_id>.zip.partial
        ↓ 下载完成
校验 ZIP SHA-256
        ↓
解压到 <bank_id>.staging/
        ↓
校验 sqlite 文件、schema、BankMeta、完整性
        ↓
旧文件改名为 <bank_id>.bak
        ↓
staging 原子替换为正式目录
        ↓
更新 QuestionBank.version
```

如果校验或替换失败，保留旧题库继续运行，不应让用户失去已经安装的题库。

### 8.3 是否需要升级 App

如果新题库只增加/修改内容，且 `schema_version` 不超过当前 App 支持范围：

```text
不需要升级 App
只需要更新 manifest 和题库文件
```

如果题库 schema 改变，例如增加客户端无法识别的字段或关系：

```text
先发布兼容新 schema 的 App
再发布新题库
```

manifest 中的 `min_app_version` 用于避免旧 App 下载无法读取的题库。

### 8.4 增量更新

第一阶段建议只做“单题库完整文件替换”，不要一开始实现 SQLite 增量 patch：

- 实现简单。
- 容易校验。
- 失败后容易回滚。
- 适合题库数量较少的场景。

题库文件很大且更新频繁时，再增加：

```text
base_version
patch_url
patch_hash
```

增量包必须在应用端重建出完整 SQLite 后再校验，不能直接把不完整 patch 当题库打开。

## 9. yikaobang 生产端改造

### 9.1 从硬编码改为题库配置

当前 `save_data.py` 使用固定路径和固定目录：

```python
working_dir = '/Users/huzongyao/ReverseProjects/yikaobang'
read_json_files(...口腔医学期末..., 30401)
read_json_files(...临床医学期末..., 20101)
read_json_files(...护理学期末..., 11070)
```

建议改成配置驱动：

```yaml
banks:
  - bank_id: clinical_final
    name: 临床医学期末
    identity_id: "20101"
    source_path: resource/临床医学期末
    output_path: dist/clinical_final.sqlite

  - bank_id: dental_final
    name: 口腔医学期末
    identity_id: "30401"
    source_path: resource/口腔医学期末
    output_path: dist/dental_final.sqlite

  - bank_id: nursing_final
    name: 护理学期末
    identity_id: "11070"
    source_path: resource/护理学期末
    output_path: dist/nursing_final.sqlite

  - bank_id: dental_license
    name: 口腔执业资格考试
    identity_id: "40001"
    source_path: resource/口腔执业资格考试
    output_path: dist/dental_license.sqlite
```

每次构建输出一个独立 SQLite 文件，并生成：

```text
bank_id
version
schema_version
question_count
subject_count
chapter_count
sha256
```

### 9.2 不同来源需要导入适配器

如果“口腔执业资格考试”也来自医考帮 API，可以复用现有：

```text
login
get_subjects
get_chapters
get_question_list
DES_decode
```

如果来源是其他 API、Excel、PDF、JSON 或人工录入，则不能直接复用 `spider.py` 的响应解析逻辑，需要统一转换为标准题目模型：

```text
外部来源
    ↓
SourceQuestion
    ↓ 标准化/ID 映射
CanonicalQuestion
    ↓
save_data.py
    ↓
独立题库 SQLite
```

标准化过程必须负责：

- 分配或读取稳定的 `question_id`。
- 分配或读取稳定的 `chapter_id`。
- 识别与已有题库相同的题目。
- 维护来源题目 ID 到全局题目 ID 的映射。
- 禁止重复分配已存在的 ID。

### 9.3 ID 不变规则

题库管理必须把 ID 当作公开数据契约，而不是数据库自增临时值。

#### 题目

```text
如果只是修改题干、解析、选项格式或来源说明：保留 question_id
如果只是修改章节归属：保留 question_id，更新 IdentityQuestion
如果题目被删除：标记 deprecated，不立即复用 ID
如果题目变成另一道题：新建 question_id
```

#### 章节

```text
如果只是修改章节名称：保留 chapter_id
如果章节内题目增删：保留 chapter_id
如果章节移动到其他课程：保留 chapter_id，更新关系
如果章节含义发生根本变化：新建 chapter_id，旧章节标记 deprecated
```

#### 共享题目识别

优先使用来源稳定 ID；来源 ID 不稳定时，可以使用标准化内容指纹辅助匹配：

```text
question_key = hash(
  normalized_title +
  normalized_options +
  normalized_answer
)
```

内容指纹只能作为辅助，不能在没有人工审核的情况下自动覆盖已有题目 ID，因为题目解析或选项格式变化可能导致指纹变化。

## 10. 旧版本兼容升级方案

### 10.1 建议保持原包名

如果希望兼容现有用户，建议保持原来的 Android application ID、iOS bundle identifier、Windows/Linux/macOS 应用标识和数据目录。

保持原包名时，系统通常会保留原应用沙盒中的：

```text
user_data.sqlite
question_data.sqlite
```

改包名会让系统认为这是一个全新的应用：

- 新 App 通常拿不到旧沙盒目录。
- 旧用户数据不会自动迁移。
- 需要用户手动导出/导入，或自行实现跨应用复制方案。

因此，**改包名并不能简化兼容升级，通常会使数据迁移更困难。** 只有在准备放弃旧用户数据、或旧包名已经无法继续发布时，才考虑改包名。

### 10.2 迁移前备份

首次启动新版本时，先检查：

```text
旧 question_data.sqlite 是否存在
旧 user_data.sqlite 是否存在
新 QuestionBank/ 是否已经完成迁移
```

迁移前复制：

```text
question_data.sqlite -> migration_backup/question_data.sqlite
user_data.sqlite     -> migration_backup/user_data.sqlite
```

备份目录应包含迁移版本和时间戳。迁移失败时保留旧文件，不删除用户数据。

### 10.3 旧题库拆分

旧版本是一个合并的 `question_data.sqlite`。可以根据配置的根 identity 将它拆分成独立题库。

例如：

```text
20101 -> clinical_final
30401 -> dental_final
11070 -> nursing_final
```

拆分流程：

1. 读取旧 `Identity` 树。
2. 根据根 identity 建立 bank_id 映射。
3. 为每个 bank 创建新的 SQLite 文件。
4. 复制该 bank 需要的 `Identity` 树。
5. 复制对应的 `IdentitySubject`、`IdentityChapter`、`IdentityQuestion`。
6. 根据关系表收集需要的 Subject、Chapter、Question。
7. 复制对应 Comment（如果需要）。
8. 写入新的 `BankMeta`。
9. 执行 schema 检查和 `PRAGMA integrity_check`。
10. 将新文件登记到 `QuestionBank` 表。

共享题目会被复制到多个题库文件中，但仍然使用同一个 `Question.id`。用户库不复制多份状态。

### 10.4 拆分失败时的兼容策略

如果旧数据库缺少明确的 identity 映射，或者数据关系无法安全拆分：

1. 保留旧的合并库，例如：

   ```text
   QuestionBank/legacy_combined/legacy_question_data.sqlite
   ```

2. 将它注册为一个特殊的 `legacy_combined` 题库。
3. 新架构仍然使用旧用户库。
4. 提示用户可以稍后重新下载或重新拆分。
5. 不删除旧库，直到所有新题库验证完成。

这样不会因为迁移失败而导致用户无法继续刷题。

### 10.5 旧用户库迁移

现有用户库中的 `Question.id` 已经是全局主键，因此可以直接保留：

```text
旧 user_data.Question
        ↓
新 user_data.Question
```

这会自然保留：

- 作答状态。
- 历史答案。
- 收藏。
- 斩题状态。

需要迁移的部分主要是：

- 新增 `QuestionBank` 目录表。
- 用户课程/章节统计表增加 `bank_id`。
- `Activities` 增加结构化题库和题目字段。
- 依据新题库关系重建统计。

旧的 `IdentitySubject` 和 `IdentityChapter` 统计不建议直接相信，因为旧版本存在累计误差、章节主键不完整和关系结构变化问题。迁移后应使用：

```text
旧用户 Question.status
    JOIN
新题库 IdentityQuestion
    ↓
按每个 bank_id 全量重建统计
```

### 10.6 SQLite 版本迁移

当前 `UserDBHelper` 使用 `version: 1`，没有完整的 `onUpgrade` 流程。升级时应改为明确版本：

```text
version 1：当前旧用户库
version 2：增加 QuestionBank 目录和 bank_id 统计字段
version 3：Activities 结构化字段、迁移标记和索引
```

示例迁移顺序：

```dart
openDatabase(
  path,
  version: 3,
  onCreate: createUserSchema,
  onUpgrade: migrateUserSchema,
);
```

每个迁移必须：

- 可重复检测。
- 使用事务。
- 迁移失败可报告具体步骤。
- 不删除原始用户字段，除非已经完成备份。
- 迁移完成后写入 schema 版本。

## 11. 迁移状态机和回滚

建议增加迁移状态表：

```sql
CREATE TABLE IF NOT EXISTS MigrationState (
    migration_id TEXT PRIMARY KEY,
    from_version INTEGER NOT NULL,
    to_version INTEGER NOT NULL,
    state TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    finished_at INTEGER NOT NULL DEFAULT 0,
    error TEXT NOT NULL DEFAULT ''
);
```

状态：

```text
not_started
running
validated
completed
failed
rolled_back
```

启动流程：

```text
检测旧数据
    ↓
创建备份
    ↓
写入 running
    ↓
升级 user_data schema
    ↓
拆分/导入题库
    ↓
验证文件、ID、关系、统计
    ↓
写入 completed
    ↓
删除过期临时文件
```

任何步骤失败：

```text
停止使用新文件
    ↓
恢复旧文件或继续使用 legacy_combined
    ↓
写入 failed/rolled_back
    ↓
保留错误日志和备份
```

## 12. 兼容性结论

### 12.1 是否可以兼容现有用户

**可以，建议保持原包名，并通过应用内迁移完成。**

现有用户数据最有价值的部分是 `user_data.Question`，而它本身已经使用全局 `question_id`，与共享题目设计天然兼容。

最大的迁移工作是：

- 将旧合并题库拆分为多个文件。
- 建立题库目录。
- 将旧统计按题库重新计算。
- 让 Flutter 从固定 `DatabaseHelper` 改为按 `bank_id` 打开题库。

### 12.2 是否必须改包名

**不建议为了数据库升级而改包名。**

改包名不会自动解决 schema 迁移问题，反而会导致新旧应用使用不同数据目录。如果改包名，必须额外提供：

```text
旧应用导出数据
    ↓
文件/云端传输
    ↓
新应用导入数据
```

只有在不要求保留旧用户本地数据时，才可以考虑改包名作为一次性破坏性升级。

### 12.3 旧版 App 的行为

旧版 App 只认识：

```text
question_data.sqlite
```

它不会认识新题库目录和 manifest。新版本可以保留一个兼容层：

- 首次迁移期间继续提供旧 `question_data.sqlite`。
- 新题库全部验证成功后，再将旧库标记为 legacy。
- 新版不再把新题库合并回旧单文件。

不建议让新旧 App 同时写同一个题库文件；旧 App 只读题库，理论上风险较低，但更新/替换时仍应避免文件竞争。

## 13. 分阶段实施计划

### 阶段 0：冻结数据契约

目标：先保证共享题目语义成立。

工作：

1. 建立全局 `question_id` 注册表。
2. 建立全局 `chapter_id` 注册表。
3. 明确 ID 永不复用规则。
4. 明确题目从一个章节移动到另一个章节时只更新关系、不改题目 ID。
5. 增加题库构建校验脚本。

交付标准：

```text
同一道题在所有题库中 question_id 相同
不同题目不会复用 question_id
章节迁移不改变 chapter_id
```

### 阶段 1：改造 yikaobang 生成端

工作：

1. `save_data.py` 改为配置驱动。
2. 每个题库独立输出 SQLite。
3. 生成 `BankMeta`。
4. 生成题库统计和 hash。
5. 修正关系表主键。
6. 支持外部来源导入适配器。
7. 生成在线 manifest。

交付文件示例：

```text
dist/clinical_final.sqlite
 dist/dental_final.sqlite
 dist/nursing_final.sqlite
 dist/dental_license.sqlite
 banks-manifest.json
```

### 阶段 2：改造 Flutter 用户库

工作：

1. 增加 `QuestionBank` 表。
2. 增加 SQLite schema migration。
3. 保持用户 `Question.id` 全局主键。
4. 为课程/章节统计增加 `bank_id`。
5. 增加 `Activities` 结构化字段。
6. 重写 `rebuildQuestionCount(bankId)`。
7. 增加迁移状态和备份。

### 阶段 3：改造题库访问层

工作：

1. 新增 `QuestionBankDatabaseManager`。
2. 新增 `QuestionBankRepository`。
3. 去掉页面对固定 `question_data.sqlite` 的依赖。
4. 所有课程、章节、题目查询带上当前 `bank_id` 的数据库连接。
5. 用户题目状态仍然只按全局 `question_id` 查询。
6. 清理 `transferData()` 和旧 `checkTransferScuess()`。

### 阶段 4：改造题库管理和下载

工作：

1. manifest 下载。
2. 题库清单页面。
3. 独立安装。
4. 独立更新。
5. 删除/禁用题库。
6. ZIP hash、SQLite integrity、schema 和 BankMeta 校验。
7. staging 目录和原子替换。
8. 失败回滚。

### 阶段 5：兼容迁移发布

工作：

1. 保持原包名。
2. 首次启动检测旧库。
3. 备份旧数据库。
4. 拆分旧 `question_data.sqlite`。
5. 迁移 user_data schema。
6. 重建每个题库的统计。
7. 验证共享题目状态。
8. 逐步删除 legacy 代码。

## 14. 必须覆盖的验证场景

### 14.1 共享题目

```text
题库 A 和题库 B 都包含 question_id=100
在 A 作答
切换到 B
B 中 question_id=100 必须显示同样的答案和状态
```

### 14.2 题库独立更新

```text
更新 clinical_final
dental_final 的文件、版本和用户状态不受影响
```

### 14.3 新题库安装

```text
首次安装 dental_license
已有三个题库仍可正常使用
新题库无需重新下载其他题库
```

### 14.4 章节稳定性

```text
章节名称修改但 chapter_id 不变
用户进度仍然存在
```

### 14.5 题目章节迁移

```text
题目从 chapter_A 移到 chapter_B
question_id 不变
全局用户状态不丢失
统计重建后出现在 chapter_B
```

### 14.6 题库更新失败

```text
下载中断或 hash 错误
旧题库仍然可以打开
QuestionBank.install_state=failed
用户数据不受影响
```

### 14.7 旧版升级

```text
旧 question_data.sqlite 存在
旧 user_data.sqlite 存在
新版本首次启动
迁移失败时旧库仍可恢复
迁移成功后历史答案、收藏、斩题保持不变
```

## 15. 风险和需要提前决定的问题

1. **共享题目的定义必须稳定。** 如果两个题目只是题干相似但答案或考查知识点不同，不能复用同一个 `question_id`。
2. **题目状态是全局还是上下文相关，需要保持统一。** 本方案选择全局共享，符合“一道题只做一次”的产品目标。
3. **统计是否跨题库共享，需要产品确认。** 本方案建议状态全局共享、统计按题库上下文分别聚合。
4. **题目内容更新不能覆盖用户状态。** 题库更新只替换题库库，不能写入用户库 `Question`。
5. **ID 不变必须由生产端工具强制检查。** 不能只依靠人工约定。
6. **旧数据库拆分需要 identity 映射。** 如果历史数据库没有明确边界，应保留 legacy 合并库作为回退。
7. **不能用 `INSERT OR REPLACE` 无条件覆盖题目。** 生成端应区分新增、内容更新、关系更新和废弃。
8. **题库数据库必须只读打开。** 下载更新通过临时文件和原子替换完成，不能在 App 使用过程中修改正式文件。
9. **题库 manifest 必须校验。** 至少校验 `bank_id`、版本、schema、大小、SHA-256、BankMeta 和 SQLite integrity。
10. **改包名会损害兼容性。** 如果保留用户数据是目标，应保持原包名和数据目录。

## 16. 最终推荐架构

```text
QuestionBank catalog（user_data.sqlite 或独立元数据库）
│
├── bank_id: clinical_final
│     └── QuestionBank/clinical_final/clinical_final.sqlite
│
├── bank_id: dental_final
│     └── QuestionBank/dental_final/dental_final.sqlite
│
├── bank_id: nursing_final
│     └── QuestionBank/nursing_final/nursing_final.sqlite
│
└── bank_id: dental_license
      └── QuestionBank/dental_license/dental_license.sqlite

user_data.sqlite
│
├── Question
│     └── id 为全局共享 question_id
│
├── IdentitySubject
│     └── bank_id + identity_id + subject_id
│
├── IdentityChapter
│     └── bank_id + identity_id + subject_id + chapter_id
│
├── Activities
│     └── 记录 bank_id 和 question_id
│
└── MigrationState
```

数据读取关系：

```text
当前 bank_id
    ↓
独立题库 SQLite
    ├── Question 内容
    ├── IdentityQuestion 出现关系
    └── Subject/Chapter 总数

全局 question_id
    ↓
user_data.Question
    ├── user_answer
    ├── status
    ├── collection
    └── cut_question

题库关系 + 全局用户状态
    ↓
当前题库的课程/章节统计
```

最终可以实现：

```text
临床医学期末、口腔医学期末、护理学期末、口腔执业资格考试
可以分别安装、分别更新、分别删除

同一道题如果 question_id 相同
用户只作答一次
切换题库后状态继续保留
```

## 17. 相关现有代码和研究依据

本方案直接基于以下现有代码：

- `docs/gpt/database_research.md`
- `docs/yikaobang/src/spider.py`
- `docs/yikaobang/src/save_data.py`
- `docs/yikaobang/README.md`
- `lib/db/database_helper.dart`
- `lib/db/data_transfer.dart`
- `lib/db/settings.dart`
- `lib/models/identity.dart`
- `lib/models/subject.dart`
- `lib/models/chapter.dart`
- `lib/models/question.dart`
- `lib/screens/home_page.dart`
- `lib/screens/identity_list_page.dart`
- `lib/screens/subjects_list_page.dart`
- `lib/screens/question_grid_page.dart`
- `lib/screens/question_detail_page.dart`
- `lib/common/app_strings.dart`
- `yibubang_update.json`

当前没有实际 SQLite/ZIP 产物，因此具体迁移脚本实施前还需要使用真实发布数据库进行一次：

```text
schema 检查
identity 映射检查
question_id 重复/共享检查
chapter_id 稳定性检查
用户状态迁移演练
PRAGMA integrity_check
```
