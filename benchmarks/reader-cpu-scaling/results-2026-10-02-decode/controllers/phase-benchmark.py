#!/usr/bin/env python3
"""Private, fresh-process Arrow phase-cap screen. Run only in an exclusive window."""

import argparse
import csv
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(os.environ['DTATOOLS_DECODE_WORK'])
OLD = Path(os.environ['DTATOOLS_PREVIOUS_READER_WORK'])
REPO = Path(os.environ['DTATOOLS_REPO'])
HARNESS = REPO / 'benchmarks/r-file-readers'
PHASES = ((16, 16), (16, 4), (4, 16), (4, 4), (12, 8), (12, 12))
REFERENCES = ('diagnostic_16_16', 'stock_16')
METRICS = ('read_wall', 'read_cpu', 'read_user', 'read_system',
           'process_wall', 'process_cpu', 'process_user', 'process_system',
           'maxrss_bytes')
BOOTSTRAP_REPLICATES = 10000
BOOTSTRAP_SEED = 20261002


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    require(bool(rows), 'Refusing to write an empty result table')
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def round_orders(settings):
    # Each rotation is followed by its reverse: balanced pairwise precedence,
    # but seven settings over six rounds cannot have exact position balance.
    for pair, shift in enumerate((0, 2, 4), 1):
        order = settings[shift:] + settings[:shift]
        yield 2 * pair - 1, order
        yield 2 * pair, list(reversed(order))


def summaries(records, settings):
    result = []
    for setting in settings:
        rows = [row for row in records if row['setting'] == setting['id']]
        require(len(rows) == 6, 'Incomplete setting: ' + setting['id'])
        result.append(dict(setting=setting['id'], library=setting['library'],
            decode_cap=setting['decode_cap'], fill_cap=setting['fill_cap'],
            public_threads=16, observations=len(rows),
            **{metric + '_median': statistics.median(row[metric] for row in rows)
               for metric in METRICS},
            **{metric + '_min': min(row[metric] for row in rows) for metric in METRICS},
            **{metric + '_max': max(row[metric] for row in rows) for metric in METRICS}))
    return result


