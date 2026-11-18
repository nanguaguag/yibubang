# 53本教材实施与操作记录

当前状态：53本教材的本地处理、Google文本导入、全部R2页图上传和App功能开发/验收完成。原PDF未上传；可从最新调试版的「AI搜索 → 右上书本 → 教材检索」体验。

更新2026-11-13：页图/小图合计41338对象、7714259450 bytes；AI生成已迁移内置Answer/streamAnswer，Cloud Run00018-q7c/100%。设置可选1–25证据和来源比例，默认12/8:4；每日200额度/基础1–改写2–流式3。近期Android缩放和桌面快捷键通过模拟回归，其他真机/目标地区网络/医学人工校对仍未验收。[最新状态](../CURRENT_STATUS.md) · [费用](../ai-search/COSTS_AND_BUILTIN_MODELS.md)。下方按阶段记录保留各次实施证据。

## 数据与资源

- 本地原PDF：`/Volumes/My PSSD/书籍/自用53本课本（可复制）`，原文件保持不变。
- 本地可迁移主库：`/Volumes/My PSSD/书籍/医不帮教材知识库/textbooks.sqlite`，Books/Pages/Blocks；各书目录另保留原始OCR块、清洗页JSONL和书籍源SHA256。
- 标准检索语料：`scripts/knowledge_base/artifacts/current/` 的corpus.sqlite、documents.jsonl、chunks.jsonl；既有题库和教材共用稳定格式，可以接现有embed.py/Qdrant适配。更换Embedding模型仍需重新计算向量，PDF提取和清洗不必重做。
- Google：yibubang-search/global，Data Store `yibubang-medical-v1`，Engine `yibubang-medical-search`。本次新增21991教材块，原149472题块保留，删除0。不是RAG Engine Corpus或Vector Search Collection。
- 私有R2：`yibubang-textbooks`；独立Worker `yibubang-textbook-pages`；Cloud Run `yibubang-ai-search`只签阅读链接，图片不经过Google。安装鉴权后签名有效5分钟；管理上传密钥与阅读签名密钥隔离，App没有管理密钥。

## 处理结果与质量边界

53本、20669页；2991页双OCR层按位置选层/去重（实际原始序列检查0交错），16558个书页标签候选。36页无可索引文字，但所有页都有阅读图片。239页稀疏/封面/图版候选、375页含待核对的医学符号或公式；没有宣称所有OCR和书页标签已人工校准。版次/ISBN尚未从版权页人工确认，不把文件序号视为版次。

Google只收清洗文本与必要来源字段，不上传PDF、坐标明细或图片；不调用云OCR/Layout Parser、额外Embedding或逐页LLM。原始文本和几何坐标留本地。符号/公式复核标记会传递到App与AI证据；读者应打开原图核对，AI不得据未校对证据断言公式、单位、剂量。

全部20669张WebP经格式/尺寸/完整性/散列检查，缺页0；共7336669280 bytes（6.833GiB），平均346.6KiB/页，长边约2400像素、WebP quality85。完整直立扫描且无可见额外内容时复用嵌入图，其余本地完整渲染。小样核对了医学正文、数学公式、双OCR扫描及病理页；不是所有图版诊断质量的人工验收。

## App使用

进入底栏「AI搜索」，点击右上角书本图标打开「教材检索」。可选择全部教材或指定书名，输入知识点，查看包含关键词的片段和PDF页/书页；点击结果打开原页。教材纯检索不调用Gemini，与AI共用每日200次额度、每分钟6次请求等服务端限制（教材纯检索每次1额度，AI基础/改写/改写加流式分别1/2/3额度）。图片读取使用独立1000次/天、60次/分钟的签名额度；缓存命中无云请求、不扣搜索次数。

AI答案中的题目引用继续打开原题；教材引用打开对应书籍源版本的物理页。阅读器支持双指缩放、翻页、指定PDF页跳转和下载失败重试；按稳定对象键缓存最近160页，已缓存页离线可读。历史会话仍只在本地保存，引用保存稳定身份，不保存过期的阅读链接。

## 后续增加教材或源版本

在原目录加入可读PDF，或使用--source指定目录。运行前确保外置盘连接，原PDF不在其他软件中被写入。下列命令针对当前环境；来源参数和输出路径可更换。

