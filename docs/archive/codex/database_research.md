# yibubang / yikaobang 数据库研究

> 研究范围：当前工作区根目录 `./`（yibubang）及 `./docs/yikaobang/` 的源码、脚本、配置和说明文档。
>
> 研究时间：2026-08-11。
>
> 重要限制：当前工作区没有实际的 `question_data.sqlite`、`user_data.sqlite` 或题库 ZIP 产物；`docs/yikaobang/src/*.py` 中的工作目录指向工作区外的 `/Users/huzongyao/ReverseProjects/yikaobang`。因此本文对最终发布数据库的判断，主要依据生成脚本、Flutter 查询语句和版本发布配置，未能直接对远程 ZIP 做 SQLite schema 实测。

## 1. 结论摘要

两个项目之间不是运行时直接连接，而是一个离线生产、远程发布、客户端下载的流水线：

```text
医考帮 API
   │  spider.py：登录、签名、获取 identity/章节/题目、DES 解密、JSON 清洗
   ▼
按 identity/课程/章节组织的 JSON
   │  人工移动/合并目录
   ▼
save_data.py：建表、导入 identity、课程、章节、题目、关系
   ▼
question_data.sqlite
   │  压缩、发布；yibubang_update.json 提供 URL + ZIP MD5
   ▼
yibubang HomePage：运行时下载 ZIP 并解压到 sqflite 数据库目录
   ▼
question_data.sqlite（只读题库库） + user_data.sqlite（可写用户库）
```

yibubang 的实际数据库模型是：

- **`question_data.sqlite`：题库主库，只读。** 存 identity 树、Subject、Chapter、完整 Question、IdentityQuestion 关系、题库总数，以及可选的 Comment。题干、选项、正确答案、解析和图片 URL 都在这里。
- **`user_data.sqlite`：用户状态库，可写。** 存题目作答状态、历史答案、收藏、斩题、课程/章节正确错误计数、课程选择状态和 Activities。它不复制完整题干。
- **`SharedPreferences`：轻量设置和会话存储。** 存当前 identity、筛选/模式、上次题目位置、登录凭据、重算标记等，不是 SQLite 的替代品，但参与数据库选择和业务流程。

应用读取题目时以题库库为准，再以题目 ID 到用户库补充或懒初始化状态；应用修改时原则上只修改用户库，题库库不应被写入。

当前没有发现真正运行中的题库全文搜索、随机抽题或答题上传逻辑。课程搜索是已加载课程名称后的内存 `contains` 过滤，章节内题目按 `q.id` 顺序读取。

## 2. 代码范围和主要入口

### 2.1 yibubang Flutter 应用

| 层次 | 文件 | 作用 |
| --- | --- | --- |
| 应用入口 | `lib/main.dart` | 初始化 Flutter、sqflite 平台实现和 SharedPreferences，进入 `HomePage` |
| 题库交付 | `lib/screens/home_page.dart` | 读取版本配置，检查/下载 ZIP，解压 `question_data.sqlite`，触发统计重算 |
| 数据库辅助层 | `lib/db/database_helper.dart` | `DatabaseHelper` 打开只读题库库；`UserDBHelper` 打开/创建用户库；定义用户库 schema |
| 统计/遗留迁移 | `lib/db/data_transfer.dart` | `rebuildQuestionCount()` 是当前可用的跨库重算；`transferData()` 是已过时且没有调用点的迁移方案 |
| 设置 | `lib/db/settings.dart` | 初始化 identity、筛选、模式、上次位置、上传开关、重算标记和登录信息 |
| identity 查询 | `lib/models/identity.dart` | 查询题库 `Identity` 树 |
| 课程查询 | `lib/models/subject.dart` | 合并题库课程/总数与用户库选择/正确错误统计 |
| 章节查询 | `lib/models/chapter.dart` | 合并题库章节/总数与用户库正确错误统计 |
| 题目查询/修改 | `lib/models/question.dart` | 读取章节题目、懒初始化用户题目、简单状态更新、答题统计更新 |
| 题目列表 | `lib/screens/question_grid_page.dart` | 按用户状态、收藏、斩题和题型在内存筛选；批量重做 |
| 题目详情 | `lib/screens/question_detail_page.dart` | 展示题目、解析和远程统计；提交答案、收藏、斩题 |
| 课程选择 | `lib/screens/subjects_list_page.dart` | 内存搜索课程名称并更新用户库 `selected` |
| 题库选择 | `lib/screens/identity_list_page.dart` | 查询 identity 树并将当前 identity 写入 SharedPreferences |
| 网络接口 | `lib/common/request.dart` | 登录、评论/统计等 API 的通用请求；不执行本地 SQLite 题库生成 |
| 加密/签名 | `lib/common/ykb_encrypt.dart` | API 请求签名、密码 MD5、客户端侧 DES 解密实现 |
| 远程/本地设置 | `lib/common/app_strings.dart` | 可选择题库 ID、筛选项和模式列表 |

`lib/services/` 当前没有参与数据库流程的服务实现。数据库访问主要集中在 `lib/db` 和 `lib/models`，不是独立的 Repository/DAO 层。

### 2.2 docs/yikaobang 题库生产工具

| 文件 | 作用 |
| --- | --- |
| `docs/yikaobang/src/encrypt.py` | API 时间戳、密码 MD5、DES-CBC 解密和签名 |
| `docs/yikaobang/src/spider.py` | 登录、获取 identity/课程章节、获取题目、解密清洗并写 JSON；还包含未接入主流程的评论导入和答题上传函数 |
| `docs/yikaobang/src/save_data.py` | 创建 SQLite schema，将 JSON 导入 `question_data.sqlite` |
| `docs/yikaobang/README.md` | 说明先爬 JSON、再人工整理目录、最后导入 SQLite 的两阶段流程 |
| `docs/yikaobang/.gitignore` | 忽略 SQLite、缓存和本地配置等文件 |

