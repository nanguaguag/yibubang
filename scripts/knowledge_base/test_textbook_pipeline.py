import json
import unittest
from build import google_document

try:
    from textbooks import extract_page
except ImportError:
    extract_page = None


class PortableTextbookTests(unittest.TestCase):
    def test_google_export_keeps_page_identity_without_local_coordinates_or_paths(self):
        row=google_document({'id':'c-id','document_id':'book:b:page:3','title':'书 · PDF第3页',
            'text':'Na⁺与K⁺','uri':'yibubang://book/b?page=3','content_hash':'hash',
            'metadata':{'kind':'textbook','source_ids':['b'],'book_id':'book','source_version':'v1',
                'page_start':3,'printed_page':'I','page_count':500,'image_key':'textbooks/book/v1/pages/0003.webp',
                'blocks':[{'bbox':[0,1,2,3]}],'source_path':'private.pdf',
                'quality':['medical_symbols_or_formula_review']}})
        self.assertEqual(row['structData']['printed_page'],'I')
        self.assertEqual(row['structData']['page_start'],3)
        self.assertNotIn('bbox',json.dumps(row))
        self.assertNotIn('private.pdf',json.dumps(row))
        self.assertTrue(row['structData']['needs_review'])


@unittest.skipIf(extract_page is None,'Install the local PDF pipeline requirements')
class ExtractionTests(unittest.TestCase):
    def span(self,font,seq,text,x,y):
        return {'font':font,'seqno':seq,'bbox':(x,y,x+len(text)*10,y+10),
                'chars':tuple((ord(ch),0,(x+i*10,y+8),(x+i*10,y,x+(i+1)*10,y+10)) for i,ch in enumerate(text))}
    def page(self,traces):
        import pymupdf
        class Page:
            rect=pymupdf.Rect(0,0,600,800)
            rotation=0
            def get_texttrace(self):return traces
        return Page()
    def test_overlapping_layers_preserve_complete_new_pass_and_uncovered_page_label(self):
        old=self.span('HiddenHorzOCR',1,'旧'*40,50,100)
        new=self.span('SimSun',3,'新'*40,50,100)
        page=self.page([self.span('Times-Roman',0,'12',10,20),old,new])
        r=extract_page(page)
        self.assertIn('新'*40,r['text'])
        self.assertNotIn('旧',r['text'])
        self.assertEqual(r['printed_page'],'12')
        self.assertEqual(r['removed_glyphs'],40)
        self.assertEqual(len(r['raw_blocks']),3)
    def test_repeated_word_at_different_position_is_retained(self):
        r=extract_page(self.page([self.span('SimSun',1,'细胞',10,100),self.span('SimSun',2,'细胞',10,120)]))
        self.assertEqual(r['text'].count('细胞'),2)
    def test_symbols_are_flagged_not_silently_rewritten(self):
        r=extract_page(self.page([self.span('SimSun',1,'Ⅱ-2与IL-2',10,100)]))
        self.assertIn('Ⅱ-2与IL-2',r['text'])
        self.assertIn('medical_symbols_or_formula_review',r['quality'])


if __name__=='__main__':unittest.main()
