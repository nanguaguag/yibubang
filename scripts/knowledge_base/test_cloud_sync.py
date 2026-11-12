"""Import state tests without Google/network calls."""
import contextlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from build import build, dumps
from cloud import synchronize
from test_knowledge_base import bank


class FakeCloud:
    config = {"project": "test-project", "location": "global", "data_store": "test-store"}
    store = "test/store"

    def __init__(self, short_count=False):
        self.imported = []
        self.deleted = []
        self.short_count = short_count

    def import_files(self, files, build_id, operation_file, acknowledgements):
        rows = []
        for p in files:
            rows.extend(json.loads(l) for l in p.read_text().splitlines())
        self.imported.extend(r["id"] for r in rows)
        return {"name": "fake-operation", "done": True,
                "metadata": {"successCount": len(rows) - int(self.short_count)}}

    def request(self, method, resource):
        if method != "DELETE":
            raise AssertionError("Unexpected call")
        self.deleted.append(resource.rsplit("/", 1)[1])
        return {}

    def wait(self, operation, record=None):
        return operation


class CloudSyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.source = self.root / "bank.sqlite"
        bank(self.source, [("q1", "心肌", "动作电位。" * 500)])
        self.config = self.root / "config.json"
        self.config.write_text(dumps({"format_version": 1, "output": "output", "chunk_chars": 300,
            "overlap_chars": 30, "sources": [{"id": "test", "type": "sqlite", "path": str(self.source)}]}))

    def tearDown(self):
        self.tmp.cleanup()

    def snapshot(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return build(self.config)

    def sync(self, cloud, snapshot):
        with contextlib.redirect_stdout(io.StringIO()):
            synchronize(cloud, snapshot, False)

    def test_cloud_baseline_survives_multiple_offline_builds_and_noop(self):
        cloud = FakeCloud()
        snapshot = self.snapshot()
        self.sync(cloud, snapshot)
        original = set(cloud.imported)
        self.assertGreater(len(original), 1)
        cloud.imported.clear()
        self.sync(cloud, snapshot)
        self.assertEqual(cloud.imported, [])
        with contextlib.closing(sqlite3.connect(self.source)) as db, db:
            db.execute("UPDATE Question SET explain='短解析'")
        self.snapshot()
        snapshot = self.snapshot()  # local delta is now zero, cloud delta is not
        self.sync(cloud, snapshot)
        self.assertEqual(len(cloud.imported), 1)
        self.assertEqual(set(cloud.deleted), original - set(cloud.imported))

    def test_partial_count_does_not_acknowledge(self):
        snapshot = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, "成功导入计数"):
            self.sync(FakeCloud(short_count=True), snapshot)
        state_path = snapshot.parent / "cloud" / "test-project-global-test-store.sqlite"
        with contextlib.closing(sqlite3.connect(state_path)) as state:
            self.assertEqual(state.execute("SELECT COUNT(*) FROM acknowledged").fetchone()[0], 0)

    def test_completed_operation_after_crash_is_acknowledged_without_reimport(self):
        snapshot = self.snapshot()
        folder = snapshot.parent / "cloud"
        folder.mkdir()
        op_path = folder / "test-project-global-test-store-operation.json"
        with contextlib.closing(sqlite3.connect(snapshot / "corpus.sqlite")) as db:
            acknowledgements = list(db.execute("SELECT id,export_hash FROM chunks"))
        op_path.write_text(dumps({"name": "finished-job", "done": True,
                                  "metadata": {"successCount": len(acknowledgements)}}))
        op_path.with_suffix(".plan.json").write_text(dumps({"operation": "finished-job", "acknowledgements": acknowledgements}))
        cloud = FakeCloud()
        self.sync(cloud, snapshot)
        self.assertEqual(cloud.imported, [])
        self.assertFalse(op_path.with_suffix(".plan.json").exists())

    def test_recovery_count_mismatch_does_not_acknowledge(self):
        snapshot = self.snapshot()
        folder = snapshot.parent / "cloud"
        folder.mkdir()
        op_path = folder / "test-project-global-test-store-operation.json"
        op_path.write_text(dumps({"name": "partial-job", "done": True, "metadata": {"successCount": 0}}))
        op_path.with_suffix(".plan.json").write_text(dumps({"operation": "partial-job", "acknowledgements": [["c-test", "hash"]]}))
        with self.assertRaisesRegex(RuntimeError, "恢复任务成功计数"):
            self.sync(FakeCloud(), snapshot)

    def test_concurrent_sync_does_not_remove_existing_lock(self):
        snapshot = self.snapshot()
        folder = snapshot.parent / "cloud"
        folder.mkdir()
        lock = folder / "test-project-global-test-store.lock"
        lock.write_text("another process")
        with self.assertRaisesRegex(ValueError, "同目标云导入已在运行"):
            self.sync(FakeCloud(), snapshot)
        self.assertTrue(lock.exists())


if __name__ == "__main__":
    unittest.main()
