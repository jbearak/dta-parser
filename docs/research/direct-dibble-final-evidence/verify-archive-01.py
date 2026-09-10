"""Independent complete tar stream verification, without extraction or producers."""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

bundle = Path(sys.argv[1])
out = Path(sys.argv[2])
if out.exists():
    raise ValueError('Fresh verification record required')
selection_bytes = (bundle / 'selection.json').read_bytes()
selection = json.loads(selection_bytes)
transport = json.loads((bundle / 'transport-result.json').read_text())
archive = bundle / 'records.tar.gz'
archive_digest = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
if transport['status'] != 'complete' or archive_digest != transport['archive']['sha256']:
    raise ValueError('Archive identity differs from transport')
if archive.stat().st_size != transport['archive']['bytes']:
    raise ValueError('Compressed byte count differs')
if hashlib.sha256(selection_bytes).hexdigest() != transport['selection']['sha256']:
    raise ValueError('Selection identity differs from transport')
rows = selection['files']
if len(rows) != selection['count'] or sum(r['bytes'] for r in rows) != selection['bytes']:
    raise ValueError('Selection totals differ')
count = 0
payload_bytes = 0
seen = set()
with tarfile.open(archive, 'r|gz') as stream:
    for member in stream:
        if count >= len(rows):
            raise ValueError('Extra archive member')
        expected = rows[count]
        path = member.name
        if path in seen or path != expected['member'] or not path.startswith('records/'):
            raise ValueError('Member identity/order differs')
        if any(part in ('', '.', '..') for part in path.split('/')):
            raise ValueError('Unsafe member path')
        if not member.isfile() or member.size != expected['bytes'] or member.mode != int(expected['mode'], 8):
            raise ValueError('Member type, size or mode differs')
        source = stream.extractfile(member)
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
        if digest != expected['sha256']:
            raise ValueError('Member digest differs: ' + path)
        count += 1
        payload_bytes += member.size
        seen.add(path)
if count != len(rows) or count != transport['members'] or payload_bytes != transport['uncompressed_bytes']:
    raise ValueError('Final member totals differ')
result = dict(accepted=True, archive_sha256=archive_digest, compressed_bytes=archive.stat().st_size,
    selection_sha256=hashlib.sha256(selection_bytes).hexdigest(), members=count,
    uncompressed_bytes=payload_bytes, verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    scope='Independent full member order/path/type/mode/size/SHA256 stream comparison. No extraction, source copy or workload.')
with out.open('x') as f:
    f.write(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
