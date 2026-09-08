"""Copy observed Stage 5 diagnostic records without rewriting their identities."""
from pathlib import Path
import hashlib
import json
import shutil

origin = Path('/private/tmp/dta-direct-stage5-validation/implementation')
output = Path('/private/tmp/dta-direct-stage5/benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-diagnostics')
if output.exists() or output.is_symlink():
    raise RuntimeError('Fresh diagnostic archive required')
output.mkdir()

def identity(path):
    data = path.read_bytes()
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), mode=oct(path.stat().st_mode & 0o777))

def write(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')

sources = [path for path in origin.iterdir() if path.is_file() and
    (path.name.startswith(('development', 'focused-27', 'install-27', 'install-985', 'focused-installed', 'lifetime-expired', 'check-driver-guards')))]
for name in ['candidate-27d700d', 'candidate-985e26b', 'candidate-final-01', 'focused-985e26b-01', 'focused-final-01']:
    sources.extend(path for path in (origin/name).iterdir() if path.is_file() and path.name != 'source.tar')
for name in ['candidate-final-01-launch.log', 'focused-985e26b-01-launch.log', 'focused-final-01-launch.log']:
    sources.append(origin/name)
for name in ['semantics-review', 'api-review']:
    sources.extend(path for path in (origin/name).rglob('*') if path.is_file())
sources.append(Path(__file__))
rows = []
for path in sorted(set(sources)):
    relative = path.relative_to(origin)
    destination = output/relative
    before = identity(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)
    if before != identity(path) or before != identity(destination):
        raise RuntimeError('Changed diagnostic source or copy: ' + str(path))
    rows.append(dict(source=str(path), path=str(relative), **before))
write(output/'inclusion-manifest.json', dict(files=rows,
    scope='Selected original diagnostic logs, commands, execution/input/output indexes and independent review records. Bytes and modes observed at inclusion. No experiments rerun; omitted Git exports, build trees and installations remain identified in the original indexes.'))
write(output/'inclusion-receipt.json', dict(files=len(rows), manifest=identity(output/'inclusion-manifest.json')))
print(json.dumps(dict(files=len(rows), bytes=sum(row['bytes'] for row in rows), manifest=identity(output/'inclusion-manifest.json'))))
