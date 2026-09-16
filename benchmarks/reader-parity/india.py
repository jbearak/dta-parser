#!/usr/bin/env python3
"""Ten fresh reads each with dtatools, haven and Stata, including process resources."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

from run import HERE, absolute_path, child, installed_binding, sha, stata_program, write_csv


METHODS = ('read_dta', 'read_arrow', 'haven', 'stata')


def round_orders():
    # Ten rounds cannot balance four positions exactly. Pair every rotation
    # with its reverse: each pair of methods precedes each other five times,
    # and each method occupies every position either twice or three times.
    result = []
    for shift in range(5):
        offset = shift % len(METHODS)
        forward = METHODS[offset:] + METHODS[:offset]
        result.extend((forward, tuple(reversed(forward))))
    return result


def summarize(observations):
    result = []
    for method in METHODS:
        rows = [r for r in observations if r['method'] == method]
        elapsed = [r['elapsed_seconds'] for r in rows]
        result.append(dict(method=method, observations=len(rows),
            median_seconds=statistics.median(elapsed), min_seconds=min(elapsed),
            max_seconds=max(elapsed),
            median_process_cpu_seconds=statistics.median(r['process_cpu_seconds'] for r in rows),
            median_peak_rss_bytes=statistics.median(r['peak_rss_bytes'] for r in rows)))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('cases', 'library', 'build', 'output'):
        parser.add_argument('--' + name, type=absolute_path, required=True)
    parser.add_argument('--case', default='india-all')
    parser.add_argument('--smoke', action='store_true', help='One validation round on a small fixture; not publishable timings')
    parser.add_argument('--stata', type=absolute_path,
        default=Path('/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp'))
    parser.add_argument('--experiment', action='append', default=[])
    args = parser.parse_args()
    matches = [c for c in json.loads(args.cases.read_text()) if c['id'] == args.case]
    if len(matches) != 1 or matches[0]['selection_mode'] != 'all':
        raise ValueError('Select exactly one full-read case')
    case = matches[0]
    case = dict(case, **{kind: str(absolute_path(case[kind])) for kind in ('dta', 'arrow')})
    experiments = dict(item.split('=', 1) for item in args.experiment)
    if any(not key.startswith('DTATOOLS_EXPERIMENT_') for key in experiments):
        raise ValueError('Only private experimental controls are accepted')
    if 'DTATOOLS_EXPERIMENT_TRACE' in experiments:
        raise ValueError('Tracing must remain disabled during measurements')
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_'))}
    args.output.mkdir(parents=True, exist_ok=False)
    rscript = Path(shutil.which('Rscript')).resolve()
    runtime_code = '''.libPaths(c(commandArgs(TRUE)[1], .libPaths()));
      packages <- c("dtatools", "haven", "readr", "vctrs", "rlang", "tibble", "tidyselect", "jsonlite");
      cat(jsonlite::toJSON(list(R=R.version.string, platform=R.version$platform,
        packages=setNames(lapply(packages, function(x) as.character(packageVersion(x))), packages),
        haven_path=find.package("haven")), auto_unbox=TRUE))'''
    schedule = round_orders()[:1] if args.smoke else round_orders()
    total = len(schedule) * len(METHODS)

    def binding():
        # Hashing both complete files also warms the filesystem cache before
        # timing. No conversion or signature traversal runs in timed children.
        runtime = json.loads(subprocess.check_output([str(rscript), '--vanilla', '-e',
            runtime_code, str(args.library)], env=environment, text=True))
        haven = Path(runtime.pop('haven_path')).resolve()
        return dict(build=installed_binding(args.library, args.build),
            inputs={kind: dict(sha256=sha(case[kind]), bytes=Path(case[kind]).stat().st_size)
                    for kind in ('dta', 'arrow')},
            workers={p.name: sha(p) for p in (Path(__file__), HERE / 'india.R', HERE / 'run.py')},
            haven_installed={str(p.relative_to(haven)): sha(p)
                             for p in sorted(haven.rglob('*')) if p.is_file()},
            haven_path=str(haven),
            Rscript_sha256=sha(rscript), stata_sha256=sha(args.stata), runtime=runtime,
            host=platform.platform(), cpu_count=os.cpu_count(), experiments=experiments,
            dimensions=dict(rows=case['rows'], columns=case['columns']),
            threads='dtatools adaptive default; Stata settings recorded per observation',
            thread_environment={k: environment[k] for k in ('OMP_NUM_THREADS',
                'RAYON_NUM_THREADS', 'R_PARALLEL_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
                'VECLIB_MAXIMUM_THREADS') if k in environment},
            protocol=dict(rounds=len(schedule), smoke=args.smoke, calls_per_process=1, cache='warm filesystem',
                orders=schedule, arrow_verification=True,
                read_wall='read call, including first reader initialization, excluding process startup',
                process_cpu='wait4 user plus system CPU for the whole fresh process',
                peak_rss='wait4 maximum resident bytes for the whole fresh process',
                qualification='dimensions checked each read; canonical DTA/Arrow signatures checked separately'))

    initial = binding()
    (args.output / 'binding.json').write_text(json.dumps(initial, indent=2) + '\n')
    observations = []
    configurations = []
    for iteration, order in enumerate(schedule, 1):
        for position, method in enumerate(order, 1):
            directory = args.output / f'{iteration:02d}-{method}'
            directory.mkdir()
            output = directory / 'result.json'
            env = environment.copy()
            print(f'START round {iteration}/{len(schedule)}, {method}, position {position}/4', flush=True)
            if method == 'stata':
                script = directory / 'read.do'
                script.write_text(stata_program(case, 'fresh', 1, output))
                resources = child([str(args.stata), '-b', 'do', str(script)], directory, env)
                value = dict(elapsed_seconds=float(output.read_text()), read_cpu_seconds=None,
                    rows=case['rows'], columns=case['columns'])
                configuration = [line.strip() for p in directory.glob('*.log')
                    for line in p.read_text().splitlines() if any(f'c({key})' in line
                    for key in ('processors', 'processors_lic', 'stata_version', 'edition', 'MP'))]
                if not configuration:
                    raise ValueError('Missing Stata runtime configuration')
                configurations.append(configuration)
                if configuration != configurations[0]:
                    raise ValueError('Stata configuration changed between observations')
            else:
                if method != 'haven':
                    env.update(experiments)
                job = dict(library=str(args.library), method=method, haven_path=initial['haven_path'],
                    path=case['arrow' if method == 'read_arrow' else 'dta'],
                    rows=case['rows'], columns=case['columns'])
                job_file = directory / 'job.json'
                job_file.write_text(json.dumps(job))
                resources = child([str(rscript), '--vanilla', str(HERE / 'india.R'),
                    str(job_file), str(output)], directory, env)
                value = json.loads(output.read_text())
            row = dict(iteration=iteration, position=position, method=method, **value, **resources)
            if (not math.isfinite(row['elapsed_seconds']) or row['elapsed_seconds'] < 0
                    or (not args.smoke and row['elapsed_seconds'] == 0)
                    or any(not math.isfinite(row[key]) or row[key] <= 0 for key in
                           ('process_cpu_seconds', 'peak_rss_bytes'))):
                raise ValueError('Invalid timing or resource measurement')
            if (row['rows'], row['columns']) != (case['rows'], case['columns']):
                raise ValueError('Read dimensions differ')
            observations.append(row)
            temporary = args.output / 'observations.tmp'
            write_csv(temporary, observations)
            temporary.replace(args.output / 'observations.csv')
            print(f'DONE {len(observations)}/{total}: {method} {row["elapsed_seconds"]:.3f}s, '
                  f'{row["process_cpu_seconds"]:.3f}s process CPU, '
                  f'{row["peak_rss_bytes"] / 1e9:.3f} GB peak RSS', flush=True)
    if binding() != initial:
        raise ValueError('Source, installation, workers or inputs changed during measurement')
    write_csv(args.output / 'summary.csv', summarize(observations))
    (args.output / 'stata-configuration.json').write_text(json.dumps(configurations[0], indent=2) + '\n')
    (args.output / 'COMPLETE').write_text(f'{total} successful reads; smoke={args.smoke}; final bindings matched.\n')
    print(f'COMPLETE: {len(schedule)} reads per method; smoke={args.smoke}; final bindings matched.', flush=True)


if __name__ == '__main__':
    main()
