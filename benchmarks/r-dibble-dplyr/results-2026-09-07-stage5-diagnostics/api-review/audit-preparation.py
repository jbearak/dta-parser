"""Read-only inventory audit of the bounded Stage 5 preparation artifacts."""
from pathlib import Path
import hashlib,json,stat
ROOT=Path('/private/tmp/dta-direct-stage5-validation/implementation/api-review')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
reports=[]
for directory, count in [('/private/tmp/dta-direct-stage5-helper-proof',66),('/private/tmp/dta-direct-stage5-helper-proof-r460',19)]:
    directory=Path(directory)
    index=directory/'artifact-index.json'
    records=json.loads(index.read_text())['files']
    if len(records)!=count: raise RuntimeError(f'Wrong record count at {index}')
    for record in records:
        path=directory/record['path']
        if path.stat().st_size!=record['bytes'] or sha(path)!=record['sha256'] or oct(stat.S_IMODE(path.stat().st_mode))!=record['mode']:
            raise RuntimeError(f'Indexed identity mismatch: {path}')
    reports.append({'directory':str(directory),'indexed_records':len(records),'indexed_bytes':sum(r['bytes'] for r in records),'index_sha256':sha(index),'sizes_hashes_current_modes_match':True})
preview=Path('/private/tmp/dta-direct-stage5-minimum-archive-preparation/preview')
checksums=preview/'SHA256SUMS'
indexed=set()
for line in checksums.read_text().splitlines():
    expected,relative=line.split('  ',1)
    path=preview/relative
    if relative in indexed or sha(path)!=expected:raise RuntimeError(f'Preview checksum mismatch: {path}')
    indexed.add(relative)
actual={str(path.relative_to(preview)) for path in preview.rglob('*') if path.is_file()}
if actual!=indexed|{'SHA256SUMS'} or len(actual)!=181:raise RuntimeError('Preview inventory mismatch')
records=json.loads((preview/'selection-index.json').read_text())['classifications']
selected=[r for r in records if r['selection']!='omit']
omitted=[r for r in records if r['selection']=='omit']
reports.append({'directory':str(preview),'total_files':len(actual),'total_bytes':sum((preview/p).stat().st_size for p in actual),'checksum_sha256':sha(checksums),'selected_original_records':len(selected),'omitted_original_records':len(omitted),'all_checksum_entries_match':True,'scope':'Selected text inventory only; no runtime rerun, installed-tree qualification or replay-completeness claim.'})
output={'scope':'Independent preparatory inventory audit. Final repository inclusion still requires an exact destination inventory comparison and review of its wrapper labels. Historical mode and host-runtime limits in original READMEs remain unchanged.','reports':reports}
with (ROOT/'preparation-inventory-audit.json').open('x') as stream:json.dump(output,stream,indent=2);stream.write('\n')
print(json.dumps(output,indent=2))
