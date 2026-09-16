#!/usr/bin/env python3
"""Matched Stata/R reads. Screening runs cannot satisfy the release gate."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import shutil
import sys

HERE = Path(__file__).resolve().parent


def absolute_path(value):
    # Workers run in per-job directories, so CLI paths must keep their meaning
    # after the controller changes the child's working directory.
    return Path(value).resolve()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def installed_binding(library, record):
    value = json.loads(record.read_text())
    actual = {str(p.relative_to(library / 'dtatools')): sha(p)
              for p in sorted((library / 'dtatools').rglob('*')) if p.is_file()}
    if actual != value['installed']:
        raise ValueError('Installed package differs from its build record')
    return dict(commit=value['source_commit'], tree=value['package_tree'], installed=actual)


def orders(methods, repetitions):
    # Every method occupies every position, in forward and reverse orders.
    cycle = [methods[i:] + methods[:i] for i in range(len(methods))]
    cycle += [list(reversed(x)) for x in cycle]
    return [cycle[i % len(cycle)] for i in range(repetitions)]


def stata_string(value):
    if any(c in value for c in '\n\r"`$'):
        raise ValueError('Unsupported character in Stata benchmark path')
    return '"' + value + '"'


def stata_program(case, mode, calls, output):
    path = stata_string(case['dta'])
    selection = case.get('selection', [])
    if any(not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', x) for x in selection):
        raise ValueError('Benchmark needs Stata identifier column names')
    names = ' '.join(selection)
    if case['selection_mode'] == 'all':
        read = f'quietly use {path}, clear'
    elif case['selection_mode'] == 'known':
        read = f'quietly use {names} using {path}, clear'
    else:
        read = (f'quietly describe using {path}, varlist\n'
                'local available `r(varlist)\'\n'
                f'local requested {names}\n'
                'local selected : list requested & available\n'
                f'quietly use `selected\' using {path}, clear')
    warm = read + '\nclear\n' if mode == 'warm' else ''
    return f'''version 18.0
clear all
set more off
set maxvar 32767
creturn list
{warm}timer clear 1
timer on 1
forvalues i = 1/{calls} {{
{read}
}}
timer off 1
quietly timer list 1
local elapsed = r(t1) / {calls}
assert _N == {case['rows']}
assert c(k) == {case['columns']}
file open result using {stata_string(str(output))}, write text replace
file write result %21.12f (`elapsed') _n
file close result
exit, clear
'''


def child(command, directory, environment):
    with (directory / 'process.log').open('w') as stream:
        process = subprocess.Popen(command, cwd=directory, env=environment,
                                   stdout=stream, stderr=subprocess.STDOUT)
        _, status, usage = os.wait4(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command)
    return dict(peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
                process_cpu_seconds=usage.ru_utime + usage.ru_stime)


def write_csv(path, rows):
    with path.open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def summaries(observations, eligible):
    result = []
    groups = sorted({(r['case'], r['mode'], r['cohort']) for r in observations})
    for case, mode, cohort in groups:
        group = [r for r in observations if (r['case'], r['mode'], r['cohort']) == (case, mode, cohort)]
        stata = statistics.median(r['elapsed_seconds'] for r in group if r['method'] == 'stata')
        stata_calls = min(r.get('calls', 1) for r in group if r['method'] == 'stata')
        for method in sorted({r['method'] for r in group}):
            rows = [r for r in group if r['method'] == method]
            values = [r['elapsed_seconds'] for r in rows]
            median = statistics.median(values)
            # Both clocks are quantized to milliseconds. Require at least ten
            # ticks per timed interval; batching applies only to warm reads.
            resolved = (median * min(r.get('calls', 1) for r in rows) >= 0.010
                        and stata * stata_calls >= 0.010)
            result.append(dict(case=case, mode=mode, cohort=cohort, method=method,
                observations=len(rows), median_seconds=median, min_seconds=min(values),
                max_seconds=max(values), stata_median_seconds=stata,
                timer_resolved=resolved,
                median_peak_rss_bytes=statistics.median(r['peak_rss_bytes'] for r in rows),
                median_cpu_seconds=statistics.median(r['cpu_seconds'] for r in rows
                    if r['cpu_seconds'] is not None) if method != 'stata' else None,
                parity=eligible and len(rows) >= 12 and resolved and median > 0 and median <= stata))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', type=absolute_path, required=True)
    parser.add_argument('--output', type=absolute_path, required=True)
    for variant in ('baseline', 'candidate'):
        parser.add_argument('--' + variant + '-library', type=absolute_path, required=variant == 'baseline')
        parser.add_argument('--' + variant + '-build', type=absolute_path, required=variant == 'baseline')
    parser.add_argument('--stata', type=absolute_path, default=Path('/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp'))
    parser.add_argument('--repetitions', type=int, default=20)
    parser.add_argument('--cohorts', type=int, default=2)
    parser.add_argument('--screen', action='store_true')
    parser.add_argument('--qualify-only', action='store_true')
    parser.add_argument('--case', action='append', default=[])
    parser.add_argument('--mode', choices=('fresh', 'warm'), action='append')
    parser.add_argument('--experiment', action='append', default=[], help='Candidate-only NAME=VALUE')
    args = parser.parse_args()
    if args.repetitions < 1 or args.cohorts < 1:
        parser.error('Counts must be positive')
    variants = ['baseline'] + (['candidate'] if args.candidate_library else [])
    if bool(args.candidate_library) != bool(args.candidate_build):
        parser.error('Candidate library and build record must be supplied together')
    methods = [v + '-' + r for v in variants for r in ('dta', 'arrow')] + ['stata']
    modes = args.mode or ['fresh', 'warm']
    eligible = (not args.screen and not args.qualify_only and len(variants) == 2 and args.cohorts >= 2
                and args.repetitions >= 12 and args.repetitions % (2 * len(methods)) == 0
                and not args.case and modes == ['fresh', 'warm'])
    if not args.screen and not args.qualify_only and not eligible:
        parser.error('Release runs need both builds, >=2 cohorts, a balanced >=12 repetitions, all cases and both modes')
    cases = json.loads(args.cases.read_text())
    if len({c['id'] for c in cases}) != len(cases):
        raise ValueError('Duplicate cases')
    selected = [c for c in cases if not args.case or c['id'] in args.case]
    if not selected or set(args.case) - {c['id'] for c in selected}:
        raise ValueError('Missing selected cases')
    args.output.mkdir(parents=True, exist_ok=False)
    bindings = {v: installed_binding(getattr(args, v + '_library'), getattr(args, v + '_build')) for v in variants}
    paths = sorted({c[k] for c in cases for k in ('dta', 'arrow')})
    inputs = {p: sha(p) for p in paths}
    experiment = dict(x.split('=', 1) for x in args.experiment)
    if any(not key.startswith('DTATOOLS_EXPERIMENT_') for key in experiment):
        raise ValueError('Only private experimental controls are accepted')
    binding = dict(builds=bindings, manifest_sha256=sha(args.cases),
        inputs=[dict(sha256=h, bytes=Path(p).stat().st_size) for p, h in inputs.items()],
        workers={p.name: sha(p) for p in (HERE / 'worker.R', Path(__file__))},
        stata_sha256=sha(args.stata), host=platform.platform(), cpu_count=os.cpu_count(),
        cache='warm filesystem', experiments=experiment, eligible=eligible,
        cohorts=args.cohorts, repetitions=args.repetitions)
    rscript = Path(shutil.which('Rscript')).resolve()
    binding['Rscript_sha256'] = sha(rscript)
    runtime_code = '''.libPaths(c(commandArgs(TRUE)[1], .libPaths()));
      packages <- c("dtatools", "rlang", "tibble", "tidyselect", "vctrs");
      cat(jsonlite::toJSON(list(R=R.version.string, platform=R.version$platform,
          packages=setNames(lapply(packages, function(x) as.character(packageVersion(x))), packages)),
          auto_unbox=TRUE))'''
    binding['runtimes'] = {v: json.loads(subprocess.check_output([str(rscript), '--vanilla', '-e',
        runtime_code, str(getattr(args, v + '_library'))], text=True)) for v in variants}
    binding['threads'] = dict(R_reader='default adaptive policy, threads=0',
        stata='recorded from creturn in each Stata worker',
        environment={k: os.environ[k] for k in ('OMP_NUM_THREADS', 'RAYON_NUM_THREADS',
            'R_PARALLEL_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS') if k in os.environ})
    (args.output / 'binding.json').write_text(json.dumps(binding, indent=2) + '\n')
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_'))}
    counter = 0

    def run(case, method, mode):
        nonlocal counter
        counter += 1
        directory = args.output / f'job-{counter:06d}'
        directory.mkdir()
        output = directory / 'result.json'
        calls = case.get('warm_calls', 1) if mode == 'warm' else 1
        env = environment.copy()
        if method == 'stata':
            script = directory / 'read.do'
            script.write_text(stata_program(case, mode, calls, output))
            resources = child([str(args.stata), '-b', 'do', str(script)], directory, env)
            value = dict(elapsed_seconds=float(output.read_text()), cpu_seconds=None)
            configuration = [line.strip() for p in directory.glob('*.log') for line in p.read_text().splitlines()
                if re.search(r'c\((processors[a-z_]*|stata_version|edition[a-z_]*|flavor|MP)\)', line)]
            if configuration:
                if 'stata_configuration' in binding and configuration != binding['stata_configuration']:
                    raise ValueError('Stata configuration changed during measurement')
                binding['stata_configuration'] = configuration
                (args.output / 'binding.json').write_text(json.dumps(binding, indent=2) + '\n')
        else:
            variant, reader = method.split('-')
            if variant == 'candidate':
                env.update(experiment)
            job = dict(case, library=str(getattr(args, variant + '_library').resolve()),
                       reader='read_' + reader, path=case[reader], mode=mode, calls=calls)
            path = directory / 'job.json'
            path.write_text(json.dumps(job))
            resources = child(['Rscript', '--vanilla', str(HERE / 'worker.R'), str(path), str(output)], directory, env)
            value = json.loads(output.read_text())
        if mode != 'qualify':
            if not math.isfinite(value['elapsed_seconds']) or value['elapsed_seconds'] < 0:
                raise ValueError('Invalid reader clock')
            value.update(resources)
            value['calls'] = calls
            value.pop('rows', None)
            value.pop('columns', None)
        return value

    # R-to-R qualification precedes timing, including projected ordering/metadata.
    # Stata loads the identical DTA and checks dimensions; cross-language semantic
    # conformance is a separate gate, not an equivalence of signature algorithms.
    qualifications = []
    for case in selected:
        expected = None
        warnings = {}
        for method in methods[:-1]:
            value = run(case, method, 'qualify')
            method_warnings = value.pop('warnings')
            variant, reader = method.split('-')
            if variant == 'baseline':
                warnings[reader] = method_warnings
            elif method_warnings != warnings[reader]:
                raise ValueError('Reader warnings differ: ' + case['id'] + '/' + method)
            if (value['rows'], value['columns']) != (case['rows'], case['columns']):
                raise ValueError('Qualified dimensions differ from manifest: ' + case['id'])
            if expected is not None and value != expected:
                raise ValueError('Semantic qualification failed: ' + case['id'] + '/' + method)
            expected = value
        print('QUALIFIED ' + case['id'], flush=True)
        qualifications.append(dict(case=case['id'], **expected, warnings=warnings))
    (args.output / 'qualification.json').write_text(json.dumps(qualifications, indent=2) + '\n')

    def validate_final():
        if {p: sha(p) for p in paths} != inputs or sha(args.cases) != binding['manifest_sha256']:
            raise ValueError('Inputs or manifest changed during measurement')
        if {p.name: sha(p) for p in (HERE / 'worker.R', Path(__file__))} != binding['workers']:
            raise ValueError('Workers changed during measurement')
        if sha(args.stata) != binding['stata_sha256'] or sha(rscript) != binding['Rscript_sha256']:
            raise ValueError('Executables changed during measurement')
        for v in variants:
            if installed_binding(getattr(args, v + '_library'), getattr(args, v + '_build')) != bindings[v]:
                raise ValueError('Installation changed during measurement')

    if args.qualify_only:
        validate_final()
        print('SEMANTIC QUALIFICATION COMPLETE; no timing gate attempted', flush=True)
        return 0
    observations = []
    for cohort in range(1, args.cohorts + 1):
        cohort_cases = selected if cohort % 2 else list(reversed(selected))
        for case in cohort_cases:
            for mode in modes:
                schedule = orders(methods, args.repetitions)
                if cohort % 2 == 0:
                    schedule.reverse()
                for repetition, order in enumerate(schedule, 1):
                    for position, method in enumerate(order, 1):
                        value = run(case, method, mode)
                        observations.append(dict(case=case['id'], selection_mode=case['selection_mode'],
                            mode=mode, cohort=cohort, repetition=repetition, position=position,
                            method=method, **value))
                        write_csv(args.output / 'observations.csv', observations)
                print(f'MEASURED {cohort}/{case["id"]}/{mode}', flush=True)
    validate_final()
    summary = summaries(observations, eligible)
    write_csv(args.output / 'summary.csv', summary)
    passed = eligible and all(r['parity'] for r in summary if r['method'].startswith('candidate-'))
    (args.output / 'gate.json').write_text(json.dumps(dict(timing_parity=passed,
        eligible=eligible, note='Memory, downstream, corpus and conformance gates are separate.'), indent=2) + '\n')
    print('TIMING PARITY: ' + ('PASS' if passed else 'NOT MET'), flush=True)
    return 0 if passed or args.screen else 1


if __name__ == '__main__':
    sys.exit(main())
