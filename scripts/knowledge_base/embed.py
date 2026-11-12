#!/usr/bin/env python3
"""Optional migration: OpenAI-compatible embeddings -> cached Qdrant JSONL.

No embedding API is called by build/cloud. Use this only when choosing a backend.
"""
import argparse
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
import urllib.error
import urllib.request
import uuid

from build import digest, dumps, readonly


def check_vectors(response, expected, dimensions):
    data = sorted(response["data"], key=lambda v: v["index"])
    if [v["index"] for v in data] != list(range(expected)):
        raise ValueError("Embedding响应数量或index不完整")
    vectors = [v["embedding"] for v in data]
    size = len(vectors[0]) if vectors else 0
    if size == 0 or (dimensions and size != dimensions):
        raise ValueError("Embedding维度与配置不同")
    if any(len(v) != size or any(isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) for n in v) for v in vectors):
        raise ValueError("Embedding向量维度不一致或含非有限数字")
    return vectors, size


def embed(args):
    key = os.environ.get(args.api_key_env)
    if not key:
        raise ValueError("请设置环境变量 " + args.api_key_env + "；不要把密钥写进配置")
    if not args.endpoint.startswith("https://") and not args.endpoint.startswith("http://localhost:"):
        raise ValueError("Embedding endpoint需要https（localhost可http）")
    cache_dir = args.snapshot.parent / "embeddings"
    cache_dir.mkdir(exist_ok=True)
    identity = dumps({"endpoint": args.endpoint, "model": args.model, "dimensions": args.dimensions,
                      "revision": args.model_revision, "document_prefix": args.document_prefix})
    cache_id = digest(identity)[:24]
    cache = sqlite3.connect(cache_dir / (cache_id + ".sqlite"))
    cache.execute("CREATE TABLE IF NOT EXISTS vectors(hash TEXT PRIMARY KEY,vector TEXT)")
    cache.execute("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT)")
    old_size = cache.execute("SELECT value FROM settings WHERE key='dimensions'").fetchone()
    size = int(old_size[0]) if old_size else args.dimensions
    batch = []
    api_batches = 0

    def send():
        nonlocal size, api_batches
        if not batch:
            return
        body = {"model": args.model, "input": [args.document_prefix + c["text"] for c in batch]}
        if args.dimensions:
            body["dimensions"] = args.dimensions
        req = urllib.request.Request(args.endpoint, data=dumps(body).encode(), headers={
            "Authorization": "Bearer " + key, "Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=120) as r:
            response = json.loads(r.read())
        vectors, returned_size = check_vectors(response, len(batch), size)
        size = returned_size
        cache.executemany("INSERT OR REPLACE INTO vectors VALUES(?,?)", ((c["content_hash"], dumps(v)) for c, v in zip(batch, vectors)))
        cache.execute("INSERT OR REPLACE INTO settings VALUES('dimensions',?)", (str(size),))
        cache.commit()
        api_batches += 1
        print(f"Embedding已缓存批次 {api_batches}（{len(batch)}块、{size}维）", flush=True)
        batch.clear()

    # Deduplicate identical texts before paid embedding calls.
    with readonly(args.snapshot / "corpus.sqlite") as db:
        for row in db.execute("SELECT content_hash,MIN(payload) FROM chunks GROUP BY content_hash ORDER BY content_hash"):
            if not cache.execute("SELECT 1 FROM vectors WHERE hash=?", (row[0],)).fetchone():
                batch.append(json.loads(row[1]))
                if len(batch) >= args.batch_size:
                    send()
        send()
    output = cache_dir / (cache_id + "-qdrant.jsonl")
    stage = output.with_suffix(".tmp")
    count = 0
    with stage.open("w", encoding="utf-8") as f, readonly(args.snapshot / "corpus.sqlite") as db:
        for row in db.execute("SELECT payload FROM chunks ORDER BY id"):
            chunk = json.loads(row[0])
            vector = json.loads(cache.execute("SELECT vector FROM vectors WHERE hash=?", (chunk["content_hash"],)).fetchone()[0])
            point = {"id": str(uuid.uuid5(uuid.NAMESPACE_URL, "yibubang:chunk:" + chunk["id"])),
                     "vector": vector, "payload": chunk}
            f.write(dumps(point) + "\n")
            count += 1
    stage.replace(output)
    metadata = {"model_identity": json.loads(identity), "vector_dimensions": size, "points": count,
                "api_batches_this_run": api_batches,
                "qdrant_collection": {"vectors": {"size": size, "distance": "Cosine"}},
                "query_note": "查询必须使用相同模型、revision和维度；按模型要求设置query前缀。"}
    output.with_suffix(".manifest.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    cache.close()
    print("迁移数据生成：" + str(output), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=Path(__file__).parent / "artifacts" / "current")
    parser.add_argument("--endpoint", required=True, help="完整URL，例如https://供应商/v1/embeddings")
    parser.add_argument("--model", required=True)
    parser.add_argument("--model-revision", required=True, help="固定版本或人为修订号；模型升级时换值以免误用旧向量")
    parser.add_argument("--dimensions", type=int, default=0, help="0=采用模型默认；部分供应商不支持dimensions参数")
    parser.add_argument("--document-prefix", default="", help="某些检索模型需要passage:等前缀")
    parser.add_argument("--api-key-env", default="EMBEDDING_API_KEY")
    parser.add_argument("--batch-size", type=int, default=16)
    args = parser.parse_args()
    try:
        if not 1 <= args.batch_size <= 128:
            raise ValueError("batch-size必须在1–128之间")
        embed(args)
    except (ValueError, OSError, KeyError) as exc:
        # Do not dump HTTP request headers or keys.
        print("Embedding失败（已完成批次已缓存）：" + str(exc), file=sys.stderr)
        sys.exit(1)
