#!/usr/bin/env python3
"""Compare complete corpus values, metadata, warnings and failures in two R builds."""
import argparse
import json
import os
from pathlib import Path
from run import HERE, absolute_path, child, installed_binding, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('inputs', 'output', 'baseline_library', 'baseline_build', 'candidate_library', 'candidate_build'):
        parser.add_argument('--' + field.replace('_', '-'), type=absolute_path, required=True)
    parser.add_argument('--experiment', action='append', default=[])
    args = parser.parse_args()
    variants = ('baseline', 'candidate')
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = json.loads(args.inputs.read_text())
    if not inputs or len({r['id'] for r in inputs}) != len(inputs):
        raise ValueError('Input IDs must be nonempty and unique')
    builds = {v: installed_binding(getattr(args, v + '_library'), getattr(args, v + '_build')) for v in variants}
    hashes = {p: sha(p) for p in sorted({r['path'] for r in inputs})}
    scripts = [Path(__file__), HERE / 'qualify-corpus.R', HERE / 'run.py']
    workers = {p.name: sha(p) for p in scripts}
    manifest_hash = sha(args.inputs)
    experiment = dict(x.split('=', 1) for x in args.experiment)
    if any(not k.startswith('DTATOOLS_EXPERIMENT_') for k in experiment):
        raise ValueError('Invalid experimental control')
    binding = dict(builds=builds, workers=workers, manifest_sha256=manifest_hash,
        experiments=experiment, inputs=[dict(id=r['id'], reader=r['reader'],
            bytes=Path(r['path']).stat().st_size, sha256=hashes[r['path']]) for r in inputs])
    (args.output / 'binding.json').write_text(json.dumps(binding, indent=2) + '\n')
    environment = {k: v for k, v in os.environ.items() if not k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_'))}
    results = {}
    for variant in variants:
        directory = args.output / variant
        directory.mkdir()
        output = directory / 'records.jsonl'
        child(['Rscript', '--vanilla', str(HERE / 'qualify-corpus.R'),
            str(getattr(args, variant + '_library')), str(args.inputs), str(output)],
            directory, environment | (experiment if variant == 'candidate' else {}))
        records = [json.loads(line) for line in output.read_text().splitlines()]
        if [r['id'] for r in records] != [r['id'] for r in inputs]:
            raise ValueError('Incomplete or reordered corpus records')
        results[variant] = records
        print('COMPLETED ' + variant + ': ' + str(len(records)) + ' inputs', flush=True)
    differences = [a['id'] for a, b in zip(results['baseline'], results['candidate']) if a != b]
    if hashes != {p: sha(p) for p in hashes} or manifest_hash != sha(args.inputs):
        raise ValueError('Corpus inputs changed during qualification')
    if workers != {p.name: sha(p) for p in scripts}:
        raise ValueError('Corpus qualification workers changed')
    for variant in variants:
        if builds[variant] != installed_binding(getattr(args, variant + '_library'), getattr(args, variant + '_build')):
            raise ValueError('Corpus installation changed')
    summary = dict(inputs=len(inputs), matched=len(inputs) - len(differences),
        differences=differences, baseline_errors=[r['id'] for r in results['baseline'] if r['status'] == 'error'],
        candidate_errors=[r['id'] for r in results['candidate'] if r['status'] == 'error'])
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary), flush=True)
    if differences:
        raise ValueError('Corpus semantic or failure behavior differs')


if __name__ == '__main__':
    main()
