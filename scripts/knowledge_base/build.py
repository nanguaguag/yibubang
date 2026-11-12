#!/usr/bin/env python3
"""Offline, reproducible corpus builder. Source banks are ALWAYS opened read-only."""
import argparse
import base64
from contextlib import contextmanager
import hashlib
import html
from html.parser import HTMLParser
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
import tempfile
import time
import unicodedata

VERSION = 1
FIELDS = ("id", "title", "public_title", "option", "answer", "explain", "restore",
          "year", "type", "type_str", "title_img", "explain_img", "restore_img")


def dumps(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


class TextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.hidden += 1
        if tag in ("br", "p", "div", "li", "tr"):
            self.parts.append("\n")
        if tag == "img":
            alt = dict(attrs).get("alt", "")
            if alt:
                self.parts.append("[图：" + alt + "]")

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.hidden = max(0, self.hidden - 1)
        if tag in ("p", "div", "li", "tr", "h1", "h2", "h3"):
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def clean(value):
    s = str(value or "")
    # Parse only actual tags; retain medical inequalities such as K+ < 3.5.
    if re.search(r"</?[a-zA-Z][\w:-]*(?:\s[^<>]*|\s*/?)>", s):
        p = TextParser()
        p.feed(s)
        s = "".join(p.parts)
    s = unicodedata.normalize("NFC", html.unescape(s)).replace("\r", "\n")
    s = re.sub(r"[\t \u00a0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n\n", s).strip()


def normalize(raw):
    fields = {k: clean(raw.get(k)) for k in FIELDS if k != "option"}
    options = raw.get("option") or "[]"
    try:
        options = json.loads(options) if isinstance(options, str) else options
    except (ValueError, TypeError) as exc:
        raise ValueError(f"题目 {fields['id']} 选项不是合法 JSON") from exc
    if not isinstance(options, list) or any(not isinstance(o, dict) for o in options):
        raise ValueError(f"题目 {fields['id']} 选项必须是对象数组")
    fields["options"] = [{"key": clean(o.get("key")), "text": clean(o.get("title")),
                          "image": str(o.get("img") or "")} for o in options]
    return fields


def question_text(fields):
    parts = []
    for label, key in [("共用题干", "public_title"), ("题干", "title")]:
        if fields[key]:
            parts.append(label + "：" + fields[key])
    parts += [o["key"] + ". " + o["text"] for o in fields["options"]]
    for label, key in [("正确答案", "answer"), ("解析", "explain"), ("教材依据", "restore")]:
        if fields[key]:
            parts.append(label + "：" + fields[key])
    images = [fields[k] for k in ("title_img", "explain_img", "restore_img") if fields[k]]
    images += [o["image"] for o in fields["options"] if o["image"]]
    if images:
        parts.append("含配图；图片内容未做 OCR，检索文本不含图片内信息。")
    return "\n\n".join(parts), images


def split_text(text, limit, overlap):
    """Deterministic character chunks. These are NOT tokenizer token counts."""
    start = 0
    while start < len(text):
        end = min(start + limit, len(text))
        if end < len(text):
            cut = max(text.rfind("\n", start + limit // 2, end),
                      text.rfind("。", start + limit // 2, end))
            if cut >= 0:
                end = cut + 1
        yield text[start:end]
        if end == len(text):
            break
        start = max(start + 1, end - overlap)


@contextmanager
def readonly(path):
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA query_only=ON")
    try:
        yield db
    finally:
        db.close()


def load_sqlite(db, source, path):
    with readonly(path) as bank:
        columns = {r["name"] for r in bank.execute("PRAGMA table_info(Question)")}
        required = {"id", "title", "answer", "explain", "option"}
        if not required <= columns:
            raise ValueError(f"{path}: 不是内容题库（禁止导入 user_data.sqlite）")
        if bank.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError(f"{path}: SQLite quick_check 失败")
        cols = [k for k in FIELDS if k in columns]
        count = 0
        for row in bank.execute('SELECT ' + ','.join('"' + k + '"' for k in cols) + ' FROM Question ORDER BY id'):
            raw = dict(row)
            qid = str(raw["id"] or "")
            if not qid:
                raise ValueError(f"{path}: 空 question_id")
            fields = normalize(raw)
            db.execute("INSERT INTO variants VALUES(?,?,?,?,?,?)", (
                source["id"], qid, dumps(raw), dumps(fields), digest(dumps(fields)),
                int(source.get("priority", 0))))
            count += 1
        tables = {r[0] for r in bank.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {"IdentityQuestion", "Subject", "Chapter"} <= tables:
            raise ValueError(f"{path}: 缺少题库权威关系表")
        relations = bank.execute("""
            SELECT r.question_id, r.identity_id, r.subject_id, r.chapter_id,
                   s.name AS subject, c.name AS chapter
            FROM IdentityQuestion r
            LEFT JOIN Subject s ON s.id=r.subject_id
            LEFT JOIN Chapter c ON c.id=r.chapter_id
            ORDER BY r.question_id,r.identity_id,r.subject_id,r.chapter_id
        """)
        db.executemany("INSERT OR IGNORE INTO relations VALUES(?,?,?)", (
            (source["id"], str(r["question_id"]), dumps({
                "bank_id": source["id"], "identity_id": str(r["identity_id"]),
                "subject_id": str(r["subject_id"]), "chapter_id": str(r["chapter_id"]),
                "subject": clean(r["subject"]), "chapter": clean(r["chapter"])
            })) for r in relations))
    return count


def load_pages(db, source, path):
    if source["type"] == "pdf":
        try:
            from pypdf import PdfReader
        except ImportError as exc:
            raise ValueError("导入 PDF 需在独立虚拟环境安装 pypdf；参见 README") from exc
        reader = PdfReader(str(path))
        if reader.is_encrypted and not reader.decrypt(""):
            raise ValueError(f"{path}: 加密 PDF，先提供可读版本")
        rows = ({"page": i + 1, "text": p.extract_text() or ""} for i, p in enumerate(reader.pages))
    else:
        def read_rows():
            with path.open(encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        yield json.loads(line)
        rows = read_rows()
    count = 0
    blank = []
    seen = set()
    for row in rows:
        page = int(row["page"])
        if page < 1 or page in seen:
            raise ValueError(f"{path}: 重复或非法页码 {page}")
        seen.add(page)
        text = clean(row["text"])
        if not text:
            blank.append(page)
        payload = dumps({"page": page, "text": text})
        db.execute("INSERT INTO pages VALUES(?,?,?)", (source["id"], page, payload))
        count += 1
    if count == 0 or len(blank) == count:
        raise ValueError(f"{path}: 无可检索文本；扫描 PDF 请先在本地 OCR")
    return count, blank


class JsonlWriter:
    def __init__(self, folder, prefix, max_bytes=64 * 1024 * 1024):
        self.folder = folder
        self.prefix = prefix
        self.max_bytes = max_bytes
        self.files = []
        self.f = None
        self.size = 0

    def write(self, value):
        data = (dumps(value) + "\n").encode("utf-8")
        if len(data) >= 1_000_000:
            raise ValueError("Google 文档行超过 1 MB；减小 chunk_chars")
        if self.f is None or self.size + len(data) > self.max_bytes:
            self.close()
            p = self.folder / f"{self.prefix}-{len(self.files):05d}.jsonl"
            self.files.append(p)
            self.f = p.open("wb")
            self.size = 0
        self.f.write(data)
        self.size += len(data)

    def close(self):
        if self.f:
            self.f.close()
        self.f = None


def google_document(chunk):
    m = chunk["metadata"]
    title = chunk["title"]
    content = '<html lang="zh"><head><meta charset="utf-8"><title>' + html.escape(title) + '</title></head><body><h1>' + html.escape(title) + '</h1><pre>' + html.escape(chunk["text"]) + '</pre></body></html>'
    return {"id": chunk["id"], "structData": {
        "title": title, "uri": chunk["uri"], "text": chunk["text"],
        "document_id": chunk["document_id"], "question_id": m.get("question_id", ""),
        "kind": m["kind"], "bank_ids": m.get("bank_ids", []),
        "subjects": m.get("subjects", []), "source_ids": m["source_ids"],
        "page_start": m.get("page_start", 0), "page_end": m.get("page_end", 0),
        "content_hash": chunk["content_hash"]
    }, "content": {"mimeType": "text/html", "rawBytes": base64.b64encode(content.encode()).decode()}}


def google_schema():
    props = {}
    for k in ("title", "uri", "text", "document_id", "question_id", "kind", "content_hash"):
        props[k] = {"type": "string", "retrievable": True}
    props["title"]["keyPropertyMapping"] = "title"
    props["uri"]["keyPropertyMapping"] = "uri"
    props["text"]["searchable"] = True
    for k in ("question_id", "kind", "document_id"):
        props[k]["indexable"] = True
    for k in ("bank_ids", "subjects", "source_ids"):
        props[k] = {"type": "array", "items": {"type": "string", "retrievable": True, "indexable": True}}
    for k in ("page_start", "page_end"):
        props[k] = {"type": "integer", "retrievable": True, "indexable": True}
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "properties": props}


def build(config_path):
    started = time.monotonic()
    config_path = config_path.resolve()
    config = json.loads(config_path.read_text())
    if config.get("format_version") != VERSION:
        raise ValueError("未知配置版本")
    limit = int(config.get("chunk_chars", 1800))
    overlap = int(config.get("overlap_chars", 160))
    if not 100 <= limit <= 20000 or not 0 <= overlap < limit // 2:
        raise ValueError("chunk_chars 应为100–20000，overlap_chars应小于一半")
    out = (config_path.parent / config["output"]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    lock = out / ".build.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise ValueError(f"已有构建锁 {lock}；确认无构建进程后才可删除") from exc
    os.close(fd)
    stage = Path(tempfile.mkdtemp(prefix=".build-", dir=out))
    db = None
    try:
        previous = out / "current"
        old_db = previous / "corpus.sqlite"
        db = sqlite3.connect(stage / "corpus.sqlite")
        db.row_factory = sqlite3.Row
        db.executescript("""
            CREATE TABLE sources(id TEXT PRIMARY KEY, fingerprint TEXT, config TEXT, item_count INTEGER, blank_pages TEXT);
            CREATE TABLE variants(source_id TEXT, question_id TEXT, raw TEXT, fields TEXT, hash TEXT, priority INTEGER,
                                  PRIMARY KEY(source_id,question_id));
            CREATE INDEX variant_question ON variants(question_id,priority DESC,source_id);
            CREATE TABLE relations(source_id TEXT,question_id TEXT,payload TEXT,PRIMARY KEY(source_id,question_id,payload));
            CREATE INDEX relation_question ON relations(question_id,payload);
            CREATE TABLE pages(source_id TEXT,page INTEGER,payload TEXT,PRIMARY KEY(source_id,page));
            CREATE TABLE documents(id TEXT PRIMARY KEY,payload TEXT);
            CREATE TABLE chunks(id TEXT PRIMARY KEY,document_id TEXT,content_hash TEXT,export_hash TEXT,payload TEXT);
        """)
        if old_db.exists():
            db.execute("ATTACH DATABASE ? AS previous", (old_db.resolve().as_uri() + "?mode=ro",))
        stats = {"format_version": VERSION, "sources": [], "documents": 0, "chunks": 0,
                 "conflicting_questions": 0, "new_or_updated_chunks": 0, "deleted_chunks": 0,
                 "text_bytes": 0, "image_documents": 0, "empty_documents": 0,
                 "answer_letter_conflicts": 0, "answer_content_conflicts": 0}
        ids = set()
        for source in config["sources"]:
            sid = source["id"]
            if not re.fullmatch(r"[a-z][a-z0-9_-]{0,62}", sid) or sid in ids:
                raise ValueError(f"来源 id 非法或重复：{sid}")
            ids.add(sid)
            path = (config_path.parent / source["path"]).resolve()
            if not path.is_file():
                raise ValueError(f"来源文件不存在：{path}")
            before = path.stat()
            fingerprint = file_hash(path)
            settings = dumps({**source, "path": str(path), "builder_version": VERSION})
            old = db.execute("SELECT * FROM previous.sources WHERE id=?", (sid,)).fetchone() if old_db.exists() else None
            cached = bool(old and old["fingerprint"] == fingerprint and old["config"] == settings)
            blank = []
            if cached:
                for table in ("variants", "relations", "pages"):
                    db.execute(f"INSERT INTO {table} SELECT * FROM previous.{table} WHERE source_id=?", (sid,))
                count = old["item_count"]
                blank = json.loads(old["blank_pages"])
            elif source["type"] == "sqlite":
                count = load_sqlite(db, source, path)
            elif source["type"] in ("pdf", "pages_jsonl"):
                count, blank = load_pages(db, source, path)
            else:
                raise ValueError(f"未知来源类型：{source['type']}")
            after = path.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValueError(f"构建期间来源改变：{path}，关闭题库同步后重试")
            if any(Path(str(path) + suffix).exists() for suffix in ("-wal", "-journal")):
                raise ValueError(f"{path}: 来源有未合并事务日志，请先关闭应用并导出一致快照")
            db.execute("INSERT INTO sources VALUES(?,?,?,?,?)", (sid, fingerprint, settings, count, dumps(blank)))
            stats["sources"].append({"id": sid, "type": source["type"], "sha256": fingerprint,
                                      "items": count, "reused_cache": cached, "blank_pages": blank})
            db.commit()
            print(f"来源 {sid}: {count} 项，{'缓存复用' if cached else '只读清洗'}", flush=True)
        cloud_dir = stage / "google"
        cloud_dir.mkdir()
        full = JsonlWriter(cloud_dir, "full")
        delta = JsonlWriter(cloud_dir, "delta")
        portable = (stage / "chunks.jsonl").open("w", encoding="utf-8")
        docs_file = (stage / "documents.jsonl").open("w", encoding="utf-8")
        conflicts = (stage / "conflicts.jsonl").open("w", encoding="utf-8")

        def emit(document):
            stats["documents"] += 1
            db.execute("INSERT INTO documents VALUES(?,?)", (document["id"], dumps(document)))
            docs_file.write(dumps(document) + "\n")
            if not document["text"]:
                stats["empty_documents"] += 1
                return
            if document["metadata"].get("images"):
                stats["image_documents"] += 1
            for i, text in enumerate(split_text(document["text"], limit, overlap)):
                # Include stable context on every segment of a long record.
                context = document.get("chunk_context", "")
                text = (context + "\n\n" + text) if context else text
                cid = "c-" + digest(document["id"])[:32] + f"-{i:04d}"
                chunk = {"format_version": VERSION, "id": cid, "document_id": document["id"],
                         "chunk_index": i, "title": document["title"], "uri": document["uri"],
                         "text": text, "content_hash": digest(text), "metadata": document["metadata"]}
                google = google_document(chunk)
                export_hash = digest(dumps(google))
                db.execute("INSERT INTO chunks VALUES(?,?,?,?,?)", (cid, document["id"], chunk["content_hash"], export_hash, dumps(chunk)))
                portable.write(dumps(chunk) + "\n")
                full.write(google)
                old = db.execute("SELECT export_hash FROM previous.chunks WHERE id=?", (cid,)).fetchone() if old_db.exists() else None
                if not old or old[0] != export_hash:
                    delta.write(google)
                    stats["new_or_updated_chunks"] += 1
                stats["chunks"] += 1
                stats["text_bytes"] += len(text.encode())

        relation_groups = iter(itertools.groupby(db.execute("SELECT question_id,payload FROM relations ORDER BY question_id,payload"), lambda r: r[0]))
        relation_qid, relation_rows = next(relation_groups, (None, []))
        variants = db.execute("SELECT * FROM variants ORDER BY question_id,priority DESC,source_id")
        for qid, group in itertools.groupby(variants, lambda r: r["question_id"]):
            rows = list(group)
            selected = rows[0]
            while relation_qid is not None and relation_qid < qid:
                list(relation_rows)
                relation_qid, relation_rows = next(relation_groups, (None, []))
            relations = []
            if relation_qid == qid:
                relations = [json.loads(r[1]) for r in relation_rows]
                relation_qid, relation_rows = next(relation_groups, (None, []))
            fields = json.loads(selected["fields"])
            all_fields = [(r["source_id"], json.loads(r["fields"])) for r in rows]
            answer_letter_conflict = len({f["answer"] for _, f in all_fields}) > 1
            def answer_text(f):
                return sorted(o["text"] for o in f["options"] if o["key"] in f["answer"]) if f["options"] else [f["answer"]]
            answer_variants = [{"source_id": sid, "answer": f["answer"], "answer_text": answer_text(f)} for sid, f in all_fields]
            answer_content_conflict = len({dumps(v["answer_text"]) for v in answer_variants}) > 1
            stats["answer_letter_conflicts"] += int(answer_letter_conflict)
            stats["answer_content_conflicts"] += int(answer_content_conflict)
            if len({r["hash"] for r in rows}) > 1:
                stats["conflicting_questions"] += 1
                conflicts.write(dumps({"question_id": qid, "selected_source": selected["source_id"],
                                       "changed_fields": sorted({k for _, f in all_fields for k in fields if f[k] != fields[k]}),
                                       "answer_content_conflict": answer_content_conflict,
                                       "answer_variants": answer_variants if answer_letter_conflict or answer_content_conflict else [],
                                       "variants": [{"source_id": r["source_id"], "hash": r["hash"], "priority": r["priority"]} for r in rows]}) + "\n")
            text, images = question_text(fields)
            title = (fields["title"] or fields["public_title"] or "医学题目 " + qid)[:240]
            context = "题目ID：" + qid + "；题干：" + title
            if fields["answer"]:
                context += "；正确答案：" + fields["answer"]
            if answer_content_conflict:
                warning = "【来源答案存在分歧，尚未进行医学审核】本段采用 " + selected["source_id"] + " 的来源版本。"
                versions = "；".join(v["source_id"] + "=" + v["answer"] + "(" + ",".join(v["answer_text"]) + ")" for v in answer_variants)
                text = warning + "\n" + versions + "\n\n" + text.replace("正确答案：", "所选来源答案：")
                context = warning + "\n" + context.replace("正确答案：", "所选来源答案：")
            emit({"format_version": VERSION, "id": "question:" + qid, "title": title,
                  "uri": "yibubang://question/" + qid, "text": text, "fields": fields,
                  "chunk_context": context, "metadata": {"kind": "question", "question_id": qid,
                    "selected_source": selected["source_id"], "source_ids": sorted(r["source_id"] for r in rows),
                    "answer_content_conflict": answer_content_conflict, "answer_variants": answer_variants if answer_content_conflict else [],
                    "bank_ids": sorted(r["source_id"] for r in rows), "relations": relations,
                    "subjects": sorted({r["subject"] for r in relations if r["subject"]}), "images": images}})
        for source in config["sources"]:
            if source["type"] not in ("pdf", "pages_jsonl"):
                continue
            for row in db.execute("SELECT payload FROM pages WHERE source_id=? ORDER BY page", (source["id"],)):
                page = json.loads(row[0])
                title = source.get("title", source["id"])
                emit({"format_version": VERSION, "id": f"book:{source['id']}:page:{page['page']}",
                      "title": f"{title} · PDF第{page['page']}页", "uri": f"yibubang://book/{source['id']}?page={page['page']}",
                      "text": page["text"], "chunk_context": title + " " + source.get("edition", "") + f" PDF第{page['page']}页",
                      "metadata": {"kind": "textbook", "source_ids": [source["id"]], "edition": source.get("edition", ""),
                                   "page_start": page["page"], "page_end": page["page"],
                                   "printed_page": page["page"] + int(source.get("printed_page_offset", 0))}})
        full.close()
        delta.close()
        portable.close()
        docs_file.close()
        conflicts.close()
        with (stage / "deleted_ids.jsonl").open("w") as f:
            if old_db.exists():
                for row in db.execute("SELECT id FROM previous.chunks WHERE id NOT IN (SELECT id FROM chunks) ORDER BY id"):
                    f.write(dumps({"id": row[0]}) + "\n")
                    stats["deleted_chunks"] += 1
        db.commit()
        if old_db.exists():
            db.execute("DETACH DATABASE previous")
        db.close()
        db = None
        (stage / "google_schema.json").write_text(dumps(google_schema()) + "\n")
        stats["seconds"] = round(time.monotonic() - started, 2)
        stats["config_sha256"] = file_hash(config_path)
        stats["files"] = [{"path": str(p.relative_to(stage)), "sha256": file_hash(p), "bytes": p.stat().st_size}
                          for p in sorted(stage.rglob("*")) if p.is_file()]
        stats["build_id"] = digest(dumps({k: v for k, v in stats.items() if k not in ("seconds", "sources")}))[:24]
        (stage / "manifest.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n")
        (stage / "config.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
        # Keep the last successful snapshot; a failed build never alters current.
        backup = out / "previous"
        if backup.exists():
            shutil.rmtree(backup)
        if previous.exists():
            previous.rename(backup)
        stage.rename(previous)
        print(json.dumps({k: v for k, v in stats.items() if k != "files"}, ensure_ascii=False, indent=2))
        return previous
    finally:
        if db:
            db.close()
        if stage.exists():
            shutil.rmtree(stage)
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(__file__).with_name("config.json"))
    args = parser.parse_args()
    try:
        build(args.config)
    except (ValueError, OSError, sqlite3.Error) as exc:
        print("构建失败：" + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
