#!/usr/bin/env python3
"""Bind completed final integration checks. Runs no tests or benchmarks.

The Rust launch supplement is post-run. Historical measurement receipts keep
their original sources; this receipt qualifies only the combined source below.
"""
from collections import Counter
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
REPO = Path('<final_repository>')
SOURCE = '3eadb244253fb817d5773b01b11cb36c284f3a1d'
PACKAGE_SOURCE = '754b38ce8f81707506ecac9016167fb66d60487f'
BASE = '213ceeee5a0f7953bf0f13316e2207a766dcbb24'
ADAPTIVE = 'd98495c25598098e3d00131a666a34bc47fc90c8'
LOCATOR = '0f9a13c6deed3c97f8e67b5c165218b1bb54a5f2'
CANONICAL = '19f573720b4897a4f742bad0cebba22ce17d9a88'
PACKAGE = 'r-package/dtatools/'
BUILD = EVIDENCE / 'final-combined-build'
FOCUSED = EVIDENCE / 'final-focused-v1'
RECORDER = Path('<recorder_repository>/benchmarks/native-operations/run.py')
GIT_ENV = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}


def need(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(Path(path).read_bytes())


def read(path):
    return json.loads(Path(path).read_text())


def git(*args, **kwargs):
    return subprocess.check_output(['git', '--no-replace-objects', *args],
                                   cwd=REPO, env=GIT_ENV, **kwargs)


def blob(pin, path):
    return git('show', pin + ':' + path)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def committed_package(pin):
    entries = []
    for entry in git('ls-tree', '-rz', pin, '--', PACKAGE).split(b'\0'):
        if not entry:
            continue
        header, path = entry.split(b'\t', 1)
        mode, kind, oid = header.split()
        need(kind == b'blob' and mode in (b'100644', b'100755'), 'Nonregular package source')
        entries.append((path.decode().removeprefix(PACKAGE), oid))
    raw = git('cat-file', '--batch', input=b''.join(oid + b'\n' for _, oid in entries))
    cursor, result = 0, {}
    for path, oid in entries:
        end = raw.index(b'\n', cursor)
        actual, kind, size = raw[cursor:end].split()
        size = int(size)
        cursor = end + 1
        data = raw[cursor:cursor + size]
        need(actual == oid and kind == b'blob' and len(data) == size and
             raw[cursor + size:cursor + size + 1] == b'\n', 'Invalid immutable blob response')
        result[path] = data
        cursor += size + 1
    need(cursor == len(raw) and result, 'Incomplete immutable source')
    return result


def strict_count(value):
    need(isinstance(value, str) and re.fullmatch(r'[0-9]+', value) is not None,
         'Malformed nonnegative count')
    return int(value)


def child(parent, name):
    p = Path(name)
    need(not p.is_absolute() and '..' not in p.parts and p.parts, 'Unsafe artifact child')
    result = parent / p
    need(result.is_file() and result.resolve().is_relative_to(parent.resolve()), 'Missing/escaped artifact')
    return result


def normalized_diff(first, second, path):
    return '\n'.join(line for line in git('diff', '--no-ext-diff', '--no-textconv',
        first, second, '--', path).decode().splitlines()
        if not line.startswith(('diff ', 'index ', '--- ', '+++ ', '@@ ')))


def main():
    artifacts = {}

    def bind(path):
        path = Path(path)
        key = str(path.relative_to(EVIDENCE)) if path.is_relative_to(EVIDENCE) else str(path)
        value = sha(path)
        need(key not in artifacts or artifacts[key] == value, 'Artifact changed while binding')
        artifacts[key] = value
        return value

    def children(parent, mapping):
        need(isinstance(mapping, dict) and mapping, 'Empty artifact inventory')
        for name, expected in mapping.items():
            need(bind(child(parent, name)) == expected, 'Artifact hash mismatch: ' + name)

    for pin in (SOURCE, PACKAGE_SOURCE, BASE, ADAPTIVE, LOCATOR, CANONICAL):
        need(re.fullmatch('[0-9a-f]{40}', pin) and git('cat-file', '-t', pin).strip() == b'commit',
             'Invalid source pin')
    need(not git('diff', '--name-only', PACKAGE_SOURCE, SOURCE, '--', PACKAGE),
         'Benchmark-only commit changed package')
    committed = committed_package(SOURCE)
    current = {str(p.relative_to(REPO / PACKAGE)): sha(p)
               for p in (REPO / PACKAGE).rglob('*') if p.is_file()}
    expected_source = {p: digest(data) for p, data in committed.items()}
    need(current == expected_source, 'Current package differs from full immutable inventory')

    # Recheck the exact source unions, not only the earlier review's PASS label.
    changed = {p.removeprefix(PACKAGE) for p in git('diff', '--name-only', CANONICAL,
               SOURCE, '--', PACKAGE).decode().splitlines()}
    integrated = {'src/numeric-arithmetic-float-reciprocal.h',
        'src/numeric-arithmetic-pair-long-float.h', 'src/rust/src/owned_numeric.rs',
        'tests/testthat/test-native-arithmetic-parity.R',
        'tests/testthat/test-arithmetic-payload-lifetime.R', 'tools/native-test-manifest.json'}
    need(changed == integrated, 'Unexpected canonical integration delta')
    reciprocal = 'src/numeric-arithmetic-float-reciprocal.h'
    need(committed[reciprocal] == blob(ADAPTIVE, PACKAGE + reciprocal), 'Adaptive writer changed')
    test_paths = ['tests/testthat/test-native-arithmetic-parity.R',
                  'tests/testthat/test-arithmetic-payload-lifetime.R']
    for path in test_paths:
        base, adaptive, canonical = (blob(pin, PACKAGE + path) for pin in (BASE, ADAPTIVE, CANONICAL))
        need(adaptive.startswith(base) and canonical.startswith(base), 'Parent test prefix changed')
        need(committed[path] == adaptive + canonical[len(base):], 'Appended test union changed')
    owned = PACKAGE + 'src/rust/src/owned_numeric.rs'
    need(normalized_diff(BASE, CANONICAL, owned) == normalized_diff(LOCATOR, SOURCE, owned),
         'Canonical Rust fact delta changed during locator integration')
    pair = 'src/numeric-arithmetic-pair-long-float.h'
    original = blob(CANONICAL, PACKAGE + pair).decode()
    edits = [
        ('    for (size_t start = 0; start < (size_t) length;) {\n        R_CheckUserInterrupt();\n',
         '    size_t completed_since_poll = 0;\n    R_CheckUserInterrupt();\n    for (size_t start = 0; start < (size_t) length;) {\n'),
        ('        unsigned failures = 0;\n',
         '        /* Preserve complete native spans. Captured read claims keep these\n'
         '           pointers stable across the check before processing this span. */\n'
         '        if (count > 16384 - completed_since_poll) {\n'
         '            R_CheckUserInterrupt();\n            completed_since_poll = 0;\n        }\n'
         '        unsigned failures = 0;\n'),
        ('        start += count;\n', '        start += count;\n        completed_since_poll += count;\n')]
    for old, new in edits:
        need(original.count(old) == 1, 'Polling integration replacement is not unique')
        original = original.replace(old, new)
    need(committed[pair] == original.encode(), 'Canonical/polling writer union changed')
    manifest = json.loads(committed['tools/native-test-manifest.json'])
    for pin in (ADAPTIVE, LOCATOR, CANONICAL):
        old = json.loads(blob(pin, PACKAGE + 'tools/native-test-manifest.json'))
        for family in old['families']:
            matches = [f for f in manifest['families'] if f['id'] == family['id']]
            need(len(matches) == 1 and all(b in matches[0]['blocks'] for b in family['blocks']),
                 'Parent manifest obligation lost')
    for family in manifest['families']:
        for entry in family['files']:
            need(expected_source[entry['path']] == entry['sha256'], 'Manifest source digest mismatch')

    records = load_module('final_integration_records', RECORDER)
    inventory = records.inventory(BUILD, 'baseline')
    receipt = inventory['receipt']
    need(receipt['base_commit'] == SOURCE and receipt['source_patch_sha256'] == digest(b'') and
         receipt['exit_code'] == 0 and receipt['pre_post_source_equal'] is True, 'Wrong clean build')
    need(inventory['source'] == expected_source, 'Clean build differs from committed package')
    need(bind(BUILD / 'build.log') == receipt['build_log_sha256'], 'Build log changed')
    need(bind(BUILD / 'input-record.json') == receipt['input_record_sha256'], 'Build input record changed')
    bind(BUILD / 'build-receipt.json')
    # These are semantic builder/recorder identities, not files relative to
    # BUILD. records.inventory already replays verified_receipt's exact map.
    need(set(receipt['artifact_sha256']) == {'builder', 'recorder', 'existing_recorder_helpers'},
         'Unexpected clean-build dependency schema')

    before, after, done, command = (read(FOCUSED / name) for name in
                                  ('before.json', 'after.json', 'completion.json', 'command.json'))
    need(before == after and before['build'] == inventory and done['before_after_equal'] is True,
         'Focused source/runtime changed')
    need(done['status'] == 'PASS' and done['source_commit'] == done['test_source_head'] == SOURCE and
         before['test_source_head'] == SOURCE and before['test_source_patch_sha256'] == digest(b''),
         'Focused source pin changed')
    need((FOCUSED / 'test-source.patch').read_bytes() == b'', 'Focused source was patched')
    expected_tests = {p.removeprefix('tests/'): h for p, h in expected_source.items() if p.startswith('tests/')}
    need(before['tests'] == expected_tests, 'External test/helper/fixture inventory differs')
    controls = [EVIDENCE / 'run-focused.py', EVIDENCE / 'focused.R', RECORDER]
    need(before['controllers'] == {p.name: bind(p) for p in controls}, 'Focused controller changed')
    rt = before['runtime']
    need(command['exit_code'] == 0 and command['cwd'] == str(REPO) and
         command['command'] == [rt['launcher'], '--vanilla', str(EVIDENCE / 'focused.R'),
             str(BUILD / 'library'), str(REPO / PACKAGE / 'tests/testthat'), str(FOCUSED / 'focused.csv')],
         'Focused command/cwd changed')
    launcher = Path(rt['launcher'])
    home, version = subprocess.check_output([str(launcher), '--vanilla', '-e',
        'cat(R.home(), R.version.string, sep=intToUtf8(10L))'], text=True).splitlines()
    need(sha(launcher) == rt['launcher_sha256'] and home == rt['R_home'] and version == rt['R_version'] and
         sha(Path(home) / 'bin/exec/R') == rt['R_runtime_sha256'] == receipt['toolchain']['R_runtime_sha256'],
         'Exact focused/build runtime changed')
    children(FOCUSED, done['artifacts'])
    need(set(done['artifacts']) == {p.name for p in FOCUSED.iterdir() if p.is_file()} - {'completion.json'},
         'Focused completion inventory is incomplete')
    bind(FOCUSED / 'completion.json')
    rows = list(csv.DictReader((FOCUSED / 'focused.csv').open()))
    focused_paths = test_paths + ['tests/testthat/test-compact-float-domain.R']
    blocks = Counter((Path(path).name, title) for path in focused_paths
        for title in re.findall(r'^test_that\("([^"\\]*)"', committed[path].decode(), re.M))
    need(all(n == 1 for n in blocks.values()) and Counter((r['file'], r['test']) for r in rows) == blocks,
         'Focused block matrix is incomplete/duplicated')
    for row in rows:
        for key in ('passed', 'failed', 'warning'):
            strict_count(row[key])
        need(row['failed'] == row['warning'] == '0' and row['error'] == row['skipped'] == 'FALSE',
             'Focused failure/error/skip/warning')
    totals = {k: sum(strict_count(row[k]) for row in rows) for k in ('passed', 'failed', 'warning')}
    need(done['blocks'] == len(blocks) == 47 and done['totals'] == totals and totals['passed'] == 38954,
         'Focused summary changed')
    for family in manifest['families']:
        for obligation in family['blocks']:
            matches = [r for r in rows if (r['file'], r['test']) == (obligation['file'], obligation['test'])]
            if matches:
                need(len(matches) == 1 and int(matches[0]['passed']) >= obligation['min_pass'],
                     'Focused manifest minimum not met')

    guards = read(HERE / 'guards.json')
    scripts = ['scripts/test_native_manifest.py', 'scripts/test_arithmetic_dependencies.py',
        'benchmarks/integer-reciprocal/test-work-count.py', 'benchmarks/long-float-addition/test-work-count.py',
        'benchmarks/long-float-addition/test-run.py', 'benchmarks/compact-float-domain/strict/test-run.py',
        'benchmarks/compact-float-domain/unknown/test-run.py', 'benchmarks/scalar-float-blocks/test-kernel.py']
    need(guards['status'] == 'PASS' and guards['source_commit'] == SOURCE and
         guards['runner_sha256'] == bind(HERE / 'run-guards.py'), 'Guard source/runner changed')
    need(guards['files'] == {p: digest(blob(SOURCE, p)) for p in scripts}, 'Guard scripts differ from commit')
    for script in scripts:
        need(sha(REPO / script) == guards['files'][script], 'Current guard source changed')
    expected_commands = Counter(tuple(([script] if not optimized else ['-O', script]))
        for script in scripts for optimized in (False, True))
    need(Counter(tuple(g['command'][1:]) for g in guards['commands']) == expected_commands,
         'Guard command matrix changed')
    for g in guards['commands']:
        need(g['returncode'] == 0 and g['cwd'] == str(REPO) and
             bind(child(HERE, g['log'])) == g['log_sha256'], 'Guard execution/log binding failed')
    bind(HERE / 'guards.json')

    rust = read(HERE / 'rust-command.json')
    need(rust['status'] == 'PASS' and rust['source_commit'] == SOURCE and rust['cwd'] == str(REPO) and
         rust['command'] == ['cargo', 'test', '--manifest-path', 'r-package/dtatools/src/rust/Cargo.toml', '--locked'] and
         rust['environment'] == {'CARGO_TARGET_DIR': '<private-work>/dta-native-comparison-followup/target'},
         'Rust launch supplement changed')
    need(bind(HERE / 'rust.log') == rust['log_sha256'], 'Rust log changed')
    rust_counts = re.findall(r'test result: ok\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored;',
                             (HERE / 'rust.log').read_text())
    need(rust_counts == [('71', '0', '0')] and (rust['passed'], rust['failed'], rust['ignored']) == (71, 0, 0),
         'Rust test count/failure changed')
    bind(HERE / 'rust-command.json')

    structural = {}
    for name, folder, count in [('canonical', 'compact-float-domain', 162),
            ('unknown', 'long-float-addition', 162), ('polling', 'retained-arithmetic-polling', 18),
            ('integer', 'integer-reciprocal', 64)]:
        directory = EVIDENCE / ('final-' + name + '-structural-v1')
        result = read(directory / 'receipt.json')
        need(result['commit'] == SOURCE and result['require_proved'] is True and result['exit_code'] == 0,
             'Structural source/gate failed')
        if name != 'integer':
            need(result['root'] == str(REPO) and result['source_before_after_equal'] is True and
                 (result['cases'], result['semantic_failures'], result['work_failures']) == (count, 0, 0),
                 'Structural matrix/failures changed')
        else:
            need(result['working_tree_status'] == '' and result['source_patch_sha256'] == digest(b''),
                 'Integer structural source was dirty')
        for rel, expected in result['source_sha256'].items():
            need(expected_source['src/' + rel] == expected, 'Structural source differs from commit')
        controller = REPO / 'benchmarks' / folder / 'work-count.py'
        probe = controller.with_suffix('.c')
        for path, key in [(controller, 'controller_sha256'), (probe, 'probe_sha256')]:
            need(bind(path) == result[key] == digest(blob(SOURCE, str(path.relative_to(REPO)))),
                 'Structural controller/probe changed')
        if name == 'polling':
            need(bind(controller.parent / 'cadence.h') == result['cadence_sha256'] ==
                 digest(blob(SOURCE, str((controller.parent / 'cadence.h').relative_to(REPO)))),
                 'Polling cadence source changed')
        need(sha(Path(result['command'][0])) == result['compiler_sha256'], 'Structural compiler changed')
        children(directory, result['artifact_sha256'])
        bind(directory / 'receipt.json')
        csv_text = (directory / 'work-count.csv').read_text()
        probe_rows = list(csv.DictReader(csv_text.splitlines()))
        need(len(probe_rows) == count, 'Incomplete structural rows')
        module = load_module('integration_' + name + '_probe', controller)
        if name in ('canonical', 'unknown'):
            need(module.validate_rows(probe_rows) == (0, 0), 'Structural row validation failed')
        elif name == 'integer':
            module.validate_case_matrix(csv_text)
        else:
            expected = {(1000000, p, x, y, r) for p in ('ordinary', 'sparse')
                for x, y in ((0, 0), (8191, 16385), (7, 11)) for r in (0, 1)}
            expected |= {(n, 'ordinary', 7, 11, r) for n in (16383, 16384, 16385) for r in (0, 1)}
            actual = [(int(r['length']), r['pattern'], int(r['long_chunk']), int(r['float_chunk']),
                       int(r['reverse'])) for r in probe_rows]
            need(len(set(actual)) == count and set(actual) == expected, 'Polling geometry matrix changed')
            for r in probe_rows:
                need(r['semantic_error'] == r['work_error'] == '0' and
                     int(r['interrupt_calls']) == int(r['work_bound']) and
                     int(r['span_calls']) == int(r['expected_span_calls']) and
                     r['span_trace'] == r['expected_span_trace'] and r['poll_trace'] == r['expected_poll_trace'] and
                     int(r['max_poll_gap']) == int(r['expected_max_poll_gap']), 'Polling work/semantic gate failed')
        need((directory / 'work-count.log').read_text() ==
             f'PASS: 0 semantic failures, 0 proved-work failures across {count} cases\n', 'Structural summary changed')
        structural[name] = dict(cases=count, semantic_failures=0, work_failures=0,
                                receipt_sha256=sha(directory / 'receipt.json'))

    # A complete immutable archive is mandatory. A running or failed job cannot bind.
    archive = read(HERE / 'conformance.json')
    launch = read(HERE / 'conformance-command.json')
    need(archive['source_commit'] == SOURCE and launch['commit'] == SOURCE and launch.get('exit_code') == 0,
         'Required archive conformance has not completed successfully')
    flags = ['checked_source_matches_clean_export', 'clean_export_matches_source_commit',
        'exact_packaged_source_inventory', 'expected_hashes_from_committed_blobs',
        'repository_environment_overrides_removed', 'required_conformance_passed']
    need(all(archive[k] is True for k in flags), 'Archive validation flags failed')
    for name, field in [('run-conformance.py', 'controller_sha256'),
            ('conformance-gate.sh', 'wrapper_sha256'), ('validate-conformance-archive.py', 'validator_sha256')]:
        need(bind(HERE / name) == launch[field], 'Archive controller/wrapper/validator changed')
    export = HERE / 'conformance-export'
    need(launch['cwd'] == str(export) and launch['command'] == ['sh', str(HERE / 'conformance-gate.sh')] and
         launch['environment'] == {'DTA_REQUIRE_R_CONFORMANCE': '1', 'R_ENVIRON_USER': '/dev/null',
             'R_PROFILE_USER': '/dev/null', 'CARGO_TARGET_DIR': '<private-work>/dta-native-comparison-followup/target'},
         'Archive invocation changed')
    conformance_script = blob(SOURCE, 'scripts/conformance.sh')
    need(sha(export / 'scripts/conformance.sh') == digest(conformance_script) == launch['original_script_sha256'],
         'Original conformance script changed')
    old = 'trap \'rm -rf "$temporary"\' EXIT HUP INT TERM'
    new = 'trap \'cp -R "$temporary" ' + str(HERE / 'conformance-preserved') + '; rm -rf "$temporary"\' EXIT HUP INT TERM'
    need(conformance_script.decode().count(old) == 1 and
         (HERE / 'conformance-gate.sh').read_text() == conformance_script.decode().replace(old, new),
         'Conformance wrapper changed more than retention trap')
    need(bind(HERE / 'conformance.tar.gz') == archive['source_archive_sha256'], 'Archive bytes changed')
    scoped = {p: h for p, h in expected_source.items()
              if p == '.Rbuildignore' or p.startswith(('src/', 'R/', 'tests/', 'tools/'))}
    ignored = ('src/dta-tools/examples/', 'src/dta-tools/target/', 'src/dta-tools/tests/',
               'src/rust/target/', 'src/rust/v/')
    ignored_files = ('src/Makevars', 'src/Makevars.win', 'tests/testthat/testthat-problems.rds')
    excluded = {p for p in scoped if p.startswith(ignored) or p in ignored_files}
    checked = {p: h for p, h in scoped.items() if p != '.Rbuildignore' and p not in excluded}
    need(archive['verified_files'] == checked and set(archive['deliberately_excluded_by_buildignore']) == excluded and
         len(archive['deliberately_excluded_by_buildignore']) == len(excluded) and
         archive['buildignore_sha256'] == scoped['.Rbuildignore'], 'Archive source inventory is incomplete')
    for rel, expected in scoped.items():
        need(sha(export / PACKAGE / rel) == expected, 'Clean archive export source changed')
    packaged = {}
    with tarfile.open(HERE / 'conformance.tar.gz', 'r:gz') as tar:
        for member in tar.getmembers():
            rel = member.name.removeprefix('dtatools/')
            if member.isdir() or not member.name.startswith('dtatools/') or not rel.startswith(('src/', 'R/', 'tests/', 'tools/')):
                continue
            need(member.isfile() and rel not in packaged, 'Nonregular/duplicate packaged source')
            packaged[rel] = digest(tar.extractfile(member).read())
    need(packaged == checked, 'Actual archive source bytes differ')
    log = (HERE / 'conformance.log').read_text()
    need('R package conformance: PASS (current source built and checked with offline Cargo archive)' in log,
         'Required conformance PASS marker absent')
    rout = HERE / 'conformance-preserved/dtatools.Rcheck/tests/testthat.Rout'
    counts = re.findall(r'\[ FAIL ([0-9]+) \| WARN ([0-9]+) \| SKIP ([0-9]+) \| PASS ([0-9]+) \]', rout.read_text())
    need(counts and len(set(counts)) == 1, 'Full archived R suite lacks a unique terminal count')
    failed, warnings, skipped, passed = map(int, counts[-1])
    need(failed == skipped == 0 and warnings == 7 and passed >= totals['passed'], 'Archived full R suite failed')
    for path in [HERE / 'conformance.json', HERE / 'conformance-command.json', HERE / 'conformance.log', rout,
                 HERE / 'conformance-preserved/dtatools.Rcheck/00check.log']:
        bind(path)

    # These hashes are current replay dependencies, distinct from the three
    # direct dependencies recorded contemporaneously by run-focused.py.
    dependency_root = RECORDER.parents[2]
    dependencies = [RECORDER, dependency_root / 'benchmarks/r-file-readers/record-builds.py',
                    dependency_root / 'benchmarks/io-optimization/record-builds.py',
                    dependency_root / 'benchmarks/r-file-readers/build-snapshot.py']
    replay_dependencies = {str(p): bind(p) for p in dependencies}
    bind(Path(__file__).resolve())
    result = dict(status='PASS', source_commit=SOURCE, package_source_commit=PACKAGE_SOURCE,
        component_sources=dict(base=BASE, adaptive=ADAPTIVE, locator=LOCATOR, canonical=CANONICAL),
        exact_component_union=True, parent_manifest_obligations_preserved=True,
        source_inventory=expected_source, installed_inventory=inventory['installed'],
        clean_build_receipt_sha256=inventory['receipt_sha256'], runtime=rt,
        focused=dict(blocks=len(rows), passed=totals['passed'], failed=0, error=0, skipped=0, warnings=0),
        rust=dict(passed=71, failed=0, ignored=0, launch_binding='post-run supplement'),
        guards=dict(commands=16, failed=0), structural=structural,
        archive=dict(passed=passed, failed=failed, warnings=warnings, skipped=skipped,
            source_files=len(checked), buildignore_exclusions=len(excluded),
            source_archive_sha256=archive['source_archive_sha256']),
        recorder_dependencies_replayed_now=replay_dependencies, artifact_sha256=artifacts,
        scope='Combined immutable source, clean installed build, 47-block focused correctness, '
              '71 Rust tests with explicitly post-run launch supplement, 16 guard commands, '
              'current-header structural checks, and required full archived package conformance. '
              'No benchmark is run or rebound to this source by this receipt; historical timings retain their original commits.')
    (HERE / 'integration-binding.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('PASS final integration:', totals['passed'], 'focused assertions;', passed, 'archived R assertions')


if __name__ == '__main__':
    main()
