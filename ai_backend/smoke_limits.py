"""Verify production policy using only the dedicated smoke installation's counters.

Admin ADC/gcloud login required. Original fixture fields are restored in finally.
No global/IP counters or real users are modified; no Gemini requests are made.
"""
import argparse
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import secrets
import shutil
import subprocess
import time
from urllib.parse import urlencode

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gcloud', default=shutil.which('gcloud'))
    parser.add_argument('--endpoint', default='https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app')
    parser.add_argument('--project', default='yibubang-search')
    args = parser.parse_args()
    if not args.gcloud:
        parser.error('Specify --gcloud /path/to/gcloud')
    directory = Path(__file__).parent / '.local'
    identity = json.loads((directory / 'smoke-device.json').read_text())
    device_headers = {'X-Device-ID': identity['installation_id'], 'Authorization': 'Bearer ' + identity['secret']}
    token = subprocess.check_output([args.gcloud, 'auth', 'print-access-token'], text=True).strip()
    admin_headers = {'Authorization': 'Bearer ' + token}
    url = f"https://firestore.googleapis.com/v1/projects/{args.project}/databases/yibubang-ai/documents/ai_devices/{identity['installation_id']}"
    fields = ['day', 'used', 'minute', 'minute_used', 'lease_until', 'last_request']
    mask = urlencode([('updateMask.fieldPaths', f) for f in fields])
    now = time.time()
    day = datetime.fromtimestamp(now, timezone(timedelta(hours=8))).strftime('%Y-%m-%d')
    report = {'scope': 'dedicated smoke installation only', 'checked_at_utc': datetime.now(timezone.utc).isoformat(), 'checks': {}}
    with httpx.Client(timeout=30) as client:
        original = client.get(url, headers=admin_headers)
        original.raise_for_status()
        saved = {k: v for k, v in original.json()['fields'].items() if k in fields}
        def update(values):
            result = client.patch(url + '?' + mask, headers=admin_headers, json={'fields': values})
            result.raise_for_status()
        def try_search(request_id=None):
            return client.post(args.endpoint + '/v1/search', headers=device_headers,
                               json={'question': '限额探针，请勿实际生成', 'request_id': request_id or secrets.token_hex(16)})
        try:
            state = deepcopy(saved)
            state.update({'day': {'stringValue': day}, 'used': {'integerValue': '100'}, 'lease_until': {'doubleValue': 0}})
            update(state)
            quota = client.get(args.endpoint + '/v1/quota', headers=device_headers)
            assert quota.json()['remaining'] == 0
            report['checks']['daily_100'] = try_search().status_code
            assert report['checks']['daily_100'] == 429
            state.update({'used': {'integerValue': saved.get('used', {}).get('integerValue', '0')},
                          'minute': {'integerValue': str(int(now // 60))}, 'minute_used': {'integerValue': '6'}})
            update(state)
            report['checks']['minute_6'] = try_search().status_code
            assert report['checks']['minute_6'] == 429
            state.update({'minute_used': {'integerValue': '0'}, 'lease_until': {'doubleValue': now + 180}})
            update(state)
            report['checks']['concurrent_lease'] = try_search().status_code
            assert report['checks']['concurrent_lease'] == 429
            replay = secrets.token_hex(16)
            state.update({'lease_until': {'doubleValue': 0}, 'last_request': {'stringValue': replay}})
            update(state)
            report['checks']['duplicate_request'] = try_search(replay).status_code
            assert report['checks']['duplicate_request'] == 409
            wrong = {**device_headers, 'Authorization': 'Bearer ' + secrets.token_hex(32)}
            report['checks']['wrong_secret'] = client.get(args.endpoint + '/v1/quota', headers=wrong).status_code
            assert report['checks']['wrong_secret'] == 401
        finally:
            update(saved)
        restored = client.get(url, headers=admin_headers).json()['fields']
        assert {k: v for k, v in restored.items() if k in fields} == saved
        report['restored'] = True
        report['status'] = 'PASS'
        (directory / 'limits-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
