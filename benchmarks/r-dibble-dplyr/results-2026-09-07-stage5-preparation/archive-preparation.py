from pathlib import Path
import datetime
import hashlib
import json
import shutil

repo = Path('/private/tmp/dta-direct-stage5')
out = repo/'benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation'
if out.exists(): raise RuntimeError('Fresh preparation archive required')
out.mkdir()
records = []
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if sha(source) != sha(destination): raise RuntimeError('Copy mismatch: '+str(source))
    records.append(dict(source=str(source), destination=str(destination.relative_to(out)),
        bytes=source.stat().st_size, mode=oct(source.stat().st_mode & 0o777), sha256=sha(source)))
preview = Path('/private/tmp/dta-direct-stage5-minimum-archive-preparation/preview')
if sha(preview/'SHA256SUMS') != 'd1afb744bdca3f77a2e249a55b3a0c8cc9ba31319a7879f879740937e7646162':
    raise RuntimeError('Preview index changed')
for line in (preview/'SHA256SUMS').read_text().splitlines():
    digest, name = line.split('  ',1)
    if sha(preview/name) != digest: raise RuntimeError('Preview file changed: '+name)
for path in sorted(preview.rglob('*')):
    if path.is_file(): copy(path,out/'dta-direct-stage5-minimum-preflight'/path.relative_to(preview))
# Keep the original sibling research link resolvable, without changing either
# immutable helper README. The same note also remains in preview/raw/.
copy(Path('/private/tmp/dta-direct-stage5-minimum-preflight/dplyr-r46-minimum.md'),
    out/'dta-direct-stage5-minimum-preflight/dplyr-r46-minimum.md')
for name,index_sha in [
    ('dta-direct-stage5-helper-proof','bb907a08b4566579b6fad1ebad6f2bf8a588e2219ac162c06d2ef43306af1931'),
    ('dta-direct-stage5-helper-proof-r460','cb479c9fd9118b9fd90cc47e81a2f56469c079ecbcb6a7c08ba7370ff50d7593')]:
    root=Path('/private/tmp')/name
    index=root/'artifact-index.json'
    if sha(index)!=index_sha:raise RuntimeError('Original index changed')
    entries=json.loads(index.read_text())['files']
    for entry in entries:
        path=root/entry['path']
        if sha(path)!=entry['sha256'] or path.stat().st_size!=entry['bytes'] or oct(path.stat().st_mode&0o777)!=entry['mode']:
            raise RuntimeError('Original helper file changed: '+str(path))
        copy(path,out/name/entry['path'])
    for file in ['artifact-index.json','artifact-index-receipt.json']:copy(root/file,out/name/file)
copy(Path(__file__),out/'archive-preparation.py')
manifest=dict(created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    scope='Selective minimum-version text preview and complete indexed helper proofs; historical bytes/modes preserved. No experiments rerun.',files=records)
# Compute contents before opening this new index; it is not its own input.
payload=json.dumps(manifest,indent=2,sort_keys=True)+'\n'
with (out/'inclusion-manifest.json').open('x') as file:file.write(payload)
with (out/'inclusion-receipt.json').open('x') as file:json.dump(dict(manifest_sha256=sha(out/'inclusion-manifest.json'),files=len(records)),file,indent=2)
print(len(records),sha(out/'inclusion-manifest.json'))
