#!/usr/bin/env python3
"""Bind the read-only auditor and all available proof records before its run."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
destinations = [root / name for name in ['audit-v2-inputs-before.json', 'audit-v2-launch.log',
                'audit-v2-output-manifest.json', 'audit-v2-receipt.json',
                'audit-result-v2.json', 'existing-output-guard-v2.log']]
if any(path.exists() or path.is_symlink() for path in destinations):
    raise RuntimeError('Auditor output already exists')

def record(path):
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)

before = [record(path) for path in sorted(root.rglob('*')) if path.is_file()]
command = ['python3', str(root / 'audit-proof-v2.py')]
write(destinations[0], {'command': command, 'inputs': before,
                       'scope': 'All existing local proof files including launcher and auditor; Python/OS closure not frozen.'})
with destinations[1].open('x') as log:
    code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
changed = [item['path'] for item in before if record(Path(item['path'])) != item]
products = [record(path) for path in destinations if path.exists() and path not in destinations[2:4]]
write(destinations[2], {'code': code, 'changed_inputs': changed, 'products': products,
                       'excluded_self': str(destinations[2])})
write(destinations[3], {'manifest': record(destinations[2]), 'code': code, 'changed_inputs': changed})
if code != 0 or changed:
    raise RuntimeError('Auditor failed or changed bound local input')
print(json.dumps({'code': code, 'bound_local_files': len(before),
                  'receipt': record(destinations[3])}))
