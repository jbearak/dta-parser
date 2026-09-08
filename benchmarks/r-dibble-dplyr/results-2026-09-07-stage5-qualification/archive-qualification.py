"""Preserve observed Stage 5 qualification records with explicit omission scope."""
from pathlib import Path
import hashlib
import json
import shutil

origin = Path('/private/tmp/dta-direct-stage5-validation/implementation')
output = Path('/private/tmp/dta-direct-stage5/benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-qualification')
if output.exists() or output.is_symlink():
    raise RuntimeError('Fresh qualification archive required')
output.mkdir()

def identity(path):
    data = path.read_bytes()
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), mode=oct(path.stat().st_mode & 0o777))

def write(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')

names = ['candidate-final-02', 'full-final-01', 'rust-final-01', 'native-final-01',
         'package-final-01', 'candidate-final-03', 'package-final-02']
sources = []
for name in names:
    sources.extend(path for path in (origin/name).iterdir() if path.is_file() and
        not path.name.endswith(('.tar', '.tar.gz', '.tgz')))
    launch = origin/(name+'-launch.log')
    if launch.is_file(): sources.append(launch)
for name in ['package-final-01', 'package-final-02']:
    sources.extend(origin/name/'dtatools.Rcheck'/file for file in
        ['00check.log', '00install.out', 'tests/testthat.Rout'])
sources.extend(path for path in (origin/'native-final-01/atoms').iterdir() if path.is_file())
previous = json.loads((output.parent/'results-2026-09-07-stage5-diagnostics/inclusion-manifest.json').read_text())
already = {row['source'] for row in previous['files']}
for name in ['api-review', 'semantics-review']:
    sources.extend(path for path in (origin/name).rglob('*') if path.is_file() and str(path) not in already)
sources.extend(origin/name for name in ['news-only-package-equivalence.json', 'news-parse-fixed-01.log',
    'news-parser-source-01.log', 'news-parser-source-02.log', 'check-driver-guards-02.log', 'check-driver-guards-03.log'])
sources.append(Path(__file__))
rows = []
for path in sorted(set(sources)):
    relative = path.relative_to(origin)
    destination = output/relative
    before = identity(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)
    if before != identity(path) or before != identity(destination):
        raise RuntimeError('Changed qualification source or copy: ' + str(path))
    rows.append(dict(source=str(path), path=str(relative), **before))
write(output/'inclusion-manifest.json', dict(files=rows,
    scope='Selected original qualification logs, command records, input/output indexes, runtime identities and review audits. Bytes and modes observed at inclusion. No experiments rerun. Generated Git exports, installations, native binaries, archives and build trees are omitted with original identities retained in indexes.'))
write(output/'inclusion-receipt.json', dict(files=len(rows), manifest=identity(output/'inclusion-manifest.json')))
print(json.dumps(dict(files=len(rows), bytes=sum(row['bytes'] for row in rows), manifest=identity(output/'inclusion-manifest.json'))))