def paired_summaries(records, settings):
    rng = random.Random(BOOTSTRAP_SEED)
    # The same resampled round indices are used for every metric/comparison.
    draws = [rng.choices(range(6), k=6) for _ in range(BOOTSTRAP_REPLICATES)]
    result = []
    for reference in REFERENCES:
        old = {row['round']: row for row in records if row['setting'] == reference}
        require(set(old) == set(range(1, 7)), 'Incomplete reference rounds')
        for setting in settings:
            if setting['id'] == reference:
                continue
            new = {row['round']: row for row in records if row['setting'] == setting['id']}
            require(set(new) == set(old), 'Unmatched comparison rounds')
            for metric in METRICS:
                ratios = [new[i][metric] / old[i][metric] for i in range(1, 7)
                          if old[i][metric] > 0 and new[i][metric] > 0]
                boot = sorted(statistics.median(ratios[i] for i in sample)
                              for sample in draws) if len(ratios) == 6 else []
                result.append(dict(reference=reference, setting=setting['id'],
                    metric=metric, pairs=6, resolved_pairs=len(ratios),
                    reference_median=statistics.median(row[metric] for row in old.values()),
                    setting_median=statistics.median(row[metric] for row in new.values()),
                    paired_ratio=statistics.median(ratios) if boot else None,
                    lower95=boot[249] if boot else None,
                    upper95=boot[9749] if boot else None))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=ROOT / 'final-arrow-phases')
    args = parser.parse_args()
    require(sys.platform in ('darwin', 'linux'), 'Unsupported wait4 RSS units')
    # Do this before runtime inventory and again in each worker environment.
    cleared_inherited_names = sorted(key for key in os.environ
                                     if key.startswith('DIAGNOSTIC_ARROW_'))
    for key in cleared_inherited_names:
        del os.environ[key]
    spec = importlib.util.spec_from_file_location('reader_benchmark', HARNESS / 'run.py')
    bench = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bench)
    recorder_spec = importlib.util.spec_from_file_location('reader_build_records', HARNESS / 'record-builds.py')
    recorder = importlib.util.module_from_spec(recorder_spec)
    recorder_spec.loader.exec_module(recorder)
    output = args.work.resolve()
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    private = output / 'private-jobs'
    private.mkdir(mode=0o700)
    libraries = {'diagnostic': ROOT / 'candidate-arrow-phases/library',
                 'stock': OLD / 'candidate-final-v2/library'}
    build_work = {key: path.parent for key, path in libraries.items()}
    records_to_bind = {
        'diagnostic_receipt': ROOT / 'candidate-arrow-phases/build-receipt.json',
        'diagnostic_completion': ROOT / 'candidate-arrow-phases/diagnostic-completion.json',
        'diagnostic_patch': ROOT / 'arrow-phase-caps.patch',
        'stock_receipt': OLD / 'candidate-final-v2/build-receipt.json',
        'stock_bindings': OLD / 'bindings-final-v2/build-bindings.json',
        'fixture_controls': OLD / 'controls.json',
        'prior_input_bindings': OLD / 'final-large/provenance-before.json',
        'prior_thread_qualification': ROOT / 'final-sweep/qualification.json',
        'adapted_controller': ROOT / 'thread-sweep.py',
    }
    receipts = {key: json.loads(records_to_bind[key + '_receipt'].read_text())
                for key in libraries}
    expected = {key: receipt['installed_inventory'] for key, receipt in receipts.items()}
    require(all(receipt['exit_code'] == 0 and receipt['pre_post_source_equal']
                for receipt in receipts.values()), 'Unqualified build receipt')
    require(json.loads(records_to_bind['stock_bindings'].read_text())['libraries']['candidate']
            == expected['stock'], 'Stock receipt differs from earlier build bindings')
    fixture = next(item for item in json.loads(records_to_bind['fixture_controls'].read_text())['reads']
                   if item['id'] == 'india')
    known = json.loads(records_to_bind['prior_input_bindings'].read_text())['inputs']['india']['arrow']
    prior = json.loads(records_to_bind['prior_thread_qualification'].read_text())
    known_signatures = {row['datasig'] for row in prior}
    require(len(known_signatures) == 1 and bool(prior), 'Prior thread signatures disagree')
    expected_signature = known_signatures.pop()
    rscript_found = shutil.which('Rscript')
    require(rscript_found is not None, 'Rscript unavailable')
    rscript = str(Path(rscript_found).resolve())
    settings = [dict(id=f'diagnostic_{decode}_{fill}', library='diagnostic',
                     decode_cap=decode, fill_cap=fill) for decode, fill in PHASES]
    settings.append(dict(id='stock_16', library='stock', decode_cap=None, fill_cap=None))

    def bindings():
        # Both are candidate builds: stock is the previous final candidate,
        # not the unchanged Git baseline. Replay each recorded source patch.
        proof = {key: recorder.verified_receipt(path, 'candidate')
                 for key, path in build_work.items()}
        value = dict(
            libraries={key: item[0]['installed_inventory'] for key, item in proof.items()},
            builds={key: dict(receipt=item[0], receipt_sha256=item[2])
                    for key, item in proof.items()},
            input=dict(sha256=bench.sha(fixture['arrow']),
                       bytes=Path(fixture['arrow']).stat().st_size),
            runtimes={key: bench.runtime(rscript, path) for key, path in libraries.items()},
            rscript_sha256=bench.sha(rscript),
            workers={name: bench.sha(HARNESS / name)
                     for name in ('run.py', 'worker.R', 'common.R', 'runtime.R')},
            controller_sha256=bench.sha(Path(__file__)),
            records={key: bench.sha(path) for key, path in records_to_bind.items()},
            host=dict(platform=platform.platform(), machine=platform.machine(),
                      logical_cpus=os.cpu_count()),
            thread_environment={key: os.environ.get(key) for key in (
                'OMP_NUM_THREADS', 'OMP_THREAD_LIMIT', 'OPENBLAS_NUM_THREADS',
                'ARROW_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'MKL_NUM_THREADS',
                'RCPP_PARALLEL_NUM_THREADS', 'R_DATATABLE_NUM_THREADS')})
        require(value['libraries'] == expected, 'Installed library does not match its build receipt')
        require(value['input'] == known, 'Arrow input differs from prior bound fixture')
        return value

    before = bindings()
    write_json(output / 'provenance-before.json', before)
    write_json(output / 'build-bindings.json', dict(schema_version=1,
        binding_kind='two verified candidate builds with replayed source patches; stock role is previous final candidate v2',
        roles={'stock': 'previous final candidate v2', 'diagnostic': 'private Arrow phase caps'},
        libraries=before['libraries'], builds=before['builds']))
    for key, work in build_work.items():
        (output / (key + '.patch')).write_bytes((work / 'source.patch').read_bytes())

    def worker_environment(setting):
        env = {key: value for key, value in bench.environment(libraries[setting['library']]).items()
               if not key.startswith('DIAGNOSTIC_ARROW_')}
        if setting['decode_cap'] is not None:
            env['DIAGNOSTIC_ARROW_DECODE_THREADS'] = str(setting['decode_cap'])
            env['DIAGNOSTIC_ARROW_FILL_THREADS'] = str(setting['fill_cap'])
        return env

    def invoke(setting, mode, key):
        command = [rscript, '--vanilla', str(HARNESS / 'worker.R'), mode,
                   'dtatools_arrow_dibble', fixture['arrow'], '16',
                   str(fixture['rows']), str(fixture['columns']), '-']
        log = private / (key + '.log')
        started = time.monotonic()
        with log.open('w') as stream:
            child = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                     env=worker_environment(setting))
            try:
                _, status, usage = os.wait4(child.pid, 0)
                finished = time.monotonic()
                child.returncode = os.waitstatus_to_exitcode(status)
            except BaseException:
                child.kill()
                try:
                    _, status, _ = os.wait4(child.pid, 0)
                    child.returncode = os.waitstatus_to_exitcode(status)
                except ChildProcessError:
                    pass
                raise
        require(child.returncode == 0, 'Worker failed: ' + key)
        prefix = 'QUALIFIED\t' if mode.startswith('qualify') else 'MEASURE\t'
        fields = [line.split('\t') for line in log.read_text().splitlines()
                  if line.startswith(prefix)]
        require(len(fields) == 1, 'Unexpected worker records: ' + key)
        if mode.startswith('qualify'):
            result = bench.validate_qualification(fields[0], {
                'qualification': 'signature', 'consumption': 'omitted_read_only'})
            result['log_sha256'] = bench.sha(log)
            return result
        result = bench.validate_record(fields[0], fixture)
        result.update(read_user=float(fields[0][2]), read_system=float(fields[0][3]),
            process_user=usage.ru_utime, process_system=usage.ru_stime,
            process_cpu=usage.ru_utime + usage.ru_stime,
            process_wall=finished - started,
            maxrss_bytes=usage.ru_maxrss * (1 if sys.platform == 'darwin' else 1024),
            minor_page_faults=usage.ru_minflt, major_page_faults=usage.ru_majflt,
            voluntary_context_switches=usage.ru_nvcsw,
            involuntary_context_switches=usage.ru_nivcsw,
            log_sha256=bench.sha(log))
        require(all(math.isfinite(result[metric]) and result[metric] >= 0
                    for metric in METRICS), 'Invalid recorded process metric')
        return result

    protocol = dict(settings=settings, public_threads=16, rounds=6,
        observations_planned=42, cache='warm filesystem; no cold-cache claim',
        output='dibble', input='existing full India Arrow fixture', verification=True,
        dimensions=dict(rows=fixture['rows'], columns=fixture['columns']),
        effective_workers='caps only; actual worker counts not instrumented',
        order='rotations 0,2,4, each immediately followed by its reverse; balanced pairwise precedence, not exact positions',
        boundaries='read user/system/wall in the same R proc.time interval; pre-read full GC outside that interval; process metrics cover the entire fresh worker',
        qualification='one separate fresh process per configuration; complete datasig traversal, no timed qualification work',
        bootstrap=dict(unit='round-paired setting/reference ratios', statistic='median paired ratio',
                       rounds=6, replicates=BOOTSTRAP_REPLICATES, seed=BOOTSTRAP_SEED,
                       interval='empirical 2.5 and 97.5 percentiles; order statistics 250 and 9750',
                       references=list(REFERENCES), direction='below one favors setting'),
        filtering='no outlier removal; nonpositive metric pairs marked unresolved, not silently excluded from intervals',
        cleared_inherited_diagnostic_variable_names=cleared_inherited_names,
        exclusive_execution='controller does not prevent unrelated host work; caller supplies the exclusive window')
    write_json(output / 'protocol.json', protocol)
    qualification = []
    for setting in settings:
        actual = invoke(setting, 'qualify-signature-read', 'qualify-' + setting['id'])
        require(actual['signature'] == expected_signature,
                'Signature mismatch for ' + setting['id'])
        qualification.append(dict(setting=setting['id'], **actual))
        write_json(output / 'qualification.json', qualification)
    records = []
    for round_number, order in round_orders(settings):
        for position, setting in enumerate(order, 1):
            row = invoke(setting, 'read', f'{round_number:02}-{setting["id"]}')
            row.update(round=round_number, position=position, setting=setting['id'],
                       library=setting['library'], public_threads=16,
                       decode_cap=setting['decode_cap'], fill_cap=setting['fill_cap'])
            records.append(row)
            with (output / 'raw.jsonl').open('a') as stream:
                stream.write(json.dumps(row, sort_keys=True) + '\n')
        print('Completed Arrow phase round', round_number, flush=True)
    require(len(records) == 42, 'Incomplete observation set')
    write_csv(output / 'raw.csv', records)
    write_csv(output / 'summary.csv', summaries(records, settings))
    write_csv(output / 'paired-summary.csv', paired_summaries(records, settings))
    after = bindings()
    write_json(output / 'provenance-after.json', after)
    require(before == after, 'Pre/post bindings differ')
    write_json(output / 'completion.json', dict(observations=len(records),
        configurations=len(settings), qualified_configurations=len(qualification),
        datasig=expected_signature, bindings_matched=True,
        controller_sha256=before['controller_sha256'],
        result_sha256={name: bench.sha(output / name) for name in (
            'raw.jsonl', 'raw.csv', 'summary.csv', 'paired-summary.csv',
            'qualification.json', 'protocol.json', 'provenance-before.json',
            'provenance-after.json', 'build-bindings.json', 'stock.patch',
            'diagnostic.patch')}))
    print('Completed', len(records), 'observations; bindings matched', flush=True)


if __name__ == '__main__':
    main()
