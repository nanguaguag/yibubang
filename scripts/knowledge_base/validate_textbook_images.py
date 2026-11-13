#!/usr/bin/env python3
"""Check every expected book/page WebP and export a checksum asset manifest."""
import argparse
import json
from pathlib import Path
import time

from PIL import Image
from build import dumps,file_hash


def validate(output):
    books=json.loads((output/'catalog.json').read_text())['books']
    missing=[]
    count=size=0
    manifest=output/'image-manifest.jsonl.part'
    with manifest.open('w',encoding='utf8') as out:
        for b in books:
            for page in range(1,b['page_count']+1):
                key=f"textbooks/{b['book_id']}/{b['source_version']}/pages/{page:04d}.webp"
                path=output/'images'/key
                if not path.exists():
                    missing.append(key);continue
                with Image.open(path) as image:
                    assert image.format=='WEBP',key
                    width,height=image.size
                    assert width>0 and height>0 and max(width,height)<=2400,key
                    image.verify()
                n=path.stat().st_size
                out.write(dumps({'key':key,'book_id':b['book_id'],'source_version':b['source_version'],
                    'pdf_page':page,'width':width,'height':height,'bytes':n,'sha256':file_hash(path)})+'\n')
                count+=1;size+=n
    if missing:
        raise RuntimeError(f'{len(missing)} missing page images; first={missing[:5]}')
    manifest.replace(output/'image-manifest.jsonl')
    report={'status':'PASS','books':len(books),'pages':count,'bytes':size,'gib':round(size/1024**3,3),
            'mean_kib':round(size/max(count,1)/1024,1),'missing_pages':0}
    (output/'image-validation.json').write_text(dumps(report)+'\n')
    print(dumps(report))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=Path('/Volumes/My PSSD/书籍/医不帮教材知识库'))
    validate(p.parse_args().output)
