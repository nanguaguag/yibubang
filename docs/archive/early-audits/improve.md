# 医不帮 (yibubang) 项目全维度深度锐评与技术重构改进报告

> **审查对象**：`yibubang` 完整代码库（Flutter 客户端、SQLite 存储体系、Python 生产端与反编译爬虫流水线）
> **项目背景**：核心业务框架由作者手写，后期在 Vibe Coding 模式下由 AI 辅助补齐多题库、统计与同步功能。
> **文档目标**：深度剖析项目的架构闪光点与技术债，列出重大 Bug、结构缺陷与隐患，并提供工业级的改进方案。

---

## 1. 总体锐评：实用主义黑客精神与 Vibe Coding 的撕裂共生

### 1.1 项目的工程闪光点（为什么它能成功跑通并解决痛点）
从工程实用主义（Pragmatic Engineering）视角来看，本项目展现了极强的**“目标导向黑客精神”**：
1. **精准打击医学备考核心痛点**：正版 App 必须在线联网、题目加载慢、跨平台体验割裂，而本项目通过逆向抓取、DES 解密、清洗入库，打造成了一个**极致轻快、纯离线、全平台**的医学刷题利器。
2. **多题库拆分演进设计方向完全正确**：从早期 287MB 单体巨石库重构为“独立题库只读 SQLite + 全局共享用户状态”，并确立了“题目是跨题库共享实体，`question_id` 全局唯一”的契约，这在离线刷题类软件中是非常成熟且高级的设计决策。
3. **关键性能瓶颈抓得很准**：在移动端冷启动时，针对百兆级 SQLite 整库扫描耗时问题，设计了基于文件大小与修改时间的持久化指纹校验缓存（`bank_validation_cache`），把启动延迟从数秒优化到毫秒级；在跨库重算时采用了 SQLite 原生 `ATTACH DATABASE`，避开了漫长的 Dart 内存循环。

### 1.2 Vibe Coding 带来的典型技术断层与“拼接怪”现象
当开发模式从“手写核心”转向“AI 辅助的 Vibe Coding”后，项目的代码质量和架构一致性出现了显著的**双重人格（Schizophrenia）现象**：
- **“局部优雅，全局撕裂”**：AI 单独写 `RecordSyncService` 或 `fl_chart` 图表页时，代码显得非常标准、类型严密；但 AI 并不真正通读并遵守你早期手写代码里的隐性约定，导致了数据字段标准的严重割裂（最典型的是斩题字段，同一字段有 `0`、`'1'`、`"cutted"`、`""` 四种完全不兼容的语义）。
- **“AI 堆砌代码”造就上千行上帝类**：以 1403 行的 [`QuestionDetailPage`](../../../lib/screens/question_detail_page.dart) 为代表，AI 每次接到需求（加测试模式计时、加字号缩放、加评论翻页、加图片全屏预览、加快捷交卷）就直接在这个类里顺延插入 `setState` 和私有方法，导致该页面承担了至少 8 种完全无关的职责。
- **幽灵代码与幻觉残留**：建表建了从来没人读写的 `Notes` 和 `Cards` 表，且外键直接引用了不存在的 `questions(id)`；伪随机函数直接调用 `DateTime.now().microsecond % 900000`（AI 把纳秒/微秒范围当成了毫秒），产生了严重的并发主键碰撞隐患。

---

## 2. 重大 Bug 与运行时致命隐患清单 (Critical Bugs)

### P0 级致命缺陷 1：斩题状态（`cut_question`）契约三方撕裂，多端合并后题目在列表彻底消失

