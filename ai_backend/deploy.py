"""Idempotent deployment of the independent AI service. Requires logged-in gcloud."""
import argparse
import ast
import json
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='yibubang-search')
    parser.add_argument('--region', default='asia-northeast1')
    parser.add_argument('--gcloud', default=shutil.which('gcloud'))
    args = parser.parse_args()
    if not args.gcloud:
        parser.error('Specify --gcloud /path/to/google-cloud-sdk/bin/gcloud')
    root = Path(__file__).resolve().parent
    copied = {name for line in (root / 'Dockerfile').read_text().splitlines()
              if line.startswith('COPY ') for name in line.split()[1:-1]}
    for name in copied:
        if not name.endswith('.py'):
            continue
        for node in ast.walk(ast.parse((root / name).read_text())):
            if isinstance(node, ast.ImportFrom) and node.module:
                local = node.module.split('.')[0] + '.py'
                if (root / local).exists() and local not in copied:
                    raise RuntimeError('Docker image missing local module: ' + local)
    def run(*cmd, capture=False):
        return subprocess.run([args.gcloud, *cmd, '--project='+args.project, '--quiet'],
                              check=True, text=True, capture_output=capture)
    run('services', 'enable', 'run.googleapis.com', 'artifactregistry.googleapis.com',
        'cloudbuild.googleapis.com', 'firestore.googleapis.com',
        'discoveryengine.googleapis.com')
    databases = json.loads(run('firestore', 'databases', 'list', '--format=json', capture=True).stdout)
    if not any(d['name'].endswith('/yibubang-ai') for d in databases):
        run('firestore', 'databases', 'create', '--database=yibubang-ai',
            '--location='+args.region, '--type=firestore-native')
    account_id = 'yibubang-ai-runtime'
    account = account_id+'@'+args.project+'.iam.gserviceaccount.com'
    accounts = json.loads(run('iam', 'service-accounts', 'list', '--format=json', capture=True).stdout)
    if not any(a['email'] == account for a in accounts):
        run('iam', 'service-accounts', 'create', account_id, '--display-name=Yibubang AI runtime')
    role = 'YibubangAiInference'
    permissions = 'discoveryengine.servingConfigs.search,discoveryengine.servingConfigs.answer'
    existing = subprocess.run([args.gcloud, 'iam', 'roles', 'describe', role,
                               '--project='+args.project, '--format=json'], capture_output=True, text=True)
    run('iam', 'roles', 'update' if existing.returncode == 0 else 'create', role,
        '--title=Yibubang AI inference only', '--permissions='+permissions, '--stage=GA')
    run('projects', 'add-iam-policy-binding', args.project, '--member=serviceAccount:'+account,
        '--role=projects/'+args.project+'/roles/'+role, '--condition=None', '--format=none')
    run('projects', 'add-iam-policy-binding', args.project, '--member=serviceAccount:'+account,
        '--role=roles/datastore.user', '--format=none',
        '--condition=expression=resource.name=="projects/'+args.project+'/databases/yibubang-ai",title=yibubang-ai-database')
    for collection in ('ai_registration_limits', 'ai_request_limits'):
        run('firestore', 'fields', 'ttls', 'update', 'expires_at', '--database=yibubang-ai',
            '--collection-group='+collection, '--enable-ttl', '--async')
    from setup_answer_engine import ensure_answer_engine
    ensure_answer_engine(args.project, args.gcloud)
    run('run', 'deploy', 'yibubang-ai-search', '--source='+str(root), '--region='+args.region,
        '--service-account='+account, '--allow-unauthenticated', '--ingress=all',
        '--min-instances=0', '--max-instances=2', '--concurrency=16', '--cpu=1',
        '--memory=512Mi', '--timeout=180', '--no-cpu-boost',
        '--update-env-vars=GOOGLE_CLOUD_PROJECT='+args.project+',FIRESTORE_DATABASE=yibubang-ai,'
        'SEARCH_ENGINE=yibubang-medical-search,ANSWER_ENGINE=yibubang-medical-answer,'
        'ANSWER_MODEL=stable,GLOBAL_DAILY_LIMIT=2000,IP_DAILY_LIMIT=300',
        '--remove-env-vars=GEMINI_MODEL,GEMINI_LOCATION')
    url = run('run', 'services', 'describe', 'yibubang-ai-search', '--region='+args.region,
              '--format=value(status.url)', capture=True).stdout.strip()
    print('AI_SEARCH_ENDPOINT='+url)


if __name__ == '__main__':
    main()
