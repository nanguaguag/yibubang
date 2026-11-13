import json
import unittest

import httpx

from policy import retrieval_query
from retrieval import retrieve, textbook_count, result_count
from policy import PolicyError


class RetrievalTests(unittest.IsolatedAsyncioTestCase):
    def test_total_limit_and_source_split_are_validated_before_search(self):
        self.assertEqual(result_count({}), 12)
        for total in (1, 12, 25):
            self.assertEqual(result_count({'result_count': total}), total)
            self.assertEqual(textbook_count({'result_count': total, 'textbook_count': total}), total)
        for total in (0, -1, 26, True, '25', 25.0, None):
            with self.assertRaises(PolicyError):
                result_count({'result_count': total})
        with self.assertRaises(PolicyError):
            textbook_count({'result_count': 10, 'textbook_count': 11})

    async def test_twenty_five_results_reach_both_sources_with_complete_numbering(self):
        for books in (0, 17, 25):
            requests = []
            def respond(request):
                body = json.loads(request.content); requests.append(body)
                kind = 'textbook' if 'textbook' in body['filter'] else 'question'
                return httpx.Response(200, json={'results': [
                    {'document': {'structData': {'kind': kind, 'question_id': str(i),
                     'book_id': 'b', 'source_version': 'v', 'page_start': i,
                     'text': ('气流受限慢阻肺'*1000)}}} for i in range(body['pageSize'])]})
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                items, failed = await retrieve(client, 'https://search.example', {}, '慢阻肺', books, 25)
            self.assertEqual(len(items), 25)
            self.assertEqual([i['kind'] for i in items], ['textbook']*books + ['question']*(25-books))
            self.assertEqual([i['number'] for i in items], list(range(1,26)))
            self.assertLessEqual(sum(len(i['text']) for i in items), 60000)
            self.assertTrue(all(len(i['text']) > 1000 for i in items))
            self.assertEqual(len(requests), 1 if books in (0,25) else 2)
            self.assertEqual(failed, [])

    def test_ratio_is_optional_and_strictly_bounded(self):
        self.assertEqual(textbook_count({}), 8)
        for n in (0, 6, 12):
            self.assertEqual(textbook_count({"textbook_count": n}), n)
        for n in (-1, 13, True, "8", 8.0, None):
            with self.assertRaises(PolicyError):
                textbook_count({"textbook_count": n})

    async def test_selected_ratio_and_single_source_skip_unused_search(self):
        for count in (0, 3, 6, 9, 12):
            requests = []
            def respond(request):
                body = json.loads(request.content); requests.append(body)
                kind = 'textbook' if 'textbook' in body['filter'] else 'question'
                return httpx.Response(200, json={'results': [
                    {'document': {'structData': {'kind': kind, 'question_id': str(i),
                     'book_id': 'b', 'source_version': 'v', 'page_start': i,
                     'text': '证据'*3000}}} for i in range(12)]})
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                items, failed = await retrieve(client, 'https://search.example', {}, '查询', count)
            self.assertEqual([i['kind'] for i in items], ['textbook']*count+['question']*(12-count))
            self.assertEqual([i['number'] for i in items], list(range(1,13)))
            self.assertLessEqual(sum(len(i['text']) for i in items), 28000)
            self.assertEqual(len(requests), 1 if count in (0,12) else 2)
            self.assertEqual(failed, [])

    async def test_only_source_failure_is_an_error(self):
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(503))) as client:
            for count in (0,12):
                with self.assertRaises(httpx.HTTPStatusError):
                    await retrieve(client, 'https://search.example', {}, '查询', count)

    def test_new_topic_is_not_contaminated_but_explicit_followup_has_context(self):
        history = [{'question': '肝硬化发生的原因是什么？', 'answer': '肝炎'}]
        query = retrieval_query('名词解释：慢阻肺', history)
        self.assertNotIn('肝硬化', query)
        self.assertIn('慢性阻塞性肺疾病', query)
        self.assertEqual(query, retrieval_query('名词解释：慢阻肺', []))
        self.assertIn('肝硬化', retrieval_query('它的并发症呢？', history))

    async def test_independent_source_search_preserves_textbooks_and_single_numbering(self):
        requests = []
        def respond(request):
            body = json.loads(request.content);requests.append(body)
            kind = 'textbook' if 'textbook' in body['filter'] else 'question'
            results = [{'document': {'structData': {'kind':kind,'question_id':str(i),
                'book_id':'b','source_version':'v','page_start':i,
                'text':'证据'*3000}}} for i in range(12)]
            return httpx.Response(200,json={'results':results})
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            items, failed = await retrieve(client,'https://search.example',{},'慢阻肺')
        self.assertEqual([i['kind'] for i in items], ['textbook']*8+['question']*4)
        self.assertEqual([i['number'] for i in items], list(range(1,13)))
        self.assertLessEqual(sum(len(i['text']) for i in items),28000)
        self.assertEqual({r['query'] for r in requests},{'慢阻肺'})
        self.assertEqual(failed,[])

    async def test_one_source_failure_keeps_other_and_both_fail_raise(self):
        def respond(request):
            if 'textbook' in json.loads(request.content)['filter']:
                return httpx.Response(503)
            return httpx.Response(200,json={'results':[{'document':{'structData':{'question_id':'q','text':'test'}}}]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            items, failed = await retrieve(client,'https://search.example',{},'q')
        self.assertEqual(failed,['textbook']);self.assertEqual(items[0]['question_id'],'q')
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _:httpx.Response(503))) as client:
            with self.assertRaises(httpx.HTTPStatusError):
                await retrieve(client,'https://search.example',{},'q')
