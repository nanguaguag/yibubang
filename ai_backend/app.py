"""Cloud Run: device quota + Search retrieval + Gemini SSE. No cloud chat storage."""
import asyncio
import hashlib
import json
import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
import ipaddress

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from google.cloud import firestore
import google.auth
import google.auth.transport.requests
import httpx

from policy import (PolicyError, authenticate, day_key, generation_body,
                    quota_info, reserve_device, retrieval_query, secret_hash,
                    validate_identity, validate_question)

PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "yibubang-search")
ENGINE = os.environ.get("SEARCH_ENGINE", "yibubang-medical-search")
MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.8-flash")
MODEL_LOCATION = os.environ.get("GEMINI_LOCATION", "global")
GLOBAL_LIMIT = int(os.environ.get("GLOBAL_DAILY_LIMIT", "2000"))
IP_LIMIT = int(os.environ.get("IP_DAILY_LIMIT", "300"))
DATABASE = os.environ.get("FIRESTORE_DATABASE", "yibubang-ai")
credentials = None
db = None
http = None
token_lock = asyncio.Lock()


@asynccontextmanager
async def lifespan(app):
    global credentials, db, http
    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    db = firestore.Client(project=PROJECT, database=DATABASE)
    http = httpx.AsyncClient(timeout=httpx.Timeout(90, connect=10))
    yield
    await http.aclose()
    db.close()


app = FastAPI(lifespan=lifespan)


@app.exception_handler(PolicyError)
async def policy_error(request, error):
    return JSONResponse({"message": error.message}, status_code=error.status,
                        headers={"Retry-After": "60"} if error.status == 429 else {})


@app.middleware("http")
async def size_limit(request, call_next):
    # Buffer once to enforce an actual bound, including chunked HTTP bodies.
    if request.method == "POST":
        chunks = []
        size = 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > 64000:
                return JSONResponse({"message": "请求内容过长"}, status_code=413)
            chunks.append(chunk)
        request._body = b"".join(chunks)
    return await call_next(request)


def identity(request):
    device_id = request.headers.get("x-device-id", "")
    auth = request.headers.get("authorization", "")
    secret = auth[7:] if auth.startswith("Bearer ") else ""
    validate_identity(device_id, secret)
    return device_id, secret


def ip_key(request):
    # Use the rightmost valid address appended by the managed ingress.
    # IP limits are a supplementary signal; installation/global quotas are authoritative.
    forwarded = request.headers.get("x-forwarded-for", "")
    parts = [p.strip() for p in forwarded.split(",") if p.strip()]
    address = parts[-1] if parts else (request.client.host if request.client else "unknown")
    try:
        address = str(ipaddress.ip_address(address))
    except ValueError:
        address = "unknown"
    return hashlib.sha256(address.encode()).hexdigest()[:40]


def register_transaction(transaction, device_id, secret, ip, now):
    ref = db.collection("ai_devices").document(device_id)
    existing = ref.get(transaction=transaction)
    if existing.exists:
        authenticate(existing.to_dict(), secret)
        return
    ip_ref = db.collection("ai_registration_limits").document(day_key(now) + "-" + ip)
    global_ref = db.collection("ai_registration_limits").document(day_key(now) + "-global")
    ip_data = ip_ref.get(transaction=transaction).to_dict() or {}
    global_data = global_ref.get(transaction=transaction).to_dict() or {}
    if ip_data.get("count", 0) >= 3 or global_data.get("count", 0) >= 100:
        raise PolicyError("今天新设备注册较多，请稍后再试")
    transaction.set(ref, {"secret_hash": secret_hash(secret), "created_at": now})
    transaction.set(ip_ref, {"count": ip_data.get("count", 0) + 1,
                             "expires_at": datetime.fromtimestamp(now, timezone.utc) + timedelta(days=3)})
    transaction.set(global_ref, {"count": global_data.get("count", 0) + 1,
                                 "expires_at": datetime.fromtimestamp(now, timezone.utc) + timedelta(days=3)})


def reserve_transaction(transaction, device_id, secret, ip, request_id, now):
    ref = db.collection("ai_devices").document(device_id)
    device = ref.get(transaction=transaction).to_dict()
    authenticate(device, secret)
    updates = reserve_device(device, now, request_id)
    global_ref = db.collection("ai_request_limits").document(day_key(now) + "-global")
    ip_ref = db.collection("ai_request_limits").document(day_key(now) + "-" + ip)
    global_data = global_ref.get(transaction=transaction).to_dict() or {}
    ip_data = ip_ref.get(transaction=transaction).to_dict() or {}
    if global_data.get("count", 0) >= GLOBAL_LIMIT:
        raise PolicyError("今天的服务额度已用完，请明天再来", 503)
    if ip_data.get("count", 0) >= IP_LIMIT:
        raise PolicyError("当前网络请求较多，请稍后再试")
    transaction.update(ref, updates)
    transaction.set(global_ref, {"count": global_data.get("count", 0) + 1,
                                 "expires_at": datetime.fromtimestamp(now, timezone.utc) + timedelta(days=3)})
    transaction.set(ip_ref, {"count": ip_data.get("count", 0) + 1,
                             "expires_at": datetime.fromtimestamp(now, timezone.utc) + timedelta(days=3)})
    return quota_info(updates, now)


