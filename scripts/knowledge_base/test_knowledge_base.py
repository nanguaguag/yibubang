"""Offline integration regression using disposable source SQLite files."""
import base64
import contextlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from build import build, clean, file_hash, readonly
from embed import check_vectors


def bank(path, questions):
    with contextlib.closing(sqlite3.connect(path)) as db, db:
        db.executescript("""
            CREATE TABLE Question(id TEXT PRIMARY KEY,title TEXT,public_title TEXT,option TEXT,
                                  answer TEXT,explain TEXT,restore TEXT,user_answer TEXT,cut_question TEXT);
            CREATE TABLE Subject(id TEXT PRIMARY KEY,name TEXT);
            CREATE TABLE Chapter(id TEXT PRIMARY KEY,name TEXT);
            CREATE TABLE IdentityQuestion(identity_id TEXT,subject_id TEXT,chapter_id TEXT,question_id TEXT);
            INSERT INTO Subject VALUES('s','生理学'); INSERT INTO Chapter VALUES('c','心脏');
        """)
        for qid, title, explanation in questions:
            db.execute("INSERT INTO Question VALUES(?,?,?,?,?,?,?,?,?)", (
                qid, title, "共用病例", '[{"key":"A","title":"钾离子"}]',
                "A", explanation, "教材P98", "PRIVATE-ANSWER", "1"))
            db.execute("INSERT INTO IdentityQuestion VALUES('i','s','c',?)", (qid,))


class CorpusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.a = self.root / "old bank's.sqlite"
        self.b = self.root / "new.sqlite"
        bank(self.a, [("q1", "旧题干", "旧解析"), ("only-old", "旧库独有题", "保留")])
        bank(self.b, [("q1", "新题干", "钾离子复极化。" * 400)])
        self.config = self.root / "config.json"
        self.settings = {"format_version": 1, "output": "output", "chunk_chars": 300, "overlap_chars": 30,
            "sources": [{"id": "old", "type": "sqlite", "path": str(self.a), "priority": 0},
                        {"id": "new", "type": "sqlite", "path": str(self.b), "priority": 10}]}
        self.write_config()

    def tearDown(self):
        self.tmp.cleanup()

    def write_config(self):
        self.config.write_text(json.dumps(self.settings))

    def run_build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return build(self.config)

    def test_readonly_dedup_priority_provenance_and_google_format(self):
        hashes = [file_hash(self.a), file_hash(self.b)]
        snapshot = self.run_build()
        self.assertEqual(hashes, [file_hash(self.a), file_hash(self.b)])
        with readonly(snapshot / "corpus.sqlite") as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM documents").fetchone()[0], 2)
            doc = json.loads(db.execute("SELECT payload FROM documents WHERE id='question:q1'").fetchone()[0])
            self.assertEqual(doc["fields"]["title"], "新题干")
            self.assertEqual(doc["metadata"]["source_ids"], ["new", "old"])
            self.assertEqual(len(doc["metadata"]["relations"]), 2)
            self.assertNotIn("user_answer", doc["fields"])
            self.assertNotIn("PRIVATE-ANSWER", json.dumps(doc))
            self.assertGreater(db.execute("SELECT COUNT(*) FROM chunks WHERE document_id='question:q1'").fetchone()[0], 2)
        for f in (snapshot / "google").glob("full-*.jsonl"):
            for line in f.read_text().splitlines():
                row = json.loads(line)
                self.assertRegex(row["id"], r"^c-[a-f0-9]{32}-[0-9]{4}$")
                content = base64.b64decode(row["content"]["rawBytes"], validate=True).decode()
                self.assertIn("正确答案", content)
                self.assertNotIn("PRIVATE-ANSWER", line)
        manifest = json.loads((snapshot / "manifest.json").read_text())
        self.assertEqual(manifest["conflicting_questions"], 1)

    def test_unchanged_cache_and_zero_delta(self):
        self.run_build()
        snapshot = self.run_build()
        m = json.loads((snapshot / "manifest.json").read_text())
        self.assertTrue(all(s["reused_cache"] for s in m["sources"]))
        self.assertEqual(m["new_or_updated_chunks"], 0)
        self.assertEqual(m["deleted_chunks"], 0)
        self.assertFalse(list((snapshot / "google").glob("delta-*")))

    def test_shrinking_document_removes_old_chunks(self):
        old = self.run_build()
        old_ids = {json.loads(l)["id"] for l in (old / "chunks.jsonl").read_text().splitlines()}
        with contextlib.closing(sqlite3.connect(self.b)) as db, db:
            db.execute("UPDATE Question SET explain='短解析' WHERE id='q1'")
        snapshot = self.run_build()
        ids = {json.loads(l)["id"] for l in (snapshot / "chunks.jsonl").read_text().splitlines()}
        deleted = {json.loads(l)["id"] for l in (snapshot / "deleted_ids.jsonl").read_text().splitlines()}
        self.assertEqual(deleted, old_ids - ids)
        self.assertGreater(len(deleted), 0)

    def test_failed_build_keeps_successful_snapshot(self):
        snapshot = self.run_build()
        before = file_hash(snapshot / "corpus.sqlite")
        self.settings["sources"][0]["path"] = "missing.sqlite"
        self.write_config()
        with self.assertRaises(ValueError):
            self.run_build()
        self.assertEqual(file_hash(snapshot / "corpus.sqlite"), before)

    def test_user_database_refused(self):
        user = self.root / "user_data.sqlite"
        with contextlib.closing(sqlite3.connect(user)) as db, db:
            db.execute("CREATE TABLE Question(id TEXT PRIMARY KEY,user_answer TEXT)")
        self.settings["sources"] = [{"id": "user", "type": "sqlite", "path": str(user)}]
        self.write_config()
        with self.assertRaisesRegex(ValueError, "禁止导入"):
            self.run_build()

    def test_textbook_pages_incremental_metadata(self):
        pages = self.root / "pages.jsonl"
        pages.write_text(json.dumps({"page": 1, "text": "钾通道与动作电位"}) + "\n" + json.dumps({"page": 2, "text": ""}) + "\n")
        self.settings["sources"].append({"id": "physiology-10", "type": "pages_jsonl", "path": str(pages),
            "title": "生理学", "edition": "第10版", "printed_page_offset": -1})
        self.write_config()
        snapshot = self.run_build()
        with readonly(snapshot / "corpus.sqlite") as db:
            doc = json.loads(db.execute("SELECT payload FROM documents WHERE id='book:physiology-10:page:1'").fetchone()[0])
            self.assertEqual(doc["metadata"]["page_start"], 1)
            self.assertEqual(doc["metadata"]["printed_page"], 0)
        m = json.loads((snapshot / "manifest.json").read_text())
        self.assertEqual(m["sources"][-1]["blank_pages"], [2])
        self.assertEqual(m["empty_documents"], 1)

    def test_html_and_medical_symbols(self):
        self.assertEqual(clean("<p>Na⁺ &amp; K⁺</p><script>hidden</script>"), "Na⁺ & K⁺")
        self.assertEqual(clean("K+ < 3.5 mmol/L；CD8⁺T；HLA-Ⅰ"), "K+ < 3.5 mmol/L；CD8⁺T；HLA-Ⅰ")

    def test_same_letter_different_answer_content_is_flagged(self):
        with contextlib.closing(sqlite3.connect(self.b)) as db, db:
            db.execute('UPDATE Question SET option=?', ('[{"key":"A","title":"钙离子"}]',))
        snapshot = self.run_build()
        with readonly(snapshot / "corpus.sqlite") as db:
            doc = json.loads(db.execute("SELECT payload FROM documents WHERE id='question:q1'").fetchone()[0])
            self.assertTrue(doc["metadata"]["answer_content_conflict"])
            self.assertIn("尚未进行医学审核", doc["text"])
            self.assertIn("所选来源答案", doc["text"])
            self.assertEqual(len(doc["metadata"]["answer_variants"]), 2)

    def test_embedding_response_order_dimensions_and_nan(self):
        vectors, size = check_vectors({"data": [{"index": 1, "embedding": [3, 4]}, {"index": 0, "embedding": [1, 2]}]}, 2, 2)
        self.assertEqual(vectors, [[1, 2], [3, 4]])
        self.assertEqual(size, 2)
        with self.assertRaises(ValueError):
            check_vectors({"data": [{"index": 0, "embedding": [float('nan'), 1]}]}, 1, 2)
        with self.assertRaises(ValueError):
            check_vectors({"data": [{"index": 0, "embedding": [1]}]}, 2, 2)


if __name__ == "__main__":
    unittest.main()