- **问题定位**：
  1. 数据库建表 DDL（[`database_helper.dart:444`](../../../lib/db/database_helper.dart#L444)）：`cut_question TEXT DEFAULT 0 NOT NULL`
  2. UI 界面逻辑（[`question_grid_page.dart:121`](../../../lib/screens/question_grid_page.dart#L121)、[`question_detail_page.dart:951`](../../../lib/screens/question_detail_page.dart#L951)）：
     ```dart
     // 过滤:
     if (cutType == 1 && uq.cutQuestion != "cutted") return false;
     if (cutType == 2 && uq.cutQuestion != "") return false;
     // 点击斩题:
     userQuestion.cutQuestion = userQuestion.cutQuestion == "cutted" ? "" : "cutted";
     ```
  3. AI 编写的做题记录同步合并服务（[`record_sync_service.dart:152`](../../../lib/db/record_sync_service.dart#L152)）：
     ```dart
     final newCut = (localCut == '1' || srcCut == '1') ? '1' : localCut;
     ```
- **Bug 触发场景与后果**：
  当用户在一台设备导出数据，并在另一台设备选择“导入做题记录（合并）”后，被斩题目的 `cut_question` 字段被 AI 逻辑强制写入了 `'1'`。此时用户回到题目格子页：
  - 勾选“已斩”，因为 `'1' != 'cutted'`，该题目被过滤掉；
  - 勾选“未斩”，因为 `'1' != ''`，该题目再次被过滤掉；
  - **结果**：该题目在两个分类下彻底“人间蒸发”，用户再也无法在网格中找到这道题！

---

### P0 级致命缺陷 2：护理期末题库近万道题（占总数 15%）因题型不支持直接死锁瘫痪

- **问题定位**：
  经实测拆分数据库统计，`nursing_final.sqlite` 中存在 **9,681 道非单选/多选题的主观题**（填空题 2,799 道、名词解释 2,569 道、简答题 3,379 道、论述题 388 道、病例分析 547 道，题型代码分别为 3~7），且其正确答案字段 `answer` 均为空字符串 `""`。
  而在核心做题界面 [`question_detail_page.dart:229-286`](../../../lib/screens/question_detail_page.dart#L229-L286)：
  ```dart
  switch (question.type) {
    case '1': // 单选题 RadioListTile
    case '2': // 多选题 CheckboxListTile
    default:
      return const Text('未知的题目类型');
  }
  ```
- **Bug 触发场景与后果**：
  任何护理学专业用户或全库搜索搜到主观题的用户，打开题目后只看到一片空白和灰色的“未知的题目类型”，没有输入框，也没有可点击选项。在 `submitAnswer` 逻辑中由于 `userAnswer` 为空，弹窗提示“不能不填答案哦~”，题目无法提交、无法作答、无法标记对错，题库中近 15% 的内容处于死锁不可用状态。

---

### P1 级严重隐患 3：题目答案与字段空指针强解包（`question.answer!`）引发红屏崩溃

- **问题定位**：
  在 [`question_detail_page.dart:1231`](../../../lib/screens/question_detail_page.dart#L1231) 与 [`第 383 行`](../../../lib/screens/question_detail_page.dart#L383)：
  ```dart
  if (sortString(userAnswer) == sortString(question.answer!)) // 强解包
  final bool answerContains = question.answer!.contains(key);  // 强解包
  ```
  在 Dart 数据模型 [`lib/models/question.dart`](../../../lib/models/question.dart#L63) 中，`answer` 字段明确声明为可空类型 `String? answer;`。
- **Bug 触发场景与后果**：
  虽然当前期末选择题大多有答案，但在爬虫清洗异常、主观题缺失答案或导入特殊题目时，只要 `answer` 为 `null`，用户提交答案或查看已做题目时将瞬间触发 `Null check operator used on a null value`，Flutter 抛出致命未捕获红屏。

---

### P1 级严重隐患 4：离线刷题核心场景下 `Image.network` 裸奔无异常捕获与离线缓存

- **问题定位**：
  [`question_detail_page.dart:350`](../../../lib/screens/question_detail_page.dart#L350) 与 [`comment_page.dart:456`](../../../lib/screens/comment_page.dart#L456)：
  ```dart
  Image.network(
    titleImg,
    height: 200,
  )
  ```
- **Bug 触发场景与后果**：
  “医不帮”主打离线刷题（题库已内置本地 SQLite）。然而配图直接使用 Flutter 原生 `Image.network`，**未配置任何 `errorBuilder`，更没有使用磁盘缓存库（如 `cached_network_image`）**。
  当用户在图书馆、地铁或断网环境下刷题，遇到解剖图、病理切片图时，Flutter 无法联网拉取图片，会直接抛出网络异常，并在界面呈现大面积灰红色错误条幅或刺眼的默认异常框，严重破坏“离线”承诺。

---

### P1 级严重隐患 5：`generateSimpleId()` 伪随机算法缺陷导致批量操作主键碰撞

- **问题定位**：
  [`database_helper.dart:9-13`](../../../lib/db/database_helper.dart#L9-L13)：
  ```dart
  String generateSimpleId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (100000 + (DateTime.now().microsecond % 900000));
    return '$timestamp$random';
  }
  ```
- **算法缺陷分析**：
  在 Dart 中，`DateTime.now().microsecond` 返回的是当前微秒在毫秒内的余数，其**取值范围仅为 `0 ~ 999`**。
  因此，`microsecond % 900000` 恒等于 `microsecond` 本身，`random` 的实际取值被限制在 `100000 ~ 100999`（仅 1000 种可能，根本不是 6 位随机数）。
- **灾难场景**：
  在 [`data_transfer.dart:160-185`](../../../lib/db/data_transfer.dart#L160-L185) 的 `repairActivities` 方法中，系统在单个 CPU 同步循环中为成百上千道历史题目连续调用 `generateSimpleId()` 插入 `Activities`。由于现代 CPU 运行该循环只需数毫秒，极易在同一毫秒内生成完全相同的时间戳和微秒数，导致触发 `UNIQUE constraint failed: Activities.id`，使修复事务全盘崩溃中断。

---

### P2 级设计缺陷 6：幽灵表 `Notes` 携带错误外键，开启外键约束必死锁

- **问题定位**：
  [`database_helper.dart:452-459`](../../../lib/db/database_helper.dart#L452-L459)：
  ```sql
  CREATE TABLE IF NOT EXISTS Notes (
    id TEXT PRIMARY KEY,
    question_id TEXT NOT NULL,
    content TEXT NOT NULL,
    imgs TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (question_id) REFERENCES questions(id)
  )
  ```
- **缺陷分析**：
  外键声明为 `REFERENCES questions(id)`（带复数 s），然而整个数据库中的题目表名为单数 `Question`。SQLite 默认未开启外键检查因此未报错，但一旦执行 `PRAGMA foreign_keys = ON;`，任何对 `Notes` 的插入都将直接报错 `no such table: main.questions`。
  更具讽刺意味的是，通过全局代码检索，整个 Dart 客户端中**没有任何一处代码对 `Notes` 或 `Cards` 表进行过任何读写**，完全是随手建下的“僵尸表”。

---

### P2 级设计缺陷 7：网络层 `basicReq` 原地修改不可变参数与 HTTP 响应未验

- **问题定位**：
  [`lib/common/request.dart:22-25`](../../../lib/common/request.dart#L22-L25)：
  ```dart
  if (loggedin) {
    params['token'] = prefs.getString('token') ?? '';
    params['secret'] = prefs.getString('secret') ?? '';
    params['user_id'] = prefs.getString('user_id') ?? '';
  }
  ```
- **缺陷分析**：
  直接原地对入参 `params` 进行修改。如果调用者传入的是只读常量 Map（如 `const {'app_id': '1'}`）或不可修改集合，将直接抛出 `Unsupported operation: Cannot modify unmodifiable map`。
  此外，在发起 `http.post` 后，代码未检查 `response.statusCode == 200`，直接盲目执行 `json.decode(response.body)`。如果遇到医考帮 API 服务器维护、反向代理 502/504 返回 HTML 页面，客户端将直接抛出 `FormatException: Unexpected character` 崩溃。

---

## 3. 架构设计与技术债务深度诊断 (Shortcomings & Technical Debt)

### 3.1 架构分层缺失与 Active Record 反模式
在传统标准架构中，层次划分应当为：`UI View -> State/ViewModel -> Repository -> Local/Remote DataSource`。
而在当前项目中，代码职责高度混淆：
- **Model 层严重越权（Active Record 反模式）**：
  在 [`lib/models/subject.dart`](../../../lib/models/subject.dart) 和 [`lib/models/question.dart`](../../../lib/models/question.dart) 中，数据实体类本身居然包含几百行直接拼接 SQL、管理 SharedPreferences、发起事务的重量级逻辑（例如 `getSubjectTreeByIdentity()`、`updateQuestion()`）。这导致 Model 无法脱离特定的持久化层进行独立测试。
- **UI 层反向渗透到数据库**：
  各个 UI 页面（如 `question_grid_page.dart`、`choosed_subjects_page.dart`）直接引入 `sqflite` 和 `DatabaseHelper`，自己管理数据库事务、判断表字段、拼接 SQL 字符串。

### 3.2 严重的 N+1 数据库查询导致首页卡顿
在首页核心加载方法 [`getSubjectsWithChapters()`](../../../lib/screens/choosed_subjects_page.dart#L19-L31) 中：
```dart
Future<List<SubjectWithChapters>> getSubjectsWithChapters() async {
  List<Subject> subjects = await getSelectedSubjects();
  List<SubjectWithChapters> subjectWithChapters = [];

  for (final subject in subjects) { // 循环遍历
    List<Chapter> chapters = await getChaptersBySubject(subject); // 内部执行多条 SQL
    subjectWithChapters.add(SubjectWithChapters(subject: subject, chapters: chapters));
  }
  return subjectWithChapters;
}
```
每勾选一门课程，就会在 Dart 线程循环中按顺序发起 2~4 次数据库查询。若用户选了 15 门医学基础课与专业课，首页初始化需要串行执行 **40~60 次 SQLite I/O 交互**，在低端 Android 机器上造成极其显著的白屏等待。

### 3.3 统计页 7 次连续大表扫描阻滞主线程
进入 [`StatisticsPage`](../../../lib/screens/statistics_page.dart#L37-L73) 时，`_load()` 方法按顺序 `await` 执行了：
1. `todayStats`（今日）
2. `weekStats`（本周）
3. `monthStats`（本月）
4. `heatByDay`（过去 365 天）
5. `todayChart`（小时细分）
6. `weekChart`（7天细分）
7. `monthChart`（30天细分）

每个方法内部都独立向 `Activities` 跑一次 SQL 查询。在做题流水累积到数万条时，7 次连续的磁盘扫描会导致点击“统计”Tab 时界面发生肉眼可见的掉帧顿挫。实际上，只需一次性拉取过去一年的作答时间戳与用时，在内存中完成分组统计即可。

### 3.4 状态管理的原始与撕裂
- 全项目没有引入统一状态管理体系（无 Provider / Riverpod / Bloc），仅主题使用了 `ValueNotifier`（`ThemeController`）；
- 核心页面使用千行级 `StatefulWidget`，大面积依赖 `setState()` 触发全局重绘；
- 页面间传参通过 `Navigator.push` 返回后简单粗暴地调用 `_refreshData()`，导致整个页面所有数据被全量重新拉取，丢失用户当前的滚动位置与临时上下文。

### 3.5 安全合规与隐私泄露大忌
- **真实账户 Token 硬编码并公开于 Git**：
  在 本地历史工具 `docs/yikaobang/src/spider.py:16-19`（未纳入Git） 中，曾包含开发者真实账号凭据。归档时已删除示例中的敏感值，保留问题说明；未经脱敏原稿仅留本地：
  ```python
  token = '[REDACTED]'
  secret = '[REDACTED]'
  user_id = '[REDACTED]'
  user_uuid = '[REDACTED]'
  working_dir = '[REDACTED]'
  ```
  该文件不仅泄露了个人的医考帮鉴权密钥，还泄露了开发机的本地私有绝对目录。一旦代码开源或推送至公共仓库，账号凭据即可被任何人窃取滥用。
- **固定 Salt 与常量硬编码**：
  在客户端 [`ykb_encrypt.dart`](../../../lib/common/ykb_encrypt.dart#L5-L30) 中，设备 UUID、签名固定混淆串等被死写在客户端。

---

## 4. 系统化重构与改进路线图 (Actionable Roadmap)

为彻底解决上述顽疾，建议按四个阶段推进工程重构：

```mermaid
flowchart LR
    Phase1["阶段 1：止血与契约修正\n(修复斩题Bug/主观题死锁/强解包/UUID碰撞)"]
    Phase2["阶段 2：体验与离线加固\n(图片三级缓存/离线兜底/N+1查询消除)"]
    Phase3["阶段 3：架构分层与组件解耦\n(拆解千行上帝类/领域层抽象/Riverpod状态管理)"]
    Phase4["阶段 4：高级特性与合规治理\n(凭据剥离/FTS5搜索/主观题自测交互)"]

    Phase1 --> Phase2 --> Phase3 --> Phase4
```

### 第一阶段：紧急修复与数据契约统一（高优先级 / 立即实施）

#### 1. 彻底统一斩题状态契约
废弃所有的 `"cutted"` 和 `0` 字符串比较，将斩题状态在数据库、UI 与同步服务中**强制标准化为整型数字或明确常量**：
- 数据库与 Dart 模型：统一使用整型 `int isCut`（`0`: 未斩, `1`: 已斩）；
- 同步合并代码修正：统一为 `(localCut == 1 || srcCut == 1) ? 1 : 0`；
- 在数据库启动升级脚本中执行清洗：`UPDATE Question SET cut_question = '1' WHERE cut_question = 'cutted';`。

#### 2. 安全随机 ID 算法重写
替换不可靠的 `generateSimpleId()`，改用标准的纳秒级时间戳或 `dart:math` 配合安全随机源：
```dart
import 'dart:math';

final _random = Random.secure();
String generateSecureId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final r = _random.nextInt(900000) + 100000;
  return '$now$r';
}
```

#### 3. 移除危险的强解包 (`!`)
在所有计算答案比较的地方，引入空值保护：
```dart
final String correctAns = question.answer ?? '';
if (correctAns.isNotEmpty && sortString(userAnswer) == sortString(correctAns)) {
  userQuestion.status = 1;
} else if (correctAns.isNotEmpty) {
  userQuestion.status = 2;
}
```

---

### 第二阶段：性能调优与离线体验加固（中优先级）

#### 1. 消除首页 N+1 查询
重写 [`getSubjectsWithChapters()`](../../../lib/screens/choosed_subjects_page.dart#L19-L31)，在 SQL 层面一次性联表拉取所有选中课程及其章节：
```sql
SELECT
  S.id AS subject_id, S.name AS subject_name,
  C.id AS chapter_id, C.name AS chapter_name,
  IC.total AS chapter_total,
  UIC.correct AS chapter_correct, UIC.incorrect AS chapter_incorrect
FROM IdentitySubject AS UIS
JOIN Subject AS S ON S.id = UIS.subject_id
JOIN IdentityChapter AS IC ON IC.subject_id = S.id AND IC.identity_id = UIS.identity_id
JOIN Chapter AS C ON C.id = IC.chapter_id
LEFT JOIN IdentityChapter AS UIC ON UIC.bank_id = UIS.bank_id
                                AND UIC.chapter_id = C.id
WHERE UIS.bank_id = ? AND UIS.selected = 1;
```
由一条 SQL 在底层完成 Join 过滤，Dart 端只做组装，首页载入速度可实现成倍提升。

#### 2. 图片三级缓存与离线兜底
引入 `cached_network_image`，并封装统一的 `AppNetworkImage` 组件：
```dart
Widget buildQuestionImage(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
  return CachedNetworkImage(
    imageUrl: imageUrl,
    height: 200,
    fit: BoxFit.contain,
    placeholder: (context, url) => const SizedBox(
      height: 200,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    errorWidget: (context, url, error) => Container(
      height: 120,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey),
          SizedBox(height: 8),
          Text('图片离线不可用或加载失败', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    ),
  );
}
```

---

### 第三阶段：架构解耦与千行页面拆治（演进重构）

#### 1. 拆解 1400 行上帝组件 `QuestionDetailPage`
将单体巨类按责任拆分成独立的小型 StatelessWidget / StatefulWidget：
- `QuestionHeaderWidget`：负责展示题型标签、序号进度、公共题干与配图；
- `QuestionOptionsSelector`：负责单选/多选题列表渲染、选项状态绑定；
- `QuestionExplainCard`：解析展示卡片、正确答案徽章、考点标签；
- `TestModeTimerController`：将测试计时逻辑与 UI 解耦，避免每秒触发整个题目详情页 `setState`；
- `QuestionActionsBar`：收藏、斩题、复制题干解析、报错按钮栏。

#### 2. 引入现代状态管理（如 Riverpod 或 Signals）
- 建立 `ActiveBankController`：统一监听当前激活题库的切换，避免依赖各页面反查 `SharedPreferences`；
- 建立 `UserQuestionStateNotifier`：按题目 ID 提供作答流式订阅，题目状态变更时精准局部刷新单个卡片或格子，无需页面整树重绘。

---

### 第四阶段：功能健全度与安全合规升级

#### 1. 扩充主观题交互模式（盘活护理题库近万道题）
针对 `type` 为 3~7（填空题、名词解释、简答题、论述题、病例分析）的主观题：
1. **隐藏单选/多选选项列表**；
2. **提供“显示参考答案与解析”大按钮**；
3. **引入“自我评估”机制**：用户看完题目和解析后，点击“记住了（标为正确）”或“没记住（标为错误）”，完成状态落库与章节进度累加。

#### 2. 安全合规与敏感信息整肃
1. 立即从 `spider.py` 中删除固化的 `token`、`secret`、`user_id`；
2. 引入 `python-dotenv`，所有测试账号信息均从本地不入库的 `.env` 中读取；
3. 将 `.env`、`*.local` 正式加入根目录 `.gitignore`；
4. 建议在医考帮后台重置被泄露 Token 的账号密码，使历史提交记录失效。

---

## 5. 总结：给开发者的寄语

“医不帮”是一个**极其具有实际生产力和用户价值的作品**。它没有那些大公司开源项目里繁文缛节的包装，而是从一名医学生的真实刷题痛点出发，用硬核的逆向手段、离线 SQLite 架构和扎实的自制主题，打造出了一个远比原厂 App 轻快纯粹的工具。

在 Vibe Coding 时代，AI 确实成倍放大了你的开发速度，让多题库拆分、跨库搜索、图表聚合等原本需要两周的功能在几天内落地；但本次体检也清楚地证明：**AI 目前只具备“局部补丁能力”，缺乏“系统性架构审美与契约把控力”**。

消灭掉上述这几个由于前后契约不一致导致的隐蔽 Bug，再把 N+1 查询与千行上帝类做一次针对性手术，这个项目在代码质量、健壮性与架构设计上就真正具备了工业级开源精品的质感！