## 3. yikaobang：从 API 到 SQLite

### 3.1 认证、签名和通用请求

`docs/yikaobang/src/spider.py` 的 `basic_req()` 负责所有 API 请求：

1. 使用 `get_timestamp()` 生成秒级时间戳。
2. 登录后将 `token`、`secret`、`user_id` 注入请求参数。
3. 缺少 `app_id` 时默认填入 `1`。
4. 设置 Android 客户端请求头，包括 `timestamp`、`signature`、`uuid`、`app-version`、`channel` 和 `app-type`。
5. 使用 `POST` 或 `GET` 调用 `https://api.yikaobang.com.cn/index.php`，解析 JSON 返回值。

`login()` 调 `/User/Main/login`。密码在本地先通过 `encrypt.py:encrpyt_pswd()` 做 MD5，随后把响应中的 token、secret、user ID 等写入 Python 全局变量。

签名实现位于 `encrypt.py:get_signature()`：将参数按 key 排序并拼接，再与 `app_id`、时间戳组合，先 MD5，再追加固定字符串并 SHA-1。客户端对应实现位于 `lib/common/ykb_encrypt.dart:getSignature()`，实际请求封装在 `lib/common/request.dart:basicReq()`。

风险：爬虫脚本和 Flutter 客户端都包含固定设备标识、签名常量和 API 相关常量；爬虫还会打印登录返回的凭据。生产使用时应避免把真实账号凭据或有效令牌写入源码、日志或研究文档。

### 3.2 获取 identity、课程和章节树

`get_subjects()` 调用 `/allQuestion/question/subjectV2`，返回专业/学期层级树。

`save_all_identities(parent, root_dir, depth, cached)` 递归处理这棵树：

- 根节点下每个 child 建立 `<identity_id>_<title>` 目录。
- 中间节点继续按相同规则建立目录。
- 叶节点跳过 identity `0`（自主组题）。
- 叶节点根据 API 返回的 `category`、`am_pm`、`app_id`、`module_type` 等参数调用 `/allquestion/question/chapter`。
- 章节列表响应保存为叶节点目录下的 `<identity_id>_<title>.json`。
- `cached=True` 时，如果该 JSON 已存在且可解析，则不再重复请求章节列表。

因此 identity JSON 和题目 JSON 的目录结构保留了 API 的层级关系，后续 `save_data.py` 可以递归导入 identity。

### 3.3 当前实际爬取范围

`spider.py` 中有一个 identity 白名单。源码当前只启用了：

```python
'110505'
```

口腔、临床、护理、药学等其他课程组在当前工作区代码中都是注释项。README 说明可以手动取消注释，例如口腔期末的 `304010` 到 `304013`、临床期末的 `201010` 到 `201013`、护理期末的 `110701` 到 `110704`。

这意味着：

- README 描述的是可配置的爬取能力，不代表当前源码每次运行会爬取全量专业。
- yibubang 支持的 identity 是 `20101`、`30401`、`11070`（见 `lib/common/app_strings.dart`），与当前爬虫白名单的 `110505` 不是同一层级/同一个 ID。
- 最终数据库是否包含应用支持的题库，取决于运行爬虫时实际启用的 identity，以及后续人工目录合并步骤。

### 3.4 获取、解密和清洗题目

`save_question_data()` 对章节树逐层处理：

1. 从章节节点读取 `identity_id`、`chapter_id`、标题及请求参数。
2. 调用 `/allquestion/question/list`。
3. 对响应中的 `data` 使用 `DES_decode()` 解密。
4. 删除控制字符。
5. 使用正则修复疑似未转义的双引号和非法反斜杠。
6. 找到第一个 `[`，将其包装为 `{"questionList": [...]}`。
7. 删除 surrogate 字符后通过 `json.loads()` 解析。
8. 按 `<subject_id>_<subject_title>/<chapter_id>_<chapter_title>.json` 保存。

`encrypt.py:DES_decode()` 的配置是：

- Base64 解码密文。
- DES-CBC。
- key 为 `de158b87` 的 8 字节前缀。
- IV 为 `12345678` 的 8 字节前缀。
- 去除 PKCS 填充并按 UTF-8/转义规则转换为字符串。

清洗逻辑是启发式修复，不是严格协议解析。可能的问题包括：找不到 JSON 起始数组时生成无效内容；引号/反斜杠替换可能改变原题干；解析异常处理不完整；原始响应中出现异常 Unicode 时可能丢失字符。爬虫先保存 JSON，而不是在抓取时直接写 SQLite，这使得抓取和导库可以分开重试，但也引入了人工目录管理步骤。

### 3.5 SQLite schema 生成

`docs/yikaobang/src/save_data.py:create_tables()` 创建以下表。

#### 3.5.1 `Identity`

```sql
Identity(
  id TEXT PRIMARY KEY,
  parent_id TEXT REFERENCES Identity(id),
  name TEXT NOT NULL
)
```

表示专业/学期等 identity 树。`insert_identities(root, parent_id)` 递归读取 `resource/identities` 下的目录名，将目录名按第一个下划线分成 ID 和名称，并用 `INSERT OR REPLACE` 写入；identity `0` 被排除。

#### 3.5.2 `Subject` 和 `Chapter`

```sql
Subject(id TEXT PRIMARY KEY, name TEXT NOT NULL)
Chapter(id TEXT PRIMARY KEY, name TEXT NOT NULL)
```

