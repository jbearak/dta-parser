"""Verify numbered publication parts and reconstruct the accepted archive bytes."""
from pathlib import Path
import hashlib
import json
import stat
import sys

if len(sys.argv) != 3:
    raise ValueError('Usage: reassemble.py ARCHIVE_PARTS_JSON FRESH_ARCHIVE_PATH')
manifest_path = Path(sys.argv[1])
output = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
parts = manifest['parts']
if manifest['status'] != 'complete' or len(parts) < 2:
    raise ValueError('Completed multi-part publication required')
expected_names = ['records.tar.gz.part%03d' % i for i in range(1, len(parts) + 1)]
if [x['name'] for x in parts] != expected_names or len(parts) > 999:
    raise ValueError('Wrong part names or order')
if sum(x['bytes'] for x in parts) != manifest['archive']['bytes']:
    raise ValueError('Part byte totals differ')
digest = hashlib.sha256()
with output.open('xb') as target:
    for item in parts:
        part = manifest_path.parent / item['name']
        info = part.lstat()
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size < 80 * 1024 * 1024 or info.st_size != item['bytes']:
            raise ValueError('Part type or size differs: ' + item['name'])
        part_digest = hashlib.sha256()
        with part.open('rb') as source:
            while block := source.read(1024 * 1024):
                part_digest.update(block)
                digest.update(block)
                target.write(block)
        if part_digest.hexdigest() != item['sha256']:
            raise ValueError('Part digest differs: ' + item['name'])
if output.stat().st_size != manifest['archive']['bytes'] or digest.hexdigest() != manifest['archive']['sha256']:
    raise ValueError('Reassembled archive identity differs')
print(json.dumps(dict(accepted=True, archive=str(output), bytes=output.stat().st_size,
                     sha256=digest.hexdigest(), parts=len(parts))))
