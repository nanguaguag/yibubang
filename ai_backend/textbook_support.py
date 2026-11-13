"""Typed evidence and private textbook image signing, separate from generation."""
import json
import os
from pathlib import Path
import re
import hashlib
import hmac
import time
from urllib.parse import urlencode

from policy import PolicyError, day_key


def catalog():
    path = Path(__file__).with_name("textbook_catalog.json")
    return json.loads(path.read_text()).get("books", []) if path.exists() else []


def citation(fields, number):
    item = {"number": number, "kind": fields.get("kind", "question"),
            "question_id": str(fields.get("question_id", "")), "title": fields.get("title", ""),
            "source_ids": fields.get("source_ids", [])}
    if item["kind"] == "textbook":
        item.update({k:fields.get(k, "") for k in ("book_id", "book_title", "source_version", "edition", "isbn", "image_key", "printed_page")})
        item.update({k:fields.get(k, 0) for k in ("page_count", "page_width", "page_height")})
        item["pdf_page"] = int(fields.get("page_start", 0))
        item["needs_review"] = bool(fields.get("needs_review", False))
    return item


def evidence(results):
    items = []
    seen = set()
    for result in results:
        f = result.get("document", {}).get("structData", {})
        text = f.get("text", "")
        identity = ((f.get("book_id"), f.get("source_version"), f.get("page_start"))
                    if f.get("kind") == "textbook" else f.get("question_id"))
        if text and identity not in seen:
            seen.add(identity)
            items.append({**citation(f, len(items)+1), "text":text[:4200]})
    return items


def search_snippet(text, query, limit=900):
    terms=re.findall(r"[A-Za-z0-9+-]{2,}|[\u4e00-\u9fff]{2,}",query)[:30]
    lower=text.lower()
    anchors=[lower.find(t.lower()) for t in terms if lower.find(t.lower())>=0]
    if not anchors:
        return text[:limit]
    windows=[max(0,p-90) for p in anchors]
    start=max(windows,key=lambda p:sum(len(t) for t in terms if t.lower() in lower[p:p+limit]))
    return ("…" if start else "")+text[start:start+limit]+("…" if start+limit<len(text) else "")


def resolve_page(book_id, version, page):
    b = next((b for b in catalog() if b["book_id"] == book_id and b["source_version"] == version), None)
    if b is None or page < 1 or page > b["page_count"]:
        raise PolicyError("教材或页码不存在", 404)
    return b, f"textbooks/{book_id}/{version}/pages/{page:04d}.webp"


def image_quota(device, now):
    day = day_key(now)
    used = device.get("image_used",0) if device.get("image_day") == day else 0
    minute = int(now//60)
    minute_used = device.get("image_minute_used",0) if device.get("image_minute") == minute else 0
    if used >= 1000 or minute_used >= 60:
        raise PolicyError("翻页较快，请稍后继续阅读")
    return {"image_day":day,"image_used":used+1,"image_minute":minute,"image_minute_used":minute_used+1}


def signed_page(key):
    if os.environ.get("TEXTBOOK_IMAGE_ENDPOINT") and os.environ.get("TEXTBOOK_IMAGE_SIGNING_KEY"):
        expires = int(time.time()) + 300
        signature = hmac.new(os.environ["TEXTBOOK_IMAGE_SIGNING_KEY"].encode(),
            (key+"\n"+str(expires)).encode(),hashlib.sha256).hexdigest()
        return os.environ["TEXTBOOK_IMAGE_ENDPOINT"].rstrip("/")+"/"+key+"?"+urlencode({"expires":expires,"signature":signature})
    if not all(os.environ.get(k) for k in ("R2_ACCOUNT_ID","R2_BUCKET","R2_ACCESS_KEY_ID","R2_SECRET_ACCESS_KEY")):
        raise PolicyError("教材页图正在准备中，请稍后再打开", 503)
    import boto3
    from botocore.config import Config
    client = boto3.client("s3", endpoint_url="https://"+os.environ["R2_ACCOUNT_ID"]+".r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        region_name="auto",config=Config(signature_version="s3v4"))
    return client.generate_presigned_url("get_object",Params={"Bucket":os.environ["R2_BUCKET"],"Key":key},ExpiresIn=300)
