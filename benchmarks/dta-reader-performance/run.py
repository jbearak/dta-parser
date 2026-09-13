#!/usr/bin/env python3
"""Qualify all variants against stock, then run sequential reader experiments."""
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import shlex
import shutil
import signal
import statistics
import subprocess
import sys
import time


def sha(path):
    """Hash a file without loading the whole input into memory."""
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    """Write an indented JSON record with a trailing newline."""
    path.write_text(json.dumps(value, indent=2) + '\n')


def child_environment(variant, qualify):
    """Apply explicit variant flags and reserve qualification controls for the runner."""
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('DTA_READ_PERF_', 'DTATOOLS_EXPERIMENT_'))}
    env.update(variant.get('env', {}))
    # These controls belong to the runner, even if the caller sets them.
    env.update(R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null',
               DTATOOLS_BENCH_LIB=str(Path(variant['library']).resolve()),
               DTA_READ_PERF_SIGNATURE='1' if qualify else '0')
    return env


def bindings(plan, plan_path, worker, rscript):
    """Bind the exact inputs, executable, scripts, plan and installed package files."""
    paths = {worker, Path(rscript), Path(__file__).resolve(), plan_path.resolve()}
    paths.update(Path(case['path']).resolve() for case in plan['cases'])
    for variant in plan['variants']:
        library = Path(variant['library']).resolve() / 'dtatools'
        if not (library / 'DESCRIPTION').is_file():
            raise ValueError(f'missing dtatools installation: {library}')
        paths.update(path for path in library.rglob('*') if path.is_file())
    return {str(path): dict(bytes=path.stat().st_size, sha256=sha(path))
            for path in sorted(paths)}


def validate_plan(plan):
    """Reject ambiguous job names and invalid reader settings before creating output."""
    for field in ('cases', 'variants'):
        entries = plan.get(field, [])
        names = [entry['name'] for entry in entries]
        if (not names or len(set(names)) != len(names)
                or any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name)
                       for name in names)):
            raise ValueError(f'{field} require unique filename-safe names')
    keys = [f"{case['name']}-{variant['name']}"
            for case in plan['cases'] for variant in plan['variants']]
    if len(set(keys)) != len(keys):
        raise ValueError('case and variant names produce duplicate job keys')
    if 'stock' not in [variant['name'] for variant in plan['variants']]:
        raise ValueError('a stock variant is required for signature qualification')
    for field in ('repetitions', 'reads_per_process'):
        value = plan.get(field, 1)
        if type(value) is not int or value < 1:
            raise ValueError(f'{field} must be a positive integer')
    for case in plan['cases']:
        if any(type(case[field]) is not int or case[field] < 0
               for field in ('rows', 'columns')):
            raise ValueError('expected rows and columns must be nonnegative integers')
    for variant in plan['variants']:
        threads = variant.get('threads', 0)
        if type(threads) is not int or not 0 <= threads <= 2**31 - 1:
            raise ValueError('threads must be a nonnegative R integer')
        if variant.get('mode', 'dta') not in ('dta', 'arrow', 'metadata'):
            raise ValueError('unknown reader mode')
        if any(not isinstance(key, str) or not isinstance(value, str)
               for key, value in variant.get('env', {}).items()):
            raise ValueError('variant environment values must be strings')
    if plan.get('order', 'shuffle') not in ('alternate', 'shuffle'):
        raise ValueError('order must be alternate or shuffle')


def read_markers(log, case, expected):
    """Check read counts, elapsed values and dimensions in a child log."""
    markers = [line.split('\t')[1:] for line in log.read_text().splitlines()
               if line.startswith('READ\t')]
    if len(markers) != expected:
        raise RuntimeError(f'{log.name}: expected {expected} READ markers')
    for index, marker in enumerate(markers, 1):
        if len(marker) != 4:
            raise RuntimeError(f'{log.name}: malformed READ marker')
        number, elapsed, rows, columns = marker
        if (int(number) != index or not math.isfinite(float(elapsed))
                or float(elapsed) < 0
                or (int(rows), int(columns)) != (case['rows'], case['columns'])):
            raise RuntimeError(f'{log.name}: invalid READ result or dimensions')
    return markers