```sh
scripts/knowledge_base/.venv/bin/python -m pip install -r scripts/knowledge_base/textbook-requirements.txt
scripts/knowledge_base/.venv/bin/python scripts/knowledge_base/textbooks.py extract --workers 3
python3 scripts/knowledge_base/build.py
python3 scripts/knowledge_base/validate.py
```

构建会保留既有来源与云成功ID/hash基线。新增版本使用源内容SHA生成不同版本身份，历史引用继续指向旧版本。确认本地统计、质量和delta后更新Google schema（如新增字段）并执行增量sync：

```sh
python3 scripts/knowledge_base/cloud.py sync
```

不要用FULL导入局部delta，也不要重新创建原Store/Engine。CLI正在等待云操作时，用现有operation查询进度，不重复提交。

先在App检索新内容，再制作页图与上传：

```sh
scripts/knowledge_base/.venv/bin/python scripts/knowledge_base/textbooks.py images --workers 6
scripts/knowledge_base/.venv/bin/python scripts/knowledge_base/validate_textbook_images.py
ai_backend/.venv/bin/python scripts/knowledge_base/r2_pages.py upload --workers 16
```

可用--watch边制作边上传已经原子写完的页；成功回执记录在外置盘r2-upload.sqlite，只上传未确认/散列变化的文件。上传工具有进程锁。首次配置Worker/Secret Manager使用r2_pages.py deploy/configure；已配置后日常导入无需重新创建服务或密钥。将新的公开catalog.json复制到ai_backend/textbook_catalog.json，并部署Cloud Run；不要把含本地来源路径、OAuth或管理密钥的文件复制进后端镜像。

上传工具当前使用本机Wrangler已授权OAuth管理独立Worker，实际文件经单独管理凭据传给R2绑定；本机凭据仅存ai_backend/.local（Git忽略/0600）。读取签名密钥在Google Secret Manager，运行账号只有该密钥的读取权限。上传脚本运行环境为macOS，App保持原跨平台接口。

## 验证入口与已取得证据

- 本地导出58来源散列与3个原医学探针PASS；Python管线18项、后端18项；Worker鉴权/过期/路径/上传散列/阅读测试PASS。
- Flutter全量337项PASS、联网测试默认跳过；新增功能相关22项PASS；analyze0。一次旧目录性能门限1532ms/1500ms受并行页图编码影响，临时释放本任务编码CPU后全量337项通过，随后编码已恢复；未放宽门限或修改无关目录功能。
- `TEXTBOOK_LIVE_TEST=1 flutter test --no-pub test/textbook_live_test.dart`：真实App页→生产客户端→Cloud Run→Search通过，实际命中医学免疫学PDF100/书页73。
- `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/textbook_reader_test.dart -d macos`：实际AI引用→原页→双指缩放→翻页101→跳转125→离线缓存PASS。原生截图在ai_backend/.local/screenshots。
- `ai_backend/.venv/bin/python ai_backend/textbook_smoke.py`：真实教材筛选、混合题目/教材AI流式引用、R2字节与本地SHA一致、匿名401/无签名与篡改403，阅读不消耗搜索次数PASS。测试设备搜索额度98→96。

R2全量20669页/7336669280 bytes上传完成，进程正常结束；《医学计算机应用》《医患沟通》《法医学》末页通过正式签名接口下载、SHA与本地一致，不扣搜索次数（ai_backend/.local/textbook-final-images-live.json）。最新analyze0、管线18/后端18/Worker、Flutter相关14及Android/macOS正常main调试构建通过。

最终`verify_textbook_release.py` PASS：重新核对53原PDF散列、完整20669页manifest（无漏页/重复）、全部本地页图SHA与R2成功回执、171463 Google当前导出hash及教材引用→页图映射。回执为`artifacts/cloud/textbook-final-validation.json`，Google未确认块0；本核查使用上传时R2写入后返回的SHA回执，另有实际远端下载抽检，不宣称重新下载全部页图。

