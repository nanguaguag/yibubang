"""Real register/quota/retrieval/Answer/follow-up smoke. Credentials never printed."""
import argparse
import json
import os
from pathlib import Path
import secrets
import time

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--endpoint', default='https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app')
    parser.add_argument('--credentials', type=Path,
                        default=Path(__file__).parent / '.local' / 'smoke-device.json')
    parser.add_argument('--check-only', action='store_true', help='Only register, quota and health; no model call')
    args = parser.parse_args()
    path = args.credentials
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        identity = json.loads(path.read_text())
    else:
        identity = {'installation_id': secrets.token_hex(16), 'secret': secrets.token_hex(32)}
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(identity, f)
    headers = {'X-Device-ID': identity['installation_id'], 'Authorization': 'Bearer ' + identity['secret']}
    report = {'endpoint': args.endpoint, 'tested_at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    with httpx.Client(base_url=args.endpoint, timeout=180) as client:
        report['health'] = client.get('/health').json()
        registration = client.post('/v1/devices', headers=headers, json=identity)
        if registration.status_code != 200:
            raise RuntimeError('registration ' + str(registration.status_code) + ': ' + registration.text)
        quota = client.get('/v1/quota', headers=headers)
        quota.raise_for_status()
        report['quota_before'] = quota.json()
        report['anonymous_search_status'] = client.post('/v1/search', json={}).status_code
        assert report['anonymous_search_status'] == 401
        if args.check_only:
            print(json.dumps(report, ensure_ascii=False, indent=2))
            return
        turns = []
        report['searches'] = []
        for question in ('为什么 HLA Ⅰ类分子向 CD8 T 细胞提呈抗原？', '那么它与 HLA Ⅱ类的区别是什么？'):
            request_id = secrets.token_hex(16)
            payload = {'question': question, 'request_id': request_id, 'history': turns}
            start = time.monotonic()
            event = ''
            events = []
            answer = ''
            citations = []
            first_delta = None
            with client.stream('POST', '/v1/search', headers=headers, json=payload) as result:
                result.raise_for_status()
                for line in result.iter_lines():
                    if line.startswith('event:'):
                        event = line[6:].strip()
                    elif line.startswith('data:'):
                        data = json.loads(line[5:])
                        events.append(event)
                        if event == 'delta':
                            answer += data['text']
                            if first_delta is None:
                                first_delta = round(time.monotonic() - start, 2)
                        if event == 'citations':
                            citations = data['items']
                        if event == 'answer':
                            answer = data['text']
                        if event == 'error':
                            raise RuntimeError(data['message'])
            assert events[-1] == 'done', events
            assert citations and any(c['question_id'] for c in citations)
            assert '[' in answer, 'No inline citation in model answer'
            turns.append({'question': question, 'answer': answer})
            report['searches'].append({'question': question, 'answer': answer, 'citations': citations,
                                      'delta_count': events.count('delta'), 'first_delta_seconds': first_delta,
                                      'elapsed_seconds': round(time.monotonic()-start, 2)})
            replay = client.post('/v1/search', headers=headers, json=payload)
            assert replay.status_code == 409, replay.text
        report['quota_after'] = client.get('/v1/quota', headers=headers).json()
        assert report['quota_before']['remaining'] - report['quota_after']['remaining'] == 6
        report['status'] = 'PASS'
        (path.parent / 'smoke-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
