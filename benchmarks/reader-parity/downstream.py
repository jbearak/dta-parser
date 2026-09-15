#!/usr/bin/env python3
"""Compare full/sparse consumption and first writes after installed reads."""
import argparse
import json
import os
from pathlib import Path
import statistics
from run import HERE, child, installed_binding, write_csv


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('cases', 'output', 'baseline_library', 'baseline_build', 'candidate_library', 'candidate_build'):
        parser.add_argument('--' + name.replace('_', '-'), type=Path, required=True)
    parser.add_argument('--case', action='append', required=True)
    parser.add_argument('--repetitions', type=int, default=6)
    parser.add_argument('--experiment', action='append', default=[])
    args = parser.parse_args()
    variants = ('baseline', 'candidate')
    bindings = {v: installed_binding(getattr(args, v + '_library'), getattr(args, v + '_build')) for v in variants}
    cases = [c for c in json.loads(args.cases.read_text()) if c['id'] in args.case]
    if len(cases) != len(set(args.case)) or args.repetitions < 2:
        raise ValueError('Unknown cases or insufficient repetitions')
    experiment = dict(x.split('=', 1) for x in args.experiment)
    if any(not k.startswith('DTATOOLS_EXPERIMENT_') for k in experiment):
        raise ValueError('Invalid experimental control')
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'binding.json').write_text(json.dumps(dict(builds=bindings, experiments=experiment), indent=2))
    environment = {k: v for k, v in os.environ.items() if not k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_'))}
    rows = []
    checks = {}
    for case in cases:
        for reader in ('dta', 'arrow'):
            for workload in ('sparse', 'traverse', 'first_write', 'r_vector'):
                for repetition in range(args.repetitions):
                    for variant in variants if repetition % 2 == 0 else reversed(variants):
                        directory = args.output / f'job-{len(rows) + 1:05d}'
                        directory.mkdir()
                        job = dict(case, library=str(getattr(args, variant + '_library').resolve()),
                                   reader='read_' + reader, path=case[reader], workload=workload)
                        (directory / 'job.json').write_text(json.dumps(job))
                        env = environment | (experiment if variant == 'candidate' else {})
                        resource = child(['Rscript', '--vanilla', str(HERE / 'downstream.R'),
                            str(directory / 'job.json'), str(directory / 'result.json')], directory, env)
                        result = json.loads((directory / 'result.json').read_text())
                        key = (case['id'], reader, workload)
                        if key in checks and checks[key] != result['result']:
                            raise ValueError('Downstream values differ: ' + str(key))
                        checks[key] = result['result']
                        rows.append(dict(case=case['id'], reader=reader, workload=workload,
                            variant=variant, repetition=repetition + 1,
                            load_seconds=result['load_seconds'], elapsed_seconds=result['elapsed_seconds'],
                            cpu_seconds=result['cpu_seconds'], **resource,
                            native_before=json.dumps(result['native_before']), native_after=json.dumps(result['native_after'])))
                        write_csv(args.output / 'observations.csv', rows)
                print('MEASURED ' + '/'.join(key), flush=True)
    summary = []
    for key in checks:
        for variant in variants:
            group = [r for r in rows if (r['case'], r['reader'], r['workload']) == key and r['variant'] == variant]
            record = dict(case=key[0], reader=key[1], workload=key[2], variant=variant)
            for field in ('elapsed_seconds', 'load_seconds', 'cpu_seconds', 'peak_rss_bytes'):
                values = [r[field] for r in group]
                record.update({label + '_' + field: fn(values) for label, fn in
                               (('median', statistics.median), ('min', min), ('max', max))})
            summary.append(record)
    write_csv(args.output / 'summary.csv', summary)
    for v in variants:
        if installed_binding(getattr(args, v + '_library'), getattr(args, v + '_build')) != bindings[v]:
            raise ValueError('Installation changed during downstream measurements')


if __name__ == '__main__':
    main()
