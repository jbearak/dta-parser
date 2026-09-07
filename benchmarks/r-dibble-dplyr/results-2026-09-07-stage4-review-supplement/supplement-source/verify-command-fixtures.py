"""Verify copied command-fixture bytes, restored modes and executed behavior."""
from pathlib import Path
import hashlib
import json
import subprocess

TARGET = Path('/private/tmp/dta-direct-stage4-review-supplement/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-supplement')
OUTPUT = Path('/private/tmp/dta-direct-stage4-validation/evidence-review-followup/fixture-mode-check.json')
index = json.loads((TARGET / 'index.json').read_text())
rows = []
for record in index['files']:
    if not record['copy'].startswith('native-fixtures/'):
        continue
    source, copy = Path(record['source']), TARGET / record['copy']
    before = {str(path): {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'mode': format(path.stat().st_mode & 0o777, '04o')} for path in (source, copy)}
    if any(row != {'sha256': record['sha256'], 'mode': '0755'} for row in before.values()):
        raise RuntimeError('Fixture source or copy is not the expected executable')
    original = subprocess.run([str(source)], capture_output=True)
    replay = subprocess.run([str(copy)], capture_output=True)
    if (original.returncode, original.stdout, original.stderr) != (replay.returncode, replay.stdout, replay.stderr):
        raise RuntimeError('Command behavior differs')
    after = {str(path): {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'mode': format(path.stat().st_mode & 0o777, '04o')} for path in (source, copy)}
    if before != after:
        raise RuntimeError('Fixture changed during execution')
    rows.append({'copy': record['copy'], 'before': before, 'after': after,
                 'original_exit': original.returncode, 'copied_exit': replay.returncode,
                 'stdout_sha256': hashlib.sha256(replay.stdout).hexdigest(),
                 'stderr_sha256': hashlib.sha256(replay.stderr).hexdigest()})
if len(rows) != 16:
    raise RuntimeError('Wrong fixture count')
with OUTPUT.open('x') as stream:
    json.dump({'driver_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               'scope': 'Actual execution of all16 byte-identical0755 original and copied command replacements; exit/stdout/stderr equality', 'fixtures': rows}, stream, indent=2)
    stream.write('\n')
print('All16 copied command fixtures execute identically with restored0755 modes')
