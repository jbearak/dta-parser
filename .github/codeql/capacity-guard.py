#!/usr/bin/env python3
"""Private capacity diagnostic, not a production Code Scanning result."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request

SOURCE = '531600a2c451d42bfaaf42e8d7f69006c6af06af'
BUNDLE_URL = 'https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.1/codeql-bundle-linux64.tar.gz'
BUNDLE_SHA256 = '1d380f79896ededc654c7b21fafb3360136f1aeb678ad4df4df9af3910c6b815'
ADDED = {
    '.github/workflows/codeql-capacity-qualification.yml',
    '.github/codeql/capacity-config.yml',
    '.github/codeql/capacity-guard.py',
    '.github/codeql/capacity-scope.json',
    '.github/codeql/capacity-expected-queries.json',
    '.github/codeql/preview-source-coverage.ql',
    '.github/codeql/verify-preview-coverage.py',
}
ROOT = Path.cwd().resolve()
CONFIG = ROOT / '.github/codeql'
TEMP = Path(os.environ['RUNNER_TEMP'])
OUT = TEMP / 'codeql-capacity-results'
DB = TEMP / 'codeql-capacity-db'
HELPER = TEMP / 'codeql-capacity-coverage'
GIT_ENV = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}


def require(ok, message):
    if not ok:
        raise SystemExit(message)


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def git(*args):
    return subprocess.check_output(['git', '--no-replace-objects', *args], env=GIT_ENV, text=True).strip()


def resource():
    disk = shutil.disk_usage(ROOT)
    return {'time_utc_epoch': time.time(), 'disk_total': disk.total,
            'disk_used': disk.used, 'disk_free': disk.free}


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def run(name, command):
    start = resource()
    with (OUT / (name + '.stdout')).open('w') as stdout, (OUT / (name + '.stderr')).open('w') as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr)
    write(name + '.json', {'command': command, 'exit_code': result.returncode,
          'before': start, 'after': resource(),
          'stdout_sha256': sha(OUT / (name + '.stdout')), 'stderr_sha256': sha(OUT / (name + '.stderr'))})
    require(result.returncode == 0, name + ' failed; inspect retained command logs')
    return (OUT / (name + '.stdout')).read_text()


def scope():
    data = json.loads((CONFIG / 'capacity-scope.json').read_text())
    require(data['source_commit'] == SOURCE, 'Wrong final source pin')
    require(sha(CONFIG / 'capacity-scope.json') == '3a778322505098fdae7c673849ecd2c911bd4f7a0b55b1f504e19dee75f5ff02', 'Inventory changed')
    excluded = data['proposed_exclusions']
    retained = data['previous_main_historical_must_retain'] + data['current_runtime_and_maintained_must_retain']
    require(len(excluded) == 117 and len(retained) == 116, 'Wrong scope sizes')
    require(len({r['path'] for r in excluded + retained}) == 233, 'Duplicate scope path')
    for row in excluded + retained:
        require(sha(ROOT / row['path']) == row['sha256'], 'Source changed: ' + row['path'])
    expected = ('name: Frozen snapshot capacity qualification\n'
                '# Only exact newly added historical C/H copies; all prior-main files remain eligible.\n'
                'paths-ignore:\n' + ''.join('  - ' + json.dumps(r['path']) + '\n' for r in excluded))
    require((CONFIG / 'capacity-config.yml').read_text() == expected, 'Unexpected query/path configuration')
    require(not git('status', '--porcelain', '--untracked-files=no'), 'Tracked checkout changed')
    return data


def unchanged():
    scope()
    before = json.loads((OUT / 'before.json').read_text())
    require(before['head'] == git('rev-parse', 'HEAD'), 'Head changed during analysis')
    require(before['controllers'] == {p: sha(ROOT / p) for p in sorted(ADDED)}, 'Controller changed')
    return before


def prepare():
    require(not OUT.exists(), 'Output must start absent')
    OUT.mkdir()
    git('merge-base', '--is-ancestor', SOURCE, 'HEAD')
    require(set(git('diff', '--name-only', SOURCE, 'HEAD').splitlines()) == ADDED,
            'Only the seven reviewed diagnostic files may differ from final source')
    scope()
    require(not git('status', '--porcelain', '--untracked-files=all'), 'Initial checkout must contain no untracked files')
    require(os.environ.get('CODEQL_OVERLAY_DATABASE_MODE') == 'none', 'Full analysis must be explicit')
    require(os.environ.get('GITHUB_EVENT_NAME') == 'push', 'Qualification must be a branch push')
    require(os.environ.get('GITHUB_REF') == 'refs/heads/codex/codeql-capacity-qualification', 'Unexpected branch')
    write('before.json', {'source': SOURCE, 'head': git('rev-parse', 'HEAD'),
          'tree': git('rev-parse', 'HEAD^{tree}'),
          'controllers': {p: sha(ROOT / p) for p in sorted(ADDED)}, 'resources': resource()})


def bundle():
    unchanged()
    target = TEMP / 'codeql-capacity-bundle.tar.gz'
    require(not target.exists(), 'Bundle target must start absent')
    with urllib.request.urlopen(BUNDLE_URL) as response, target.open('xb') as output:
        shutil.copyfileobj(response, output)
    observed = sha(target)
    write('bundle.json', {'url': BUNDLE_URL, 'sha256': observed, 'bytes': target.stat().st_size})
    require(observed == BUNDLE_SHA256, 'Official bundle digest differs from reviewed release asset')


def query_name(path):
    # The exact bundle has cpp-queries/1.9.0, as recorded by the managed run.
    marker = '/qlpacks/codeql/cpp-queries/1.9.0/'
    require(marker in path.as_posix(), 'Query resolved outside the pinned bundled C++ pack')
    return 'codeql/cpp-queries/' + path.as_posix().split(marker, 1)[1]


def initialized():
    unchanged()
    codeql = str(Path(os.environ['CODEQL']).resolve())
    version = json.loads(run('codeql-version', [codeql, 'version', '--format=json']))
    require(version['version'] == '2.27.1', 'Unexpected CLI version')
    action_temp = Path(os.environ.get('CODEQL_ACTION_TEMP', str(TEMP)))
    state_path = action_temp / 'config'
    state = json.loads(state_path.read_text())
    expected = {'name': 'Frozen snapshot capacity qualification',
                'paths-ignore': [r['path'] for r in scope()['proposed_exclusions']]}
    require(state['languages'] == ['cpp'] and state['buildMode'] == 'none', 'Wrong language/build mode')
    require(state['analysisKinds'] == ['code-scanning'] and state['overlayDatabaseMode'] == 'none', 'Wrong analysis mode')
    require(state['originalUserInput'] == expected and state['computedConfig'] == expected,
            'Action changed queries, models, or path configuration')
    require(state['extraQueryExclusions'] == [], 'Queries were filtered')
    require(Path(state['codeQLCmd']).resolve() == Path(codeql), 'Action used a different executable')
    require(Path(state['dbLocation']).resolve() == DB.resolve(), 'Wrong database location')
    suite = DB / 'cpp/temp/config-queries.qls'
    generated = action_temp / 'user-config.yaml'
    for name, path in [('action-config.json', state_path), ('generated-config.yml', generated), ('generated-suite.qls', suite)]:
        shutil.copyfile(path, OUT / name)
    paths = json.loads(run('resolved-security-queries', [codeql, 'resolve', 'queries', '--format=json', str(suite)]))
    queries = {query_name(Path(p)): Path(p) for p in paths}
    expected_queries = json.loads((CONFIG / 'capacity-expected-queries.json').read_text())
    require(len(paths) == len(queries) == 61 and set(queries) == set(expected_queries), 'Generated suite is not the exact 61 queries')
    query_inputs = {}
    for q, path in sorted(queries.items()):
        query_inputs[q] = {'source': str(path), 'sha256': sha(path)}
        compiled = path.with_suffix('.qlx')
        if compiled.is_file():
            query_inputs[q]['compiled_sha256'] = sha(compiled)
    packs = Path(codeql).parent / 'qlpacks'
    cpp_all = list((packs / 'codeql/cpp-all').glob('*/qlpack.yml'))
    require(len(cpp_all) == 1, 'Ambiguous bundled C++ library')
    library_version = cpp_all[0].parent.name
    require(not HELPER.exists(), 'Coverage helper directory must start absent')
    HELPER.mkdir()
    helper_query = HELPER / 'preview-source-coverage.ql'
    shutil.copyfile(CONFIG / helper_query.name, helper_query)
    (HELPER / 'qlpack.yml').write_text('name: dta/private-capacity-coverage\nversion: 0.0.0\ndependencies:\n  codeql/cpp-all: ' + json.dumps(library_version) + '\n')
    # Resolve solely from the verified bundle; no pack-install/download command is used.
    run('compile-coverage', [codeql, 'query', 'compile', '--search-path=' + str(packs),
                            '--threads=4', '--ram=14575', str(helper_query)])
    write('initialized.json', {'codeql': codeql, 'executable_sha256': sha(Path(codeql)),
          'queries': query_inputs, 'suite_source': str(suite), 'suite_sha256': sha(suite),
          'action_config_source': str(state_path), 'action_config_sha256': sha(state_path),
          'generated_config_source': str(generated), 'generated_config_sha256': sha(generated),
          'cpp_all_metadata_source': str(cpp_all[0]), 'cpp_all_metadata_sha256': sha(cpp_all[0]),
          'helper_pack_sha256': sha(HELPER / 'qlpack.yml'), 'helper_query_sha256': sha(helper_query),
          'resources_before_analysis': resource()})
    # The verified tarball is no longer needed; keep its digest, not redundant disk use.
    (TEMP / 'codeql-capacity-bundle.tar.gz').unlink()


def finish():
    OUT.mkdir(exist_ok=True)
    write('final-resources.json', resource())
    # No query or database mutation on a failed analysis. Logs/SARIF are retained by the next step.


def verify():
    before = unchanged()
    initialized = json.loads((OUT / 'initialized.json').read_text())
    codeql = initialized['codeql']
    require(str(Path(os.environ['CODEQL']).resolve()) == codeql, 'Executable path changed')
    require(sha(Path(codeql)) == initialized['executable_sha256'], 'Executable changed')
    for key in ['suite', 'action_config', 'generated_config', 'cpp_all_metadata']:
        require(sha(Path(initialized[key + '_source'])) == initialized[key + '_sha256'], key + ' changed')
    for q, item in initialized['queries'].items():
        path = Path(item['source'])
        require(sha(path) == item['sha256'], q + ' changed')
        if 'compiled_sha256' in item:
            require(sha(path.with_suffix('.qlx')) == item['compiled_sha256'], q + ' compiled bytes changed')
    results = {}
    all_results = sorted(DB.rglob('*.bqrs'))
    write('observed-bqrs-paths.json', [str(p.relative_to(DB)) for p in all_results])
    # Match complete pack-relative query suffixes, allowing the CLI's pack-version directory.
    # The database is fresh and the separate coverage query has not run yet.
    for path in all_results:
        relative = path.relative_to(DB).as_posix()
        matches = [q for q in initialized['queries']
                   if relative.endswith('/' + q.removeprefix('codeql/cpp-queries/')[:-3] + '.bqrs')]
        require('/results/codeql/cpp-queries/' in '/' + relative and len(matches) == 1,
                'Unrecognized security result path: ' + relative)
        query = matches[0]
        require(query not in results, 'Duplicate query result: ' + query)
        results[query] = path
    require(set(results) == set(initialized['queries']), 'Executed result set differs from the exact 61 queries')
    write('query-results.json', {q: {'path': str(p.relative_to(DB)), 'sha256': sha(p)} for q, p in sorted(results.items())})
    write('analysis-completed.json', {'status': 'PASS', 'queries': 61, 'resources_after_analysis': resource(),
          'database_metadata_sha256': sha(DB / 'cpp/codeql-database.yml')})
    bqrs = OUT / 'coverage.bqrs'
    csv = OUT / 'extracted-paths.csv'
    query = HELPER / 'preview-source-coverage.ql'
    require(sha(query) == initialized['helper_query_sha256'] and sha(HELPER / 'qlpack.yml') == initialized['helper_pack_sha256'], 'Coverage helper changed')
    packs = Path(codeql).parent / 'qlpacks'
    run('run-coverage', [codeql, 'query', 'run', '--database=' + str(DB / 'cpp'),
                        '--search-path=' + str(packs), '--threads=4', '--ram=14575',
                        '--output=' + str(bqrs), str(query)])
    run('decode-coverage', [codeql, 'bqrs', 'decode', '--format=csv', '--no-titles',
                           '--result-set=#select', '--output=' + str(csv), str(bqrs)])
    run('verify-coverage', [sys.executable, str(CONFIG / 'verify-preview-coverage.py'),
        '--inventory', str(CONFIG / 'capacity-scope.json'), '--query', str(query),
        '--bqrs', str(bqrs), '--decoded-csv', str(csv), '--output', str(OUT / 'coverage-check.json')])
    unchanged()
    write('completion.json', {'status': 'PASS', 'source': SOURCE, 'head': before['head'],
          'scope': 'Full C++ capacity qualification only; no production Code Scanning result uploaded',
          'queries': 61, 'excluded_absent': 117, 'retained_present': 116,
          'resources_after': resource(), 'artifacts': {p.name: sha(p) for p in OUT.iterdir() if p.is_file()}})


if __name__ == '__main__':
    operations = {'prepare': prepare, 'bundle': bundle, 'initialized': initialized, 'verify': verify, 'finish': finish}
    require(len(sys.argv) == 2 and sys.argv[1] in operations, 'Expected prepare, bundle, initialized, verify, or finish')
    operations[sys.argv[1]]()
