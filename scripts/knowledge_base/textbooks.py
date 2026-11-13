#!/usr/bin/env python3
"""Local PDF OCR-layer extraction, portable page corpus, resumable page images.

Never uploads a PDF and never invokes a cloud OCR/model API. PDF physical pages
are the only navigation identity; unverified printed labels remain null.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import time
import unicodedata

import pymupdf as fitz
from PIL import Image

from build import dumps, file_hash

PIPELINE = "ocr-layer-v1"
DEFAULT_SOURCE = Path("/Volumes/My PSSD/书籍/自用53本课本（可复制）")
DEFAULT_OUTPUT = Path("/Volumes/My PSSD/书籍/医不帮教材知识库")


def box_union(boxes):
    return [min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes)]


def extract_page(page):
    traces = page.get_texttrace()
    raw = [{"font": s["font"], "sequence": s["seqno"], "bbox": list(s["bbox"]),
            "text": "".join(chr(c[0]) for c in s["chars"] if c[0] >= 0)} for s in traces]
    hidden = [s for s in traces if s["font"].startswith("Hidden")]
    modern = [s for s in traces if s["font"] == "SimSun"]
    dual = (sum(len(s["chars"]) for s in hidden) > 30 and
            sum(len(s["chars"]) for s in modern) >= .65 * sum(len(s["chars"]) for s in hidden))
    cutoff = min((s["seqno"] for s in modern), default=0)
    # Separate producer's complete newer pass; retain any old glyph outside its
    # spatial coverage (for example a page number absent from the newer pass).
    selected = [s for s in traces if not dual or s["seqno"] >= cutoff]
    grid = defaultdict(list)
    for s in selected:
        for c in s["chars"]:
            b = c[3]
            cx, cy = (b[0]+b[2])/2, (b[1]+b[3])/2
            grid[(int(cx//12), int(cy//12))].append(b)
    glyphs = []
    removed = 0
    for s in traces:
        for c in s["chars"]:
            if c[0] < 0:
                continue
            b = c[3]
            cx, cy = (b[0]+b[2])/2, (b[1]+b[3])/2
            if dual and s["seqno"] < cutoff:
                near = [bb for x in range(int(cx//12)-1,int(cx//12)+2)
                        for y in range(int(cy//12)-1,int(cy//12)+2) for bb in grid[(x,y)]]
                if any(bb[0]-2 <= cx <= bb[2]+2 and bb[1]-2 <= cy <= bb[3]+2 for bb in near):
                    removed += 1
                    continue
            glyphs.append((chr(c[0]), b, c[2], s["font"]))
    # Cluster physical baselines, preserving horizontal reading and glyph boxes.
    rows = []
    for g in sorted(glyphs, key=lambda g: (g[2][1], g[1][0])):
        if rows and abs(g[2][1]-rows[-1][0]) < 3.5:
            rows[-1][1].append(g)
        else:
            rows.append([g[2][1], [g]])
    blocks = []
    printed = None
    split_rows = []
    for baseline, chars in rows:
        chars.sort(key=lambda g: g[1][0])
        groups = [[]]
        for g in chars:
            if groups[-1] and g[1][0]-groups[-1][-1][1][2] > 18:
                groups.append([])
            groups[-1].append(g)
        split_rows.extend(groups)
    for chars in split_rows:
        text = unicodedata.normalize("NFC", "".join(g[0] for g in chars)).strip()
        if not text:
            continue
        box = box_union([g[1] for g in chars])
        margin = box[3] < page.rect.height*.085 or box[1] > page.rect.height*.92
        if margin and re.fullmatch(r"[0-9]{1,4}", text):
            if printed is None:
                printed = text
            elif printed != text:
                printed = None
        blocks.append({"bbox": box, "text": text, "margin": margin})
    text = "\n".join(b["text"] for b in blocks)
    bad = sum(ch == "\ufffd" or 0xe000 <= ord(ch) <= 0xf8ff for ch in text)
    quality = []
    if dual:
        quality.append("dual_ocr_layer_deduplicated")
    if len(text.strip()) < 40:
        quality.append("sparse_or_nontext_page")
    if bad > max(3, len(text)*.01):
        quality.append("unusable_text_needs_review")
    if re.search(r"[ⅡⅢⅣ]-\d|[∫∑√]", text):
        quality.append("medical_symbols_or_formula_review")
    return {"text": text, "raw_blocks": raw, "blocks": blocks,
            "printed_page": printed, "quality": quality, "removed_glyphs": removed,
            "width": page.rect.width, "height": page.rect.height, "rotation": page.rotation}


def process_book(job):
    path, output = map(Path, job)
    sha = file_hash(path)
    title = re.sub(r"^\d+\.", "", path.stem)
    title = re.sub(r"[（(]\s*可复制\s*[）)]", "", title).strip()
    bid = "tb_" + hashlib.sha256(title.encode()).hexdigest()[:12]
    version = sha[:16]
    folder = output / "books" / bid / version
    folder.mkdir(parents=True, exist_ok=True)
    completed = folder / "book.json"
    if completed.exists() and json.loads(completed.read_text()).get("pipeline") == PIPELINE:
        return {"book_id": bid, "reused": True}
    before = (path.stat().st_size, path.stat().st_mtime_ns)
    pdf = fitz.open(path)
    margin_counts = Counter()
    quality = Counter()
    part = folder / "pages.raw.jsonl.part"
    with part.open("w", encoding="utf8") as out:
        for i, page in enumerate(pdf):
            record = extract_page(page)
            record.update({"page": i+1, "page_id": f"{bid}:{version}:{i+1}",
                "image_key": f"textbooks/{bid}/{version}/pages/{i+1:04d}.webp"})
            out.write(dumps(record)+"\n")
            margin_counts.update({b["text"] for b in record["blocks"] if b["margin"]})
            quality.update(record["quality"])
    page_count = len(pdf)
    pdf.close()
    if before != (path.stat().st_size, path.stat().st_mtime_ns):
        raise RuntimeError("PDF changed during extraction")
    part.rename(folder / "pages.raw.jsonl")
    repeated = {s for s,n in margin_counts.items() if n >= max(8,page_count*.2)}
    count = 0
    with (folder / "pages.jsonl.part").open("w", encoding="utf8") as out:
        for line in (folder / "pages.raw.jsonl").open(encoding="utf8"):
            r = json.loads(line)
            r["blocks"] = [b for b in r["blocks"] if not (b["margin"] and (b["text"] in repeated or b["text"] == r["printed_page"]))]
            r["text"] = "\n".join(b["text"] for b in r["blocks"])
            r["indexable"] = bool(r["text"].strip()) and "unusable_text_needs_review" not in r["quality"]
            if not r["indexable"]:
                r["text"] = ""
            r.pop("raw_blocks")
            out.write(dumps(r)+"\n")
            count += 1
    (folder / "pages.jsonl.part").rename(folder / "pages.jsonl")
    book = {"book_id": bid, "source_version": version, "source_sha256": sha,
            "source_path": str(path), "title": title, "edition": "", "isbn": "",
            "page_count": count, "pipeline": PIPELINE, "quality_counts": dict(quality),
            "pages_path": str(folder / "pages.jsonl")}
    completed.write_text(dumps(book)+"\n")
    print(f"{title}: {count} pages; quality={dict(quality)}", flush=True)
    return {"book_id": bid, "reused": False}


def finalize(output):
    books = [json.loads(p.read_text()) for p in sorted((output / "books").glob("*/*/book.json"))]
    db_path = output / "textbooks.sqlite.part"
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    db.executescript("""CREATE TABLE Books(book_id TEXT,source_version TEXT,payload TEXT,PRIMARY KEY(book_id,source_version));
        CREATE TABLE Pages(book_id TEXT,source_version TEXT,page INTEGER,payload TEXT,PRIMARY KEY(book_id,source_version,page));
        CREATE TABLE Blocks(page_id TEXT,position INTEGER,payload TEXT,PRIMARY KEY(page_id,position));""")
    public = []
    for book in books:
        db.execute("INSERT INTO Books VALUES(?,?,?)", (book["book_id"],book["source_version"],dumps(book)))
        for line in Path(book["pages_path"]).open(encoding="utf8"):
            r = json.loads(line)
            db.execute("INSERT INTO Pages VALUES(?,?,?,?)", (book["book_id"],book["source_version"],r["page"],dumps(r)))
            db.executemany("INSERT INTO Blocks VALUES(?,?,?)", [(r["page_id"],i,dumps(b)) for i,b in enumerate(r["blocks"])])
        public.append({k:v for k,v in book.items() if k not in ("source_path","pages_path")})
    db.commit()
    assert db.execute("PRAGMA quick_check").fetchone()[0] == "ok"
    db.close()
    db_path.replace(output / "textbooks.sqlite")
    (output / "catalog.json").write_text(dumps({"format_version":1,"books":public})+"\n")
    config_path = Path(__file__).parent / "config.json"
    config = json.loads(config_path.read_text())
    config["sources"] = [s for s in config["sources"] if not s["id"].startswith("tb_")]
    for b in books:
        config["sources"].append({"id": b["book_id"]+"_"+b["source_version"], "type":"pages_jsonl",
            "path": b["pages_path"], "title":b["title"], "edition":b["edition"],
            "book_id":b["book_id"], "source_version":b["source_version"],"page_count":b["page_count"]})
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+"\n")
    print(dumps({"books":len(books),"pages":sum(b["page_count"] for b in books),"database":str(output/"textbooks.sqlite")}))


def page_image(page):
    """Reuse only a complete upright scan with no visible additions or masks."""
    infos=page.get_image_info(xrefs=True)
    visible=[kind for kind,_ in page.get_bboxlog() if kind != "ignore-text"]
    if (len(infos)==1 and visible==["fill-image"] and not page.rotation and
            not list(page.annots() or [])):
        info=infos[0]
        rect=fitz.Rect(info['bbox'])
        a,b,c,d,e,f=info['transform']
        if (info['xref'] and abs(b)<.01 and abs(c)<.01 and a>0 and d>0 and
                all(abs(x-y)<.1 for x,y in zip(rect,page.rect)) and
                abs(info['width']/info['height']-page.rect.width/page.rect.height)<.005):
            image=page.parent.extract_image(info['xref'])
            # Image masks are visible content; the complete render is authoritative.
            if not image.get('smask'):
                im=Image.open(io.BytesIO(image['image'])).convert('RGB')
                im.thumbnail((2400,2400),Image.Resampling.LANCZOS)
                return im,"embedded_complete_scan"
    scale=2400/max(page.rect.width,page.rect.height)
    pix=page.get_pixmap(matrix=fitz.Matrix(scale,scale),alpha=False)
    return Image.frombytes("RGB",(pix.width,pix.height),pix.samples),"full_page_render"


def render_book(job):
    book_file, output = map(Path,job)
    b = json.loads(book_file.read_text())
    source=Path(b["source_path"])
    before=(source.stat().st_size,source.stat().st_mtime_ns)
    if file_hash(source)!=b["source_sha256"]:
        raise RuntimeError('PDF source changed: extract a new source version before rendering')
    pdf = fitz.open(source)
    total = 0
    for i,p in enumerate(pdf):
        key = f"textbooks/{b['book_id']}/{b['source_version']}/pages/{i+1:04d}.webp"
        target = output / "images" / key
        if target.exists():
            total += target.stat().st_size
            continue
        target.parent.mkdir(parents=True,exist_ok=True)
        im, method = page_image(p)
        part = target.with_suffix(".part")
        im.save(part,format="WEBP",quality=85,method=4)
        part.replace(target)
        total += target.stat().st_size
    pdf.close()
    if before!=(source.stat().st_size,source.stat().st_mtime_ns):
        raise RuntimeError('PDF changed during page rendering')
    print(f"images {b['title']}: {b['page_count']} pages, {total/1024**2:.1f} MiB",flush=True)
    return total


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("action",choices=["extract","images","finalize"])
    p.add_argument("--source",type=Path,default=DEFAULT_SOURCE)
    p.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    p.add_argument("--workers",type=int,default=3)
    args=p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    if args.action=="extract":
        files=sorted(args.source.glob("*.pdf"))
        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            list(pool.map(process_book,[(str(f),str(args.output)) for f in files]))
        finalize(args.output)
    elif args.action=="finalize":
        finalize(args.output)
    else:
        files=sorted((args.output / "books").glob("*/*/book.json"))
        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            sizes=list(pool.map(render_book,[(str(f),str(args.output)) for f in files]))
        print(dumps({"image_bytes":sum(sizes),"books":len(files)}))


if __name__=="__main__":
    main()
