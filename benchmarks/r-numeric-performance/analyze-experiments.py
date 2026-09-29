#!/usr/bin/env python3
"""Compare verified public-operation timings with fixed bootstrap indices."""
import collections
import csv
import json
from pathlib import Path
import sys
import numpy as np

root, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
fields = ['n', 'width', 'groups', 'mode', 'scenario', 'engine']
labels = ['experiments', 'merged-main']
cells = {}
raw_records = {}
for label in labels:
    rows = list(csv.DictReader((root / label / 'raw.csv').open()))
    raw_records[label] = rows
    grouped = collections.defaultdict(list)
    for row in rows:
        grouped[tuple(row[name] for name in fields)].append(row)
    cells[label] = {}
    for key, observations in grouped.items():
        observations.sort(key=lambda row: int(row['sample']))
        assert [int(row['sample']) for row in observations] == list(range(1, 21)), key
        cells[label][key] = np.array([float(row['us']) for row in observations])
assert cells[labels[0]].keys() == cells[labels[1]].keys()
# Shared row indices retain within-sample engine pairing. Main and candidate
# were separate runs, so the between-build comparison resamples independently.
rng = np.random.default_rng(20260929)
paired_indices = rng.integers(0, 20, size=(10000, 20))
main_indices = rng.integers(0, 20, size=(10000, 20))
np.savez_compressed(output / 'bootstrap-indices.npz', paired=paired_indices, main=main_indices)
medians = {label: {key: float(np.median(values)) for key, values in table.items()}
           for label, table in cells.items()}
bootstrap = {key: np.median(values[paired_indices], axis=1)
             for key, values in cells['experiments'].items()}
rows = []
for key in sorted(cells['experiments'], key=lambda k: (k[3],int(k[2]),int(k[0]),int(k[1]),k[4],k[5])):
    if key[-1] in ('data_table_plain', 'dplyr_plain'):
        continue
    row = dict(zip(fields, key))
    candidate = medians['experiments'][key]
    row.update(main_us=medians['merged-main'][key], candidate_us=candidate,
               main_speedup=medians['merged-main'][key] / candidate)
    for engine, prefix in [('dplyr_plain', 'dplyr'), ('data_table_plain', 'data_table')]:
        reference_key = key[:-1] + (engine,)
        ratios = bootstrap[key] / bootstrap[reference_key]
        row[prefix + '_us'] = medians['experiments'][reference_key]
        row[prefix + '_ratio'] = candidate / medians['experiments'][reference_key]
        row[prefix + '_lower95'], row[prefix + '_upper95'] = map(float, np.quantile(ratios, [0.025, 0.975]))
    main_boot = np.median(cells['merged-main'][key][main_indices], axis=1)
    row['main_speedup_lower95'], row['main_speedup_upper95'] = map(float,
        np.quantile(main_boot / bootstrap[key], [0.025, 0.975]))
    rows.append(row)
with (output / 'comparisons.csv').open('w') as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
summary = {'bootstrap_resamples':10000, 'samples_per_condition':20,
           'seed':20260929, 'raw_calls': {label:len(raw_records[label]) for label in labels},
           'timed_gc_calls': {label:sum(float(r['gc_seconds'])>0 for r in raw_records[label]) for label in labels}}
for mode in ('plain', 'owned'):
    selected = [r for r in rows if r['mode'] == mode]
    summary[mode] = dict(cells=len(selected), faster_than_main=sum(r['main_speedup']>1 for r in selected),
        main_speedup_range=[min(r['main_speedup'] for r in selected),max(r['main_speedup'] for r in selected)],
        faster_dplyr=sum(r['dplyr_ratio']<1 for r in selected),
        dplyr_upper95_below1=sum(r['dplyr_upper95']<1 for r in selected),
        data_table_no_more_than_5pct_slower=sum(r['data_table_ratio']<=1.05 for r in selected),
        data_table_within_plus_minus5=sum(.95<=r['data_table_ratio']<=1.05 for r in selected),
        data_table_upper95_at_most1_05=sum(r['data_table_upper95']<=1.05 for r in selected))
(output / 'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
