from unittest.mock import patch
import unittest
from textbook_support import citation, evidence, image_quota, resolve_page, signed_page, search_snippet
from policy import PolicyError, day_key
import test_backend as base
from test_backend import HEADERS, ID, NOW

BOOK={'book_id':'tb_123456789abc','source_version':'123456789abcdef0','page_count':3,'title':'生理学'}


class TextbookPolicyTests(unittest.TestCase):
    def test_snippet_centers_on_medical_terms_instead_of_a_long_page_header(self):
        text='前文'*700+'CD8 与 MHC I 的联系。'+'后文'*600
        snippet=search_snippet(text,'cd8 MHC')
        self.assertIn('CD8 与 MHC',snippet)
        self.assertTrue(snippet.startswith('…'))
        self.assertLessEqual(len(snippet),902)
    def test_citations_preserve_page_version_and_deduplicate_chunks(self):
        fields={'kind':'textbook','book_id':BOOK['book_id'],'source_version':BOOK['source_version'],
                'page_start':2,'page_count':3,'text':'钾离子与复极化','printed_page':'I','needs_review':True}
        items=evidence([{'document':{'structData':fields}}]*2)
        self.assertEqual(len(items),1)
        self.assertEqual(items[0]['pdf_page'],2)
        self.assertEqual(items[0]['printed_page'],'I')
        self.assertTrue(items[0]['needs_review'])
        self.assertEqual(citation({'question_id':'q'},1)['kind'],'question')
    def test_page_allowlist_cannot_sign_arbitrary_paths(self):
        with patch('textbook_support.catalog',return_value=[BOOK]):
            _,key=resolve_page(BOOK['book_id'],BOOK['source_version'],2)
            self.assertTrue(key.endswith('/0002.webp'))
            for b,v,p in [('unknown',BOOK['source_version'],1),(BOOK['book_id'],'wrong',1),(BOOK['book_id'],BOOK['source_version'],4)]:
                with self.assertRaises(PolicyError):resolve_page(b,v,p)
    def test_image_limits_do_not_spend_search_quota(self):
        updates=image_quota({'used':100},NOW)
        self.assertNotIn('used',updates)
        with self.assertRaises(PolicyError):image_quota({'image_day':day_key(NOW),'image_used':1000},NOW)
        with self.assertRaises(PolicyError):image_quota({'image_minute':int(NOW//60),'image_minute_used':60},NOW)
    def test_link_expiry_and_signature(self):
        with patch.dict('os.environ',{'TEXTBOOK_IMAGE_ENDPOINT':'https://pages.example','TEXTBOOK_IMAGE_SIGNING_KEY':'secret'}),patch('textbook_support.time.time',return_value=NOW):
            url=signed_page('textbooks/book/page.webp')
            self.assertIn('expires='+str(int(NOW)+300),url)
            self.assertIn('signature=',url)


class TextbookEndpointTests(unittest.TestCase):
    setUp = base.BackendTests.setUp
    tearDown = base.BackendTests.tearDown
    respond = base.BackendTests.respond
    def test_pure_retrieval_calls_search_once_and_never_gemini(self):
        response=self.client.post('/v1/textbooks/search',headers=HEADERS,json={'question':'钾离子','request_id':'textbook_req_01'})
        self.assertEqual(response.status_code,200)
        self.assertEqual(len(self.upstream),1)
        body=__import__('json').loads(self.upstream[0].content)
        self.assertIn('textbook',body['filter'])
        self.assertEqual(self.db.data[('ai_devices',ID)]['used'],1)
        self.assertEqual(self.db.data[('ai_devices',ID)]['lease_until'],0)
    def test_image_auth_bounds_and_separate_counter(self):
        import app
        with patch.object(app,'resolve_page',return_value=(BOOK,'key')),patch.object(app,'signed_page',return_value='https://pages.example/signed'):
            path='/v1/textbooks/tb_123456789abc/123456789abcdef0/pages/2'
            self.assertEqual(self.client.get(path).status_code,401)
            response=self.client.get(path,headers=HEADERS)
            self.assertEqual(response.status_code,200)
            self.assertEqual(self.db.data[('ai_devices',ID)]['image_used'],1)
            self.assertNotIn('used',self.db.data[('ai_devices',ID)])


if __name__=='__main__':unittest.main()