两张表是课程和章节字典。`Chapter` 本身没有 `subject_id` 列，课程归属由 `IdentityChapter.subject_id` 和题目的 `chapter_parent_id` 表达。

#### 3.5.3 `Question`

题库题目表的主键是全局 `id`，主要字段如下：

| 类别 | 字段 |
| --- | --- |
| 标识/排序 | `id`、`year`、`unit`、`number`、`public_number`、`sort`、`created_at` |
| 题目内容 | `title`、`public_title`、`option`、`answer` |
| 解析内容 | `restore`、`restore_img`、`explain`、`explain_img` |
| 图片/来源 | `title_img`、`source`、`source_filter` |
| 题库归属 | `native_app_id`、`native_identity_id`、`app_id`、`identity_id`、`chapter_id`、`chapter_parent_id` |
| 题型/分类 | `type`、`type_str`、`origin_type`、`filter_type`、`am_pm` |
| 章节/考点排序 | `part_id`、`part_parent_id`、`sort_chapter*`、`sort_part*`、`outlines*`、`outlines_mastery` |
| 标志位 | `high_frequency`、`is_collection_question`、`is_real_question`、`is_new` |
| 病例 | `cases_id`、`cases_parent_id`、`sort_cases*` |
| 用户状态遗留字段 | `cut_question`、`user_answer` |

外键声明为 `chapter_id -> Chapter(id)`、`chapter_parent_id -> Subject(id)`。所有字段实际使用 SQLite 的 TEXT 类型；题库脚本不额外校验字段类型。

`option` 在 JSON 中是数组，导入时通过 `json.dumps(q['option'])` 变成 JSON 字符串。Flutter 读取后仍将它作为字符串，在 `QuestionDetailPage._getOptionJson()` 中再次 `json.decode()`。

#### 3.5.4 `Comment`

`Comment` 是一个包含大量用户、评论、回复、点赞、时间和展示字段的表，`obj_id` 外键指向 `Question(id)`。但 `create_tables()` 只创建表，主入口没有调用评论导入；评论导入逻辑位于 `spider.py:update_question_comments()`，属于可选/独立操作。

运行时 Flutter 的评论页面实际通过 `/Comment/Main/list` 远程读取，而不是查询题库 `Comment` 表。

#### 3.5.5 三张关系表

```sql
IdentitySubject(
  identity_id TEXT,
  subject_id TEXT,
  total INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (identity_id, subject_id)
)

IdentityChapter(
  identity_id TEXT,
  subject_id TEXT,
  chapter_id TEXT,
  total INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (identity_id, chapter_id)
)

IdentityQuestion(
  identity_id TEXT,
  subject_id TEXT,
  chapter_id TEXT,
  question_id TEXT,
  PRIMARY KEY (identity_id, question_id)
)
```

关系含义：

```text
Identity ──< IdentitySubject >── Subject
Identity ──< IdentityChapter >── Subject + Chapter
Identity ──< IdentityQuestion >── Subject + Chapter + Question
```

`IdentityQuestion` 插入后由 `update_identity_totals` 触发器给对应的 `IdentitySubject.total` 和 `IdentityChapter.total` 各加 1。

需要特别注意两个主键设计：

- `IdentityChapter` 的主键是 `(identity_id, chapter_id)`，没有包含 `subject_id`。
- `IdentityQuestion` 的主键是 `(identity_id, question_id)`，同一个题目在同一 identity 下只能保留一条关系，即使它出现在多个课程/章节中。

### 3.6 JSON 导入 SQLite

`read_json_files(question_path, identity_id)` 遍历课程目录和章节 JSON：

1. 从目录名 `<subject_id>_<subject_name>` 解析课程 ID/名称。
2. 从文件名 `<chapter_id>_<chapter_name>.json` 解析章节 ID/名称。
3. 对每道题断言 `chapter_id == q['chapter_id']` 和 `subject_id == q['chapter_parent_id']`。
4. 将题目包装为带课程、章节和 identity 的批次。
5. 调用 `insert_questions_batch()`。

`insert_questions_batch()` 的写入顺序是：

1. `INSERT OR IGNORE Subject`。
2. `INSERT OR IGNORE Chapter`。
3. `INSERT OR IGNORE IdentitySubject`。
4. `INSERT OR IGNORE IdentityChapter`。
5. `INSERT OR IGNORE IdentityQuestion`。
6. `INSERT OR REPLACE Question`。

这会带来两个结果：

- 关系数据保留了题目与多个 identity 的关联（受关系表主键限制）。
- `Question` 以全局题目 ID 为主键，重复题目再次导入时会被最后一次 `INSERT OR REPLACE` 覆盖。题目自身的 `identity_id`、章节归属等字段可能体现最后导入的版本，而不是所有关系。

### 3.7 yikaobang 的最终入口和交付边界

`save_data.py` 主入口执行：

```python
create_tables()
insert_identities(f'{working_dir}/resource/identities/', -1)
read_json_files(f'{working_dir}/resource/口腔医学期末', 30401)
read_json_files(f'{working_dir}/resource/临床医学期末', 20101)
read_json_files(f'{working_dir}/resource/护理学期末', 11070)
```

README 明确说明，最后三个目录是把抓取结果从 `resource/identities/` 人工移动、合并后形成的目录。因此当前交付过程不是完全可复现的构建流水线：

- spider 负责网络抓取和 JSON 落盘。
- 人工操作负责专业目录移动/合并。
- save_data 负责将人工准备好的目录导入 SQLite。
- yibubang 仓库本身不运行这些 Python 脚本，也不在 Flutter 构建时生成 SQLite。

