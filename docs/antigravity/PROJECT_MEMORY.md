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

版本、数量、部署与验证更新[开发状态](DEVELOPMENT_STATUS.md)；代理工作规则见[AGENT_RULES](AGENT_RULES.md)。
