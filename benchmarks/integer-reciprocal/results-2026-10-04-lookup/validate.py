#!/usr/bin/env python3
"""Verify published bytes, source bindings and recorded results without running R."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics
import types

HERE = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def module(path):
    # Execute only a manifest-bound controller's definitions. Its __main__
    # entry is not invoked; no measurements, builds or R processes are run.
    result = types.ModuleType('_recorded_controller')
    result.__file__ = str(path)
    exec(compile(path.read_text(), str(path), 'exec'), result.__dict__)
    return result


def close(actual, expected):
    return abs(actual - expected) <= 1e-12 * max(1, abs(actual), abs(expected))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=HERE.parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = read(HERE / 'manifest.json')
    require(manifest['format'] == 1, 'Unknown manifest format')
    actual_files = {str(p.relative_to(HERE)) for p in HERE.rglob('*')
                    if p.is_file() and p.name != 'manifest.json'}
    require(actual_files == set(manifest['files']), 'Published file inventory changed')
    for name, digest in manifest['files'].items():
        require(sha(HERE / name) == digest, 'Published file changed: ' + name)
    for name, digest in manifest['sources'].items():
        require((root / name).is_file() and sha(root / name) == digest,
                'Runtime/probe/test source changed: ' + name)
    for name, binding in manifest['copies'].items():
        require(manifest['files'][name] == binding['sha256'], 'Copy binding differs: ' + name)

    candidate = read(HERE / 'proof/candidate-receipt.json')
    negative = read(HERE / 'proof/historical-negative-control-receipt.json')
    for label, receipt, failure_count, exit_code in [
        ('candidate', candidate, 0, 0), ('historical-negative-control', negative, 709, 1)]:
        records = rows(HERE / f'proof/{label}-work-count.csv')
        require(len(records) == receipt['cases'] == 1472 and receipt['exit_code'] == exit_code,
                'Probe case count or expected exit changed')
        require(len(receipt['rounding_witnesses']) == 4 and
                len({item[1] for item in receipt['rounding_witnesses']}) == 4,
                'Four rounding modes were not witnessed')
        require(sum(int(row['work_failure']) for row in records) == failure_count,
                'Unexpected proved-work failures')
        require(f'0 semantic failures, {failure_count} proved-work failures across 1472 cases'
                in (HERE / f'proof/{label}-work-count.log').read_text(), 'Semantic proof log differs')
        for name in ('work-count.csv', 'work-count.log'):
            require(sha(HERE / f'proof/{label}-{name}') == receipt['artifact_sha256'][name],
                    'Probe artifact differs from receipt')
        require(receipt['controller_sha256'] == sha(root / 'benchmarks/integer-reciprocal/work-count.py') and
                receipt['probe_sha256'] == sha(root / 'benchmarks/integer-reciprocal/work-count.c'),
                'Executed probe/controller differs')
    require(candidate['source_commit'] == manifest['test_metadata_checkpoint'] and
            candidate['working_tree_status'] == '' and candidate['has_lookup'],
            'Candidate oracle is not committed clean source')
    require(negative['source_commit'] == manifest['historical_probe_source_commit'] and
            not negative['has_lookup'], 'Historical probe negative control changed')
    for name, digest in candidate['source_sha256'].items():
        require(manifest['sources']['r-package/dtatools/src/' + name] == digest,
                'Candidate probe source differs from runtime')
    optimized = read(HERE / 'proof/frozen-kernel-o3-receipt.json')
    require(optimized['exit_code'] == 0 and '-O3' in optimized['command'] and
            optimized['source_sha256']['numeric-arithmetic-integer-reciprocal.h'] ==
            candidate['source_sha256']['numeric-arithmetic-integer-reciprocal.h'] and
            optimized['artifact_sha256']['work-count.csv'] == candidate['artifact_sha256']['work-count.csv'],
            'Frozen-kernel optimization control changed')

    focused = read(HERE / 'validation/focused-tests-receipt.json')
    records = rows(HERE / 'validation/focused-tests.csv')
    require(sum(int(row['nb']) for row in records) == focused['assertions'] == 69092 and
            len(records) == focused['blocks'] == 136 and
            len({row['file'] for row in records}) == focused['files'] == 10,
            'Focused assertion/block/file counts changed')
    require(all(row['failed'] == row['warning'] == '0' and
                row['skipped'] == row['error'] == 'FALSE' for row in records) and
            all(focused[key] == 0 for key in ('failures', 'errors', 'warnings', 'skips', 'exit_code')),
            'Focused tests did not pass cleanly')
    for name, key in [('focused-tests.R', 'runner_sha256'), ('focused-tests.csv', 'csv_sha256'),
                      ('focused-tests.log', 'log_sha256')]:
        require(sha(HERE / 'validation' / name) == focused[key], 'Focused artifact changed')
    original = read(HERE / 'validation/original-build-receipt.json')
    corrected = read(HERE / 'validation/guard-corrected-build-receipt.json')
    build = read(HERE / 'validation/final-tests-build-receipt.json')
    # The original receipt stores R CMD INSTALL's success. The outer controller
    # failed later in its post-build guard, after writing that receipt.
    require(original['exit_code'] == 0 and build['original_controller_exit_code'] == 1 and
            build['original_receipt_sha256'] == sha(HERE / 'validation/original-build-receipt.json') and
            build['original_qualified_receipt_sha256'] == sha(HERE / 'validation/guard-corrected-build-receipt.json'),
            'Original build controller failure was not preserved')
    require(build['package_build_exit_code'] == build['post_guard_exit_code'] == build['exit_code'] == 0 and
            build['production_source_unchanged_after_build'] and build['rust_archive_unchanged'] and
            len(build['c_compile_lines']) == 1 and build['rust_compile_lines'] == [] and
            build['dll_sha256'] == focused['dll_sha256'] == manifest['candidate_dll_sha256'] and
            build['source_head'] == manifest['runtime_checkpoint'] and
            build['final_test_metadata_checkpoint'] == manifest['test_metadata_checkpoint'],
            'Qualified C-only build or test-overlay lineage changed')
    require(sha(HERE / 'validation/install.log') == build['log_sha256'], 'Install log changed')
    require(corrected['post_guard_correction'] == build['post_guard_correction'], 'Guard correction changed')
    baseline = read(HERE / 'validation/measured-baseline-build-receipt.json')
    require(baseline['exit_code'] == 0 and baseline['dll_sha256'] == manifest['measured_baseline_dll_sha256'],
            'Measured baseline build changed')

    general = read(HERE / 'general/balanced-run-receipt.json')
    supplement = read(HERE / 'supplement/receipt.json')
    for receipt, count in ((general, 12), (supplement, 4)):
        require(receipt['exit_code'] == 0 and receipt['library_before'] == receipt['library_after'] and
                len(receipt['commands']) == count and all(c['exit_code'] == 0 for c in receipt['commands']),
                'Paired worker execution or unchanged library proof failed')
        for role, digest in [('baseline', baseline['dll_sha256']), ('candidate', build['dll_sha256'])]:
            require(receipt['library_before'][role]['libs/dtatools.so'] == digest,
                    'Timing used a different installed DLL')
    require(general['worker_sha256'] == sha(root / 'benchmarks/remaining-compact-kernels/worker.R') and
            general['controller_sha256'] == sha(root / 'benchmarks/remaining-compact-kernels/run.py'),
            'General timing source changed')
    regenerated = module(root / 'benchmarks/remaining-compact-kernels/run.py').summarize(HERE / 'general', 6)
    require(regenerated == read(HERE / 'general/balanced-summary.json'), 'General summary differs from raw records')
    require(supplement['worker_sha256'] == sha(HERE / 'supplement/lookup-worker.R') and
            supplement['controller_sha256'] == sha(HERE / 'supplement/lookup-run.py'),
            'Supplement timing source changed')
    require(module(HERE / 'supplement/lookup-run.py').summarize(HERE / 'supplement', False) ==
            read(HERE / 'supplement/summary.json'), 'Supplement summary differs from raw records')

    construction = read(HERE / 'construction/summary.json')
    require(construction['status'] == 'PASS' and construction['mode'] == 'measure' and
            construction['observations'] == 72 and construction['paired_rounds'] == 6 and
            construction['before_after_equal'] and
            construction['before'] == read(HERE / 'construction/before.json'),
            'Construction qualification changed')
    require(construction['before']['worker_sha256'] == sha(HERE / 'construction/construction-worker.R') and
            construction['before']['controller_sha256'] == sha(HERE / 'construction/construction-run.py') and
            len(construction['commands']) == 12 and all(c['exit_code'] == 0 for c in construction['commands']),
            'Construction source or worker exit changed')
    controller = module(HERE / 'construction/construction-run.py')
    assembled, values = [], {}
    for number in range(1, 7):
        pair = {}
        for position, role in enumerate(('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'), 1):
            current = rows(HERE / f'construction/{role}-round{number}.csv')
            pair[role] = controller.validate(current, number, role, 'measure')
            assembled.extend(dict(build=role, build_position=str(position), **row) for row in current)
        for fixture in controller.FIXTURES:
            phase = {role: {count: 1000 * float(pair[role][fixture, count]['cpu']) /
                              int(pair[role][fixture, count]['repetitions']) for count in (0, 1, 5)}
                     for role in pair}
            values.setdefault(fixture, []).append(dict(
                constructor_cost_ratio=phase['candidate'][0] / phase['baseline'][0],
                constructor_delta_ms=phase['candidate'][0] - phase['baseline'][0],
                one_operation_workflow_speedup=phase['baseline'][1] / phase['candidate'][1],
                five_operation_workflow_speedup=phase['baseline'][5] / phase['candidate'][5]))
    require(assembled == rows(HERE / 'construction/raw.csv'), 'Construction raw records differ')
    for fixture, samples in values.items():
        for field in samples[0]:
            require(close(statistics.median(sample[field] for sample in samples),
                          construction['medians'][fixture][field]), 'Construction median differs')
    for role, digest in [('baseline', baseline['dll_sha256']), ('candidate', build['dll_sha256'])]:
        require(construction['before']['builds'][role]['dll_sha256'] == digest,
                'Construction used a different DLL')
    print(json.dumps(dict(status='PASS', published_files=len(actual_files),
        source_files=len(manifest['sources']), probe_cases=1472, focused_assertions=69092,
        general_observations=216, supplement_observations=120, construction_observations=72)))


if __name__ == '__main__':
    main()