`spider.py:upload_awnswer()` 虽然包含 `/Question/Answer/postBatchForAll` 示例，但不在 `__main__` 中调用；这不是当前题库生成链路的一部分。

## 4. 题库如何进入 yibubang

### 4.1 发布配置

`pubspec.yaml` 当前版本为 `2.0.3+203`，没有将 SQLite 声明为 Flutter asset。`assets` 目录也没有题库数据库。题库通过 `yibubang_update.json` 远程提供：

- `data_for_version["2.0.3"].url` 指向 `database-2.0.0/question_data.sqlite.zip`。
- 对应 ZIP MD5 为 `a146c7c9dd316326efa985a1803d2076`。
- 旧版本配置仍保留 `database-1.0.3` 和旧 MD5。
- `latest_app` 在当前配置中为 `2.0.2`，与 `pubspec.yaml` 的 2.0.3 不一致；它主要影响应用更新提示，不直接决定题库文件名。

### 4.2 HomePage 下载和解压流程

`lib/screens/home_page.dart` 中 `_initAsync()` 的顺序是：

1. 读取 `PackageInfo` 得到当前版本。
2. 调 `_needToDownload()`。
3. 如果需要下载，调用 `_downloadAndExtractZip()`。
4. 页面后续检查版本更新和 `needToRebuildQuestionCount` 标记。

`_needToDownload()`：

- GET `https://files.melonhu.cn/yibubang/yibubang_update.json`。
- 将 ZIP 临时文件放在 `getDatabasesPath()/question_data.sqlite.zip`。
- 查找当前应用版本的 `data_for_version` 配置。
- 计算本地 ZIP MD5，与远程配置的 ZIP MD5 比较。
- 文件不存在或 MD5 不一致时返回需要下载。
- 当前版本没有配置时返回不下载。

`_downloadAndExtractZip()`：

1. 创建数据库目录。
2. 用配置中的 URL 流式下载 ZIP。
3. 写入 `question_data.sqlite.zip`。
4. 使用 `archive` 包的 `ZipDecoder` 解压。
5. 将归档内文件写入 `$appDocDir/$fileName`。
6. 完成后将下载状态置为成功。

题库真正被 `DatabaseHelper` 使用时，文件必须位于：

```text
<sqflite getDatabasesPath()>/question_data.sqlite
```

下载函数只校验 ZIP 的 MD5，没有再次校验解压出的 `question_data.sqlite` 的 MD5 或 SQLite schema。

### 4.3 下载链路的已知风险

- 未见对下载响应 HTTP 状态码的强校验；非成功响应可能仍进入写文件流程。
- 只验证 ZIP，不验证解压后的数据库文件。
- 解压路径直接拼接 `$appDocDir/$fileName`，没有显式的路径穿越过滤。
- 归档内目录的父目录创建逻辑不完整，若 ZIP 包含多级目录，可能因父目录不存在而失败。
- ZIP 下载完成后没有明确删除旧的解压数据库或临时文件。
- `accept_update` 设置虽然初始化，但当前 `_needToDownload()` 未见使用它来阻止数据下载。
- 远程更新配置的 `latest_app` 与本地版本存在不一致，维护时容易造成误判。

## 5. yibubang 两套 SQLite 的存储模型

### 5.1 `question_data.sqlite`：只读题库库

打开位置：`lib/db/database_helper.dart:DatabaseHelper._initDB()`。

```dart
final path = join(await getDatabasesPath(), 'question_data.sqlite');
return openDatabase(path, readOnly: true, singleInstance: false);
```

如果文件不存在，会抛出“数据库文件不存在，请下载”。该 helper 是单例，提供：

- `getAll(table)`：查询表全部记录。
- `getByCondition(table, condition, args)`：条件查询。
- `getByRawQuery(sql, arguments)`：原生 SQL 查询。
- `getCountByCondition(...)`：条件计数。
- 通用 `insert/update/delete`：虽然接口存在，但题库连接是只读，业务上不应使用。
- `getDatabasePath()`：返回题库库路径。

Flutter 没有对题库库执行 `onCreate` 或迁移；题库 schema 完全依赖 yikaobang 生成端和发布 ZIP。

### 5.2 `user_data.sqlite`：可写用户库

打开位置：`lib/db/database_helper.dart:UserDBHelper._initDatabase()`。

```dart
final path = join(await getDatabasesPath(), 'user_data.sqlite');
return openDatabase(path, version: 1, onCreate: _onCreate);
```

首次打开时 `UserDBHelper._onCreate()` 创建表。

#### `IdentitySubject`

```sql
IdentitySubject(
  identity_id TEXT,
  subject_id TEXT,
  correct INTEGER DEFAULT 0 NOT NULL,
  incorrect INTEGER DEFAULT 0 NOT NULL,
  selected INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (identity_id, subject_id)
)
```

用途：记录某 identity 下某课程是否被选中，以及正确/错误累计数。

#### `IdentityChapter`

```sql
IdentityChapter(
  identity_id TEXT,
  subject_id TEXT,
  chapter_id TEXT,
  correct INTEGER DEFAULT 0 NOT NULL,
  incorrect INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (identity_id, chapter_id)
)
```

用途：记录某 identity、章节的正确/错误累计数。

代码注释已经指出主键缺少 `subject_id`。如果同一个 `chapter_id` 在同一 identity 下跨课程复用，数据会冲突，后续查询也只按 `identity_id + chapter_id` 合并。

#### 用户 `Question`

