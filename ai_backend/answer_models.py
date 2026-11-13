"""Query the official Search Answer model catalog; never enumerate Vertex models."""
import asyncio
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import time

from policy import PolicyError

MODEL_SOURCE = "https://docs.cloud.google.com/generative-ai-app-builder/docs/answer-generation-models"
MODEL_ID = re.compile(r"gemini-[a-zA-Z0-9.\-]+/answer_gen/v1")


class ModelTable(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = []
        self.row = None
        self.cell = None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        if tag in ("td", "th"):
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            if self.row is not None:
                self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        if tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def parse_models(html):
    parser = ModelTable()
    parser.feed(html)
    models = []
    for row in parser.rows:
        if len(row) < 3:
            continue
        model = row[0].strip()
        if model != "stable" and not MODEL_ID.fullmatch(model):
            continue
        resolved = MODEL_ID.search(row[1]) if model == "stable" else None
        target = resolved.group() if resolved else model
        label = target.removesuffix("/answer_gen/v1").replace("gemini-", "Gemini ")
        label = label.replace("-", " ").replace("flash", "Flash").replace("pro", "Pro")
        models.append({"id": model, "label": "自动（稳定版）" if model == "stable" else label,
                       "resolved_model": target, "context_window": row[2],
                       "preview": "preview" in target,
                       "availability": "documented"})
    # Reject changed/404/error HTML; do not silently manufacture a current list.
    if not any(m["id"] == "stable" for m in models) or len(models) < 2:
        raise ValueError("No valid Answer model table")
    return list({m["id"]: m for m in models}.values())


class AnswerModelCatalog:
    def __init__(self):
        self.fallback = json.loads(Path(__file__).with_name('answer_model_catalog.json').read_text())
        self.models = []
        self.fetched_at = 0
        self.attempted_at = 0
        self.lock = asyncio.Lock()
        self.refresh_task = None

    async def _refresh(self, client):
        async with self.lock:
            now = time.time()
            if now - self.attempted_at < 60:
                return
            self.attempted_at = now
            try:
                response = await client.get(MODEL_SOURCE, timeout=4)
                response.raise_for_status()
                if len(response.content) > 1_000_000:
                    raise ValueError("Oversized model directory")
                self.models = parse_models(response.text)
                self.fetched_at = time.time()
            except Exception:
                pass  # Always keep a labelled local snapshot available.

    async def get(self, client, refresh=False):
        now = time.time()
        if (not self.models or now - self.fetched_at >= 3600 or refresh) and now - self.attempted_at >= 60:
            if self.refresh_task is None or self.refresh_task.done():
                self.refresh_task = asyncio.create_task(self._refresh(client))
            if refresh:
                await asyncio.shield(self.refresh_task)
        # A live cache older than 24 hours is replaced by the labelled bundled
        # snapshot, never misrepresented as a current official response.
        if not self.models or time.time() - self.fetched_at > 86400:
            return {**self.fallback, "refreshing": self.refresh_task is not None and not self.refresh_task.done()}
        return {"models": self.models, "source_url": MODEL_SOURCE,
                "fetched_at": self.fetched_at, "stale": time.time() - self.fetched_at >= 3600,
                "provider": "search_answer", "default_model": "stable",
                "catalog_type": "official_documentation"}

    async def validate(self, client, model):
        if not isinstance(model, str) or (model != 'stable' and not MODEL_ID.fullmatch(model)):
            raise PolicyError("内置模型选择无效", 400)
        result = await self.get(client)
        if model not in {m["id"] for m in result["models"]}:
            raise PolicyError("该内置模型已不可选，请刷新模型列表", 400)
        return model

    def record(self, model, available):
        for item in self.models + self.fallback['models']:
            if item["id"] == model:
                item["availability"] = "verified" if available else "unavailable"
