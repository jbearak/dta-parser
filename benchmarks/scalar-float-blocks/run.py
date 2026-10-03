#!/usr/bin/env python3
"""Source-bound public scalar float screen with storage-specific full oracles."""
import argparse
import csv
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

from core import cases, require, validate_all, validate_round, summarize

HERE = Path(__file__).resolve().parent
COMMITS = {'baseline': 'dbcf75cbfe589b5ac2a78166d1e436faa7bbb896',
           'candidate': '9520f1105eb2556333642b9f591a6d3c9cf89bdc'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(dict.fromkeys(k for r in rows for k in r)))
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def inventory(build, role, repository):
    path = repository / 'benchmarks/native-operations/run.py'
    spec = importlib.util.spec_from_file_location('scalar_block_build_records', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    receipt = json.loads((build / 'build-receipt.json').read_text())
    result = module.inventory(build, receipt['variant'])
    require(result['receipt']['base_commit'] == COMMITS[role], 'Wrong measured source revision')
    require(result['receipt']['source_patch_sha256'] == hashlib.sha256(b'').hexdigest(), 'Patched source')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'candidate', 'repository', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--rounds', type=int, default=6)
    parser.add_argument('--qualify-only', action='store_true')
    parser.add_argument('--qualification', type=Path)
    args = parser.parse_args()
    phase = 'qualify' if args.qualify_only else 'measure'
    rounds = 1 if args.qualify_only else args.rounds
    require(args.qualify_only or rounds >= 6 and rounds % 6 == 0, 'Use a positive multiple of six rounds')
    require(args.qualify_only or args.qualification is not None, 'Completed qualification required')
    require(os.name != 'nt', 'This controller requires the Unix R executable layout')
    found = shutil.which('Rscript')
    require(found is not None, 'Rscript absent')
    launcher = Path(found).resolve(strict=True)
    repository = args.repository.resolve()
    builds = {v: getattr(args, v).resolve() for v in ('baseline', 'candidate')}
    controllers = {'controller': Path(__file__).resolve(), 'worker': HERE / 'worker.R',
        'validation': HERE / 'core.py', 'protocol_tests': HERE / 'test-run.py',
        'build_validation': repository / 'benchmarks/native-operations/run.py',
        'build_recorder': repository / 'benchmarks/r-file-readers/record-builds.py',
        'build_recorder_parent': repository / 'benchmarks/io-optimization/record-builds.py'}

    def binding():
        details = subprocess.check_output([str(launcher), '--vanilla', '-e',
            'cat(R.home(),"\\n",R.version.string,sep="")'], text=True).splitlines()
        execution = dict(Rscript=str(launcher), Rscript_sha256=digest(launcher),
            R_runtime_sha256=digest(Path(details[0]) / 'bin/exec/R'), R_version=details[1])
        result = {v: inventory(b, v, repository) for v, b in builds.items()}
        require(all(b['receipt']['toolchain']['R_runtime_sha256'] == execution['R_runtime_sha256']
                    for b in result.values()), 'Build/worker runtime mismatch')
        return dict(builds=result, execution=execution, controllers={k: digest(p) for k, p in controllers.items()})

    before = binding()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / 'provenance-before.json', before)
    if phase == 'measure':
        q = json.loads((args.qualification / 'completion.json').read_text())
        require(q['phase'] == 'qualify' and q['exact_results'] is True and q['observations'] == 120,
                'Incomplete qualification')
        require(json.loads((args.qualification / 'provenance-after.json').read_text()) == before,
                'Qualification binding changed')
        for name, sha in q['artifacts'].items():
            require(digest(args.qualification / name) == sha, 'Qualification artifact changed')
    patch = []
    for name in sorted(set(before['builds']['baseline']['source']) | set(before['builds']['candidate']['source'])):
        if before['builds']['baseline']['source'].get(name) == before['builds']['candidate']['source'].get(name):
            continue
        a, b = (builds[v] / 'source' / name for v in ('baseline', 'candidate'))
        patch.extend(difflib.unified_diff(a.read_text().splitlines(keepends=True) if a.exists() else [],
            b.read_text().splitlines(keepends=True) if b.exists() else [], fromfile='a/' + name, tofile='b/' + name))
    (output / 'source.patch').write_text(''.join(patch))
    write_json(output / 'protocol.json', dict(phase=phase, rounds=rounds, cases_per_build_round=len(cases()),
        host=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count(),
        input='One million plain contiguous float values, exactly representable in binary32. Seven patterns: none, sparse grid997, random exact50%, first50%, prefix256, suffix256, alltags. All27 canonical missing ranks cycle where present.',
        operations='Public x+0.1, x-0.1, x*1.01 and x/1.01. Compact-float and typed-double controls for every pattern; bare R only without missing values. Requested threads1.',
        order='Fresh R process per build/round; alternate paired build order. Rotate seven patterns and reverse on even rounds, not exhaustive permutations or equal pattern-position counts. Reverse four-operation order on even rounds. Two-representation orders alternate; no-missing three-representation cases use all six permutations.',
        oracle='Full input/rank/result/missing/metadata hashes, independent binary64 arithmetic then binary32 output rounding for compact, exact result storage/missing caches and unchanged source/native ownership. Typed and bare binary64 results intentionally differ from compact float-rounded results. Metadata stability is per case.',
        native='Actual scalar entry counter must equal every retained timed call for both typed builds; zero for bare R. A preceding public primer call settles lazy admission before the counted qualification call.',
        interval=('No clocks or calibration: one recorded call after primer and before full verification.' if phase == 'qualify' else 'Repeated public calls include result allocation and automatic GC. Construction, explicit GC, calibration, hashing and qualification excluded; >=50ms CPU calibration then target300ms retained CPU intervals.'),
        limits='One host, one million rows, modern canonical missing values, plain input only. No reader throughput, retained-layout throughput, temporal, arbitrary import, reverse-division or universal parity claim. Different patterns do not isolate branch prediction. Bare R has less storage policy.'))
    rows = []
    for number in range(1, rounds + 1):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            result = output / f'{number:02}-{variant}.csv'
            command = [str(launcher), '--vanilla', str(HERE / 'worker.R'), str(builds[variant] / 'library'), str(number), str(result)]
            if phase == 'qualify':
                command.append('qualify')
            with (output / f'{number:02}-{variant}.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            batch = read_csv(result)
            validate_round(batch, number, phase)
            rows.extend(dict(variant=variant, **r) for r in batch)
            print(f'Completed {number} {variant}', flush=True)
    validate_all(rows, rounds, phase)
    write_csv(output / 'raw.csv', rows)
    if phase == 'measure':
        write_csv(output / 'summary.csv', summarize(rows))
    after = binding()
    require(before == after, 'Source/runtime/controller changed')
    write_json(output / 'provenance-after.json', after)
    artifacts = {p.name: digest(p) for p in output.iterdir() if p.suffix in ('.json', '.csv', '.patch')}
    write_json(output / 'completion.json', dict(phase=phase, observations=len(rows), rounds=rounds,
        exact_results=True, provenance_unchanged=True, artifacts=artifacts))
    print(f'Complete: {len(rows)} qualified {phase} observations')


if __name__ == '__main__':
    main()
