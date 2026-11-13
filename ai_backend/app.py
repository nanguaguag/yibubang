"""Cloud Run: device quotas + Search retrieval and built-in Answer. Local chats."""
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
                    DAILY_LIMIT, generation_options, quota_info, reserve_device, retrieval_query, secret_hash,
                    validate_identity, validate_question)
from textbook_support import catalog, evidence as make_evidence, resolve_page, image_quota, signed_page, search_snippet
from retrieval import retrieve, textbook_count
from answer_models import AnswerModelCatalog
from builtin_answer import answer_body, answer_packets, cited_answer

PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "yibubang-search")
ENGINE = os.environ.get("SEARCH_ENGINE", "yibubang-medical-search")
ANSWER_ENGINE = os.environ.get("ANSWER_ENGINE", "yibubang-medical-answer")
MODEL = os.environ.get("ANSWER_MODEL", "stable")
model_catalog = AnswerModelCatalog()
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


def reserve_transaction(transaction, device_id, secret, ip, request_id, now, cost=1):
    ref = db.collection("ai_devices").document(device_id)
    device = ref.get(transaction=transaction).to_dict()
    authenticate(device, secret)
    updates = reserve_device(device, now, request_id, cost)
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
            "provider": "search_answer", "generation_mode": "configurable_answer",
            "default_rephrase": True, "default_streaming": True,
            "retrieval_ratio_enabled": True, "default_textbook_count": 8,
            "daily_limit": DAILY_LIMIT, "protocol": 1}


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


async def authenticated_device(request):
    device_id, secret = identity(request)
    def read():
        device = db.collection("ai_devices").document(device_id).get().to_dict()
        authenticate(device, secret)
    await asyncio.to_thread(read)
    return device_id, secret


@app.get("/v1/models")
async def models(request: Request, refresh: bool = False):
    await authenticated_device(request)
    # Refreshes use a shared bounded cache, not paid generation probes.
    return await model_catalog.get(http, refresh)


@app.get("/v1/textbooks")
async def books(request: Request):
    await authenticated_device(request)
    return {"books":catalog()}


@app.post("/v1/textbooks/search")
async def textbook_search(request: Request):
    device_id, secret = identity(request)
    try:
        body = await request.json()
    except ValueError:
        raise PolicyError("请求格式无效",400)
    if not isinstance(body,dict):
        raise PolicyError("请求格式无效",400)
    question, request_id, history = validate_question(body)
    book_id = body.get("book_id", "")
    if not isinstance(book_id,str) or (book_id and book_id not in {b["book_id"] for b in catalog()}):
        raise PolicyError("教材不存在",400)
    token = body.get("page_token", "")
    if not isinstance(token,str) or len(token)>4096:
        raise PolicyError("分页参数无效",400)
    quota = await asyncio.to_thread(firestore.transactional(reserve_transaction),db.transaction(),
        device_id,secret,ip_key(request),request_id,time.time())
    try:
        filters = 'kind: ANY("textbook")'
        if book_id:
            filters += ' AND book_id: ANY("'+book_id+'")'
        url = f"https://discoveryengine.googleapis.com/v1/projects/{PROJECT}/locations/global/collections/default_collection/engines/{ENGINE}/servingConfigs/default_search:search"
        response = await http.post(url,headers=await google_headers(),json={"query":question,
            "pageSize":10,"languageCode":"zh-CN","filter":filters,"pageToken":token})
        response.raise_for_status()
        data=response.json()
        items=make_evidence(data.get("results",[]))
        return {"items":[{**{k:v for k,v in e.items() if k!="text"},"snippet":search_snippet(e["text"],question)} for e in items],
            "next_page_token":data.get("nextPageToken", ""),"quota":quota}
    except httpx.HTTPError:
        raise PolicyError("教材检索暂时不可用，请稍后重试",503)
    finally:
        await asyncio.to_thread(firestore.transactional(release_transaction),db.transaction(),device_id,request_id)


def image_transaction(transaction, device_id, secret, now):
    ref=db.collection("ai_devices").document(device_id)
    device=ref.get(transaction=transaction).to_dict()
    authenticate(device,secret)
    transaction.update(ref,image_quota(device,now))


