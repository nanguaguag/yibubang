"""Separate Enterprise Answer app sharing the existing Store, no re-import."""
import argparse
import subprocess
import time

import httpx


def ensure_answer_engine(project, gcloud):
    token = subprocess.check_output([gcloud, 'auth', 'print-access-token'], text=True).strip()
    headers = {'Authorization': 'Bearer ' + token, 'x-goog-user-project': project}
    parent = f'https://discoveryengine.googleapis.com/v1/projects/{project}/locations/global/collections/default_collection/engines'
    with httpx.Client(headers=headers, timeout=30) as client:
        original = client.get(parent + '/yibubang-medical-search')
        original.raise_for_status()
        stores = original.json()['dataStoreIds']
        url = parent + '/yibubang-medical-answer'
        result = client.get(url)
        if result.status_code == 404:
            result = client.post(parent, params={'engineId': 'yibubang-medical-answer'}, json={
                'displayName': '医不帮基础生成回答', 'dataStoreIds': stores,
                'solutionType': 'SOLUTION_TYPE_SEARCH',
                'searchEngineConfig': {'searchTier': 'SEARCH_TIER_ENTERPRISE', 'searchAddOns': ['SEARCH_ADD_ON_LLM']},
                'commonConfig': {'companyName': '医不帮'},
                'sessionConfig': {'sessionManagementPolicy': 'NOT_MANAGED'}})
            result.raise_for_status()
            operation = result.json()
            if operation.get('error'):
                raise RuntimeError('Answer Engine creation failed: ' + str(operation['error']))
            # Some creation operations become unavailable immediately on
            # completion. Verify the concrete Engine instead of its operation.
            for _ in range(30):
                result = client.get(url)
                if result.status_code != 404:
                    break
                time.sleep(1)
        result.raise_for_status()
        config = result.json()
        search_config = config.get('searchEngineConfig', {})
        if (config['dataStoreIds'] == stores and
                search_config.get('searchTier') == 'SEARCH_TIER_ENTERPRISE' and
                not search_config.get('searchAddOns')):
            # Basic :answer also requires this application-level gate on the
            # live service. Advanced request features remain disabled by code.
            patch = client.patch(url, params={'updateMask': 'searchEngineConfig.searchAddOns'},
                json={'name': config['name'], 'searchEngineConfig': {'searchAddOns': ['SEARCH_ADD_ON_LLM']}})
            patch.raise_for_status()
            result = client.get(url)
            result.raise_for_status()
            config = result.json()
            search_config = config.get('searchEngineConfig', {})
        if (config['dataStoreIds'] != stores or
                search_config.get('searchTier') != 'SEARCH_TIER_ENTERPRISE' or
                search_config.get('searchAddOns') != ['SEARCH_ADD_ON_LLM']):
            raise RuntimeError('Existing Answer Engine differs from basic shared-Store configuration; refusing to change it')
        print('Answer Engine ready: shared Store, Enterprise + required LLM gate; original Standard Search unchanged')
        return config


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='yibubang-search')
    parser.add_argument('--gcloud', default='gcloud')
    args = parser.parse_args()
    ensure_answer_engine(args.project, args.gcloud)
