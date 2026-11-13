"""Search's built-in basic Answer API, with externally selected evidence."""
import json
from urllib.parse import quote

from policy import generation_body


def source_uri(item):
    if item.get("kind") == "textbook":
        return ("yibubang://textbooks/" + quote(item["book_id"], safe="") + "/" +
                quote(item["source_version"], safe="") + "/" + str(item["pdf_page"]))
    return "yibubang://questions/" + quote(item.get("question_id", ""), safe="")


def answer_body(question, history, evidence, model, rephrase=False):
    instructions = generation_body(question, [], [])['systemInstruction']['parts'][0]['text']
    # Keep cloud sessions disabled. Elliptical context is bounded/local and only
    # submitted as untrusted text; independent topics never inherit old evidence.
    if history:
        instructions += "\n<不可信历史对话>" + json.dumps(history, ensure_ascii=False) + "</不可信历史对话>"
    results = []
    for item in evidence:
        context = json.dumps({k: v for k, v in item.items() if k != "text"}, ensure_ascii=False)
        results.append({"unstructuredDocumentInfo": {
            "uri": source_uri(item), "title": item["title"],
            "documentContexts": [{"content": context + "\n" + item["text"]}],
        }})
    return {"query": {"text": question},
            "searchSpec": {"searchResultList": {"searchResults": results}},
            "queryUnderstandingSpec": {"queryRephraserSpec":
                {"disable": False, "maxRephraseSteps": 1} if rephrase else {"disable": True}},
            "relatedQuestionsSpec": {"enable": False},
            "answerGenerationSpec": {"modelSpec": {"modelVersion": model},
                "answerLanguageCode": "zh-CN", "includeCitations": True,
                "promptSpec": {"preamble": instructions},
                "ignoreAdversarialQuery": True,
                "ignoreNonAnswerSeekingQuery": True}}


def cited_answer(answer, evidence):
    """Google citation positions are UTF-8 byte offsets, not Python indices."""
    text = answer.get("answerText", "")
    references = answer.get("references", [])
    numbers = {source_uri(e): e["number"] for e in evidence}
    ref_numbers = {}
    for index, reference in enumerate(references):
        info = reference.get("unstructuredDocumentInfo", {})
        if not info:
            info = reference.get("chunkInfo", {}).get("documentMetadata", {})
        number = numbers.get(info.get("uri"))
        if number is not None:
            ref_numbers[str(index)] = number
    raw = text.encode("utf-8")
    inserts = {}
    for citation in answer.get("citations", []):
        try:
            end = int(citation.get("endIndex", -1))
            if not 0 <= end <= len(raw):
                continue
            # Reject offsets in the middle of a multibyte character.
            raw[:end].decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue
        found = {ref_numbers[s.get("referenceId")] for s in citation.get("sources", [])
                 if s.get("referenceId") in ref_numbers}
        if found:
            inserts.setdefault(end, set()).update(found)
    for end in sorted(inserts, reverse=True):
        # Avoid duplicate markers when the model already followed our preamble.
        prefix = raw[:end].decode("utf-8")
        suffix = raw[end:].decode("utf-8")
        marker = "[" + ", ".join(map(str, sorted(inserts[end]))) + "]"
        if not prefix.endswith(marker) and not suffix.startswith(marker):
            raw = raw[:end] + marker.encode("utf-8") + raw[end:]
    return raw.decode("utf-8")


async def answer_packets(response):
    """Decode Google's streamed JSON array incrementally, before HTTP EOF."""
    decoder = json.JSONDecoder()
    buffer = ""
    size = 0
    async for chunk in response.aiter_text():
        size += len(chunk)
        if size > 10_000_000:
            raise ValueError("Answer stream too large")
        buffer += chunk
        while True:
            buffer = buffer.lstrip(" \t\r\n[,]")
            if not buffer:
                break
            try:
                packet, end = decoder.raw_decode(buffer)
            except json.JSONDecodeError:
                if len(buffer) > 2_000_000:
                    raise ValueError("Answer packet too large")
                break
            if not isinstance(packet, dict):
                raise ValueError("Invalid Answer packet")
            buffer = buffer[end:]
            yield packet
    if buffer.strip(" \t\r\n[,]"):
        raise ValueError("Incomplete Answer stream")
