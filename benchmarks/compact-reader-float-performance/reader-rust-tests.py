"""Private release reader unit checks, bound to the installed reader build namespace."""
import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
FILTERS = ('reader_', 'compact_float_count_only_gather_',
           'numeric_facts::tests::', 'owned_numeric::tests::')


def parse_test_output(text):
    tests = re.findall(r'^test ([^\r\n]+?)(?: - should panic)? \.\.\. '
                       r'(ok|FAILED|ignored)(?:[ \t]+[^\r\n]*)?\r?$', text, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; '
                          r'(\d+) ignored; (\d+) measured; (\d+) filtered out;[^\r\n]*\r?$',
                          text, re.M)
    if len(summaries) != 1:
        raise RuntimeError('Expected exactly one Cargo test-result summary')
    status, passed, failed, ignored, measured, filtered = summaries[0]
    summary = dict(status=status, passed=int(passed), failed=int(failed),
                   ignored=int(ignored), measured=int(measured), filtered_out=int(filtered))
    counts = {name: sum(result == result_status for _, result in tests)
              for name, result_status in (('passed', 'ok'), ('failed', 'FAILED'), ('ignored', 'ignored'))}
    if (len({name for name, _ in tests}) != len(tests) or summary['measured'] != 0 or
            any(counts[key] != summary[key] for key in counts) or
            (status == 'ok') != (summary['failed'] == 0)):
        raise RuntimeError('Parsed Cargo test statuses disagree with the test-result summary')
    return dict(tests=tests, summary=summary, **counts)


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
    build_receipt = json.loads(receipt_path.read_text())
    source = Path(binding['source'])
    namespace = build_receipt['rust_namespace']
    target = source / 'src/rust/target' / namespace
    archive = target / 'release/libdtatools_r.a'
    archive_sha = sha(archive)
    require(archive_sha == build_receipt['rust_archive_sha256'], 'Own release archive differs from reader receipt')
    require(not out.exists(), 'Never overwrite original Rust test observations')
    scripts = {str(path): sha(path) for path in (Path(__file__).resolve(), binding_path)}
    out.mkdir(parents=True)
    env = os.environ.copy()
    env.update(CARGO_TARGET_DIR=str(target), CARGO_NET_OFFLINE='true')
    cargo = ['cargo', 'test', '--release', '--locked', '--offline', '--manifest-path',
             'rust/Cargo.toml', '--config', 'rust/cargo-config.toml', '--lib']
    receipt = dict(started=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   scripts=scripts, build_binding=binding, rust_namespace=namespace,
                   rust_archive_sha256=archive_sha, target=str(target),
                   controlled_environment={key: env[key] for key in ('CARGO_TARGET_DIR', 'CARGO_NET_OFFLINE')},
                   commands=[cargo + [filter] for filter in FILTERS], observations=[])
    (out / 'input.json').write_text(json.dumps(receipt, indent=2) + '\n')
    for index, filter in enumerate(FILTERS, 1):
        command = cargo + [filter]
        log_path = out / ('rust-' + str(index) + '.log')
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with log_path.open('w') as log:
            result = subprocess.run(command, cwd=source / 'src', env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
        text = log_path.read_text()
        parsed = parse_test_output(text)
        observation = dict(filter=filter, command=command, cwd=str(source / 'src'),
                           started=started, finished=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                           exit_code=result.returncode, **parsed,
                           rust_compile_lines=[line for line in text.splitlines()
                                               if re.search(r'\bCompiling\s+', line)],
                           log_sha256=sha(log_path))
        receipt['observations'].append(observation)
        (out / 'progress.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if result.returncode != 0:
            break
    unchanged = bindings.build_binding(library, receipt_path) == binding and sha(archive) == archive_sha
    scripts_unchanged = all(sha(Path(path)) == digest for path, digest in scripts.items())
    receipt.update(finished=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   bindings_unchanged=unchanged, scripts_unchanged=scripts_unchanged,
                   archive_unchanged=sha(archive) == archive_sha,
                   artifacts={p.name: sha(p) for p in sorted(out.iterdir()) if p.is_file()})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(dict(rust_namespace=namespace, bindings_unchanged=unchanged,
                         archive_unchanged=receipt['archive_unchanged'],
                         tests=[{key: item[key] for key in ('filter', 'exit_code', 'passed', 'failed', 'ignored')}
                                for item in receipt['observations']]), indent=2))
    require(len(receipt['observations']) == len(FILTERS) and unchanged and scripts_unchanged and
            all(item['exit_code'] == 0 and item['passed'] > 0 and
                item['failed'] == item['ignored'] == 0 for item in receipt['observations']),
            'Scoped release Rust tests failed; original logs/receipts are preserved')


if __name__ == '__main__':
    main()