def execute(output, worker, rscript, case, variant, key, qualify, reads):
    """Run one child, retain its exit/resource record and reap it on interruption."""
    env = child_environment(variant, qualify)
    command = [rscript, '--vanilla', str(worker), str(Path(case['path']).resolve()),
               variant.get('mode', 'dta'), str(variant.get('threads', 0)), str(reads)]
    job = dict(key=key, phase='qualification' if qualify else 'timing',
               case=case['name'], variant=variant, command=command,
               environment={key: value for key, value in env.items()
                            if key.startswith(('DTA_READ_PERF_', 'DTATOOLS_EXPERIMENT_'))
                            or key in ('R_ENVIRON_USER', 'R_PROFILE_USER', 'DTATOOLS_BENCH_LIB')},
               started=time.time(), exit_code=None)
    started = time.monotonic()
    log = output / f'{key}.log'
    try:
        with log.open('wb') as stream:
            actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                       (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
            pid = os.posix_spawn(command[0], command, env, file_actions=actions)
            try:
                _, status, usage = os.wait4(pid, 0)
            except BaseException:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                os.wait4(pid, 0)
                raise
        job.update(exit_code=os.waitstatus_to_exitcode(status),
                   peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == 'darwin' else 1024))
    finally:
        job['wall_seconds'] = time.monotonic() - started
        with (output / 'jobs.jsonl').open('a') as stream:
            stream.write(json.dumps(job) + '\n')
    if job['exit_code'] != 0:
        raise RuntimeError(f'failed: {key}; see {log}')
    return job, log


