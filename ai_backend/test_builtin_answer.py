import asyncio
import unittest
from unittest.mock import patch

import httpx
from answer_models import AnswerModelCatalog, parse_models
from builtin_answer import answer_body, answer_packets, cited_answer, source_uri
from policy import PolicyError

HTML = '<table><tr><td>stable</td><td>Now gemini-9-flash/answer_gen/v1</td><td>128K</td></tr><tr><td>gemini-9-flash/answer_gen/v1</td><td>New</td><td>128K</td></tr><tr><td>gemini-9-flash</td><td>Public Vertex model</td><td>128K</td></tr></table>'


class AnswerTests(unittest.TestCase):
    def test_live_catalog_excludes_external_models_and_rejects_error_html(self):
        models = parse_models(HTML)
        self.assertEqual([m['id'] for m in models], ['stable', 'gemini-9-flash/answer_gen/v1'])
        self.assertEqual(models[0]['resolved_model'], models[1]['id'])
        with self.assertRaises(ValueError):
            parse_models('<h1>404 page not found</h1>')

    def test_refresh_is_throttled_and_old_catalog_cannot_be_claimed_current(self):
        async def run():
            calls = []
            def respond(request):
                calls.append(request)
                return httpx.Response(200, text=HTML) if len(calls) == 1 else httpx.Response(503)
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                catalog = AnswerModelCatalog()
                with patch('answer_models.time.time', return_value=1000):
                    await catalog.get(client, refresh=True)
                    await catalog.get(client, refresh=True)
                    self.assertEqual(len(calls), 1)
                with patch('answer_models.time.time', return_value=5000):
                    self.assertTrue((await catalog.get(client,refresh=True))['stale'])
                with patch('answer_models.time.time', return_value=90000):
                    self.assertEqual((await catalog.get(client,refresh=True))['catalog_type'],'bundled_snapshot')
                with patch('answer_models.time.time', return_value=90001):
                    self.assertEqual((await catalog.get(client))['catalog_type'],'bundled_snapshot')
                    self.assertEqual(len(calls), 3)
        asyncio.run(run())

    def test_cold_catalog_returns_snapshot_before_network_finishes(self):
        async def run():
            started=asyncio.Event(); release=asyncio.Event()
            async def respond(request):
                started.set(); await release.wait()
                return httpx.Response(200,text=HTML)
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                catalog=AnswerModelCatalog()
                snapshot=await asyncio.wait_for(catalog.get(client),0.1)
                self.assertTrue(snapshot['stale'])
                self.assertEqual(snapshot['catalog_type'],'bundled_snapshot')
                await started.wait(); release.set(); await catalog.refresh_task
                self.assertEqual((await catalog.get(client))['catalog_type'],'official_documentation')
        asyncio.run(run())

    def test_json_stream_handles_network_boundaries_and_truncated_final_packet(self):
        async def run():
            import json
            class Stream(httpx.AsyncByteStream):
                def __init__(self,data):self.data=data
                async def __aiter__(self):
                    for byte in self.data: yield bytes([byte])
            packets=[{'answer':{'state':'STREAMING','answerText':'中文🙂"['}},
                     {'answer':{'state':'SUCCEEDED','answerText':'中文🙂"['}}]
            response=httpx.Response(200,stream=Stream(json.dumps(packets,ensure_ascii=False).encode()))
            self.assertEqual([p async for p in answer_packets(response)],packets)
            response=httpx.Response(200,stream=Stream(b'[{"answer":'))
            with self.assertRaises(ValueError):
                _=[p async for p in answer_packets(response)]
        asyncio.run(run())

    def test_utf8_citations_follow_reference_uri_not_result_order(self):
        evidence = [{'number': 1, 'question_id': 'q1'}, {'number': 2, 'question_id': 'q2'}]
        text = '中文与🙂公式。'
        answer = {'answerText': text,
            'references': [{'unstructuredDocumentInfo': {'uri': source_uri(evidence[1])}},
                           {'unstructuredDocumentInfo': {'uri': 'https://untrusted.invalid'}}],
            'citations': [{'endIndex': str(len(text.encode())), 'sources': [{'referenceId': '0'}, {'referenceId': '1'}]},
                          {'endIndex': '1', 'sources': [{'referenceId': '0'}]}]}
        self.assertEqual(cited_answer(answer, evidence), text + '[2]')

    def test_core_answer_keeps_selected_evidence_and_no_cloud_session_or_rephrase(self):
        evidence = [{'number': 1, 'kind': 'textbook', 'book_id': 'b', 'source_version': 'sha',
                     'pdf_page': 20, 'title': '教材', 'text': '正文', 'needs_review': True}]
        body = answer_body('问题', [], evidence, 'stable')
        self.assertNotIn('session', body)
        self.assertTrue(body['queryUnderstandingSpec']['queryRephraserSpec']['disable'])
        context = body['searchSpec']['searchResultList']['searchResults'][0]['unstructuredDocumentInfo']
        self.assertIn('true', context['documentContexts'][0]['content'])
        self.assertEqual(context['uri'], 'yibubang://textbooks/b/sha/20')


if __name__ == '__main__':
    unittest.main()
