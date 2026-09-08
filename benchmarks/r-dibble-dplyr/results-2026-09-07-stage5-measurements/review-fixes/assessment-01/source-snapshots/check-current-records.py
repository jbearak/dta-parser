"""Check selected archived facts; never execute historical reviewers or workloads."""
import ast
import csv
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile


HERE = Path(__file__).absolute().parent
ARCHIVES = HERE.parent
ORIGINAL_DRIVER_REVIEW = Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/root-driver-review-03.json')


def require(value, message):
    if not value:
        raise RuntimeError(message)


def identity(path):
    path = Path(path)
    target = path.resolve(strict=True)
    status = target.stat()
    return dict(path=str(path), resolved=str(target), bytes=status.st_size,
                mode=oct(status.st_mode & 0o777),
                sha256=hashlib.sha256(target.read_bytes()).hexdigest())


def namespace_path(rows):
    require(all('name' in row and 'path' in row for row in rows), 'Namespace schema differs')
    names = [row['name'] for row in rows]
    matches = [row['path'] for row in rows if row['name'] == 'dtatools']
    require(len(matches) == 1, 'Expected exactly one dtatools namespace')
    require(len(set(names)) == len(names), 'Duplicate namespace names')
    return matches[0]


def check_payload(row, payload, mode):
    require(len(payload) == row['bytes'], 'Selected member size differs')
    require(hashlib.sha256(payload).hexdigest() == row['sha256'], 'Selected member bytes differ')
    require(oct(mode & 0o777) == row['mode'], 'Selected member mode differs')


def self_test():
    good = [{'name': 'dtatools', 'path': '/fixture/dtatools'}, {'name': 'base', 'path': '/fixture/base'}]
    require(namespace_path(good) == '/fixture/dtatools', 'Valid namespace fixture failed')
    payload = b'original'
    row = dict(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest(), mode='0o644')
    check_payload(row, payload, 0o644)
    cases = [lambda: namespace_path([]), lambda: namespace_path(good + [good[0]]),
             lambda: namespace_path(good + [good[1]]),
             lambda: namespace_path([{'package': 'dtatools', 'path': '/fixture'}]),
             lambda: check_payload(row, b'changed!', 0o644),
             lambda: check_payload(row, payload, 0o755)]
    for case in cases:
        try:
            case()
        except RuntimeError:
            pass
        else:
            raise RuntimeError('Malformed fixture was accepted')
    return dict(status='complete', positive_cases=2, rejected_cases=len(cases),
                argv=sys.orig_argv, optimize=sys.flags.optimize, debug=__debug__,
                PYTHONOPTIMIZE=os.environ.get('PYTHONOPTIMIZE'))


