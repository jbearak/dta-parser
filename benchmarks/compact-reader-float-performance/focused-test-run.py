"""Private focused reader/LUT regression checks, preserving failed observations."""
import argparse
import collections
import csv
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
FILES = tuple('test-' + name + '.R' for name in (
    'native-arithmetic-kernels', 'native-arithmetic-parity', 'compact-float-domain',
    'arithmetic-payload-lifetime', 'compact-pair-domain', 'dense-float-reciprocal-kernel',
    'compact-reciprocal-facts', 'integer-reciprocal-lookup', 'constructor-region-inputs',
    'dta-numeric', 'reader-numeric-facts'))


def row_passes_policy(row, policy):
    return (int(row['failed']) == 0 and row['error'] == 'FALSE' and
            int(row['warning']) == 0 and policy['warnings'] == 0 and
            row['skipped'] == 'FALSE' and int(row['passed']) >= policy['min_pass'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    library, receipt_path, out = args.library.resolve(), args.receipt.resolve(), args.output.resolve()
    binding_path = HERE / 'reader-run.py'
    spec = importlib.util.spec_from_file_location('reader_bindings', binding_path)
    bindings = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bindings)
    sha, require = bindings.sha, bindings.require
    binding = bindings.build_binding(library, receipt_path)
    source = Path(binding['source'])
    test_root = library / 'dtatools/tests/testthat'
    manifest = json.loads((source / 'tools/native-test-manifest.json').read_text())
    selected = [block for family in manifest['families'] for block in family['blocks']
                if block['file'] in FILES]
    registered = {Path(file['path']).name: file['sha256']
                  for family in manifest['families'] for file in family['files']
                  if Path(file['path']).name in FILES}
    require(set(registered) == set(FILES), 'Focused test-file manifest coverage is incomplete')
    require(all(sha(test_root / name) == digest for name, digest in registered.items()),
            'Installed focused test files differ from the source manifest')
    require(sum(block['file'] == 'test-reader-numeric-facts.R' for block in selected) == 3,
            'Exactly the three new reader blocks must be selected')
    build_receipt = json.loads(receipt_path.read_text())
    archive = source / 'src/rust/target' / build_receipt['rust_namespace'] / 'release/libdtatools_r.a'
    archive_sha = sha(archive)
    require(archive_sha == build_receipt['rust_archive_sha256'], 'Reader own archive binding changed')
    scripts = {str(path): sha(path) for path in
               (Path(__file__).resolve(), HERE / 'focused-tests.R', binding_path)}
    require(not out.exists(), 'Never overwrite original focused test observations')
    out.mkdir(parents=True)
    env = os.environ.copy()
    env.update(R_MAKEVARS_USER='/dev/null', R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null')
    command = ['Rscript', '--vanilla', str(HERE / 'focused-tests.R'), str(library),
               str(test_root), str(out), str(bindings.namespace_dll(library))]
    receipt = dict(started=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   command=command, scripts=scripts, build_binding=binding,
                   rust_archive_sha256=archive_sha, selected_files=FILES,
                   expected_blocks=selected)
    (out / 'input.json').write_text(json.dumps(receipt, indent=2) + '\n')
    log_path = out / 'focused-tests.log'
    with log_path.open('w') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    table_path = out / 'test-results.csv'
    rows = list(csv.DictReader(table_path.open(newline=''))) if table_path.exists() else []
    counts = collections.Counter()
    actual = {}
    for row in rows:
        key = (row['file'], row['test'])
        counts[key] += 1
        actual[(*key, counts[key])] = row
    expected = {(block['file'], block['test'], block.get('occurrence', 1)): block
                for block in selected}
    membership = len(actual) == len(rows) and set(actual) == set(expected)
    failures = []
    if not membership:
        failures.append('Actual file/block/occurrence membership differs from the manifest')
    for key in set(actual) & set(expected):
        row, policy = actual[key], expected[key]
        if not row_passes_policy(row, policy):
            failures.append(dict(block=key, observations=row, policy=policy))
    unchanged = bindings.build_binding(library, receipt_path) == binding and sha(archive) == archive_sha
    scripts_unchanged = all(sha(Path(path)) == digest for path, digest in scripts.items())
    receipt.update(finished=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   exit_code=result.returncode, bindings_unchanged=unchanged,
                   scripts_unchanged=scripts_unchanged, block_membership_pass=membership,
                   policy_failures=failures,
                   counts={name: sum(int(row[name]) for row in rows)
                           for name in ('nb', 'passed', 'failed', 'warning')},
                   errors=sum(row['error'] != 'FALSE' for row in rows),
                   skips=sum(row['skipped'] != 'FALSE' for row in rows), blocks=len(rows),
                   artifacts={p.name: sha(p) for p in sorted(out.iterdir()) if p.is_file()})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in
                      ('exit_code', 'blocks', 'counts', 'errors', 'skips',
                       'block_membership_pass', 'bindings_unchanged', 'scripts_unchanged')}, indent=2))
    require(result.returncode == 0 and unchanged and scripts_unchanged and not failures,
            'Focused checks failed; original result/log/receipt artifacts are preserved')


if __name__ == '__main__':
    main()
