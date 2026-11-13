"""Independent source retrieval, bounded textbook-first evidence and numbering."""
import asyncio

from textbook_support import evidence, search_snippet
from policy import PolicyError


def result_count(body):
    value = body.get("result_count", 12)
    if type(value) is not int or not 1 <= value <= 25:
        raise PolicyError("检索条目数需要为 1–25", 400)
    return value


def textbook_count(body):
    total = result_count(body)
    value = body.get("textbook_count", (total * 2 + 1) // 3)
    if type(value) is not int or not 0 <= value <= total:
        raise PolicyError("教材检索比例无效", 400)
    return value


async def retrieve(client, url, headers, query, textbook_limit=8, total_limit=12):
    async def source(kind, size):
        if size == 0:
            return []
        response = await client.post(url, headers=headers, json={
            "query": query, "pageSize": size, "languageCode": "zh-CN",
            "filter": f'kind: ANY("{kind}")'})
        response.raise_for_status()
        return response.json().get("results", [])

    limits = (textbook_limit, total_limit - textbook_limit)
    batches = await asyncio.gather(
        source("textbook", max(12, limits[0]+4) if limits[0] else 0),
        source("question", max(8, limits[1]+4) if limits[1] else 0),
                                   return_exceptions=True)
    active = [b for b, limit in zip(batches, limits) if limit]
    if all(isinstance(b, Exception) for b in active):
        raise active[0]
    candidates = []
    failed = []
    for kind, limit, batch in zip(("textbook", "question"), limits, batches):
        if isinstance(batch, Exception):
            failed.append(kind)
            continue
        candidates.extend(evidence(batch)[:limit])
    # Grow the bounded evidence budget with the requested result count. Reserve
    # room for later evidence so textbooks cannot consume the entire question budget.
    remaining = 28000 if total_limit <= 12 else min(60000, total_limit * 2500)
    selected = []
    for index, item in enumerate(candidates):
        excerpt_limit = 2500 if item["kind"] == "textbook" else 2000
        budget = min(excerpt_limit, remaining // (len(candidates) - index))
        text = search_snippet(item["text"], query, budget)[:budget]
        selected.append({**item, "number": len(selected)+1, "text": text})
        remaining -= len(text)
    return selected, failed
