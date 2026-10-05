"""Publish the independently built trimmed reader panel, plus rejected evidence.

Execute only after root releases the exclusive timing slot. This program never
runs R, Cargo or a benchmark. The final R qualification is one fresh observation;
failed diagnostics and earlier test overlays are not passing final evidence.
"""
import argparse
import collections
import csv
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
TEST = 'tests/testthat/test-reader-numeric-facts.R'
MANIFEST = 'tools/native-test-manifest.json'
RUNTIME_HEAD = 'fc35f1f31ca78d3640480923d7daa3b89677220c'
RUNTIME_DLL = 'c784dfa83aba9aad90d0ab40e35ab8ffea5d513998c2b695723c80bf14b76984'
REJECTED_HEAD = '9e7c166a1f7556e85807925ecffe67bd3a3d1299'
REJECTED_DLL = '5cf31a50111846f4c19aac7402d1ce82ce114361bf6c5eb42a91269c6f0e0abb'
SCRIPT_NAMES = ('reader-worker.R', 'reader-fixtures.R', 'reader-run.py')
RUST_FILTERS = ('reader_', 'compact_float_count_only_gather_',
                'numeric_facts::tests::', 'owned_numeric::tests::')
RUST_SOURCE = ('src/rust/src/lib.rs', 'src/rust/src/owned_numeric.rs',
               'src/rust/src/numeric_facts.rs', 'src/dta-tools/src/missing.rs')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def object_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def read_csv(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def controller(path):
    spec = importlib.util.spec_from_file_location('reader_validation', path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


def verify_recorded_artifacts(directory, recorded):
    require(all((directory / name).is_file() and sha(directory / name) == digest
                for name, digest in recorded.items()), 'Recorded observation artifacts changed')


def validate_panel(summary, rows, module):
    mode = summary['mode']
    rounds = 6 if mode == 'measure' else 1
    require(summary['status'] == 'PASS' and summary['before_after_equal'] and
            summary['paired_rounds'] == rounds and summary['observations'] == len(rows) == 24 * rounds,
            'Only the sole completed six-pair panel or its one-pair qualification is eligible')
    require(len(summary['commands']) == 2 * rounds and
            all(command['exit_code'] == 0 for command in summary['commands']), 'Incomplete worker completion')
    for round_number in range(1, rounds + 1):
        order = ['baseline', 'candidate'] if round_number % 2 else ['candidate', 'baseline']
        commands = [item for item in summary['commands'] if item['round'] == round_number]
        require([item['role'] for item in commands] == order and
                [item['position'] for item in commands] == [1, 2], 'Build order is not alternating')
        for role in order:
            selected = [row for row in rows if row['round'] == str(round_number) and row['build'] == role]
            module.validate(selected, round_number, role, mode, summary['before']['inputs'])
    if mode == 'measure':
        for role in ('baseline', 'candidate'):
            for fixture in module.FIXTURES:
                for format in module.FORMATS:
                    for count in module.OPERATIONS:
                        positions = [int(row['position']) for row in rows if row['build'] == role and
                                     row['fixture'] == fixture and row['format'] == format and
                                     int(row['operations']) == count]
                        require(len(set(positions)) == 6 and sum(positions) == 39 and
                                sum(position <= 6 for position in positions) == 3, 'Phase-order imbalance')


def validate_metrics(summary, rows):
    require(len(summary['rounds']) == 24, 'Exactly four coordinates per paired round are required')
    by = {(row['build'], int(row['round']), row['fixture'], row['format'], int(row['operations'])): row
          for row in rows}
    for item in summary['rounds']:
        for clock in ('cpu', 'wall'):
            expected = {role: {str(count): 1000 * float(by[(role, item['round'], item['fixture'],
                                                          item['format'], count)][clock]) /
                                      int(by[(role, item['round'], item['fixture'], item['format'], count)]['repetitions'])
                              for count in (0, 1, 5)} for role in ('baseline', 'candidate')}
            require(item[clock + '_ms'] == expected, 'Published phase costs differ from raw observations')
            base, candidate = expected['baseline'], expected['candidate']
            require(item['reader_' + clock + '_cost_ratio'] == candidate['0'] / base['0'] and
                    item['reader_' + clock + '_delta_ms'] == candidate['0'] - base['0'], 'Reader cost metric differs')
            for count, name in ((1, 'one'), (5, 'five')):
                require(item[name + '_operation_' + clock + '_workflow_speedup'] == base[str(count)] / candidate[str(count)] and
                        item[name + '_operation_' + clock + '_workflow_saved_ms'] == base[str(count)] - candidate[str(count)],
                        'Workflow metric differs')
    fields = [key for key in summary['rounds'][0] if key.endswith(
        ('_cost_ratio', '_delta_ms', '_workflow_speedup', '_workflow_saved_ms'))]
    medians = {fixture + '/' + format: {key: statistics.median(item[key] for item in summary['rounds']
                if item['fixture'] == fixture and item['format'] == format) for key in fields}
               for fixture in ('dense_float', 'sparse_int') for format in ('dta', 'arrow')}
    require(medians == summary['medians'], 'Median metrics differ from the six paired rounds')



def compact_binding(binding):
    return {key: binding[key] for key in ('source_head', 'dll_sha256', 'receipt_sha256')} | {
        'runtime_source_inventory_sha256': object_sha(binding['source_inventory']),
        'installed_package_inventory_sha256': object_sha(binding['installed_inventory'])}


def compact_panel(panel):
    before = {key: value for key, value in panel['before'].items() if key != 'builds'}
    before['builds'] = {role: compact_binding(binding)
                        for role, binding in panel['before']['builds'].items()}
    before['inputs'] = {**before['inputs'], 'directory': 'generated separately',
        'rows': [{key: value for key, value in row.items() if key != 'path'}
                 for row in before['inputs']['rows']]}
    result = {key: value for key, value in panel.items()
              if key not in ('before', 'commands', 'artifact_sha256')}
    result.update(before=before, commands=[{key: value for key, value in item.items()
                  if key not in ('command', 'cwd')} for item in panel['commands']])
    result['private_summary_sha256'] = object_sha(panel)
    return result


def validate_r(rows, receipt, manifest):
    require(receipt['exit_code'] == 0 and receipt['bindings_unchanged'] and
            receipt['scripts_unchanged'] and receipt['block_membership_pass'] and
            not receipt['policy_failures'], 'The single final R run did not pass its receipt contract')
    require(len(rows) == receipt['blocks'] == 139 and
            all(row['failed'] == row['warning'] == '0' and
                row['error'] == row['skipped'] == 'FALSE' for row in rows),
            'The final R observation must contain all 139 passing blocks')
    require(sum(int(row['passed']) for row in rows) == receipt['counts']['passed'] and
            receipt['counts']['failed'] == receipt['counts']['warning'] ==
            receipt['errors'] == receipt['skips'] == 0, 'R counts differ from the actual receipt')
    families = manifest['families']
    expected = [block for family in families for block in family['blocks']
                if block['file'] in receipt['selected_files']]
    require(expected == receipt['expected_blocks'], 'Final R block contract differs from the exact manifest')
    seen = collections.Counter()
    actual = {}
    for row in rows:
        key = (row['file'], row['test'])
        seen[key] += 1
        actual[(*key, seen[key])] = row
    policies = {(block['file'], block['test'], block.get('occurrence', 1)): block
                for block in expected}
    require(len(actual) == len(rows) and set(actual) == set(policies), 'Final R block membership differs')
    for key, policy in policies.items():
        require(int(actual[key]['passed']) >= policy['min_pass'] and policy['warnings'] == 0,
                'Final R assertions do not satisfy the exact manifest')


def validate_rust(receipt):
    observations = receipt['observations']
    require(receipt['bindings_unchanged'] and receipt['scripts_unchanged'] and
            receipt['archive_unchanged'] and
            tuple(item['filter'] for item in observations) == RUST_FILTERS and
            all(item['exit_code'] == item['failed'] == item['ignored'] == 0 and
                item['passed'] > 0 and item['passed'] == len(item['tests'])
                for item in observations), 'The four scoped final Rust filters did not pass')


def build_summary(receipt, receipt_path):
    keys = ('source_head', 'dll_sha256', 'rust_namespace', 'rust_archive_sha256',
            'exit_code', 'source_unchanged_during_build', 'c_compile_count',
            'rust_compile_count', 'rust_archive_rebuilt', 'reused_own_rust_archive')
    return {key: receipt[key] for key in keys if key in receipt} | {
        'private_receipt_sha256': sha(receipt_path),
        'wall_seconds': (datetime.datetime.fromisoformat(receipt['finished']) -
                         datetime.datetime.fromisoformat(receipt['started'])).total_seconds(),
        'runtime_source_inventory_sha256': object_sha(receipt['source_inventory']),
        'production_source_sha256': {path: receipt['source_inventory'][path]
                                     for path in RUST_SOURCE if path in receipt['source_inventory']},
        'interpretation': 'One dtatools installation, zero C compilations, 62 Rust compilations. '
                          'No R dependencies were installed. Reused C objects and immutable seed '
                          'inputs do not imply Rust dependency cache hits.'}


def validate_assembly(directory, receipt, panel):
    require(receipt['schema'] == 1 and receipt['status'] == 'BOUND', 'Assembly witness did not qualify')
    for role, key in (('baseline', 'baseline'), ('final', 'candidate')):
        source, build = receipt['source'][role], panel['before']['builds'][key]
        require(source['commit'] == build['source_head'] and
                source['dll_sha256'] == build['dll_sha256'] and
                source['build_receipt_sha256'] == build['receipt_sha256'] and
                source['source_inventory_matches_commit_and_compiled_copy'],
                'Assembly witness does not bind the measured build')
    records = {item['file']: item['sha256'] for item in receipt['source_excerpts']}
    records.update({name: item['sha256'] for name, item in receipt['snippets'].items()})
    records.update(receipt['review_artifact_sha256'])
    final_commands = receipt['disassembly_commands']['final']
    # Complete private objdump outputs remain provenance in the receipt. The
    # portable witness publishes the exact bounded snippets listed above.
    verify_recorded_artifacts(directory, records)
    commands = [item for name, item in receipt['disassembly_commands'].items() if name != 'final']
    commands.extend(final_commands.values())
    require(commands and all(item['exit_code'] == 0 for item in commands) and
            receipt['snippets']['final-arrow-float.asm']['calls'] == 0 and
            receipt['snippets']['final-dta-float.asm']['calls'] == 0,
            'Final assembly witness has failed disassembly or per-row calls')


def report(evidence):
    lines = ['# Compact reader FLOAT performance', '',
        'The final reader implementation keeps allocation facts only for complete, strict, '
        'modern non-temporal Arrow FLOAT columns. The existing missing-count scan also '
        'computes FLOAT bounds and observed-zero counts. DTA and integer columns remain '
        'unknown. DTA bulk FLOAT uses an exact Boolean missing-count kernel, with the '
        'format-version gate outside the row loop.', '',
        'The table gives medians of six alternating baseline/candidate process pairs. '
        'Reader cost is candidate/baseline, where smaller is faster. Workflow speedup '
        'is baseline/candidate, where larger is faster. Each workflow includes the '
        'read and zero, one or five independent `1.01 / source` operations.', '',
        '| Fixture and format | Reader CPU cost | CPU delta, ms | One-operation speedup | Five-operation speedup |',
        '| --- | ---: | ---: | ---: | ---: |']
    for coordinate, item in evidence['panel']['medians'].items():
        lines.append(f"| {coordinate} | {item['reader_cpu_cost_ratio']:.3f} | "
                     f"{item['reader_cpu_delta_ms']:+.3f} | "
                     f"{item['one_operation_cpu_workflow_speedup']:.3f} | "
                     f"{item['five_operation_cpu_workflow_speedup']:.3f} |")
    dta_costs = [item['reader_cpu_cost_ratio'] for item in evidence['panel']['rounds']
                if item['fixture'] == 'dense_float' and item['format'] == 'dta']
    arrow_costs = [item['reader_cpu_cost_ratio'] for item in evidence['panel']['rounds']
                  if item['fixture'] == 'dense_float' and item['format'] == 'arrow']
    lines.extend(['', f'Arrow FLOAT reader CPU cost ranged from {min(arrow_costs):.3f} '
        f'to {max(arrow_costs):.3f} across the six pairs. DTA FLOAT was noisier, ranging '
        f'from {min(dta_costs):.3f} to {max(dta_costs):.3f}; its roughly 6% median '
        'reader gain was not consistent across pairs.', '',
        'Integer readers are controls: their reductions are unchanged. '
        'The DTA integer workflows measured about 3% slower; Arrow integer workflows were '
        'near neutral. These results do not establish an integer-reader optimization.', '',
        'The raw observations and evidence include CPU and wall clocks, calibration '
        'repetitions, all twelve workflow coordinates, and source/installed-package/fixture '
        'bindings. The 24 untimed qualification controls are separate. Warm OS file cache, '
        'one reader thread and these two million-row fixtures limit the performance claim. '
        'Allocation and automatic GC are timed; allocation volume is not measured.', '',
        'The rejected broad-facts experiment is preserved in `rejected-all-facts/`. '
        'Its 144 observations bind a different source and DLL. It raised DTA reader CPU '
        'cost by 64% for dense FLOAT and 45% for sparse INT, and slowed both one-operation '
        'DTA workflows. Those results motivated the smaller final implementation. '
        'Its gains are historical, not final measurements.', '',
        f"One fresh R qualification passed {evidence['r_checks']['blocks']} blocks and "
        f"{evidence['r_checks']['counts']['passed']:,} assertions with no failure, error, warning or skip. "
        'The exact native test manifest is included. Four release Rust filters passed '
        f"{sum(item['passed'] for item in evidence['rust_checks']['observations'])} test executions; "
        'the filters overlap, so this is not a count of distinct tests.', '',
        f"The final local build took {evidence['runtime']['wall_seconds']:.2f} seconds: "
        'zero C compilations, 62 Rust compilations and one dtatools installation. '
        'It installed no R dependencies. Existing C objects were reused; external Rust '
        'dependency cache hits are not claimed.', '',
        'The final source/DLL-bound assembly witness is in `assembly/`. Its active '
        'FLOAT loops remain scalar. Arrow removes the per-element generic tag-classifier '
        'call; DTA moves the version gate outside the loop. The exact canonical tag '
        'predicate preserves all 27 positive tags and both-sign IEEE NaNs without '
        'treating infinities or noncanonical high finite words as missing.', '',
        'Before clocks, oracles check source facts, values, metadata and compact state. '
        'After clocks, alias mutation checks verify missing-cache invalidation. The '
        'reader-only Arrow alias follows its existing retained-to-raw detachment and '
        'clears facts. Operation workflows preserve the immutable source. These '
        'ownership transitions are explicit in every recorded control.', '',
        'Validate the published records without running R, Cargo or timing:', '',
        '```sh', 'python3 publish-reader-evidence.py --check .',
        'python3 -O publish-reader-evidence.py --check .', '```', '',
        'The final `reader-run.py`, `reader-worker.R` and `reader-fixtures.R` are the '
        'exact executed sources. The Python controller\'s CLI help lists its inputs. '
        'New timings require independently installed baseline/candidate libraries, '
        'their full matching local build receipts, and the matching build-source copies. '
        'The published build summaries deliberately omit full target/vendor inventories. '
        'The standalone `--check` commands above replay recorded evidence without '
        'those installations, local build receipts or generated fixture files.', '',
        'From this directory, generate fixtures outside all clocks:', '',
        '```sh', 'Rscript --vanilla reader-fixtures.R BASELINE_LIBRARY FRESH_FIXTURES', '```', '',
        'Run the controller first with `--qualify-only` and a separate fresh output '
        'directory. Then run the six-pair timed panel with the following argument outline:', '',
        '```sh', 'python3 reader-run.py \\',
        '  --baseline-library BASELINE_LIBRARY \\',
        '  --candidate-library CANDIDATE_LIBRARY \\',
        '  --baseline-receipt BASELINE_FULL_BUILD_RECEIPT.json \\',
        '  --candidate-receipt CANDIDATE_FULL_BUILD_RECEIPT.json \\',
        '  --fixtures FRESH_FIXTURES \\',
        '  --public-workers-root REPO/benchmarks/remaining-compact-kernels \\',
        '  --target-cpu 0.3 --output FRESH_TIMED_PANEL', '```', '',
        'Failed private diagnostics are excluded from passing evidence.', ''])
    return '\n'.join(lines)


def check_public(out):
    evidence = read_json(out / 'evidence.json')
    verify_recorded_artifacts(out, evidence['artifact_sha256'])
    module = controller(out / 'reader-run.py')
    validate_panel(evidence['panel'], read_csv(out / 'raw.csv'), module)
    validate_panel(evidence['qualification'], read_csv(out / 'qualification.csv'), module)
    validate_metrics(evidence['panel'], read_csv(out / 'raw.csv'))
    rejected = evidence['rejected_all_facts']
    historical = controller(out / 'rejected-all-facts/reader-run.py')
    validate_panel(rejected['panel'], read_csv(out / 'rejected-all-facts/raw.csv'), historical)
    validate_metrics(rejected['panel'], read_csv(out / 'rejected-all-facts/raw.csv'))
    require(evidence['runtime']['source_head'] == RUNTIME_HEAD and
            evidence['runtime']['dll_sha256'] == RUNTIME_DLL and
            evidence['panel']['before']['builds']['candidate']['source_head'] == RUNTIME_HEAD and
            evidence['panel']['before']['builds']['candidate']['dll_sha256'] == RUNTIME_DLL and
            evidence['r_checks']['build_binding'] == evidence['rust_checks']['build_binding'] ==
            evidence['panel']['before']['builds']['candidate'] and
            rejected['panel']['before']['builds']['candidate']['source_head'] == REJECTED_HEAD and
            rejected['panel']['before']['builds']['candidate']['dll_sha256'] == REJECTED_DLL and
            evidence['qualification']['before'] == evidence['panel']['before'],
            'Final and rejected source/DLL or qualification identities differ')
    manifest = read_json(out / 'native-test-manifest.json')
    require(evidence['r_checks']['native_manifest_sha256'] == sha(out / 'native-test-manifest.json'),
            'Exact final manifest binding differs')
    validate_r(read_csv(out / 'r-checks.csv'), evidence['r_checks'], manifest)
    validate_rust(evidence['rust_checks'])
    validate_assembly(out / 'assembly', read_json(out / 'assembly/receipt.json'), evidence['panel'])
    require((out / 'README.md').read_text() == report(evidence), 'Report differs from the actual observations')
    for base, panel in ((out, evidence['panel']), (out / 'rejected-all-facts', rejected['panel'])):
        for name, field in zip(SCRIPT_NAMES, ('worker_sha256', 'generator_sha256', 'controller_sha256')):
            require(sha(base / name) == panel['before'][field], 'Executed reader source changed')
    print(json.dumps(dict(status='PASS', final_observations=144, qualification_controls=24,
                         rejected_observations=144, r_blocks=evidence['r_checks']['blocks'],
                         r_assertions=evidence['r_checks']['counts']['passed'],
                         rust_test_executions=sum(item['passed'] for item in evidence['rust_checks']['observations']))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', type=Path, help='Validate published artifacts without R or Cargo')
    for name in ('source-root', 'measured', 'qualified', 'r-tests', 'rust-tests',
                 'candidate-build-receipt', 'baseline-build-receipt', 'rejected-panel',
                 'assembly-dir', 'out'):
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    if args.check:
        check_public(args.check.resolve())
        return
    require(all(getattr(args, name.replace('-', '_')) for name in
                ('source-root', 'measured', 'qualified', 'r-tests', 'rust-tests',
                 'candidate-build-receipt', 'baseline-build-receipt', 'rejected-panel',
                 'assembly-dir', 'out')), 'All final and rejected observation/provenance inputs are required')
    measured, qualified, rejected_dir = args.measured.resolve(), args.qualified.resolve(), args.rejected_panel.resolve()
    panel, qualification, rejected = (read_json(directory / 'summary.json')
                                      for directory in (measured, qualified, rejected_dir))
    module, historical = controller(HERE / 'reader-run.py'), controller(HERE / 'reader-run-all-facts-executed.py')
    for directory, summary in ((measured, panel), (qualified, qualification), (rejected_dir, rejected)):
        verify_recorded_artifacts(directory, summary['artifact_sha256'])
    rows, controls, rejected_rows = (read_csv(directory / 'raw.csv')
                                     for directory in (measured, qualified, rejected_dir))
    validate_panel(panel, rows, module)
    validate_panel(qualification, controls, module)
    validate_metrics(panel, rows)
    validate_panel(rejected, rejected_rows, historical)
    validate_metrics(rejected, rejected_rows)
    require(panel['before'] == qualification['before'], 'Final qualification and timed inputs differ')
    require(panel['before']['builds']['baseline'] == rejected['before']['builds']['baseline'] and
            panel['before']['inputs'] == rejected['before']['inputs'], 'Final and rejected controls differ')
    for name, field in zip(SCRIPT_NAMES, ('worker_sha256', 'generator_sha256', 'controller_sha256')):
        require(sha(HERE / name) == panel['before'][field], 'Executed final benchmark source changed')
    historical_sources = ('reader-worker-all-facts-executed.R', 'reader-fixtures.R',
                          'reader-run-all-facts-executed.py')
    for name, field in zip(historical_sources, ('worker_sha256', 'generator_sha256', 'controller_sha256')):
        require(sha(HERE / name) == rejected['before'][field], 'Executed rejected benchmark source changed')
    candidate_path, baseline_path = args.candidate_build_receipt.resolve(), args.baseline_build_receipt.resolve()
    candidate, baseline = read_json(candidate_path), read_json(baseline_path)
    require(candidate['source_head'] == RUNTIME_HEAD and candidate['dll_sha256'] == RUNTIME_DLL and
            candidate['exit_code'] == 0 and candidate['source_unchanged_during_build'] and
            candidate['c_compile_count'] == 0 and candidate['rust_compile_count'] == 62 and
            candidate['rust_archive_rebuilt'] and not candidate['reused_own_rust_archive'],
            'Independently built trimmed reader runtime differs')
    require(rejected['before']['builds']['candidate']['source_head'] == REJECTED_HEAD and
            rejected['before']['builds']['candidate']['dll_sha256'] == REJECTED_DLL,
            'Rejected all-facts runtime identity differs')
    for role, path in (('candidate', candidate_path), ('baseline', baseline_path)):
        require(panel['before']['builds'][role]['receipt_sha256'] == sha(path), 'Measured build receipt differs')
    r_dir, rust_dir = args.r_tests.resolve(), args.rust_tests.resolve()
    r, rust = read_json(r_dir / 'receipt.json'), read_json(rust_dir / 'receipt.json')
    root = args.source_root.resolve()
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    require(head == RUNTIME_HEAD, 'Publication must begin from the frozen independently built source')
    package = root / 'r-package/dtatools'
    manifest_path = package / MANIFEST
    manifest = read_json(manifest_path)
    require(sha(manifest_path) == candidate['source_inventory'][MANIFEST], 'Final source manifest differs from build')
    validate_r(read_csv(r_dir / 'test-results.csv'), r, manifest)
    validate_rust(rust)
    for receipt in (r, rust):
        require(receipt['build_binding'] == panel['before']['builds']['candidate'],
                'Final tests and timed candidate must bind the same installed package and production source')
    for path in RUST_SOURCE:
        require(sha(package / path) == candidate['source_inventory'][path], 'Final production source changed')
    assembly_dir = args.assembly_dir.resolve()
    assembly = read_json(assembly_dir / 'receipt.json')
    validate_assembly(assembly_dir, assembly, panel)
    out = args.out.resolve()
    require(not out.exists(), 'Never overwrite published evidence')
    out.mkdir(parents=True)
    for name in SCRIPT_NAMES:
        shutil.copy2(HERE / name, out / name)
    shutil.copy2(Path(__file__).resolve(), out / 'publish-reader-evidence.py')
    for directory, name in ((measured, 'raw.csv'), (qualified, 'qualification.csv')):
        shutil.copy2(directory / 'raw.csv', out / name)
    shutil.copy2(r_dir / 'test-results.csv', out / 'r-checks.csv')
    shutil.copy2(manifest_path, out / 'native-test-manifest.json')
    for name in ('focused-test-run.py', 'focused-tests.R', 'reader-rust-tests.py'):
        source = HERE / name
        receipt = rust if name == 'reader-rust-tests.py' else r
        require(receipt['scripts'][str(source)] == sha(source), 'Executed test controller source changed')
        shutil.copy2(source, out / name)
    rejected_out = out / 'rejected-all-facts'
    rejected_out.mkdir()
    for source_name, public_name in zip(historical_sources, SCRIPT_NAMES):
        shutil.copy2(HERE / source_name, rejected_out / public_name)
    shutil.copy2(rejected_dir / 'raw.csv', rejected_out / 'raw.csv')
    assembly_out = out / 'assembly'
    assembly_out.mkdir()
    for path in sorted(assembly_dir.iterdir()):
        require(path.is_file() and path.stat().st_size < 1_000_000,
                'Assembly publication must contain only small standalone source/receipt artifacts')
        shutil.copy2(path, assembly_out / path.name)
    r_public = {key: r[key] for key in ('exit_code', 'bindings_unchanged', 'scripts_unchanged',
        'block_membership_pass', 'policy_failures', 'counts', 'errors', 'skips', 'blocks',
        'selected_files', 'expected_blocks')}
    r_public.update(private_receipt_sha256=sha(r_dir / 'receipt.json'),
                    native_manifest_sha256=sha(manifest_path), one_fresh_observation=True,
                    build_binding=compact_binding(r['build_binding']))
    rust_public = {key: rust[key] for key in ('bindings_unchanged', 'scripts_unchanged',
                                            'archive_unchanged', 'rust_namespace', 'rust_archive_sha256')}
    rust_public.update(private_receipt_sha256=sha(rust_dir / 'receipt.json'),
        build_binding=compact_binding(rust['build_binding']), observations=[{key: item[key] for key in
        ('filter', 'exit_code', 'tests', 'passed', 'failed', 'ignored', 'rust_compile_lines', 'log_sha256')}
        for item in rust['observations']])
    evidence = dict(schema_version=2, panel=compact_panel(panel), qualification=compact_panel(qualification),
        runtime=build_summary(candidate, candidate_path),
        baseline_build_receipt_sha256=sha(baseline_path), r_checks=r_public, rust_checks=rust_public,
        rejected_all_facts=dict(accepted=False, panel=compact_panel(rejected),
            reason='The broad implementation collected facts for DTA and integer readers. '
                   'It raised DTA reader CPU cost by 64% for dense FLOAT and 45% for sparse INT '
                   'in these paired controls, and slowed the one-operation DTA workflows. '
                   'The final independently built implementation removes those fact scans.'),
        mutation_qualification='Timed source values, metadata, facts and state are checked before '
            'outside-clock alias mutation. Reader-only Arrow detaches retained storage to raw and clears '
            'facts under its existing writable-access policy. Operation workflows retain the immutable source.',
        limitations='Warm OS file cache, threads=1, two million-row fixtures, twelve workflows. '
            'Allocation time and automatic GC are included; allocated-byte volume is not measured. '
            'No cold-disk, general format ranking, parallel-worker, zero-cost facts or universal parity claim.',
        artifact_sha256={})
    (out / 'README.md').write_text(report(evidence))
    evidence['artifact_sha256'] = {str(path.relative_to(out)): sha(path)
                                  for path in sorted(out.rglob('*')) if path.is_file()}
    write_json(out / 'evidence.json', evidence)
    check_public(out)


if __name__ == '__main__':
    main()
