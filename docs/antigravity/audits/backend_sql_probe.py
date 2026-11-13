"""Execute baseline backend SQL against memory fixtures; no D1/network access."""

import json
from pathlib import Path
import re
import sqlite3

root = Path(__file__).resolve().parents[3]
source = (root / "backend/src/index.ts").read_text()
queries = re.findall(r"\.prepare\(`([\s\S]*?)`\)", source)
pull = next(query for query in queries if "FROM sync_questions" in query)
upsert = next(query for query in queries if "INSERT INTO sync_questions" in query)

with sqlite3.connect(":memory:") as db:
    db.executescript((root / "backend/schema.sql").read_text())
    db.executemany(
        "INSERT INTO sync_questions(user_id,question_id,updated_at) VALUES (?,?,?)",
        [("fixture", str(i), 100 + i) for i in range(10441)],
    )
    first = db.execute(pull, ("fixture", 0)).fetchall()
    second = db.execute(pull, ("fixture", 20000)).fetchall()
    db.execute(
        "INSERT INTO sync_questions(user_id,question_id,updated_at) VALUES (?,?,?)",
        ("slow", "late", 100),
    )
    late = db.execute(pull, ("slow", 20000)).fetchall()
    values = ("replay", "q", None, None, "0", "A", 1, 0, 100)
    db.execute(upsert, values)
    before = db.total_changes
    db.execute(upsert, values)
    result = {
        "initial_rows": 10441,
        "first_pull": len(first),
        "next_pull": len(second),
        "skipped_rows": 10441 - len(first),
        "old_clock_new_ingest_visible": bool(late),
        "identical_replay_sqlite_updates": db.total_changes - before,
    }
    assert len(first) == 10000 and not second and not late
    assert result["identical_replay_sqlite_updates"] == 1
    if hasattr(db, "setlimit"):
        db.setlimit(sqlite3.SQLITE_LIMIT_VARIABLE_NUMBER, 999)
        try:
            db.execute(
                "SELECT question_id FROM sync_questions WHERE question_id IN ("
                + ",".join(["?"] * 1000)
                + ")",
                ["q"] * 1000,
            )
        except sqlite3.OperationalError as error:
            result["variable_limit_simulation"] = str(error)
        else:
            raise AssertionError("Expected the simulated 999-variable limit")
    else:
        result["variable_limit_simulation"] = "Not available in this Python version"
    print(json.dumps(result, ensure_ascii=False))
