"""Derive a paired Stage 3 regression table from fresh guarded Stage 4 runs."""
import csv
import hashlib
import json
from pathlib import Path
import re
import sys


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path):
    with path.open() as file:
        return list(csv.DictReader(file))


def load(root):
    manifest = json.loads((root / 'root-manifest.json').read_text())
    for name, entry in manifest['outputs'].items():
        require(digest(root / name) == entry['sha256'], f'Changed evidence: {root / name}')
        require(len(read_csv(root / name)) == entry['rows'], f'Changed rows: {root / name}')
    for case in manifest['memory_cases']:
        require(digest(root / case['file']) == case['sha256'], f'Changed memory evidence: {case}')
    rows = read_csv(root / 'owned-double.csv')
    keys = ('family', 'operation', 'rows', 'columns')
    keyed = {tuple(row[key] for key in keys): row for row in rows}
    require(len(keyed) == len(rows) == 46, 'Incomplete or duplicate operation matrix')
    return manifest, keys, keyed


baseline, candidate, output = map(Path, sys.argv[1:])
a, keys, before = load(baseline)
b, other_keys, after = load(candidate)
require(a['mode'] == 'baseline' and b['mode'] == 'candidate', 'Wrong comparison direction')
require(a['runner_sha256'] == b['runner_sha256'], 'Mismatched R runner bytes')
require(a['iterations'] == b['iterations'] == 7, 'Wrong iteration count')
require(keys == other_keys and before.keys() == after.keys(), 'Unpaired operations')
require(not output.exists(), f'Refusing to overwrite {output}')
records = []
for key, old in before.items():
    new = after[key]
    row = dict(zip(keys, key))
    for metric in ['median_ms', 'r_allocated_bytes', 'r_largest_allocation_bytes', 'bench_allocated_bytes']:
        row['baseline_' + metric] = float(old[metric])
        row['candidate_' + metric] = float(new[metric])
    require(row['baseline_median_ms'] > 0, 'Nonpositive baseline median')
    row['median_delta_ms'] = row['candidate_median_ms'] - row['baseline_median_ms']
    row['median_ratio'] = row['candidate_median_ms'] / row['baseline_median_ms']
    row['investigate'] = row['median_delta_ms'] > 1 and row['median_ratio'] > 1.1
    records.append(row)


def memory(root, manifest):
    answer = {}
    for case in manifest['memory_cases']:
        key = (case['operation'], case['rows'])
        require(key not in answer, 'Duplicate memory case')
        metrics = {'maximum_resident_set_size_bytes': case['maximum_resident_set_size_bytes']}
        text = (root / case['file']).read_text()
        for name in ['retained_with_source_vector_heap_bytes', 'excess_after_drop_result_bytes', 'released_with_last_result_bytes']:
            found = re.findall(rf'^{name} ([-+0-9.eE]+)\s*$', text, re.M)
            require(len(found) == 1, f'Missing or duplicate {name}')
            metrics[name] = int(float(found[0]))
        answer[key] = metrics
    require(len(answer) == 6, 'Incomplete memory matrix')
    return answer


old_memory, new_memory = memory(baseline, a), memory(candidate, b)
require(old_memory.keys() == new_memory.keys(), 'Unpaired memory')
memory_records = []
for key, old in old_memory.items():
    row = dict(zip(['operation', 'rows'], key))
    for label, metrics in [('baseline', old), ('candidate', new_memory[key])]:
        row.update({label + '_' + name: value for name, value in metrics.items()})
    memory_records.append(row)
output.mkdir(parents=True)
for filename, rows in [('operation-comparison.csv', records), ('memory-comparison.csv', memory_records)]:
    with (output / filename).open('x') as file:
        writer = csv.DictWriter(file, fieldnames=rows[0])
        writer.writeheader()
        writer.writerows(rows)
regressions = [row for row in records if row['investigate']]
with (output / 'investigate.json').open('x') as file:
    json.dump(regressions, file, indent=2)
    file.write('\n')
with (output / 'derivation.json').open('x') as file:
    json.dump({'baseline_manifest': str(baseline / 'root-manifest.json'),
               'baseline_manifest_sha256': digest(baseline / 'root-manifest.json'),
               'candidate_manifest': str(candidate / 'root-manifest.json'),
               'candidate_manifest_sha256': digest(candidate / 'root-manifest.json'),
               'deriver_sha256': digest(Path(__file__)),
               'files': {p.name: digest(p) for p in sorted(output.iterdir()) if p.name != 'derivation.json'}}, file, indent=2)
    file.write('\n')
print(f'{len(records)} paired operations and {len(memory_records)} memory cases; {len(regressions)} exceed both10% and1ms')
for row in regressions:
    print(row)