```sql
Question(
  id TEXT PRIMARY KEY,
  chapter_id TEXT,
  chapter_parent_id TEXT,
  cut_question TEXT DEFAULT 0 NOT NULL,
  user_answer TEXT DEFAULT '' NOT NULL,
  status INTEGER DEFAULT 0 NOT NULL,
  collection INTEGER DEFAULT 0 NOT NULL
)
```

字段含义：

| 字段 | 含义 |
| --- | --- |
| `id` | 对应题库 `Question.id` |
| `chapter_id` | 题目章节 |
| `chapter_parent_id` | 题目所属课程/Subject |
| `cut_question` | 斩题标志，运行时使用空字符串或 `cutted` |
| `user_answer` | 以分号分隔的多次答案历史，最后一段是当前答案 |
| `status` | `0` 未做，`1` 正确，`2` 错误，`3` 已斩（实际斩题主要由 `cut_question` 表示），`4` 测试模式已作答 |
| `collection` | `0` 未收藏，`1` 收藏 |

创建了三个索引：`chapter_id`、`chapter_parent_id`、`status`。

#### `Notes`、`Cards`、`Activities`

- `Notes`：笔记 ID、题目 ID、内容、图片和时间。
- `Cards`：正面、背面和时间，用于卡片类功能。
- `Activities`：活动 ID、标题、JSON 描述和时间；答题时写入 `NewAnswer` 活动，形式上像待上传队列。

`Notes.question_id` 声明为 `REFERENCES questions(id)`，但实际创建的表名是 `Question`，且代码没有启用外键约束检查，因此该约束存在表名不一致风险。

`UserDBHelper.database` 初始化后会调用 `dropAllTriggers()` 删除用户库触发器，再执行完整性检查。这意味着即使未来在用户库加入触发器，也会在打开时被移除。

## 6. yibubang 读取链路

### 6.1 identity 选择

`IdentityListPage` 调 `getChildrenIdentities(parentId)`：

```sql
SELECT id, parent_id, name
FROM Identity
WHERE parent_id = ?
ORDER BY name
```

结果再按数字 ID 排序。选择 identity 后只写入：

```text
SharedPreferences['identityId']
```

当前可选择 identity 由 `AppStrings.choosableIdentities` 限制为 `20101`、`30401`、`11070`。

### 6.2 课程读取和用户状态合并

`getSubjectsByIdentity()` 的主查询来自题库库：

```sql
SELECT S.id, S.name, ISUB.total
FROM IdentitySubject AS ISUB
JOIN Subject AS S ON S.id = ISUB.subject_id
WHERE ISUB.identity_id = ?
```

然后到用户库查询同一 identity 的：

```text
subject_id, correct, incorrect, selected
```

题库库提供稳定内容和题目总数；用户库提供用户选择和答题统计。若某课程在用户库不存在，则批量插入默认 `0/0/0` 记录，再在内存中合并成 `Subject`。

`getSelectedSubjects()` 的方向相反：先从用户库筛 `selected=1`，再回题库库查课程名称和总数。

`SubjectsListPage` 的“搜索课程”只对已经加载到内存的 `Subject.name` 做大小写不敏感的 `contains`，没有 SQL LIKE，也不是题干搜索。

### 6.3 章节读取和用户状态合并

`getChaptersBySubject(subject)` 从题库库读取：

```sql
SELECT C.id, C.name, IC.total
FROM IdentityChapter AS IC
JOIN Chapter AS C ON C.id = IC.chapter_id
WHERE IC.identity_id = ? AND IC.subject_id = ?
```

然后到用户库按 `identity_id` 和 `chapter_id` 读取 `correct/incorrect`。缺失的用户章节记录会被批量插入默认值。

由于用户库 `IdentityChapter` 的主键和查询都忽略 `subject_id`，同一章节 ID 在不同课程中复用时，用户统计可能被合并。

### 6.4 章节题目读取

`getQuestionsFromChapter(chapter)` 从题库库执行：

```sql
SELECT q.*
FROM Question AS q
JOIN IdentityQuestion AS iq ON q.id = iq.question_id
WHERE iq.identity_id = ?
  AND iq.subject_id = ?
  AND iq.chapter_id = ?
ORDER BY q.id
```

这条查询的特征：

- 内容字段全部来自只读题库库。
- 通过 `IdentityQuestion` 避免仅依赖 `Question` 行的最后一次 identity/章节归属。
- 题目按 ID 排序，不是随机排序。
- 没有全文搜索条件。

`Question.fromMap()` 映射题库的大部分字段；`option` 保持 JSON 字符串。详情页展示前 `json.decode()`，若解析失败则使用内置的默认 A/B/C 选项。

### 6.5 用户题目懒初始化

`getUserQuestions(questionsFuture)`：

1. 读取当前章节的题目列表。
2. 收集所有题目 ID。
3. 一次性查询用户库 `Question WHERE id IN (...)`。
4. 已有记录直接构造 `UserQuestion`。
5. 缺失记录按题库题目的章节和课程 ID 生成默认值：
   - `cutQuestion = ''`
   - `userAnswer = ''`
   - `status = 0`
   - `collection = 0`
6. 在一个事务中批量插入缺失记录。

所以用户库不是安装时预生成完整题目状态，而是用户第一次打开某章节时逐题建立。

## 7. yibubang 修改链路

### 7.1 课程选择

`SubjectsListPage` 点击课程后切换 `Subject.selected`，调用 `toggleSubjectSelected()`：

```sql
UPDATE IdentitySubject
SET selected = ?
WHERE identity_id = ? AND subject_id = ?
```

课程记录通常已经由 `getSubjectsByIdentity()` 懒初始化。

### 7.2 收藏和斩题