def main(output):
    require(not output.exists() and not output.is_symlink(), 'Fresh output required')
    output.mkdir(parents=True)
    before = None
    status = 'failed'
    error = None
    commands = []
    matched = []
    def write(name, value):
        with (output / name).open('x') as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write('\n')
    def unchanged():
        require([identity(row['path']) for row in before] == before, 'Consumed current inputs changed')
    try:
        specifications = {
            'current-expressions': [
                'implementation/semantics-review/combined-measurement-comparison-review-01.log',
                'implementation/semantics-review/combined-measurement-comparison-review-02.json'],
            'read-diagnosis': [
                'implementation/api-review/native-read-control-source-review-01.json',
                'implementation/semantics-review/atomic-read-v2-record-reader-01.log',
                'implementation/semantics-review/atomic-read-v2-evidence-review-01.json',
                'implementation/semantics-review/atomic-read-v2-states-02.csv'],
            'current-minimum': ['root-r460-integration/check-candidate-v4.py'],
            'current-owned': ['implementation/semantics-review/owned-combined-integrity-review-01.py'],
        }
        specifications['read-diagnosis'].append('implementation/semantics-review/atomic-read-repeat-preparation-review-01.py')
        for repeat in range(1, 4):
            for label in ['baseline-ec10', 'candidate-a2d8b6a']:
                specifications['read-diagnosis'].append(f'root-expression-performance/{label}-read-control-v3-{repeat:02d}/namespaces.tsv')
        inputs = {Path(__file__).absolute(), HERE / 'README.md', HERE / 'superseded-measurement.json',
                  HERE / 'original-inputs/root-driver-review-03.json', ORIGINAL_DRIVER_REVIEW,
                  Path(sys.executable).absolute(), Path(sys.orig_argv[0]).absolute()}
        for family in specifications:
            inputs.add(ARCHIVES / family / 'selection.json')
            inputs.add(ARCHIVES / family / 'records.tar.gz')
        # Plain selected members are known before parsing or checking their data.
        inputs.update(ARCHIVES / family / path for family, paths in specifications.items()
                      for path in paths if (ARCHIVES / family / path).is_file())
        inputs.add(ARCHIVES / 'historical-expressions/root-expression-performance/baseline-f622-measure-01-disposition.json')
        before = [identity(path) for path in sorted(inputs)]
        write('inputs-before.json', dict(inputs=before, argv=sys.orig_argv,
            executable=identity(Path(sys.executable).absolute()), flags=dict(optimize=sys.flags.optimize, debug=__debug__),
            environment={key: os.environ.get(key) for key in ['PATH', 'PYTHONOPTIMIZE', 'PYTHONPATH']},
            scope='Current selected-record consistency and limited facts, not historical execution-mode or runtime requalification.'))
        unchanged()
        snapshots = output / 'source-snapshots'
        snapshots.mkdir()
        for source in [Path(__file__).absolute(), HERE / 'README.md', HERE / 'superseded-measurement.json']:
            target = snapshots / source.name
            target.write_bytes(source.read_bytes())
            target.chmod(source.stat().st_mode & 0o777)
        unchanged()
        test_environment = dict(os.environ)
        test_environment.pop('PYTHONOPTIMIZE', None)
        for flag in [[], ['-O']]:
            command = [sys.executable, *flag, str(Path(__file__).absolute()), '--self-test']
            child = subprocess.run(command, text=True, capture_output=True, timeout=30,
                                   env=test_environment)
            record = dict(command=command, returncode=child.returncode, stdout=child.stdout, stderr=child.stderr,
                          environment={key: test_environment.get(key) for key in ['PATH', 'PYTHONOPTIMIZE', 'PYTHONPATH']})
            commands.append(record)
            write(f'guard-tests-{len(commands):02d}.json', record)
            require(child.returncode == 0, 'Current guard tests failed')
            observed_test = json.loads(child.stdout)
            require(observed_test['optimize'] == (1 if flag else 0), 'Unexpected guard-test optimization mode')
            require(observed_test['positive_cases'] == 2 and observed_test['rejected_cases'] == 6, 'Incomplete guard tests')
            unchanged()
        selected = {}
        for family, paths in specifications.items():
            selection = json.loads((ARCHIVES / family / 'selection.json').read_text())
            rows = {row['path']: row for row in selection['files']}
            require(len(rows) == len(selection['files']), 'Duplicate selected paths')
            wanted = set(paths)
            for path in paths:
                require(path in rows, 'Requested original is not selected: ' + path)
                if rows[path]['presentation'] == 'plain':
                    source = ARCHIVES / family / path
                    payload = source.read_bytes()
                    check_payload(rows[path], payload, source.stat().st_mode)
                    selected[(family, path)] = payload
                    matched.append(dict(family=family, **rows[path]))
                    wanted.remove(path)
            with tarfile.open(ARCHIVES / family / 'records.tar.gz', 'r|gz') as archive:
                for member in archive:
                    if member.name not in paths or rows[member.name]['presentation'] != 'bundle':
                        continue
                    require(member.name in wanted and member.isfile(), 'Duplicate or nonregular selected member')
                    payload = archive.extractfile(member).read()
                    check_payload(rows[member.name], payload, member.mode)
                    selected[(family, member.name)] = payload
                    matched.append(dict(family=family, **rows[member.name]))
                    wanted.remove(member.name)
            require(not wanted, 'Missing selected members: ' + repr(wanted))
        def read(family, path):
            return selected[(family, path)].decode()
        namespace_facts = []
        for path in specifications['read-diagnosis']:
            if path.endswith('/namespaces.tsv'):
                rows = list(csv.DictReader(io.StringIO(read('read-diagnosis', path)), delimiter='\t'))
                namespace_facts.append(dict(member=path, dtatools_rows=1, total_namespaces=len(rows),
                    unique_namespace_names=len({row['name'] for row in rows}), package_path=namespace_path(rows)))
        require(len(namespace_facts) == 6, 'Expected six saved namespace tables')
        prefix = 'implementation/semantics-review/'
        states = list(csv.DictReader(io.StringIO(read('read-diagnosis', prefix + 'atomic-read-v2-states-02.csv'))))
        require(len(states) == 3672 and all(row['handle_shared'] == 'TRUE' for row in states), 'Saved sharing facts differ')
        counts = {}
        for row in states:
            key = (row['kind'], row['backing_private'])
            counts[key] = counts.get(key, 0) + 1
        require({kind: count for (kind, private), count in counts.items() if private == 'TRUE'} == {'factor': 147, 'ordered': 147}, 'Saved private-backing facts differ')
        require('backing_private' in read('read-diagnosis', prefix + 'atomic-read-v2-record-reader-01.log'), 'Expected original false-invariant failure missing')
        ownership_review = json.loads(read('read-diagnosis', prefix + 'atomic-read-v2-evidence-review-01.json'))
        require(any('stronger than the original gate' in item for item in ownership_review['limits']), 'Original scope explanation missing')
        require('KeyError' in read('current-expressions', prefix + 'combined-measurement-comparison-review-01.log'), 'Expected original namespace failure missing')
        correction = json.loads(read('current-expressions', prefix + 'combined-measurement-comparison-review-02.json'))
        require('incorrect namespace TSV column' in correction['reviewer_attempt_history'], 'Corrected reader history missing')
        copied = HERE / 'original-inputs/root-driver-review-03.json'
        require(copied.read_bytes() == ORIGINAL_DRIVER_REVIEW.read_bytes(), 'Original review copy differs')
        require(identity(copied)['sha256'] == '7f97a226d0bb8d75c82a214414274c9e7c3ca9a61bcd59222452e003b91493a2', 'Original review identity differs')
        require(identity(copied)['mode'] == identity(ORIGINAL_DRIVER_REVIEW)['mode'], 'Original review mode differs')
        driver = read('current-minimum', 'root-r460-integration/check-candidate-v4.py').encode()
        original_binding = json.loads(copied.read_text())['files']['/private/tmp/dta-direct-stage5-validation/root-r460-integration/check-candidate-v4.py']
        require(hashlib.sha256(driver).hexdigest() == original_binding['sha256'] and len(driver) == original_binding['bytes'], 'Copied review driver binding differs')
        historical_asserts = []
        for family, filename in [('current-owned', 'owned-combined-integrity-review-01.py'), ('read-diagnosis', 'atomic-read-repeat-preparation-review-01.py')]:
            body = read(family, prefix + filename)
            historical_asserts.append(dict(family=family, filename=filename,
                assert_statements=sum(isinstance(node, ast.Assert) for node in ast.walk(ast.parse(body))),
                historical_optimization_flags='not retained; unknown'))
        write('current-facts.json', dict(namespace_facts=namespace_facts, state_rows=len(states),
            all_handles_shared=True, private_backing_counts=[dict(kind=k, value=v, count=n) for (k, v), n in sorted(counts.items())],
            historical_asserts=historical_asserts, selected_originals=matched,
            original_review_copy=identity(copied), native_source_review_present_in_original_bundle=True,
            scope='Current read-only checks of selected records; no historical script, R workload, profiler or benchmark rerun.'))
        unchanged()
        status = 'complete'
    except Exception as caught:
        error = dict(type=type(caught).__name__, message=str(caught))
    finally:
        changed = None
        if before is not None:
            try:
                after = [identity(row['path']) for row in before]
                write('inputs-after.json', after)
                changed = before != after
            except Exception as caught:
                changed = True
                error = error or dict(type=type(caught).__name__, message=str(caught))
        if changed is not False or error:
            status = 'failed'
        write('result.json', dict(status=status, changed_inputs=changed, error=error, commands=commands,
                                 completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        products = [identity(path) for path in sorted(output.rglob('*')) if path.is_file()
                    and path not in (output / 'manifest.json', output / 'receipt.json')]
        write('manifest.json', dict(products=products, excluded=['manifest.json', 'receipt.json']))
        write('receipt.json', dict(status=status, manifest=identity(output / 'manifest.json')))
    print(json.dumps(dict(status=status, receipt=identity(output / 'receipt.json'))))
    return 0 if status == 'complete' else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        print(json.dumps(self_test()))
    else:
        require(len(sys.argv) == 2, 'Expected a fresh output directory or --self-test')
        sys.exit(main(Path(sys.argv[1]).absolute()))
