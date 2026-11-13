# AI检索、Markdown与教材预览修订

更新2026-11-13；当前部署00018-q7c/100%，已迁移Search内置生成。[最初修订/外接模型费用核查原文](../archive/ai-search/SEARCH_IMPROVEMENTS.md)仅作历史证据，不能当当前模型配置。

## 当前结果

- 教材/题库独立检索，1–25证据可调、默认12/8:4，显式汇总给内置Answer；独立话题不拼旧主题，明确省略追问用有限前问。
- CommonMark/GFM原生Markdown支持引用块、列表/粗体/表格/代码和LaTeX；组合编号逐个可点。紧凑列表/中文括号粗体及引用/行内公式选择断言均已修复。
- textbooks.melonhu.com为私有R2 Worker入口，鉴权先于缓存；20669缩略图约377590170 bytes全部上传并匹配SHA，关键词高亮/右侧小图、Reader缩放/缓存/键盘完成。
- 模型/改写/流式/证据数/来源比例在统一Material设置组；默认高级，每安装日200额度，基础1/改写2/流式3。App额度不是Google计费倍数。

## 375页是什么意思

质检规则匹配类似[ⅡⅢⅣ]-数字（如OCR可能把IL-2识为Ⅱ-2）或∫/∑/√，得到375物理页/407文本块。这是人工复核候选，不是375页均已证明错误，也不是全部潜在OCR问题。原OCR保留，不自动改公式、字母、上下标、单位或剂量；App/AI证据带needs_review，应打开原页核对。

Google407个质量字段最初Import成功但GET/Search未反映；已只PATCH structData并逐条GET核验，未重传正文。这说明成功回执不能代替实际字段/检索验证。

最新357 Flutter/39后端/analyze0、线上25条/引用、Debug构建见[验收](VALIDATION.md)，医学人工核对/其他真机/大陆网络仍待完成。[教材实施](../knowledge-base/TEXTBOOK_EXECUTION.md) · [数量](RETRIEVAL_LIMITS.md) · [费用](COSTS_AND_BUILTIN_MODELS.md)。
