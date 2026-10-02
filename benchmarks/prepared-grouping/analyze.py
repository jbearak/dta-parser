#!/usr/bin/env python3
"""Recompute grouping representation ratios from completed paired observations."""
import argparse
import csv
import importlib.util
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('grouping_run', HERE / 'run.py')
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def main():
    if not __debug__:
        raise RuntimeError('Ratio validation requires Python assertions; run without -O')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    completion = json.loads((args.results / 'completion.json').read_text())
    protocol = json.loads((args.results / 'protocol.json').read_text())
    assert completion['exact_results'] and completion['provenance_unchanged']
    with (args.results / 'raw.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == completion['observations'] == 2 * protocol['rounds'] * len(RUN.EXPECTED)
    for variant in ('baseline', 'candidate'):
        for round_number in range(1, protocol['rounds'] + 1):
            RUN.validate_round([row for row in rows if row['variant'] == variant and
                                int(row['round']) == round_number], round_number, variant)
    RUN.validate_balance(rows, protocol['rounds'])
    groups = RUN.validate_results(rows)
    output = []
    for case in sorted({key[:-1] for key in groups}):
        result = dict(zip(RUN.FIELDS[:-1], case))
        for variant in ('baseline', 'candidate'):
            observations = {}
            for representation in ('compact', 'typed_double', 'ordinary'):
                selected = [row for row in groups[case + (representation,)] if row['variant'] == variant]
                observations[representation] = {int(row['round']): float(row['cpu_seconds']) /
                                                int(row['iterations']) for row in selected}
                result[variant + '_' + representation + '_cpu_seconds'] = statistics.median(
                    observations[representation].values())
                result[variant + '_' + representation + '_peak_vcell_bytes'] = statistics.median(
                    float(row['peak_vcell_bytes']) for row in selected)
            for denominator in ('typed_double', 'ordinary'):
                result[variant + '_compact_over_' + denominator] = (
                    result[variant + '_compact_cpu_seconds'] /
                    result[variant + '_' + denominator + '_cpu_seconds'])
                result[variant + '_paired_compact_over_' + denominator] = statistics.median(
                    observations['compact'][number] / observations[denominator][number]
                    for number in range(1, protocol['rounds'] + 1))
        result['compact_cpu_speedup'] = result['baseline_compact_cpu_seconds'] / result['candidate_compact_cpu_seconds']
        result['key_cache_bytes'] = 8 * int(result['n']) * int(result['key_count'])
        output.append(result)
    with args.output.open('x', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(output[0]))
        writer.writeheader()
        writer.writerows(output)
    print('Recomputed', len(output), 'case ratios from', len(rows), 'observations')


if __name__ == '__main__':
    main()
