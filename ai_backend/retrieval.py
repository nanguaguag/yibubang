"""Independent source retrieval, bounded textbook-first evidence and numbering."""
import asyncio

from textbook_support import evidence, search_snippet
from policy import PolicyError


def textbook_count(body):
    value = body.get("textbook_count", 8)
    if type(value) is not int or not 0 <= value <= 12:
        raise PolicyError("教材检索比例无效", 400)
    return value


async def retrieve(client, url, headers, query, textbook_limit=8):
    async def source(kind, size):
        if size == 0:
            return []
        response = await client.post(url, headers=headers, json={
            "query": query, "pageSize": size, "languageCode": "zh-CN",
            "filter": f'kind: ANY("{kind}")'})
        response.raise_for_status()
        return response.json().get("results", [])

    limits = (textbook_limit, 12 - textbook_limit)
    batches = await asyncio.gather(
        source("textbook", max(12, limits[0]) if limits[0] else 0),
        source("question", max(8, limits[1]) if limits[1] else 0),
                                   return_exceptions=True)
    active = [b for b, limit in zip(batches, limits) if limit]
    if all(isinstance(b, Exception) for b in active):
        raise active[0]
    selected = []
    failed = []
    remaining = 28000
    for kind, limit, batch in zip(("textbook", "question"), limits, batches):
        if isinstance(batch, Exception):
            failed.append(kind)
            continue
        excerpt_limit = 2500 if kind == "textbook" else 2000
        for item in evidence(batch)[:limit]:
            # Preserve a usable excerpt around the current topic within budget.
            text = search_snippet(item["text"], query, min(excerpt_limit, remaining))
            if len(text) < 100 and remaining < 100:
                break
            selected.append({**item, "number": len(selected)+1, "text": text})
            remaining -= len(text)
    return selected, failed
