"""Independently recompute completed screen statistics from retained intervals."""
import argparse
from collections import defaultdict
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser()
parser.add_argument('directory', type=Path)
parser.add_argument('--observations', type=int, choices=(696, 144), required=True)
args = parser.parse_args()
root = args.directory.resolve()
completion = json.loads((root / 'completion.json').read_text())
require(completion['phase'] == 'measure' and completion['exact_results'] is True and
        completion['observations'] == args.observations, 'Incomplete measured screen')
for name, expected in completion['artifacts'].items():
    require(sha(root / name) == expected, 'Completed artifact changed: ' + name)
with (root / 'raw.csv').open() as stream:
    rows = list(csv.DictReader(stream))
with (root / 'summary.csv').open() as stream:
    summary = list(csv.DictReader(stream))
require(len(rows) == args.observations, 'Wrong row count')
groups = defaultdict(list)
for row in rows:
    require(row['phase'] == 'measure', 'Wrong phase')
    key = tuple(row[k] for k in ('layout', 'pattern', 'operation', 'variant', 'representation'))
    groups[key].append(row)
for key, group in groups.items():
    require(sorted(int(r['round']) for r in group) == list(range(1, 7)), 'Incomplete group: ' + repr(key))
    group.sort(key=lambda r: int(r['round']))
    for row in group:
        require(float(row['repetitions']) == int(row['repetitions']) > 0, 'Bad count')
        require(all(math.isfinite(float(row[k])) and float(row[k]) > 0 for k in ('cpu', 'wall')), 'Bad interval')

def interval(row, metric):
    return float(row[metric]) / int(row['repetitions'])

computed = []
for reported in summary:
    key = tuple(reported[k] for k in ('layout', 'pattern', 'operation'))
    reps = sorted({group[-1] for group in groups if group[:3] == key})
    require(reps == (['compact', 'ordinary', 'typed_double'] if args.observations == 696 and key[1] == 'none'
                     else ['compact', 'typed_double']), 'Wrong representations')
    stats = dict(zip(('layout', 'pattern', 'operation'), key))
    for variant in ('baseline', 'candidate'):
        for rep in reps:
            for metric in ('cpu', 'wall'):
                stats[f'{variant}_{rep}_{metric}'] = statistics.median(interval(r, metric) for r in groups[key + (variant, rep)])
    for rep in reps:
        for metric in ('cpu', 'wall'):
            stats[f'{rep}_{metric}_speedup'] = stats[f'baseline_{rep}_{metric}'] / stats[f'candidate_{rep}_{metric}']
            stats[f'{rep}_{metric}_paired_speedup'] = statistics.median(
                interval(b, metric) / interval(c, metric)
                for b, c in zip(groups[key + ('baseline', rep)], groups[key + ('candidate', rep)]))
    for variant in ('baseline', 'candidate'):
        stats[f'{variant}_compact_typed_cpu'] = stats[f'{variant}_compact_cpu'] / stats[f'{variant}_typed_double_cpu']
        if 'ordinary' in reps:
            stats[f'{variant}_compact_ordinary_cpu'] = stats[f'{variant}_compact_cpu'] / stats[f'{variant}_ordinary_cpu']
    for field, value in stats.items():
        require(field in reported, 'Missing statistic: ' + field)
        if isinstance(value, (int, float)):
            require(math.isclose(value, float(reported[field]), rel_tol=1e-12, abs_tol=1e-15), 'Statistic differs: ' + repr(key) + ' ' + field)
        else:
            require(value == reported[field], 'Summary case changed')
    stats['paired_compact_cost_normalized_by_typed'] = statistics.median(
        (interval(c, 'cpu') / interval(b, 'cpu')) / (interval(tc, 'cpu') / interval(tb, 'cpu'))
        for b, c, tb, tc in zip(groups[key + ('baseline', 'compact')], groups[key + ('candidate', 'compact')],
                                groups[key + ('baseline', 'typed_double')], groups[key + ('candidate', 'typed_double')]))
    computed.append(stats)
require(len(computed) == (26 if args.observations == 696 else 6), 'Incomplete summary matrix')
record = dict(status='PASS', observations=len(rows), summaries=len(computed),
    raw_sha256=sha(root / 'raw.csv'), summary_sha256=sha(root / 'summary.csv'),
    completion_sha256=sha(root / 'completion.json'), auditor_sha256=sha(Path(__file__)),
    cpu_interval_range=[min(float(r['cpu']) for r in rows), max(float(r['cpu']) for r in rows)],
    wall_interval_range=[min(float(r['wall']) for r in rows), max(float(r['wall']) for r in rows)],
    statistics=computed,
    scope='Independent raw-interval median and paired-ratio replay plus complete per-case six-round groups and completed artifact hashes. Full matrix/order, semantic and current source/runtime audit is recorded separately by the root auditor.')
output = root.parent / (root.name + '-independent-statistics.json')
require(not output.exists(), 'Refusing to overwrite a statistics receipt')
output.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
print('PASS', len(rows), 'observations;', len(computed), 'summaries')
