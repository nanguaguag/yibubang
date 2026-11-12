#!/usr/bin/env python3
"""Validate real corpus export and source immutability; makes no network calls."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import sys

from build import file_hash, google_document, readonly


def validate(snapshot):
    manifest = json.loads((snapshot / "manifest.json").read_text())
    for entry in manifest["files"]:
        path = snapshot / entry["path"]
        if path.stat().st_size != entry["bytes"] or file_hash(path) != entry["sha256"]:
            raise ValueError("产物完整性失败：" + str(path))
    with readonly(snapshot / "corpus.sqlite") as db:
        for source in db.execute("SELECT * FROM sources"):
            path = Path(json.loads(source["config"])["path"])
            if file_hash(path) != source["fingerprint"]:
                raise ValueError("来源已变化或不是本次导出快照：" + str(path))
        expected = {r[0]: r[1] for r in db.execute("SELECT id,export_hash FROM chunks")}
        count = 0
        for path in sorted((snapshot / "google").glob("full-*.jsonl")):
            with path.open() as f:
                for line in f:
                    row = json.loads(line)
                    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", row["id"]):
                        raise ValueError("非法Google ID")
                    serialized = json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                    if hashlib.sha256(serialized.encode()).hexdigest() != expected.pop(row["id"], None):
                        raise ValueError("重复ID/产物与SQLite记录不同")
                    html = base64.b64decode(row["content"]["rawBytes"], validate=True)
                    if len(html) > 1_000_000 or len(line.encode()) >= 1_000_000:
                        raise ValueError("Google文档超限")
                    for forbidden in ("user_answer", "cut_question", "collection", "Activities", "Notes"):
                        if forbidden in row["structData"]:
                            raise ValueError("导出了个人字段")
                    count += 1
        if expected or count != manifest["chunks"]:
            raise ValueError("导出数量不一致")
        probes = [("1637905", "苯丙氨酸", "C"), ("1637906", "CD8", "B"), ("1084839", "平台期", "B")]
        passed = 0
        for qid, term, answer in probes:
            row = db.execute("SELECT payload FROM documents WHERE id=?", ("question:" + qid,)).fetchone()
            if row:
                doc = json.loads(row[0])
                if term not in doc["text"] or doc["fields"]["answer"] != answer:
                    raise ValueError("医学内容探针失败：" + qid)
                passed += 1
    print(json.dumps({"result": "PASS", "documents": manifest["documents"], "chunks": count,
                      "source_hashes_verified": len(manifest["sources"]), "medical_probes_passed": passed}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path, nargs="?", default=Path(__file__).parent / "artifacts" / "current")
    args = parser.parse_args()
    try:
        validate(args.snapshot)
    except (ValueError, OSError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
