# 医不帮 App AI 搜索

已接入现有医学 Search Data Store，独立 Cloud Run 服务已上线。重新构建 App 后，底栏/桌面侧栏出现「AI 搜索」，默认追加在原四项之后；可在原导航设置中重排或隐藏。

## 使用

- 输入医学问题，页面依次显示检索、整理资料、平滑流式回答。星芒呼吸动画、等待骨架、状态淡入淡出；支持深色模式和小屏/大字体，比较表格可横向滑动。
- 点回答内 `[1]` 引用或「参考题目」卡片，按全局 `question_id` 打开原题并带上已有作答。对应独立题库必须已在本机安装、启用；缺失时给出下载提示。既有全局查询不包含兼容回退的旧合并题库 `legacy_combined`，旧库需先迁移为独立题库。
- 底部继续输入即可追问；铅笔修改问题后重新生成，该问题以后的分支被替换。「重新回答」也会替换后续分支。停止按钮保留已收到的内容。
- 右上角历史按钮切换/删除会话，旁边加号开启新会话。生成期间先停止，再切换或删除。
- 会话写入 `user_data.sqlite` 的 `AiSearchSessions` / `AiSearchTurns`，约每 700 ms 保存一次，结束时再保存。异常退出后显示「回答已停止，内容已保留」。用户库升级 v24→v25；不改题库或 Question 主键。
- 对话不加入现有跨设备同步。已有整库 SQLite 备份包含这些本地表；删除会话不重置搜索额度。

## 已部署资源