`QuestionDetailPage` 的收藏按钮和斩题按钮调用 `updateQuestionSimple(uq, q)`，只更新用户库 `Question`：

```sql
UPDATE Question
SET status = ?,
    collection = ?,
    user_answer = ?,
    cut_question = ?
WHERE id = ?
```

收藏使用 `collection=0/1`；斩题使用 `cut_question=''/'cutted'`。此操作不更新课程/章节统计，也不写 `Activities`。

### 7.3 答案历史格式

`user_answer` 不是单个答案，而是分号分隔的历史字符串：

```text
AB;ABC;DC
```

`getLastAnswer()` 取最后一段；`changeLastAnswer()` 只替换最后一段。重做题目时会在结尾追加 `;`，形成新的待作答段，例如：

```text
AB;ABC;
```

详情页对答案排序后比较，单选题不允许空答案，多选题至少选两个选项。

### 7.4 普通/快刷模式提交

`QuestionDetailPage.submitAnswer()`：

- 正确答案匹配：`status=1`。
- 不匹配：`status=2`。
- 测试模式：`status=4`。
- 快刷模式下，单选题自动提交并在答对时翻页。

普通答题和测试模式都调用 `updateQuestion()`，但测试模式的 `status=4` 会走“其他状态”分支，不增加正确/错误统计。

### 7.5 `updateQuestion()` 的统计写入

`updateQuestion(uq, q, prevCorrect)` 分三部分执行：

#### 第一步：查题目关系

从只读题库库查询一个题目的全部关系：

```sql
SELECT identity_id, subject_id, chapter_id
FROM IdentityQuestion
WHERE question_id = ?
```

一个题目属于多个 identity/课程/章节时，后续会对每条关系都更新用户统计。

#### 第二步：更新课程和章节累计统计

当 `status=1`：每条关系 `correct + 1`。

当 `status=2`：每条关系 `incorrect + 1`。

当 `status=0`：根据 `prevCorrect` 将之前对应的计数减 1，并截断到不小于 0。

使用的是 SQLite UPSERT：

- 课程统计冲突键为 `(identity_id, subject_id)`。
- 章节统计冲突键为 `(identity_id, chapter_id)`，仍然忽略 `subject_id`。

这是一种“作答事件累计”模型，而不是根据当前每道题的唯一状态实时聚合的模型。因此重复提交同一题会重复增加计数；只有重做流程明确调用 `status=0` 时才尝试撤回一次。

#### 第三步：更新用户题目并写 Activity

更新用户库 `Question` 的 `status`、`collection`、`user_answer`，然后插入 `Activities`：

- `title = 'NewAnswer'`
- `description` 是仿医考帮上传接口格式的 JSON 字符串。
- `is_right = 2 - status`，因此 `status=1` 得到 `1`，`status=2` 得到 `0`，`status=4` 得到 `-2`。
- `subject_id` 在代码中硬编码为 `20101`。
- `duration` 硬编码为 `10`。

代码没有发现 Flutter 将 `Activities` 批量上传到 API 的实际调用；`questionUploud` 设置只是初始化项。`spider.py` 中的上传示例也没有被主流程调用。

### 7.6 章节重做和错题重做

`QuestionGridPage.clearUserAnswers()` 遍历当前章节全部题目：

- 对 `status=1/2` 的题目追加分号。
- 将状态置为 `0`。
- 用原状态设置 `prevCorrect`，调用 `updateQuestion()` 撤回相应统计。

`clearWrongAnswers()` 先筛出当前条件下的题目，确认都已作答，再只对 `status=2` 的题目执行同样的清除逻辑。

这些循环没有等待每个 `updateQuestion()` 的 Future 完成，多个异步更新同时发起时，虽然每次内部使用 batch，但整体完成顺序没有被调用方严格串行控制。

### 7.7 统计重建

`rebuildQuestionCount()` 是比事件增量更可靠的修复路径，位于 `lib/db/data_transfer.dart`：

1. 获取只读题库路径。
2. 在 user 数据库连接上执行 `ATTACH DATABASE '<path>' AS qbank`。
3. 清零用户库 `IdentitySubject` 和 `IdentityChapter` 的 correct/incorrect。
4. 将用户库 `Question` 与 `qbank.IdentityQuestion` JOIN。
5. 只统计 `status IN (1,2)` 的题目。
6. 按 identity、subject、chapter 聚合后写回用户库。
7. 事务结束后 `DETACH DATABASE qbank`。

伪 SQL 逻辑：

```sql
SELECT iq.identity_id,
       iq.subject_id,
       iq.chapter_id,
       SUM(CASE WHEN uq.status = 1 THEN 1 ELSE 0 END) AS correct,
       SUM(CASE WHEN uq.status = 2 THEN 1 ELSE 0 END) AS incorrect
FROM Question AS uq
JOIN qbank.IdentityQuestion AS iq ON uq.id = iq.question_id
WHERE uq.status IN (1, 2)
GROUP BY iq.identity_id, iq.subject_id, iq.chapter_id
```

HomePage 在 `needToRebuildQuestionCount=true` 时自动执行一次；`MyPage` 也提供手动“重新统计”入口。重建使用的用户章节冲突键仍是 `(identity_id, chapter_id)`，所以不能修复 schema 主键缺少 `subject_id` 的问题。

### 7.8 遗留 `transferData()`

`transferData()` 试图把题库库中的 Subject、Chapter 和 Question 复制到用户库，但它与现行 schema 不兼容：

