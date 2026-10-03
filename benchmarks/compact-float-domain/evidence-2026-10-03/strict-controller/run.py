#!/usr/bin/env python3
"""Source-bound public long+float addition screen with full-result oracles."""
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

from core import cases, require, validate_all, validate_round, summarize, FIELDS, RESULT_FIELDS, DOMAIN_FIELDS

HERE = Path(__file__).resolve().parent
COMMITS = {'baseline': '213ceeee5a0f7953bf0f13316e2207a766dcbb24',
           'candidate': '452ac7232ef6e47c398bcd22c7bb2800b55932c3'}


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
            'cat(R.home(), R.version.string, sep=intToUtf8(10L))'], text=True).splitlines()
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
        require(q['phase'] == 'qualify' and q['exact_results'] is True and q['observations'] == 2*len(cases()),
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
        input='One million rows. Original long grid (13*i)%10001-5000 and float grid ((19*i)%1001-500)/8. Sparse long rows13+997*j and float rows19+991*j; independent seeded exact50% input masks; float-only prefix/suffix256; plain alltags in both inputs. All27 ranks cycle where present; union and overlap are recorded.',
        operations='Public long+float and float+long, with exact binary64 results. Compact inputs use plain, retained8191/16385, and short7/11 layouts. Typed-double and missing-free bare controls remain plain ordinary double storage in every panel, repeated to detect within-panel drift. Requested threads1.',
        order='Fresh R process per build/round; alternate paired build order. Rotate layouts and patterns with even-round reversals. Reverse operand order on even rounds. Explicit rotations/reversals are checked, without claiming exhaustive pattern permutations. Two representations alternate; three-representation missing-free cases use all six permutations.',
        oracle='Full paired input/rank/result/missing/metadata hashes; independent binary64 sum with oracle input-missing union normalized to systemNA. Exact double storage and unchanged source state/ownership. Outside clocks and entry counts, clear every expected missing through public replacement and recheck full cleared/original results and sources. Value/rank/result hashes agree across equivalent layouts, orders and representations; metadata is stable percase.',
        native='Actual scalar entry counter must equal every retained timed call for both typed builds; zero for bare R. A preceding public primer call settles lazy admission before the counted qualification call.',
        interval=('No clocks or calibration: one recorded call after primer and before full verification.' if phase == 'qualify' else 'Repeated public calls include result allocation and automatic GC. Construction, explicit GC, calibration, hashing and qualification excluded; >=50ms CPU calibration then target300ms retained CPU intervals.'),
        domain='Read-only descriptor diagnostic must be absent for exact213ce baseline and present for the candidate. Constructed compact FLOAT inputs must have the strict-domain fact only in the candidate; both before/after states are bound. Typed and bare controls carry no compact fact.',
        limits='One host, one million rows, constructed modern canonical missing values and addition only. Random masks are independent per input, so output missing density is their recorded union, not50%. No reader, temporal, imported-format or universal parity claim. Bare controls have less storage policy. Short chunks intentionally stress span/proof overhead; typed/bare inputs are not chunked.'))
    rows = []
    for number in range(1, rounds + 1):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            result = output / f'{number:02}-{variant}.csv'
            command = [str(launcher), '--vanilla', str(HERE / 'worker.R'), str(builds[variant] / 'library'), str(number), str(result), variant]
            if phase == 'qualify':
                command.append('qualify')
            with (output / f'{number:02}-{variant}.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            batch = read_csv(result)
            validate_round(batch, number, phase)
            rows.extend(dict(variant=variant, **r) for r in batch)
            print(f'Completed {number} {variant}', flush=True)
    validate_all(rows, rounds, phase)
    if phase == 'measure':
        qualified = read_csv(args.qualification / 'raw.csv')
        validate_all(qualified, 1, 'qualify')
        expected = {(r['variant'],)+tuple(r[k] for k in FIELDS):tuple(r[k] for k in RESULT_FIELDS+DOMAIN_FIELDS) for r in qualified}
        require(all(tuple(r[k] for k in RESULT_FIELDS+DOMAIN_FIELDS)==expected[(r['variant'],)+tuple(r[k] for k in FIELDS)] for r in rows),
                'Measured semantics differ from untimed qualification')
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
