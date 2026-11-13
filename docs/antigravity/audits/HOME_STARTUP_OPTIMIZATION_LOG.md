# 首页启动最小优化记录

基线：main@d862099，用户库v24、题库v1。范围：M02投影指纹、M01同步状态无效重载、M03隐藏Tab初始化；保留所有题库校验/迁移/后台业务及数据库事务。每项独立最小修改与测试。本轮未执行commit/push/部署，改动保留供审阅。

## M02：完成

- data_transfer.dart查找及保存均使用同一真实路径/size/mtime指纹；保留ATTACH SQL、原子重算及文件变更失效，无schema/依赖变化。
- 新增6项真实SQLite回归：原路径/真实路径10次热读取零写入；符号链接；历史指纹一次重建及选课保留；文件关系变化；显式重算与共享题状态；缺文件失败保留旧投影。
- 与作答并发、重做/交卷、SQLite兼容既有回归共24/24通过。本机SQLite3.43.2；Windows符号链接创建需要额外权限，该单项在Windows注明跳过，普通路径验证仍执行。
- 最终全量/静态分析见下方总验收。

## M01：完成

- CloudSyncService保留原状态/配置通知；新增只读dataRevision，只有成功落库的非空拉取页在同步结束时失效一次。部分分页失败仍通知先前已提交数据，坏页回滚不通知，删除墓碑也覆盖。
- 首页及统计订阅数据revision；首页同页云数据更新保留旧列表，显式换库/选课刷新保持原等待行为，FutureBuilder继续处理旧请求失效。
- 新增生产页面/真实临时SQLite/模拟HTTP回归5/5：初始化和空同步无重读、协议失败pending保留、状态通知仍发送、落库等待保留课程并更新计数、部分失败/坏页回滚、统计流水增删与答题通知、退出页面后同步。原outbox9/9也通过。
- M01按通知来源减少无效重读；没有修改同步payload、ACK、游标、重试和重算SQL。

## M03：完成（仅隐藏Tab初始化切片）

- HomePage保留IndexedStack/PageView与原导航回调；宽屏未访问页面仅挂载KeepAlive壳，首次选择再挂业务页，访问后不因切Tab销毁。
- 每个Home实例4个稳定GlobalKey覆盖IndexedStack的内部包装，导航重排及当前页宽窄切换能保留对应实例；窄屏PageView保持原预加载和滑动模式。
- 新增5项实际HomePage回归5/5：初始只挂课程/无默认ReviewPlan写入；首次计划加载/反复切换/课程展开状态；自定义首Tab；重排/禁用未访问统计；1000→600→1000宽窄切换与滑动。
- 不修改目录initialize、备份、校验、迁移或后台队列时序；M03完整分阶段目录初始化和M04/M05统计/调度优化仍是后续独立方案。

## 最终验收

- Flutter全量 **314/314**，包含原298项与新增16项；后端8/8、tsc通过；flutter analyze --no-pub **0 issues**（去掉测试辅助文件的一条无用import，未屏蔽告警）。
- 修复后审计探针3/3：M01/M02改为断言正确行为；M13保持未修现状，不混入业务改动。
- 十万题macOS FFI3.43.2样本：首次投影105ms；别名路径连续10次 **2ms / SQL行变更0**，真实路径10次2ms。此前同工作量1.52–1.54秒/2000010次行变更。只代表本机合成数据，不换算实机启动秒数。
- 题库客户端只读、Question全局单列ID、用户库ATTACH事务、SQLite3.22兼容契约、schema v24及依赖保持。测试验证文件变化、显式重算、答案/收藏/计数/选课、partial-sync/失败保留与导航行为。
- git diff --check通过；只修改5个产品文件、3个测试套件和1个辅助文件及相关文档，保留开始已有的文档变更；未commit/push/部署。
- 边界：未完成Android/Windows/Linux真机启动profile；Windows符号链接测试因系统权限仅该项显式跳过。400px默认Ahem测试字体下旧每日卡片两标签Row出现横向溢出，宽窄回归用600px跨640断点，不将其称为400px真实字体验收；未在启动优化中改卡片布局。

## 源码与测试位置

- [data_transfer.dart](../../../lib/db/data_transfer.dart#L63)：共享真实路径指纹；[question_projection_cache_test.dart](../../../test/question_projection_cache_test.dart)。
- [cloud_sync_service.dart](../../../lib/services/cloud_sync_service.dart#L104)：提交数据revision；[choosed_subjects_page.dart](../../../lib/screens/choosed_subjects_page.dart#L89)、[statistics_page.dart](../../../lib/screens/statistics_page.dart#L33)：精确订阅；[home_data_refresh_test.dart](../../../test/home_data_refresh_test.dart)。
- [home_page.dart](../../../lib/screens/home_page.dart#L155)：延迟业务页面挂载；[home_startup_tabs_test.dart](../../../test/home_startup_tabs_test.dart)。

下一步：先审阅本轮diff并测用户机器冷/热启动；按实际数据决定是否认领M04/M05。协议v2服务端发布和M13算法入口属于独立目标，仍未部署/未修复。