407条复核元数据增量导入回执全成功，但在线GET/Search曾未返回新字段；仅对现有文档PATCH structData补齐，保持正文和其他元数据不变（1试点+406）。407条逐项GET核验PASS；真实Search和Cloud Run返回《耳鼻咽喉头颈外科学》PDF20页needs_review=true。回执为`artifacts/cloud/textbook-review-metadata-repair.json`和`textbook-review-live.json`。后续新增字段或元数据变更，应在线核对GET与Search实际返回，不能仅以Import成功计数或本地hash账本推断字段已生效。

最新普通产品构建：`build/macos/Build/Products/Debug/yibubang.app`、`build/app/outputs/flutter-apk/app-debug.apk`。运行原生integration test后需要重新构建普通main，以免把测试入口当成产品。Windows/Linux/iOS、Android真机与各目标地区网络尚未实测；不据macOS测试推定这些验收完成。未发布Release或push。


## 2026-11-13 检索与页图速度修订

页图正式地址改为https://textbooks.melonhu.com，仍为同一私有R2和签名Worker；鉴权后才允许命中边缘缓存。全部20669缩略图已从现有WebP本地生成/上传，377590170bytes，本地SHA与R2成功回执完整匹配；查询卡片使用独立小图/300图本地缓存，不下载整张页图作预览。增加关键词底色高亮。具体测试、独立教材优先检索、Markdown和模型费用说明见[SEARCH_IMPROVEMENTS.md](../ai-search/SEARCH_IMPROVEMENTS.md)。

## 2026-11-18 口腔教材扩充（70本）与24小时会话级页图签名

1. **口腔教材并入知识库**：
   - 来源 `/Volumes/My PSSD/书籍/口腔教科书全套/`（17 本、4,967 页）；`textbooks.py` 新增 `parse_title_edition` 剥离 `J01：` 前缀与后缀、拆出 `第X版` 至 `edition`，并过滤 macOS `._*` 元数据文件；
   - 与原 53 本合并为 **70 本 / 25,636 页**；`build.py` 增量构建全库 **175,084** 文档、**177,020** 检索块（新增 **5,557** 条口腔教材块，`deleted_chunks: 0`），已同步至 Google AI Search `yibubang-medical-v1`（operation `import-documents-8293321359334584749`）。
2. **R2 10 GB 免费额度控制与存储选型踩坑**：
   - 原 2400px/q85 渲染 17 本口腔页图达 2.002 GB，与原 53 本合并后 `yibubang-textbooks` 达 9.822 GB，且同账号另有冷备桶 `yibubang-user-backups`（R2 免费额度按**全账号 10 GB/月**核算），极易超限；
   - 改用长边 `2000px` / WebP `quality=75` 重压缩 17 本口腔页图后降至 **1.214 GB**，全库 51,272 对象（25,636 页图 + 25,636 缩略图）合计 **9,034,170,996 bytes（9.034 GB / 8.414 GiB）**；
   - 实测对比（同一批 10 张 ~325 KB 原图）：未备案域名 `melonhu.com` 绑七牛云只能使用海外新加坡桶 `yibubang-outsea`，冷/热均耗时 **2,922 ms / 2,319 ms**，反而慢于 CF 直连（**2,586 ms / 1,660 ms**），且七牛每月仅 10 GB 免费 HTTP 流量（R2 流量免费）。故最终放弃七牛，全部留存 Cloudflare R2。
3. **24 小时会话级签名优化（消除翻页 7.4s 东京签名延迟）**：
   - 实测原方案每次翻页先请求东京 Cloud Run 签名平均耗时 **7,416 ms**（总耗时 **14,803 ms**）；
   - `ai_backend` 新增 `GET /v1/textbooks/session`（部署版本 `yibubang-ai-search-00019-mdm`），`worker.js` 支持 `scope=session`（24 小时有效期），App 端 `TextbookClient` 持久化会话令牌至 `SharedPreferences`，翻页与缩略图直接走 `https://textbooks.melonhu.com`，遇到 403/过期时自动静默续签并重试一次。
4. **环境踩坑记录**：
   - `gcloud` 存在多账号时，`cloud.py sync` 需确认激活账号为 `melondoon@gmail.com`（否则 GCS 返回 403）；
   - 外置硬盘 `/Volumes/My PSSD` 休眠断连会引发 `OSError: [Errno 6] Device not configured`，重新挂载后重跑 `validate_textbook_images.py` 与 `r2_pages.py upload` 即可断点续传。