def release_transaction(transaction, device_id, request_id):
    ref = db.collection("ai_devices").document(device_id)
    device = ref.get(transaction=transaction).to_dict() or {}
    if device.get("last_request") == request_id:
        transaction.update(ref, {"lease_until": 0})


async def google_headers():
    async with token_lock:
        if not credentials.valid:
            await asyncio.to_thread(credentials.refresh, google.auth.transport.requests.Request())
    return {"Authorization": "Bearer " + credentials.token, "Content-Type": "application/json"}


def frame(event, data):
    return "event: " + event + "\ndata: " + json.dumps(data, ensure_ascii=False) + "\n\n"


@app.get("/health")
async def health():
    return {"status": "ok", "service": "yibubang-ai-search", "model": MODEL,
            "daily_limit": 100, "protocol": 1}


@app.post("/v1/devices")
async def register(request: Request):
    device_id, secret = identity(request)
    await asyncio.to_thread(firestore.transactional(register_transaction), db.transaction(), device_id, secret, ip_key(request), time.time())
    return {"registered": True}


@app.get("/v1/quota")
async def quota(request: Request):
    device_id, secret = identity(request)
    def read():
        device = db.collection("ai_devices").document(device_id).get().to_dict()
        authenticate(device, secret)
        return quota_info(device, time.time())
    return await asyncio.to_thread(read)


@app.post("/v1/search")
async def search(request: Request):
    device_id, secret = identity(request)
    try:
        body = await request.json()
    except ValueError:
        raise PolicyError("请求格式无效", 400)
    if not isinstance(body, dict):
        raise PolicyError("请求格式无效", 400)
    question, request_id, history = validate_question(body)
    quota = await asyncio.to_thread(firestore.transactional(reserve_transaction), db.transaction(), device_id, secret,
                                    ip_key(request), request_id, time.time())

    async def produce():
        try:
            yield frame("quota", quota)
            yield frame("phase", {"message": "正在检索医学题库"})
            url = f"https://discoveryengine.googleapis.com/v1/projects/{PROJECT}/locations/global/collections/default_collection/engines/{ENGINE}/servingConfigs/default_search:search"
            response = await http.post(url, headers=await google_headers(), json={
                "query": retrieval_query(question, history), "pageSize": 6, "languageCode": "zh-CN"})
            response.raise_for_status()
            evidence = []
            for item in response.json().get("results", []):
                fields = item.get("document", {}).get("structData", {})
                text = fields.get("text", "")
                if text:
                    evidence.append({"number": len(evidence) + 1, "question_id": str(fields.get("question_id", "")),
                        "title": fields.get("title", ""), "text": text[:4200], "source_ids": fields.get("source_ids", [])})
            yield frame("citations", {"items": [{k: v for k, v in e.items() if k != "text"} for e in evidence]})
            if not evidence:
                yield frame("delta", {"text": "题库中暂未检索到足够的依据。试试补充疾病名称、关键症状或知识点，我会重新查找。"})
                yield frame("done", {})
                return
            yield frame("phase", {"message": "已找到相关资料，正在整理回答"})
            host = "aiplatform.googleapis.com" if MODEL_LOCATION == "global" else MODEL_LOCATION + "-aiplatform.googleapis.com"
            url = f"https://{host}/v1/projects/{PROJECT}/locations/{MODEL_LOCATION}/publishers/google/models/{MODEL}:streamGenerateContent?alt=sse"
            size = 0
            finish = None
            async with asyncio.timeout(150):
                async with http.stream("POST", url, headers=await google_headers(),
                                       json=generation_body(question, history, evidence)) as result:
                    result.raise_for_status()
                    async for line in result.aiter_lines():
                        if await request.is_disconnected():
                            return
                        if not line.startswith("data:"):
                            continue
                        chunk = json.loads(line[5:])
                        for candidate in chunk.get("candidates", []):
                            finish = candidate.get("finishReason", finish)
                            for part in candidate.get("content", {}).get("parts", []):
                                if part.get("thought") or not part.get("text"):
                                    continue
                                text = part["text"]
                                size += len(text)
                                if size > 12000:
                                    raise RuntimeError("answer_too_long")
                                yield frame("delta", {"text": text})
            if not size:
                yield frame("error", {"message": "这次未能生成回答，请调整问题后重试"})
            elif finish != "STOP":
                yield frame("error", {"message": "回答未完整生成，已保留内容，可修改问题后重试"})
            else:
                yield frame("done", {})
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            # Log only exception type/status, never questions, answers or credentials.
            print(json.dumps({"event": "upstream_error", "type": type(exc).__name__,
                              "status": getattr(getattr(exc, "response", None), "status_code", None)}), flush=True)
            yield frame("error", {"message": "AI 服务暂时不可用，已保留当前内容，请稍后重试"})

    async def stream():
        try:
            # Covers retrieval and generation together; stays below the device lease.
            async with asyncio.timeout(165):
                async for event in produce():
                    yield event
        except TimeoutError:
            yield frame("error", {"message": "回答等待超时，已保留内容，请稍后重试"})
        finally:
            try:
                await asyncio.shield(asyncio.to_thread(firestore.transactional(release_transaction), db.transaction(), device_id, request_id))
            except Exception:
                pass  # Lease expires; no permanent lock after process termination.
    return StreamingResponse(stream(), media_type="text/event-stream", headers={
        "Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"})
