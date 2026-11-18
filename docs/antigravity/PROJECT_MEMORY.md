# 长期技术事实与系统契约

更新2026-11-13；[当前状态](../CURRENT_STATUS.md) / [历史记忆](../archive/development-history/PROJECT_MEMORY.md)。稳定契约与会变动的版本/费率分开记录。

- 医不帮是Flutter跨平台医学刷题与复习App。Android/macOS/Windows/Linux为支持目标，iOS适配中；构建SDK以[pubspec](../../pubspec.yaml)为准。
- 所有正式QuestionBank/<bank_id>/<bank_id>.sqlite只能readOnly打开；用户作答、收藏、斩题、duration/Activities、笔记及AI会话进入user_data.sqlite，当前schema25。
- Question.id在跨库系统全局唯一且为单列主键，bank_id不拆分共享用户状态。跨库统计用SQLite ATTACH，避免Dart多重循环聚合。
- 题库更新写暂存并校验/原子替换，不向正式内容库执行DML/DDL。路径统一path包；不能丢弃用户未提交Git修改。
- 路由pop后不复用失活context；桌面居中Dialog/NavigationRail，窄屏BottomSheet/NavigationBar；子路由结果须冒泡。
- 本地操作先落盘，再处理联网队列；A01–A20一致性修复不代表同步协议v2服务端已部署。启动M01/M02/M03切片优化不等于所有设备毫秒冷启动。
- AI凭据只在Cloud Run；使用Discovery Engine内置Answer，Cloudflare Worker只服务私有教材图片。模型/高级开关/证据数/来源比例保存在本机，每轮请求重读。
- AI会话仅本地保存，但当前问题/有限历史会提交Google；服务端Firestore只存认证哈希、限额/租约。删除会话或TTL不是重置搜索额度的方法。
- 可迁移知识库的资产是本地规范文字、稳定ID/来源、页号/坐标和图片键；不是Google内部向量。换Embedding模型重算向量但无需重做OCR清洗。
- 原PDF留本地，Google仅导清洗文本/来源，页图另存R2；医学符号/版次和冲突仍需审核。免费资料额度/赠金抵扣不作免扣费保证。
- 版本发布与在线更新契约：客户端检测升级始终读取 `yibubang_update.json`，发布或递增版本时必须同步更新 `pubspec.yaml` 与 `yibubang_update.json`（包含 `latest_app`、`latest_app_url`、`update_info` 及各平台 Release 资产直链），缺一不可。
- 混合冷热云同步契约：D1（`yibubang-sync-db`）负责高频细粒度增量同步（作答、流水、自制闪卡、FSRS 记忆曲线、复习计划），R2（`yibubang-user-backups`）负责按需/每周 SQLite 整库 GZip 冷备快照（两者物理隔离，R2 仅快照本地库，不能替代 D1 增量提交）。
- D1 同步性能与参数限制：Cloudflare D1 单条 SQL 绑定参数硬上限为 **100**（非普通 SQLite 的 999）；大批量上传须使用多行合并 `ON CONFLICT DO UPDATE` + 并发查重 + `push_only` 跳过中间 Pull + GZip（>16KB 自动压缩）；客户端在遇到 500/超时时自动缩减单批上限（500 -> 150 -> 50）。
- 卡片图片与 Markdown 渲染契约：卡片与每日复习统一复用 `AppMarkdown`；Markdown 图片统一居中显示且占位尺寸固定（200×140），防止加载后跳变，点击直达 `FullScreenImageView`；图片上传直连医考帮官方图床。
- 教材页图存储与 24 小时会话签名契约：Cloudflare R2 免费额度（10 GB/月）按**全账号**所有桶合计（含 `yibubang-textbooks` 与 `yibubang-user-backups`），新增教材须先本地核算总容量再上传；`textbooks.melonhu.com` Worker 支持 24 小时会话级 HMAC 令牌（`scope=session`），App 本地持久化后直连下载，遇 403 自动静默续签（仍保留单页签名向后兼容）；未备案域名无法使用国内七牛桶，海外七牛实测慢于 CF 直连。

版本、数量、部署与验证更新[开发状态](DEVELOPMENT_STATUS.md)；代理工作规则见[AGENT_RULES](AGENT_RULES.md)。
