#!/usr/bin/env python3
"""Preloaded compact-operation benchmark; run only in an exclusive window."""
import argparse, csv, fnmatch, importlib.util, json, math, os
from pathlib import Path
import platform, random, shutil, statistics, subprocess, sys, time
ROOT = Path(__file__).resolve().parent
REPO = Path(os.environ.get('DTATOOLS_BENCH_REPO', '<repository>'))
HARNESS = REPO / 'benchmarks/r-file-readers'
BUILDS = {'current': Path(os.environ.get('DTATOOLS_CURRENT_BUILD', '<scalar-work>/candidate-combined')),
          'kernel': Path(os.environ.get('DTATOOLS_KERNEL_BUILD', str(ROOT / 'candidate-kernel-final')))}
PROBE = Path(os.environ.get('DTATOOLS_PROBE_DIR', '<scalar-work>'))
METRICS = ('cpu', 'wall', 'user', 'system', 'cpu_ns_per_value', 'wall_ns_per_value')
def require(value, message):
    if not value: raise RuntimeError(message)
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result
def write_json(path, value): path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def write_csv(path, rows):
    if not rows: return
    with path.open('w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
def cases():
    result = []
    for fmt in ('dta', 'arrow'):
        for kind in ('byte', 'int', 'long', 'float'):
            for op in ('is_na', 'is_missing', 'sum', 'min', 'max'):
                result.append(dict(id=f'{fmt}-{kind}-{op}', format=fmt, kind=kind, operation=op,
                    group='core' if op in ('is_na', 'is_missing') else 'reductions'))
        result.append(dict(id=f'{fmt}-mixed-multi4', format=fmt, kind='mixed', operation='multi4', group='multi'))
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--variants', default='current,kernel')
    p.add_argument('--cases', default='core', help='core, reductions, multi, all, or comma-separated globs')
    p.add_argument('--rounds', type=int, default=6); p.add_argument('--reps', type=int, default=64)
    p.add_argument('--mode', choices=('diagnostic', 'confirmation'), default='confirmation')
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--fixtures', type=Path, default=Path('<reader-work>/fixtures'))
    p.add_argument('--parity-gate', type=float, help='Exit 42 if any compact/plain CPU median ratio exceeds threshold')
    p.add_argument('--list-cases', action='store_true')
    args = p.parse_args()
    available = cases()
    if args.list_cases:
        print('\n'.join(c['id'] + ' [' + c['group'] + ']' for c in available)); return
    selected = [c for c in available if any(x == 'all' or x == c['group'] or fnmatch.fnmatchcase(c['id'], x)
                for x in args.cases.split(','))]
    variants = args.variants.split(',')
    require(selected and len(set(variants)) == len(variants) and all(v in BUILDS for v in variants), 'Invalid cases/variants')
    require(args.rounds > 0 and args.reps > 0, 'Invalid repetitions')
    cleared = sorted(k for k in os.environ if k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_', 'DIAGNOSTIC_ARROW_')))
    for key in cleared: del os.environ[key]
    bench = module('compact_reader_helpers', HARNESS / 'run.py')
    recorder = module('compact_build_recorder', HARNESS / 'record-builds.py')
    rscript = str(Path(shutil.which('Rscript')).resolve())
    out = args.work.resolve(); out.mkdir(parents=True, exist_ok=False)
    jobs = out / 'private-jobs'; jobs.mkdir()
    libraries = {v: BUILDS[v] / 'library' for v in variants}
    fixture_files = {ext: args.fixtures.resolve() / ('compact.' + ext) for ext in ('dta', 'arrow', 'rds')}
    files = {'controller': Path(__file__), 'worker': ROOT / 'throughput-worker.R',
        'probe_source': PROBE / 'scalar-access-probe.c', 'probe_dll': PROBE / 'scalar_access_probe.so',
        'probe_build_receipt': PROBE / 'scalar-probe-build.json', 'probe_check_receipt': PROBE / 'scalar-probe-check.json',
        'helpers': HARNESS / 'run.py', 'recorder': HARNESS / 'record-builds.py', 'runtime': HARNESS / 'runtime.R'}
    probe_receipt = json.loads(files['probe_build_receipt'].read_text())
    require(probe_receipt['returncode'] == 0 and json.loads(files['probe_check_receipt'].read_text())['returncode'] == 0,
            'Probe build/check failed')
    for key in ('probe_source', 'probe_dll'):
        require(bench.sha(files[key]) == probe_receipt['files'][str(files[key])], 'Probe source/binary changed')
    def bindings():
        proofs = {v: recorder.verified_receipt(BUILDS[v], 'candidate') for v in variants}
        return dict(builds={v: dict(receipt=p[0], receipt_sha256=p[2]) for v, p in proofs.items()},
            installed={v: bench.inventory(libraries[v]) for v in variants},
            inputs={k: dict(path=str(p), bytes=p.stat().st_size, sha256=bench.sha(p)) for k,p in fixture_files.items()},
            files={k: dict(path=str(p), sha256=bench.sha(p)) for k,p in files.items()},
            runtime={v: bench.runtime(rscript, libraries[v]) for v in variants},
            rscript=dict(path=rscript, sha256=bench.sha(rscript)),
            host=dict(platform=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count()),
            thread_environment={k: os.environ.get(k) for k in ('OMP_NUM_THREADS','OMP_THREAD_LIMIT','OPENBLAS_NUM_THREADS',
                'ARROW_NUM_THREADS','VECLIB_MAXIMUM_THREADS','MKL_NUM_THREADS')})
    before = bindings(); write_json(out / 'provenance-before.json', before)
    for variant in variants:
        require(before['installed'][variant] == before['builds'][variant]['receipt']['installed_inventory'], 'Inventory mismatch')
        (out / (variant + '.patch')).write_bytes((BUILDS[variant] / 'source.patch').read_bytes())
    write_json(out / 'protocol.json', dict(variants=variants, cases=selected, rounds=args.rounds, reps=args.reps, mode=args.mode,
        build_boundary='both builds use verified candidate receipts; current is previously accepted scalar optimization',
        interval='preloaded operation repetitions with last output retained; explicit GC, input reads, reference traversal and exact pre/post qualification outside; automatic GC and output allocation inside',
        order='case rotations and reversed adjacent rounds; alternating compact/plain within each worker; rotating and reversing build order',
        process_boundary='one process per build/round for diagnostic, one per build/case/round for confirmation',
        controls='is_na and is_missing on classed compact values versus the same public function on ordinary doubles; reductions on classed compact values include public result construction; only qualification strips result metadata outside the timer',
        qualification='complete output identity plus full generic native checksum/missing counts and selected exact values/tags; reductions check native result exactly against doubles, then public result under existing Stata storage policy; compact inputs remain lazy',
        parity_gate=args.parity_gate, cleared_environment=cleared, command=sys.argv))
    records = []; job_records = []
    for round_no in range(1, args.rounds+1):
        shift = ((round_no-1)//2) % len(selected)
        ordered = selected[shift:] + selected[:shift]
        if round_no % 2 == 0: ordered = list(reversed(ordered))
        groups = [ordered] if args.mode == 'diagnostic' else [[case] for case in ordered]
        settings = []
        for i, group in enumerate(groups):
            shift_v = ((round_no-1)//2 + i) % len(variants)
            ordered_v = variants[shift_v:] + variants[:shift_v]
            if round_no % 2 == 0: ordered_v = list(reversed(ordered_v))
            settings.extend((group, v) for v in ordered_v)
        for position, (group, variant) in enumerate(settings, 1):
            key = f'{round_no:02}-{position:02}-{variant}'
            log = jobs / (key + '.log'); result = jobs / (key + '.csv')
            command = [rscript, '--vanilla', str(ROOT / 'throughput-worker.R'), str(libraries[variant]),
                str(args.fixtures.resolve()), ','.join(c['id'] for c in group), str(round_no), str(args.reps), str(result), str(files['probe_dll'])]
            started = time.monotonic()
            with log.open('w') as stream:
                child = subprocess.Popen(command, env=bench.environment(libraries[variant]), stdout=stream, stderr=subprocess.STDOUT)
                try:
                    _, status, usage = os.wait4(child.pid, 0); elapsed = time.monotonic()-started
                    child.returncode = os.waitstatus_to_exitcode(status)
                except BaseException: child.kill(); child.wait(); raise
            require(child.returncode == 0, 'Worker failed: ' + key + '; see ' + str(log))
            rows = list(csv.DictReader(result.open()))
            require(len(rows) == 2 * len(group), 'Incomplete worker rows')
            require({(r['case'],r['representation']) for r in rows} == {(c['id'],rep) for c in group for rep in ('compact','plain')}, 'Unexpected worker rows')
            for row in rows:
                for name in ('rows','columns','round','reps'): row[name] = int(row[name])
                for name in ('user','system','cpu','wall'): row[name] = float(row[name])
                require(all(math.isfinite(row[k]) and row[k] >= 0 for k in ('user','system','cpu','wall')), 'Invalid clocks')
                require(row['round'] == round_no and row['reps'] == args.reps and row['rows'] == 1000000, 'Unexpected shape')
                require(all(row[k] == 'TRUE' for k in ('exact','lazy_before','lazy_after')), 'Qualification failure')
                row.update(variant=variant, position=position, job=key,
                    cpu_ns_per_value=row['cpu']*1e9/row['reps']/row['rows']/row['columns'],
                    wall_ns_per_value=row['wall']*1e9/row['reps']/row['rows']/row['columns'])
                records.append(row)
                with (out/'raw.jsonl').open('a') as stream: stream.write(json.dumps(row, sort_keys=True)+'\n')
            job_records.append(dict(job=key, variant=variant, round=round_no, cases=[c['id'] for c in group],
                process_wall=elapsed, process_cpu=usage.ru_utime+usage.ru_stime, process_user=usage.ru_utime,
                process_system=usage.ru_stime, maxrss_bytes=usage.ru_maxrss if sys.platform=='darwin' else usage.ru_maxrss*1024,
                command=command, log_sha256=bench.sha(log), result_sha256=bench.sha(result)))
        print('Completed throughput round', round_no, flush=True)
    summary=[]; paired=[]; parity=[]
    rng=random.Random(20261002)
    draws=[rng.choices(range(args.rounds), k=args.rounds) for _ in range(10000)]
    def comparison(kind, case, metric, old, new, **details):
        ratios=[new[i][metric]/old[i][metric] for i in range(1,args.rounds+1) if old[i][metric]>0 and new[i][metric]>0]
        boots=sorted(statistics.median(ratios[j] for j in draw) for draw in draws) if len(ratios)==args.rounds else []
        return dict(comparison=kind, case=case, metric=metric, **details, pairs=args.rounds, resolved_pairs=len(ratios),
            baseline_median=statistics.median(r[metric] for r in old.values()), candidate_median=statistics.median(r[metric] for r in new.values()),
            paired_ratio=statistics.median(ratios) if boots else None, lower95=boots[249] if boots else None, upper95=boots[9749] if boots else None)
    for case in selected:
        groups={(v,rep): {r['round']:r for r in records if r['case']==case['id'] and r['variant']==v and r['representation']==rep}
                for v in variants for rep in ('compact','plain')}
        for (variant,rep), rows in groups.items():
            require(set(rows)==set(range(1,args.rounds+1)), 'Missing rounds')
            summary.append(dict(case=case['id'],variant=variant,representation=rep,observations=len(rows),reps=args.reps,
                **{metric+'_median':statistics.median(r[metric] for r in rows.values()) for metric in METRICS}))
        for variant in variants:
            for metric in METRICS:
                row=comparison('compact/plain',case['id'],metric,groups[(variant,'plain')],groups[(variant,'compact')],variant=variant)
                parity.append(row)
        for variant in variants[1:]:
            for rep in ('compact','plain'):
                for metric in METRICS:
                    paired.append(comparison('build/build',case['id'],metric,groups[(variants[0],rep)],groups[(variant,rep)],
                        reference=variants[0],variant=variant,representation=rep))
    write_csv(out/'raw.csv',records); write_csv(out/'summary.csv',summary); write_csv(out/'paired-summary.csv',paired); write_csv(out/'parity.csv',parity)
    write_json(out/'jobs.json',job_records)
    after=bindings(); require(before==after,'Pre/post provenance changed'); write_json(out/'provenance-after.json',after)
    failed=[dict(case=r['case'],variant=r['variant'],ratio=r['paired_ratio']) for r in parity if r['metric']=='cpu' and
        (r['paired_ratio'] is None or (args.parity_gate and r['paired_ratio']>args.parity_gate))] if args.parity_gate else []
    write_json(out/'completion.json',dict(observations=len(records),processes=len(job_records),bindings_matched=True,exact_validation=True,
        parity_gate=args.parity_gate,parity_failures=failed))
    print('Completed',len(records),'observations in',len(job_records),'fresh processes; bindings matched',flush=True)
    for r in parity:
        if r['metric']=='cpu': print(r['variant'],r['case'],'compact/plain CPU ratio',r['paired_ratio'])
    if failed:
        print('RED: parity target exceeded for',len(failed),'cases',flush=True); sys.exit(42)
if __name__=='__main__': main()
