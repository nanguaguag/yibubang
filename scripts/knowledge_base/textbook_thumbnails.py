"""Derive small local WebP previews from existing pages; never read/upload PDFs."""
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
import json
import hashlib
from PIL import Image

ROOT = Path('/Volumes/My PSSD/书籍/医不帮教材知识库')


def render(path):
    target = path.parent.parent/'thumbnails'/path.name
    target.parent.mkdir(exist_ok=True)
    if not target.exists():
        with Image.open(path) as image:
            image.thumbnail((360,480), Image.Resampling.LANCZOS)
            part = target.with_suffix('.part')
            image.save(part,format='WEBP',quality=65,method=4)
            part.replace(target)
    data = target.read_bytes()
    return {'key':target.relative_to(ROOT/'images').as_posix(),
            'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}


if __name__ == '__main__':
    files = sorted((ROOT/'images/textbooks').glob('*/*/pages/*.webp'))
    expected = sum(b['page_count'] for b in json.loads((ROOT/'catalog.json').read_text())['books'])
    assert len(files) == expected
    with ProcessPoolExecutor(max_workers=3) as pool:
        rows = list(pool.map(render, files, chunksize=30))
    with (ROOT/'thumbnail-manifest.jsonl').open('w') as out:
        for r in rows:out.write(json.dumps(r)+'\n')
    print(json.dumps({'thumbnails':len(rows),'bytes':sum(r['bytes'] for r in rows)}))
