# AI 搜索验证记录（2026-11-12）

项目 `yibubang-search`，独立服务东京 `yibubang-ai-search`，最终修订 `yibubang-ai-search-00003-cl2`，100% 流量。App 默认 URL 已替换为实际线上地址。

## 自动化

- `flutter analyze --no-pub`：0 issues。
- 最终 `flutter test --no-pub --reporter expanded`：**334/334 PASS**（原基线 314，新增 20）。日志 `/tmp/ybb_ai_full_final.log`。
- Python FastAPI/策略/事务/上游模拟：**11/11 PASS**，日志 `/tmp/ybb_backend_tests.log`。
- Flutter 新覆盖：任意 UTF-8 单字节/CRLF SSE 边界、无终止帧/异常 EOF、注册阶段取消不启动搜索、追问与编辑分支截断、停止保留中文/emoji、会话持久化/重开/删除、旧日零额度不阻塞新日服务端判断、未完状态恢复、重复发送/会话操作竞态、v24→v25保留原作答和外键完整性。
- UI 新覆盖：欢迎建议、320px/1.6字号、390px、1000px深色、历史/修改/新建/删除操作、检索→输出→停止、可横滑比较表格；引用走真实 `QuestionSearchRepository`→只读已安装题库→`QuestionDetailPage`，题目 `q` 打开时携带原 `user_answer=A`。
- 真实字体 PingFang + MaterialIcons 的六张截图已检查，位于 `ai_backend/.local/screenshots/`（不提交）；手机、桌面、检索骨架、表格均未溢出。截图为部件渲染，不冒充手机实测。

## 线上

- 注册成功、quota成功，未认证搜索 401，错误凭据 401。ADC runtime 的数据库条件 IAM 与推理最小权限经实际请求验证。
- 完整 Search→Gemini SSE→引用→追问探针运行两轮，每轮两次；最终修订那轮：
  - 问题：HLA I 为什么向 CD8 T 细胞提呈抗原？首文字 **3.04s**，总 **5.32s**，12个delta。
  - 追问：与 HLA II 的区别？首文字 **2.58s**，总 **6.19s**，18个delta。
  - 两次均完成 `done`，有真实题目 ID 引用；quota准确 **98→96**，重放返回409。
  - 数值只代表当前开发网络两次样本，不是延迟承诺。模型教学事实仍需要医学审核。
- `smoke_limits.py` 只临时设置专用探针安装计数，验证 **100/天→429、6/分钟→429、活动租约→429、重复请求→409、错误凭据→401**；原字段完整恢复。未调用Google生成，未修改真实用户或全站/IP计数。
- Cloud Run 自动请求日志 remoteIp 的哈希与注册计数IP键一致；当前直接 run.app 入口符合实现假设。未来添加LB/CDN需重审代理链。
- 两个日计数集合已提交 `expires_at` TTL 配置；自动删除为异步过程，本次没有等待三天验证删除。
- 只保存脱敏回执于 `.local/smoke-result.json` / `.local/limits-result.json`，安装凭据0600且忽略，不输出Google令牌。

## 构建

- `flutter build apk --debug --no-pub`：成功，`build/app/outputs/flutter-apk/app-debug.apk`（约170MiB，多架构调试包）。现有 SDK XML/Java8 废弃警告不影响构建；未升级无关依赖。
- `flutter build macos --debug --no-pub`：成功，`build/macos/Build/Products/Debug/yibubang.app`。
- 未连接Android/iOS真机；Windows/Linux未在该macOS机器构建。未发布Release、提交或push。

## 边界

- 每设备当前指安装凭据，重装/换IP/仿造安装仍需Play Integrity/App Attest、账号或边缘限流进一步防护。
- 100次包括已受理的失败、停止和重试。全站2000/天不是货币硬预算，也不阻止公共API的网络/计数读写成本。
- 仅题目引用打开原题；教材PDF页码查看尚未实现，实际PDF尚未供入。
- Google trial credit实际SKU/有效期及是否抵扣Gemini/Cloud Run/Firestore尚未验账；新费用可能单独计费。
- 测试中的题目详情既有官方网络请求被Flutter HTTP测试环境拒绝，验证的是本地原题/作答导航，不是官方在线接口。