- 现行 `UserDBHelper._onCreate()` 没有创建用户库 `Subject`、`Chapter` 表。
- 旧代码尝试向这些不存在的表写入 `selected/correct/incorrect/total` 等字段。
- 它假设题库 `Chapter` 有 `subject_id`，但 `save_data.py` 的 Chapter 表没有该字段。
- 它假设题库 `Question` 有用户状态字段，且试图读取 `status/collection`；生成端 Question schema 并不提供这些运行时字段。
- 全局搜索没有发现 `transferData()` 的调用点。

`checkTransferScuess()` 也检查用户库的 `Question`、`Chapter`、`Subject` 是否为空，但后两张表在当前用户 schema 中不存在，且没有发现实际调用点。它们应被视为旧架构残留，不应当作当前初始化流程。

## 8. 数据字段映射

| 生产题库 | Flutter 题库库 | Flutter 用户库/内存 | 说明 |
| --- | --- | --- | --- |
| `Question.id` | `Question.id` | `Question.id` | 三者关联主键 |
| `Question.chapter_id` | `Question.chapter_id` | 用户 `Question.chapter_id` | 章节归属 |
| `Question.chapter_parent_id` | `Question.chapter_parent_id` | 用户 `Question.chapter_parent_id` | Subject/课程归属 |
| `Question.option` 数组 | JSON 字符串 | `Question.option` 字符串 | 详情页再 `json.decode()` |
| `Question.answer/title/explain/restore` | 同名字段 | 不复制 | 用户库只保存用户状态 |
| `Question.cut_question`、`user_answer` | 题库表有遗留字段 | 用户库实际运行时字段 | 运行时以 user_data 为准 |
| `IdentityQuestion` | 题目到 identity/课程/章节关系 | 不复制 | 用于读取题目和统计归属 |
| `IdentitySubject.total` | 课程题目总数 | 用户 `IdentitySubject.correct/incorrect/selected` | 两库在内存中合并 |
| `IdentityChapter.total` | 章节题目总数 | 用户 `IdentityChapter.correct/incorrect` | 两库在内存中合并 |
| `Comment` | 可选本地评论表 | 不使用 | Flutter 当前通过 API 读取 |

## 9. 当前没有实现或未接通的能力

根据当前工作区源码，没有发现以下能力的有效运行调用链：

1. **随机抽题**：没有 `ORDER BY RANDOM()` 或随机题目选择函数，章节题目按 `q.id` 顺序读取。
2. **题干全文搜索**：没有对 `Question.title`、`explain` 等字段建立 FTS 或全文 SQL 查询。只有课程名称内存搜索。
3. **全题库搜索**：README 中的相关设想没有对应实现。
4. **本地答题记录上传**：`Activities` 结构类似上传队列，但没有发现批量上传调用；`questionUploud` 没有形成完整逻辑。
5. **运行时 `transferData()` 初始化**：没有调用点，且实现与当前 schema 冲突。
6. **题库生成自动化连接**：Flutter 构建过程不会运行 `docs/yikaobang` 的 Python；目录移动/课程合并仍是人工步骤。

## 10. 主要问题与风险清单

### 高优先级

1. **题库生产范围和应用 identity 不一致**：当前爬虫白名单启用 `110505`，应用可选的是 `20101/30401/11070`。发布前必须验证最终 SQLite 是否包含应用实际可选 identity。
2. **`IdentityChapter` 主键缺少 `subject_id`**：生产库和用户库都使用 `(identity_id, chapter_id)`，跨课程复用章节 ID 会冲突、覆盖或合并统计。
3. **题目关系主键可能丢失多课程关系**：`IdentityQuestion` 使用 `(identity_id, question_id)`，同题在同 identity 的多个课程/章节中出现时无法全部保留。
4. **生产交付不可完全复现**：JSON 目录需要人工移动/合并，最终数据库又不在当前工作区；无法仅凭仓库重建发布 ZIP。
5. **题库下载后没有 schema/文件校验**：只校验 ZIP MD5，不校验解压的 SQLite 文件，导致内容错包或目录结构异常时缺少明确诊断。

### 中优先级

6. **事件累计统计容易漂移**：重复提交同一题会重复累加；统计正确性依赖重做时是否准确传入 `prevCorrect`。
7. **测试模式 Activity 数据不一致**：`status=4` 会生成 `is_right=-2`，但没有进入正确/错误统计逻辑。
8. **Activity 字段硬编码**：`subject_id=20101`、`duration=10`，切换到口腔或护理题库时仍会生成临床课程 ID。
9. **异步批量重做未等待**：章节重做循环中没有等待每个 `updateQuestion()`，存在并发写入顺序和错误处理不明确的问题。
10. **遗留迁移代码误导维护者**：`transferData()`、`checkTransferScuess()` 按旧表结构实现，若未来误调用会直接因表不存在或列不存在失败。
11. **`Notes` 外键表名错误**：声明引用 `questions`，实际表为 `Question`；同时未启用外键约束检查。
12. **删除用户库触发器**：`UserDBHelper.database` 初始化时主动删除全部触发器，可能破坏未来新增的数据完整性机制。

### 安全和健壮性

13. **爬虫和客户端含敏感协议常量**：固定设备 UUID、签名常量、加密 key 和登录相关凭据处理不应进入公开发布日志或源代码。
14. **ZIP 解压缺少路径安全校验**：应拒绝绝对路径、`..` 路径和异常文件名。
15. **启发式 JSON 修复可能改变题目内容**：应优先保存原始响应，使用明确的协议解析和可审计的失败记录。
16. **Python 导入使用 `INSERT OR REPLACE`**：可能覆盖题目内容及 identity/章节字段；题库构建应明确去重、冲突和版本策略。
17. **客户端 DES 实现需兼容性验证**：Python 使用 `Crypto.Cipher.DES`，Dart 使用 PointyCastle `DESedeEngine` 配置；即使意图相同，也应使用真实响应做跨端解密回归验证。当前 Flutter 端并未参与本地题库 SQLite 生成，但远程 API 读取/解析可能受此影响。