def tool_version(command):
    """Capture an available host tool version without requiring that tool."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=15)
        return dict(command=command, exit_code=result.returncode,
                    output=(result.stdout + result.stderr).strip())
    except (OSError, subprocess.TimeoutExpired) as error:
        return dict(command=command, unavailable=str(error))


def publish_status(output, metadata):
    """Publish the current run status and a readable baseline record."""
    write_json(output / 'run-metadata.json', metadata)
    versions = '\n'.join(
        f"- {name}: {record.get('output', record.get('unavailable', 'not recorded'))}"
        for name, record in metadata['host_tools'].items())
    fixtures = '\n'.join(f"| {case['name']} | {case['rows']} | {case['columns']} | "
                         f"{case['input']['bytes']} | `{case['input']['sha256']}` |"
                         for case in metadata['fixtures'])
    (output / 'baseline.md').write_text(
        '# Reader experiment baseline\n\n'
        f"Status: **{metadata['status']}**. Control: `stock`.\n\n"
        f"Correctness: {metadata['correctness']}.\n\n"
        'All case/variant signatures must match stock in separate processes before '
        'any timed process starts. Qualification clocks and RSS are excluded from '
        'observations and summaries. Timed reads still check dimensions.\n\n'
        f"Command: `{shlex.join(metadata['command'])}`\n\n"
        f"Host: `{metadata['host']}`\n\n"
        'Host tool versions, which do not establish the build toolchain of an '
        'existing installation:\n\n' + versions + '\n\n'
        f"Rounds: {metadata['repetitions']}; reads per timed process: "
        f"{metadata['reads_per_process']}; ordering: {metadata['order']}; "
        f"seed: {metadata['seed']}.\n\n"
        '| Fixture | Rows | Columns | Input bytes | SHA-256 |\n'
        '| --- | ---: | ---: | ---: | --- |\n' + fixtures + '\n\n'
        'Exact child commands, flags, exit codes and process resource totals are in '
        '[jobs.jsonl](jobs.jsonl). [run-metadata.json](run-metadata.json) records '
        'correctness status and host tool versions; an installed compiler version '
        'does not prove which compiler built an existing R library. '
        '[binding.json](binding.json) binds input, installation, worker and plan bytes.\n')


def run(plan_path, output):
    """Qualify every case and variant against stock before collecting any timings."""
    plan = json.loads(plan_path.read_text())
    validate_plan(plan)
    worker = Path(__file__).with_name('worker.R').resolve()
    rscript = shutil.which('Rscript')
    if not rscript:
        raise RuntimeError('Rscript is unavailable')
    initial = bindings(plan, plan_path, worker, rscript)
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / 'binding.json', initial)
    write_json(output / 'plan.json', plan)
    metadata = dict(status='qualifying', command=[sys.executable, str(Path(__file__).resolve()),
                    str(plan_path.resolve()), str(output.resolve())],
                    host=dict(node=platform.node(), platform=platform.platform(),
                              machine=platform.machine(), cpus=os.cpu_count()),
                    host_tools=dict(R=tool_version([rscript, '--version']),
                                    rustc=tool_version(['rustc', '--version', '--verbose']),
                                    cc=tool_version(['cc', '--version'])),
                    repetitions=plan.get('repetitions', 1),
                    reads_per_process=plan.get('reads_per_process', 1),
                    order=plan.get('order', 'shuffle'), seed=plan.get('seed', 20260912),
                    fixtures=[dict(name=case['name'], rows=case['rows'], columns=case['columns'],
                                   input=initial[str(Path(case['path']).resolve())])
                              for case in plan['cases']],
                    correctness='pending', qualifications=[], binding_sha256=sha(output / 'binding.json'))
    publish_status(output, metadata)
    try:
        stock = next(variant for variant in plan['variants'] if variant['name'] == 'stock')
        variants = [stock] + [v for v in plan['variants'] if v is not stock]
        for case in plan['cases']:
            reference = None
            for variant in variants:
                key = f"qualify-{case['name']}-{variant['name']}"
                _, log = execute(output, worker, rscript, case, variant, key, True, 1)
                read_markers(log, case, 1)
                signatures = [line.split() for line in log.read_text().splitlines()
                              if line.startswith('SIGNATURE')]
                if (len(signatures) != 1 or len(signatures[0]) != 2
                        or not re.fullmatch(r'\d+:\d+:[0-9a-f]{16}', signatures[0][1])):
                    raise RuntimeError(f'{key}: missing or malformed signature')
                signature = signatures[0][1]
                if signature.split(':')[:2] != [str(case['rows']), str(case['columns'])]:
                    raise RuntimeError(f'{key}: signature dimensions mismatch')
                if reference is None:
                    reference = signature
                matched = signature == reference
                metadata['qualifications'].append(dict(case=case['name'], variant=variant['name'],
                    signature=signature, stock_signature=reference, matches_stock=matched,
                    log_sha256=sha(log)))
                publish_status(output, metadata)
                if not matched:
                    raise RuntimeError(f'{key}: signature differs from stock')
        if bindings(plan, plan_path, worker, rscript) != initial:
            raise RuntimeError('input, worker, plan or installation changed during qualification')
        metadata.update(status='timing', correctness='all signatures matched stock')
        publish_status(output, metadata)
        rows = []
        rng = random.Random(metadata['seed'])
        for iteration in range(1, metadata['repetitions'] + 1):
            jobs = [(case, variant) for case in plan['cases'] for variant in plan['variants']]
            if metadata['order'] == 'alternate':
                if iteration % 2 == 0:
                    jobs.reverse()
            else:
                rng.shuffle(jobs)
            for position, (case, variant) in enumerate(jobs, 1):
                key = f"{iteration:02d}-{case['name']}-{variant['name']}"
                job, log = execute(output, worker, rscript, case, variant, key, False,
                                   metadata['reads_per_process'])
                markers = read_markers(log, case, metadata['reads_per_process'])
                if any(line.startswith('SIGNATURE') for line in log.read_text().splitlines()):
                    raise RuntimeError(f'{key}: unexpected signature work in timed process')
                for number, elapsed, nrows, ncols in markers:
                    rows.append(dict(iteration=iteration, position=position, case=case['name'],
                        variant=variant['name'], read_number=int(number), elapsed_seconds=float(elapsed),
                        peak_rss_bytes=job['peak_rss_bytes'], rows=int(nrows), columns=int(ncols)))
                with (output / 'observations.csv').open('w') as stream:
                    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
                    writer.writeheader()
                    writer.writerows(rows)
                print(f'{key}: {[float(marker[1]) for marker in markers]} s', flush=True)
        final = bindings(plan, plan_path, worker, rscript)
        write_json(output / 'binding-after.json', final)
        if final != initial:
            raise RuntimeError('input, worker, plan or installation changed during timing')
        summary = []
        for case in plan['cases']:
            for variant in plan['variants']:
                selected = [row for row in rows if row['case'] == case['name']
                            and row['variant'] == variant['name']]
                times = [row['elapsed_seconds'] for row in selected]
                summary.append(dict(case=case['name'], variant=variant['name'], count=len(times),
                    median_seconds=statistics.median(times), min_seconds=min(times),
                    max_seconds=max(times), median_peak_rss_gb=statistics.median(
                        row['peak_rss_bytes'] / 1e9 for row in selected)))
        with (output / 'summary.csv').open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(summary[0]), lineterminator='\n')
            writer.writeheader()
            writer.writerows(summary)
        metadata.update(status='complete', observations=len(rows),
                        artifacts={name: dict(bytes=(output / name).stat().st_size,
                                              sha256=sha(output / name))
                                   for name in ('observations.csv', 'summary.csv', 'jobs.jsonl')})
    except BaseException as error:
        metadata.update(status='failed', error=f'{type(error).__name__}: {error}')
        publish_status(output, metadata)
        raise
    publish_status(output, metadata)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: run.py PLAN.json OUTPUT_DIRECTORY')
    run(*map(Path, sys.argv[1:]))