| 资源 | 配置 / 控制台 |
| --- | --- |
| 项目 | `yibubang-search` / `520065588983` |
| Cloud Run | [yibubang-ai-search，东京](https://console.cloud.google.com/run/detail/asia-northeast1/yibubang-ai-search/revisions?project=yibubang-search) |
| App API | `https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app` |
| Search | 既有 `global/yibubang-medical-search`，`default_search`，Data Store `yibubang-medical-v1`，Standard；沿用 149,448 道唯一题 |
| 限额数据库 | [Firestore：yibubang-ai](https://console.cloud.google.com/firestore/databases?project=yibubang-search)，Native/Standard，东京 |
| 回答模型 | Vertex `gemini-3.8-flash`，global，LOW thinking，输出上限 2048 tokens；未向客户端转发隐藏思维或 thought signature |
| 容器 | CPU 1 / 512 MiB；min 0 / max 2；concurrency 16；Cloud Run 请求上限 180 秒，检索+生成总上限 165 秒 |

运行账号 `yibubang-ai-runtime@yibubang-search.iam.gserviceaccount.com` 的自定义推理角色只包含 `discoveryengine.servingConfigs.search` 和 `aiplatform.endpoints.predict`；`roles/datastore.user` 通过 IAM condition 限定 `projects/yibubang-search/databases/yibubang-ai`。Google 凭据来自运行账号 ADC，不写入 App。Cloud Run 对外可访问，搜索接口另验安装凭据；匿名搜索返回 401。

启用 API：Cloud Run、Cloud Build、Artifact Registry、Firestore、Vertex AI 和原有 Discovery Engine。没有创建重复知识库，也不需要启用 Vector Search API。

Firestore 仅保存设备凭据哈希、服务端计数和并发租约；两个按日计数集合的 `expires_at` 已设置 TTL，约三天后异步清理。设备凭据记录保留以免重新注册重置额度。**当前问题与最多三轮已完成历史会经服务端发给 Google，用于本次回答**，服务端不持久化对话，也不主动记录问题、回答、凭据。Cloud Run 自动请求日志仍有连接信息和 URL。

## 限额与防滥用

| 规则 | 默认值 |
| --- | --- |
| 每安装/天 | 100 次，北京时间 0 点刷新，使用服务器时间 |
| 每安装/分钟 | 6 次 |
| 每安装并发 | 1 个，180 秒租约；正常结束/失败/断连释放，崩溃自动过期 |
| 每 IP/天 | 300 次 |
| 全站/天 | 2,000 次 |
| 每 IP 新注册/天 | 3 个安装 |
| 全站新注册/天 | 100 个安装 |
| 输入 | 问题 2,000 字，最多三轮历史，实际请求体 64 KB；App 根据 UTF-8 字节数裁掉过长的最早历史 |
| 上游输出 | 最多 2048 tokens / 12,000 字符；不完整输出明确标记，保留内容 |

计数在 Firestore 事务中先扣额度再调用 Google，客户端改时钟/改剩余额度/并发请求不能绕过。已受理的重试、修改、上游失败和取消也计一次，避免用失败请求耗费资源；校验/限额拒绝不计数。最近同一请求 ID 重放返回 409。断开连接停止继续转发，并取消上游流。

安装凭据不是不可伪造的硬件身份证；清 App 数据、复制安装凭据、换 IP/批量脚本仍是边界。当前 IP 取直接 Cloud Run 入口追加的最右地址哈希，线上已对照请求日志 remoteIp 验证；如果以后加负载均衡器/CDN，必须重审可信代理链，不能直接沿用该规则。

正式大规模发布建议下一步接 Android Play Integrity、iOS App Attest，以及桌面账号/一次性人机验证；按账号叠加限额并配 Cloud Armor 入口速率限制。IP 限制可能影响校园/医院共享出口，当前值适合控制试用成本，用户增长后按实际情况调整。随机安装 ID、IP 和全站配额只能降低滥用，不能替代平台证明或边缘防护。

### 调整与停用

Cloud Run 控制台「修改并部署新修订版本」→变量与密钥，可调整：

- `GLOBAL_DAILY_LIMIT`：全站总搜索，默认 2000；设为 `0` 可立即停止新搜索（需发布新修订）。
- `IP_DAILY_LIMIT`：共享网络每日总搜索，默认 300。
- `GEMINI_MODEL` / `GEMINI_LOCATION`：更换仍受支持的模型；不同模型的 thinking 参数需一并验证。
- `SEARCH_ENGINE`：更换搜索引擎。设备 100/天、6/分钟及注册限额在 `policy.py` / `app.py` 中修改并重新部署。

专项 GenAI App Builder credit **不能据此推定涵盖 Gemini、Cloud Run、Firestore**。生成及运行可能单独计费；Cloud Run 请求/Firestore读写即使拒绝也可能有成本。全站搜索限额控制已受理的模型次数，不是金额硬上限。结算控制台应按实际 trial SKU 核对，并按可接受金额设置预算通知。

## 构建与重新部署

App 已内置线上 URL，正常 `flutter run -d macos` 或 `flutter run -d <设备>` 即可。更换地址：

```sh
flutter run -d macos --dart-define=AI_SEARCH_ENDPOINT=https://你的服务地址
```

部署脚本会复用同名数据库/账号/角色，配置 TTL，并部署独立服务：

```sh
python3 ai_backend/deploy.py --project yibubang-search --gcloud /path/to/google-cloud-sdk/bin/gcloud
```

已经 provision 后仅部署代码：

```sh
gcloud run deploy yibubang-ai-search --source=ai_backend --region=asia-northeast1 --project=yibubang-search
```

本地依赖和检查：

```sh
python3 -m venv ai_backend/.venv
ai_backend/.venv/bin/pip install -r ai_backend/requirements.txt
ai_backend/.venv/bin/python -m unittest discover -s ai_backend -p 'test_*.py' -v
flutter analyze --no-pub
flutter test --no-pub
```

线上完整探针（每次消耗两次检索/生成）：

```sh
ai_backend/.venv/bin/python ai_backend/smoke.py
```

只检查注册、health、额度与匿名拒绝，不调用模型：

```sh
ai_backend/.venv/bin/python ai_backend/smoke.py --check-only
```

探针凭据首次随机生成，保存于忽略的 `ai_backend/.local/smoke-device.json`，权限 0600。不要把它加入版本控制。完整探针会验证流式终止、引用、追问、请求重放和额度准确减少。管理员限额验收脚本 `smoke_limits.py` 只临时设置专用探针设备的计数并在 finally 恢复，不动全站/IP计数或用户安装：

```sh
ai_backend/.venv/bin/python ai_backend/smoke_limits.py --gcloud /path/to/gcloud
```

## 后续知识库迁移

当前服务读取原有 Search Engine，新增题库仍按 [知识库手册](../scripts/knowledge_base/README.md) 本地 build/validate→增量 sync，App 无需重建本地会话。额度结束迁到自建向量库时，用原有标准 JSONL、稳定 chunk ID 和全局 question ID 替换服务端检索适配，继续保留 SSE 协议、引用字段与 App 会话表，不必重新清洗源数据。

当前 App 原题链接针对题库题目；尚未导入的教材 PDF 将来需要补 PDF 来源/页码查看器。结构化题目检索、教材段落检索可共存，但 PDF 引用不能假装成原题 ID。

[验证记录](VALIDATION.md) · [页面源码](../lib/screens/ai_search_page.dart) · [客户端](../lib/services/ai_search_client.dart) · [服务端](app.py)
