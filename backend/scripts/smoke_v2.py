"""协议 v2 发布冒烟；只注册并使用独立测试账号，凭据必须存于忽略目录。"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import uuid


def request(base, path, body=None, token=None, status=200):
    # 使用与发布探针一致的 curl 网络栈；配置走 stdin，不把凭据放进命令行。
    config = ['url = ' + json.dumps(base + path),
        'header = "Content-Type: application/json"']
    if token:
        config.append('header = ' + json.dumps('Authorization: Bearer ' + token))
    if body is not None:
        config.append('data = ' + json.dumps(json.dumps(body)))
    response = subprocess.run(['curl', '--silent', '--show-error', '--max-time', '50',
        '--config', '-', '--write-out', '\n%{http_code}'],
        input='\n'.join(config), text=True, capture_output=True, check=True)
    raw, actual = response.stdout.rsplit('\n', 1)
    actual = int(actual)
    assert actual == status, f"{path}: unexpected HTTP status {actual}"
    return json.loads(raw)


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    os.chmod(path, 0o600)


def setup(root, base):
    state_file = root / "smoke-credentials.json"
    assert not state_file.exists(), "Reuse existing smoke state; do not create another account"
    # 若前一个网络探针已注册成功，复用私有回执，避免重复创建测试账号。
    receipt = root / "register-response.json"
    registered = json.loads(receipt.read_text()) if receipt.exists() else request(
        base, "/api/device/register", {"device_name": "Protocol v2 release smoke"})
    save(receipt, registered)
    assert registered["code"] == 0
    primary = registered["data"]
    partner = request(base, "/api/pair/restore-passphrase", {
        "passphrase": primary["sync_passphrase"], "device_name": "Protocol v2 smoke peer",
    })["data"]
    assert partner["user_id"] == primary["user_id"]
    prefix = "release-smoke-" + uuid.uuid4().hex
    state = dict(base=base, primary=primary, partner=partner, prefix=prefix,
        stream=uuid.uuid4().hex, seed_count=501)
    save(state_file, state)
    # 仅新建测试账号的合成题目；500页边界不依赖真实用户记录。
    user = str(uuid.UUID(primary["user_id"]))
    sql = "\n".join(
        f"INSERT INTO sync_questions(user_id,question_id,user_answer,status,updated_at) "
        f"VALUES('{user}','{prefix}-{i}','A',1,1);" for i in range(501))
    (root / "smoke-seed.sql").write_text(sql + "\n")
    save(root / "smoke-summary.json", {"setup": "isolated account and restored peer", "seed_count": 501})
    print("Independent smoke account and passphrase restore verified; credentials saved privately")


def verify(root):
    state = json.loads((root / "smoke-credentials.json").read_text())
    base, token, peer = state["base"], state["primary"]["device_token"], state["partner"]["device_token"]
    sync = lambda payload, credential=token: request(base, "/api/sync", payload, credential)["data"]
    for path in ["/", "/api/health"]:
        assert request(base, path)["protocol"] == 2
    request(base, "/api/sync", {"protocol": 2, "mutations": [], "pull_cursor": 0}, status=401)
    request(base, "/api/sync", {"protocol": 1}, token, status=426)
    first = sync({"protocol": 2, "mutations": [], "pull_cursor": 0}, peer)
    assert first["protocol"] == 2 and first["accepted_seqs"] == [] and first["has_more"]
    assert len(first["pull_questions"]) == 500
    last = sync({"protocol": 2, "mutations": [], "pull_cursor": first["next_cursor"],
        "high_watermark": first["high_watermark"]}, peer)
    assert len(last["pull_questions"]) == 1 and not last["has_more"]
    assert len({q["id"] for q in first["pull_questions"] + last["pull_questions"]}) == 501
    cursor = last["next_cursor"]
    question, activity = state["prefix"] + "-0", state["prefix"] + "-activity"
    def event(seq, kind, entity, payload):
        return dict(seq=seq, stream=state["stream"], kind=kind, id=entity, payload=payload)
    def push(events, credential=token):
        return sync({"protocol": 2, "mutations": events, "pull_cursor": cursor}, credential)
    old = event(1, "question", question, {"collection": 1})
    answer = event(2, "question", question, {"user_answer": "B", "status": 2})
    assert push([old])["accepted_seqs"] == [1]
    newer = push([answer]); assert newer["accepted_seqs"] == [2]
    retried = push([old]); assert retried["accepted_seqs"] == [1]
    assert retried["high_watermark"] == newer["high_watermark"]
    row = next(q for q in retried["pull_questions"] if q["id"] == question)
    assert (row["user_answer"], row["collection"]) == ("B", 1)
    created = event(3, "activity", activity, {"timestamp": 1000, "question_id": question,
        "is_right": "0", "duration": 42})
    assert push([created])["accepted_seqs"] == [3]
    deleted = push([event(4, "activity_delete", activity, {})])
    assert activity in deleted["pull_deleted_activities"]
    # 另一个设备再次上传相同流水ID，也必须受删除墓碑约束。
    replay = push([event(1, "activity", activity, created["payload"])], peer)
    assert all(a["id"] != activity for a in replay["pull_activities"])
    assert activity in replay["pull_deleted_activities"]
    summary = json.loads((root / "smoke-summary.json").read_text())
    summary.update(http="PASS", paging="500 + 1", authentication="401 / 426 verified",
        exact_ack="PASS", stale_retry="PASS", peer_delete_replay="PASS")
    save(root / "smoke-summary.json", summary)
    print("Production HTTP smoke PASS: 501 paging, authentication, exact ACK, stale retry, peer tombstone replay")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["setup", "verify"])
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--base", default="https://yibubang.melonhu.com")
    args = parser.parse_args()
    if ".local" not in args.state_dir.parts:
        parser.error("Credentials must be stored in an ignored .local directory")
    args.state_dir.mkdir(parents=True, exist_ok=True)
    if args.stage == "setup": setup(args.state_dir, args.base)
    else: verify(args.state_dir)
