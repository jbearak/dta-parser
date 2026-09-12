#!/usr/bin/env python3
"""Run isolated, sequential reader experiments from an explicit JSON plan."""
import csv
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import sys
import time

plan_path, output_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text())
output_path.mkdir(parents=True, exist_ok=False)
worker = Path(__file__).with_name('worker.R').resolve()
rscript = shutil.which('Rscript')
assert rscript

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def bindings():
    paths = {worker, Path(rscript), Path(__file__).resolve(), plan_path.resolve()}
    for case in plan['cases']:
        paths.add(Path(case['path']))
    for variant in plan['variants']:
        paths.update(p for p in (Path(variant['library']) / 'dtatools').rglob('*') if p.is_file())
    return {str(p): dict(bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(paths)}

initial = bindings()
(output_path / 'binding.json').write_text(json.dumps(initial, indent=2) + '\n')
(output_path / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
rows = []
rng = random.Random(plan.get('seed', 20260912))
for iteration in range(1, plan['repetitions'] + 1):
    jobs = [(case, variant) for case in plan['cases'] for variant in plan['variants']]
    if plan.get('order') == 'alternate':
        if iteration % 2 == 0:
            jobs.reverse()
    else:
        rng.shuffle(jobs)
    for position, (case, variant) in enumerate(jobs, 1):
        key = f"{iteration:02d}-{case['name']}-{variant['name']}"
        env = {k: v for k, v in os.environ.items() if not k.startswith('DTA_READ_PERF_')}
        env.update(R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null',
                   DTATOOLS_BENCH_LIB=variant['library'])
        env.update(variant.get('env', {}))
        command = [rscript, '--vanilla', str(worker), case['path'],
                   variant.get('mode', 'dta'), str(variant.get('threads', 0)),
                   str(plan.get('reads_per_process', 1))]
        started = time.time()
        log = output_path / f'{key}.log'
        with log.open('wb') as stream:
            actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                       (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
            pid = os.posix_spawn(command[0], command, env, file_actions=actions)
            _, status, usage = os.wait4(pid, 0)
        job = dict(key=key, command=command, variant=variant, started=started,
                   wall_seconds=time.time() - started, exit_code=os.waitstatus_to_exitcode(status),
                   peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == 'darwin' else 1024))
        with (output_path / 'jobs.jsonl').open('a') as f:
            f.write(json.dumps(job) + '\n')
        assert job['exit_code'] == 0, f'failed: {key}'
        markers = [line.split('\t')[1:] for line in log.read_text().splitlines()
                   if line.startswith('READ\t')]
        assert len(markers) == plan.get('reads_per_process', 1), key
        for read_number, elapsed, nrows, ncols in markers:
            assert (int(nrows), int(ncols)) == (case['rows'], case['columns']), key
            row = dict(iteration=iteration, position=position, case=case['name'],
                       variant=variant['name'], read_number=int(read_number),
                       elapsed_seconds=float(elapsed), peak_rss_bytes=job['peak_rss_bytes'],
                       rows=int(nrows), columns=int(ncols))
            rows.append(row)
            with (output_path / 'observations.csv').open('w') as f:
                writer = csv.DictWriter(f, fieldnames=list(row), lineterminator='\n')
                writer.writeheader()
                writer.writerows(rows)
        print(f"{key}: {[float(m[1]) for m in markers]} s; {job['peak_rss_bytes']/1e9:.3f} GB", flush=True)
assert bindings() == initial, 'input or installation changed'
summary = []
for case in plan['cases']:
    for variant in plan['variants']:
        selected = [r for r in rows if r['case'] == case['name'] and r['variant'] == variant['name']]
        times = [r['elapsed_seconds'] for r in selected]
        rss = [r['peak_rss_bytes'] / 1e9 for r in selected]
        summary.append(dict(case=case['name'], variant=variant['name'], count=len(times),
                            median_seconds=statistics.median(times),
                            min_seconds=min(times), max_seconds=max(times),
                            median_peak_rss_gb=statistics.median(rss)))
with (output_path / 'summary.csv').open('w') as f:
    writer = csv.DictWriter(f, fieldnames=list(summary[0]), lineterminator='\n')
    writer.writeheader()
    writer.writerows(summary)
print(json.dumps(summary, indent=2), flush=True)