## 11. 建议的后续改造方向

### 11.1 先固定题库发布契约

建议将题库 SQLite schema 作为明确版本化契约：

- 在生成端输出 schema/version 元数据。
- 发布 ZIP 中固定根目录和文件名。
- 发布前执行 `PRAGMA integrity_check`、表/列清单检查、identity 数量检查、题目关系检查。
- 同时记录 SQLite 文件 SHA-256/MD5，而不是只记录 ZIP MD5。
- 生成一份机器可读的课程/章节/题目统计清单，供客户端或发布脚本校验。

### 11.2 修正关系键

如果业务允许一个章节 ID 在多个课程下复用，建议统一使用：

```text
IdentityChapter PRIMARY KEY (identity_id, subject_id, chapter_id)
```

同时检查 `IdentityQuestion` 是否应使用：

```text
(identity_id, subject_id, chapter_id, question_id)
```

用户库、重算 SQL、章节查询、统计更新都必须使用同一组键。

### 11.3 让统计以事实表重算为准

更稳妥的方案是把用户每次作答作为事实记录或唯一当前状态记录，然后通过聚合重建课程/章节统计；不要把“重复点击提交”直接等同于统计增量。至少应记录上一次状态，在 `0 -> 1`、`0 -> 2`、`1 -> 2` 等状态变化时按差分更新。

### 11.4 删除或隔离旧迁移路径

`transferData()` 和 `checkTransferScuess()` 应删除，或明确放入 `legacy/` 并加上不可调用标记；当前应用只需要：

1. 下载并验证题库库。
2. 打开/迁移用户库。
3. 按题目 ID 懒初始化用户状态。
4. 必要时执行跨库统计重建。

### 11.5 增强客户端下载和数据库初始化

建议下载流程增加：

- HTTP 状态码和 `Content-Type` 检查。
- 临时文件下载完成后再原子替换旧 ZIP。
- ZIP 内路径白名单和目录创建。
- 解压后 SQLite 文件存在性、文件 hash、schema version 和 `PRAGMA integrity_check` 检查。
- 失败时保留可诊断日志，不把损坏文件当作已完成题库。
- 题库版本与 user_data 版本的迁移策略。

## 12. 端到端调用索引

### 生产端

```text
spider.__main__
  └─ login()
  └─ get_subjects()
  └─ save_all_identities(..., cached=True)
       ├─ get_chapters()
       └─ save_question_data()
            ├─ get_question_list()
            ├─ DES_decode()
            └─ save_json_to_file()

save_data.__main__
  ├─ create_tables()
  ├─ insert_identities()
  └─ read_json_files()
       └─ insert_questions_batch()
            ├─ Subject / Chapter
            ├─ IdentitySubject / IdentityChapter
            ├─ IdentityQuestion
            └─ Question
```

### 客户端启动和读取

```text
main()
  └─ initSettings()
      └─ HomePage._initAsync()
          ├─ _needToDownload()
          ├─ _downloadAndExtractZip()
          └─ _checkForAppUpdate()
               └─ rebuildQuestionCount() [按标志]

IdentityListPage
  └─ getChildrenIdentities()

SubjectsListPage
  └─ getSubjectsByIdentity()
       ├─ question_data.IdentitySubject + Subject
       └─ user_data.IdentitySubject

Chapter page
  └─ getChaptersBySubject()
       ├─ question_data.IdentityChapter + Chapter
       └─ user_data.IdentityChapter

QuestionGridPage
  ├─ getQuestionsFromChapter()
  │    └─ question_data.Question + IdentityQuestion
  └─ getUserQuestions()
       └─ user_data.Question（缺失时懒插入）

QuestionDetailPage
  ├─ updateQuestionSimple()  [收藏/斩题]
  └─ updateQuestion()        [答题/重做]
       ├─ question_data.IdentityQuestion
       ├─ user_data.IdentitySubject / IdentityChapter
       ├─ user_data.Question
       └─ user_data.Activities
```

## 13. 研究依据文件

核心依据：

- `docs/yikaobang/README.md`
- `docs/yikaobang/src/encrypt.py`
- `docs/yikaobang/src/spider.py`
- `docs/yikaobang/src/save_data.py`
- `lib/main.dart`
- `lib/screens/home_page.dart`
- `lib/db/database_helper.dart`
- `lib/db/data_transfer.dart`
- `lib/db/settings.dart`
- `lib/models/identity.dart`
- `lib/models/subject.dart`
- `lib/models/chapter.dart`
- `lib/models/question.dart`
- `lib/screens/identity_list_page.dart`
- `lib/screens/subjects_list_page.dart`
- `lib/screens/question_grid_page.dart`
- `lib/screens/question_detail_page.dart`
- `lib/screens/my_page.dart`
- `lib/common/request.dart`
- `lib/common/ykb_encrypt.dart`
- `lib/common/app_strings.dart`
- `yibubang_update.json`
- `pubspec.yaml`

未纳入实测的内容：远程 ZIP 内 SQLite 的实际表数据、实际题目数量、当前发布数据库是否已由最新 `save_data.py` 生成，以及工作区外 `/Users/huzongyao/ReverseProjects/yikaobang` 中的真实资源目录。上述内容需要拿到具体发布 ZIP 或生成产物后，使用 SQLite schema/完整性检查再次验证。
