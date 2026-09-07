"""Compare two guarded Stage 4 outputs without altering raw evidence."""
import csv
import hashlib
import json
from pathlib import Path
import sys


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def load(root):
    manifest = json.loads((root / 'root-manifest.json').read_text())
    for name, digest in manifest['files'].items():
        require(hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, f'Changed {root / name}')
    for case in manifest.get('memory_cases', []):
        require(hashlib.sha256((root / case['file']).read_bytes()).hexdigest() == case['sha256'], f'Changed {case}')
    with (root / 'owned-atomic.csv').open() as file:
        rows = list(csv.DictReader(file))
    keys = ['kind', 'family', 'operation', 'rows', 'columns']
    keyed = {tuple(row[key] for key in keys): row for row in rows}
    require(len(keyed) == len(rows) == 206, 'Incomplete/duplicate operation matrix')
    return manifest, keys, keyed


baseline, candidate, output = map(Path, sys.argv[1:])
a, keys, before = load(baseline)
b, other_keys, after = load(candidate)
require(a['mode'] == 'baseline' and b['mode'] == 'candidate', 'Wrong comparison direction')
require(a['runner_sha256'] == b['runner_sha256'], 'Mismatched runner source')
require(a['iterations'] == b['iterations'] == 7, 'Wrong iteration count')
require(keys == other_keys and before.keys() == after.keys(), 'Unpaired cases')
require(not output.exists(), f'Refusing to replace {output}')
output.mkdir(parents=True)
records = []
for key in before:
    old, new = before[key], after[key]
    row = dict(zip(keys, key))
    for field in ['median_ms', 'r_allocated_bytes', 'r_largest_allocation_bytes', 'bench_allocated_bytes']:
        row['baseline_' + field] = float(old[field])
        row['candidate_' + field] = float(new[field])
    delta = row['candidate_median_ms'] - row['baseline_median_ms']
    row['median_delta_ms'] = delta
    require(row['baseline_median_ms'] > 0, 'Nonpositive baseline median')
    row['median_ratio'] = row['candidate_median_ms'] / row['baseline_median_ms']
    row['investigate'] = delta > 1 and row['median_ratio'] > 1.1
    records.append(row)
with (output / 'operation-comparison.csv').open('x') as file:
    writer = csv.DictWriter(file, fieldnames=records[0])
    writer.writeheader()
    writer.writerows(records)
regressions = [row for row in records if row['investigate']]
with (output / 'investigate.json').open('x') as file:
    json.dump(regressions, file, indent=2)
    file.write('\n')
print(f'{len(records)} paired operations; {len(regressions)} exceed both 10% and 1 ms')
for row in regressions:
    print(row)
if a.get('memory_cases') and b.get('memory_cases'):
    def memory_key(case):
        return (case['kind'], case['operation'], case['rows'])
    old_memory = {memory_key(case): case for case in a['memory_cases']}
    new_memory = {memory_key(case): case for case in b['memory_cases']}
    require(len(old_memory) == len(new_memory) == 30 and old_memory.keys() == new_memory.keys(), 'Unpaired memory cases')
    memory = []
    for key, old in old_memory.items():
        new = new_memory[key]
        row = dict(zip(['kind', 'operation', 'rows'], key))
        for label, case in [('baseline', old), ('candidate', new)]:
            row.update({label + '_' + metric: value for metric, value in case['metrics'].items()})
        memory.append(row)
    with (output / 'memory-comparison.csv').open('x') as file:
        writer = csv.DictWriter(file, fieldnames=memory[0])
        writer.writeheader()
        writer.writerows(memory)
print(output)

with (output / 'derivation.json').open('x') as file:
    json.dump({'baseline_manifest': str(baseline / 'root-manifest.json'),
               'baseline_manifest_sha256': hashlib.sha256((baseline / 'root-manifest.json').read_bytes()).hexdigest(),
               'candidate_manifest': str(candidate / 'root-manifest.json'),
               'candidate_manifest_sha256': hashlib.sha256((candidate / 'root-manifest.json').read_bytes()).hexdigest(),
               'deriver_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.iterdir()) if p.name != 'derivation.json'}}, file, indent=2)
    file.write('\n')