@app.get("/v1/textbooks/{book_id}/{version}/pages/{page}")
async def page_image(request: Request, book_id: str, version: str, page: int, variant: str = "page"):
    device_id, secret = identity(request)
    book,key=resolve_page(book_id,version,page)
    if variant not in ("page", "thumbnail"):
        raise PolicyError("页图类型无效", 400)
    if variant == "thumbnail":
        key = key.replace("/pages/", "/thumbnails/")
    await asyncio.to_thread(firestore.transactional(image_transaction),db.transaction(),device_id,secret,time.time())
    url=await asyncio.to_thread(signed_page,key)
    return JSONResponse({"url":url,"image_key":key,"pdf_page":page,"page_count":book["page_count"],
        "expires_in":300},headers={"Cache-Control":"private, no-store"})


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
    rephrase, streaming, cost = generation_options(body)
    textbook_limit = textbook_count(body)
    await authenticated_device(request)
    model = await model_catalog.validate(http, body.get("model", MODEL))
    quota = await asyncio.to_thread(firestore.transactional(reserve_transaction), db.transaction(), device_id, secret,
                                    ip_key(request), request_id, time.time(), cost)

    async def produce():
        try:
            yield frame("quota", {**quota, "cost": cost})
            yield frame("model", {"id": model, "provider": "search_answer",
                "mode": "stream_answer" if streaming else "answer", "rephrase": rephrase,
                "streaming": streaming, "quota_cost": cost})
            source_label = "题库" if textbook_limit == 0 else "教材" if textbook_limit == 12 else "题库与教材"
            yield frame("phase", {"message": "正在检索" + source_label})
            url = f"https://discoveryengine.googleapis.com/v1/projects/{PROJECT}/locations/global/collections/default_collection/engines/{ENGINE}/servingConfigs/default_search:search"
            evidence, failed_sources = await retrieve(http, url, await google_headers(),
                                                     retrieval_query(question, history), textbook_limit)
            if failed_sources:
                missing = "教材" if "textbook" in failed_sources else "题库"
                yield frame("phase", {"message": missing+"检索暂时不可用，正依据其余资料整理回答"})
            yield frame("citations", {"items": [{k: v for k, v in e.items() if k != "text"} for e in evidence]})
            if not evidence:
                yield frame("delta", {"text": "题库与教材中暂未检索到足够的依据。试试补充疾病名称、关键症状或知识点，我会重新查找。"})
                yield frame("done", {})
                return
            yield frame("phase", {"message": "已找到相关资料，正在整理回答"})
            method = "streamAnswer" if streaming else "answer"
            url = f"https://discoveryengine.googleapis.com/v1/projects/{PROJECT}/locations/global/collections/default_collection/engines/{ANSWER_ENGINE}/servingConfigs/default_search:{method}"
            payload = answer_body(retrieval_query(question, history), history, evidence, model, rephrase)
            answer = {}
            streamed_text = ""
            async with asyncio.timeout(150):
                if streaming:
                    async with http.stream("POST", url, headers=await google_headers(), json=payload) as result:
                        if result.is_error:
                            await result.aread()
                        result.raise_for_status()
                        async for packet in answer_packets(result):
                            if await request.is_disconnected():
                                return
                            if "error" in packet:
                                raise ValueError("Google Answer stream failed")
                            part = packet.get("answer", {})
                            if part.get("state") == "SUCCEEDED":
                                answer = part
                                break  # Final answerText is the full answer, not another delta.
                            if part.get("state") in ("FAILED", "SKIPPED"):
                                raise ValueError("Google Answer did not succeed")
                            text = part.get("answerText", "")
                            streamed_text += text
                            if len(streamed_text) > 12000:
                                raise ValueError("Answer too long")
                            if text:
                                yield frame("delta", {"text": text})
                    if streamed_text and not answer.get("answerText"):
                        answer["answerText"] = streamed_text
                else:
                    result = await http.post(url, headers=await google_headers(), json=payload)
                    result.raise_for_status()
                    answer = result.json().get("answer", {})
            if await request.is_disconnected():
                return
            model_catalog.record(model, True)
            text = cited_answer(answer, evidence)
            print(json.dumps({"event": "builtin_answer", "model": model,
                "provider": "search_answer", "state": answer.get("state"),
                "rephrase_disabled": not rephrase, "streaming": streaming, "quota_cost": cost,
                "textbook_count": textbook_limit,
                "references": len(answer.get("references", []))}), flush=True)
            if len(text) > 12000:
                yield frame("error", {"message": "回答过长，请缩小问题范围后重试"})
            elif not text or answer.get("state") != "SUCCEEDED":
                yield frame("error", {"message": "这次未能生成有依据的回答，请调整问题后重试"})
            else:
                if streaming and streamed_text:
                    # References may arrive after text. Reconcile from the final
                    # authoritative Answer using original UTF-8 offsets/URIs.
                    yield frame("answer", {"text": text})
                else:
                    yield frame("delta", {"text": text, "reveal": "typing" if streaming else "lines"})
                yield frame("done", {})
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            # Log only exception type/status, never questions, answers or credentials.
            print(json.dumps({"event": "upstream_error", "type": type(exc).__name__,
                              "status": getattr(getattr(exc, "response", None), "status_code", None)}), flush=True)
            message = "AI 服务暂时不可用，已保留当前内容，请稍后重试"
            if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code == 400:
                detail = exc.response.text.lower()
                if 'add-on' in detail:
                    message = "内置回答尚未配置完成，请稍后重试"
                elif 'model' in detail:
                    model_catalog.record(model, False)
                    message = "所选内置模型暂不支持此应用，请查询模型并选择其他版本"
            yield frame("error", {"message": message})

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
