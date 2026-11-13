#!/usr/bin/env python3
"""Reconcile all page assets, R2 acknowledgements and Google export hashes."""
import argparse
import json
from pathlib import Path
import sqlite3

from build import dumps, readonly, file_hash


def verify(output, artifacts):
    catalog=json.loads((output/'catalog.json').read_text())['books']
    for b in catalog:
        local=json.loads((output/'books'/b['book_id']/b['source_version']/'book.json').read_text())
        if file_hash(Path(local['source_path']))!=local['source_sha256']:
            raise RuntimeError('Original PDF changed since text extraction: '+b['title'])
    expected={f"textbooks/{b['book_id']}/{b['source_version']}/pages/{page:04d}.webp"
        for b in catalog for page in range(1,b['page_count']+1)}
    with (output/'image-manifest.jsonl').open() as manifest:
        rows=[json.loads(line) for line in manifest]
    assets={r['key']:r for r in rows}
    if len(assets)!=len(rows):
        raise RuntimeError('Duplicate page keys in image manifest')
    if set(assets)!=expected:
        raise RuntimeError(f'Page manifest coverage differs: missing={len(expected-set(assets))}, unexpected={len(set(assets)-expected)}')
    for key,r in assets.items():
        path=output/'images'/key
        if not path.is_file() or path.stat().st_size!=r['bytes'] or file_hash(path)!=r['sha256']:
            raise RuntimeError('Local page image missing or changed: '+key)
    with readonly(output/'r2-upload.sqlite') as db:
        uploaded={r['key']:r['hash'] for r in db.execute('SELECT key,hash FROM uploaded')}
    bad=[key for key,r in assets.items() if uploaded.get(key)!=r['sha256']]
    if bad:raise RuntimeError(f'{len(bad)} missing/different R2 acknowledgements; first={bad[:5]}')
    config=json.loads((artifacts/'current/config.json').read_text())['google']
    target=f"{config['project']}-{config['location']}-{config['data_store']}"
    cloud=artifacts/'cloud'/(target+'.sqlite')
    with readonly(artifacts/'current/corpus.sqlite') as db:
        db.execute('ATTACH DATABASE ? AS cloud',(cloud.resolve().as_uri()+'?mode=ro',))
        pending=db.execute('SELECT COUNT(*) FROM chunks c LEFT JOIN cloud.acknowledged a ON c.id=a.id WHERE a.id IS NULL OR c.export_hash<>a.hash').fetchone()[0]
        if pending:raise RuntimeError(f'{pending} Google chunks not acknowledged at current export hash')
        books=questions=review=0
        for row in db.execute('SELECT payload FROM chunks'):
            r=json.loads(row[0]);m=r['metadata']
            if m['kind']=='textbook':
                books+=1
                if m.get('image_key') not in assets:raise RuntimeError('Citation has no page asset: '+r['id'])
                if 'medical_symbols_or_formula_review' in m.get('quality',[]):review+=1
            else:questions+=1
    report={'status':'PASS','original_pdf_hashes_verified':len(catalog),'expected_pages':len(expected),
        'page_assets':len(assets),'local_page_hashes_verified':len(assets),'r2_acknowledged_at_matching_sha256':len(assets),
        'google_textbook_chunks':books,'google_question_chunks':questions,'pending_google_chunks':pending,
        'review_flagged_chunks':review,'image_bytes':sum(r['bytes'] for r in assets.values())}
    (artifacts/'cloud/textbook-final-validation.json').write_text(dumps(report)+'\n')
    print(dumps(report))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=Path('/Volumes/My PSSD/书籍/医不帮教材知识库'))
    p.add_argument('--artifacts',type=Path,default=Path(__file__).parent/'artifacts')
    a=p.parse_args();verify(a.output,a.artifacts)
