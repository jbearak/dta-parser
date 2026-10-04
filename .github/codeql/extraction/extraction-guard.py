#!/usr/bin/env python3
"""Private extraction-only collection. No operation runs a security suite."""
import csv
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import time
import urllib.request

SOURCE = '531600a2c451d42bfaaf42e8d7f69006c6af06af'
ACTION = '2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2'
CLI_SHA = '938af3639d0709b587251e45d9f8d2bdc3505696'
SCOPE_SHA = '3a778322505098fdae7c673849ecd2c911bd4f7a0b55b1f504e19dee75f5ff02'
BUNDLE_URL = 'https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.1/codeql-bundle-linux64.tar.gz'
BUNDLE_SHA = '1d380f79896ededc654c7b21fafb3360136f1aeb678ad4df4df9af3910c6b815'
EXPECTED_QUERIES_SHA = 'cd1d9aa5a2973e2812be1318843c738146a731c50cb1e74aa0bc03d03ff77f2c'
PREFIX = '.github/codeql/extraction/'
WORKFLOW = '.github/workflows/codeql-extraction-followup.yml'
WORKFLOW_SHA = '2f9fcacea8f9b718a29815e91703a0122a192a9bf4ca5a1c8f89f1090ddba45d'
QUERY_SHA = {'bodies.ql': '951cde2b8d3b43b1ca9cab9da74b62175a2fe35b71cc7b0ca6f82a2fccca284c', 'compilations.ql': 'beafa076f0450701b94de7280fcd5dc3d0bab6f88ca143ec6093e4d17c702fc0', 'diagnostics.ql': '3d9965475feb22a6e7d5387d3f96d4dd62c3bd7190f439023325bdf4ca62fde7', 'files.ql': 'a6d53cd3bdf9450b15b62e3d96d0d7cc1c449cd180b58563e717f2402649fab2', 'includes.ql': 'd90e2335dff6318788c8c0fcab0229bb303548ede53fdd73f2c4a5041b476d64', 'qlpack.yml': '7ad362871b0327e5a119f91d32e26e89928c5e788286111b6f6d7a59e1406630'}
NAMES = ('diagnostics', 'compilations', 'includes', 'files', 'bodies')
ADDED = {WORKFLOW, *(PREFIX + n for n in (
    'extraction-guard.py', 'scope.json', 'cpp-control.yml', 'cpp-filtered.yml',
    'expected-query-names.json', 'queries/qlpack.yml',
    *(f'queries/{n}.ql' for n in NAMES)))}
ENV_KEYS = ('CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'SDKROOT', 'INCLUDE',
            'CODEQL_EXTRACTOR_CPP_OPTION_INCLUDE_PATH', 'CODEQL_EXTRACTOR_CPP_OPTION_EXTRA_INCLUDE_PATH',
            'CODEQL_OVERLAY_DATABASE_MODE')

def require(ok, message):
    if not ok:
        raise ValueError(message)

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def safe_relative(value):
    require(isinstance(value, str) and value and not value.startswith('/'), 'Invalid relative path')
    require('\\' not in value and ':' not in value and all(ord(c) >= 32 for c in value), 'Invalid path characters')
    require(all(x not in ('', '.', '..') for x in value.split('/')), 'Noncanonical path')
    require(str(PurePosixPath(value)) == value, 'Changed path normalization')
    return value

def scope_sets(data):
    require(data['status'] == 'PASS' and data['source_commit'] == SOURCE, 'Wrong source inventory')
    excluded = [safe_relative(r['path']) for r in data['proposed_exclusions']]
    kept = [safe_relative(r['path']) for r in data['previous_main_historical_must_retain'] + data['current_runtime_and_maintained_must_retain']]
    require(len(excluded) == len(set(excluded)) == 117, 'Wrong exclusions')
    require(len(kept) == len(set(kept)) == 116 and not set(kept) & set(excluded), 'Wrong retained scope')
    return set(excluded), set(kept)

def strict_coverage(data, raw_csv, arm):
    require(arm in ('control', 'filtered'), 'Unknown arm')
    excluded, kept = scope_sets(data)
    rows = list(csv.reader(io.StringIO(raw_csv.decode('utf-8')), strict=True))
    require(rows and rows[0] == ['file'] and len(rows) > 1, 'Wrong files CSV schema')
    require(all(len(row) == 1 for row in rows[1:]), 'Wrong files CSV width')
    paths = [safe_relative(row[0]) for row in rows[1:]]
    require(len(paths) == len(set(paths)), 'Duplicate source path')
    observed = set(paths)
    missing, seen = sorted(kept - observed), sorted(excluded & observed)
    return {'status': 'FAIL' if missing or (arm == 'filtered' and seen) else 'PASS',
            'retained_expected': 116, 'retained_missing': missing,
            'excluded_expected': 117, 'excluded_observed': seen,
            'excluded_absence_required': arm == 'filtered',
            'all_observed_relative_paths': sorted(observed),
            'additional_observed_paths': sorted(observed - kept - excluded),
            'scope': 'Original retained116 predicate; exclusion absence only applies to filtered arm. FAIL remains FAIL. File metric presence is not semantic completeness.'}

def expected_config(data, arm):
    return {'name': 'Frozen snapshot capacity qualification',
            'paths-ignore': [r['path'] for r in data['proposed_exclusions']] if arm == 'filtered' else []}

def validate_state(state, expected):
    require(state['languages'] == ['cpp'] and state['buildMode'] == 'none', 'Wrong language/build mode')
    require(state['analysisKinds'] == ['code-scanning'] and state['overlayDatabaseMode'] == 'none', 'Wrong full extraction mode')
    require(state['originalUserInput'] == expected and state['computedConfig'] == expected, 'Changed effective config')
    require(state['extraQueryExclusions'] == [], 'Query filtering is not allowed')

def validate_metadata(text, head, checkout):
    require(re.search(r'^finalised: true\s*$',text,re.M), 'Database not finalized')
    require(re.findall(r'^\s+sha: ([0-9a-f]{40})\s*$',text,re.M) == [head], 'Database metadata has wrong source head')
    require(re.search(r'^\s+cliVersion: 2\.27\.1\s*$',text,re.M) and re.search(r'^buildMode: none\s*$',text,re.M), 'Wrong metadata CLI/build mode')
    require(re.findall(r'^sourceLocationPrefix: (.+)$',text,re.M) == [checkout], 'Wrong database source root')

def validate_workflow_contract(document):
    """Check a YAML-parsed workflow in private tests; runtime binds its reviewed bytes."""
    require(document['on'] == {'push':{'branches':['codex/codeql-extraction-followup']}}, 'Wrong trigger')
    require(set(document['jobs']) == {'control','filtered'}, 'Wrong arm jobs')
    for arm,job in document['jobs'].items():
        require(job['env'] == {'CODEQL_OVERLAY_DATABASE_MODE':'none','EXTRACTION_ARM':arm}, 'Wrong guard arm environment')
        require(job['runs-on'] == 'ubuntu-latest', 'Different runner label')
        if arm == 'filtered':
            require(job['needs'] == 'control' and job['if'] == "${{ always() && needs.control.result != 'cancelled' }}", 'Wrong sequential arm dependency')
        else:
            require('needs' not in job and 'if' not in job, 'Unexpected control dependency')
        steps=job['steps'];require(len(steps)==9, 'Unexpected workflow step')
        require([s.get('run') for s in steps if 'run' in s] == [
            'python3 .github/codeql/extraction/extraction-guard.py '+op
            for op in ('prepare','bundle','initialized','collect','finish')], 'Unexpected workflow command')
        require([s.get('uses') for s in steps if 'uses' in s] == [
            'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803',
            'github/codeql-action/init@'+ACTION,'github/codeql-action/analyze@'+ACTION,
            'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a'], 'Action pins changed')
        require(steps[0]['with'] == {'fetch-depth':0,'persist-credentials':False}, 'Wrong checkout policy')
        require(steps[3]['id']=='init' and steps[3]['with'] == {
            'languages':'c-cpp','build-mode':'none','tools':'${{ runner.temp }}/extraction-bundle.tar.gz',
            'config-file':PREFIX+'cpp-'+arm+'.yml','db-location':'${{ runner.temp }}/extraction-db',
            'trap-caching':False,'dependency-caching':False,'debug':False}, 'Wrong init scope/config')
        require(steps[5]['with'] == {'output':'${{ runner.temp }}/extraction-unused-sarif',
            'skip-queries':True,'upload':'never','upload-database':False,'category':'/private-extraction/'+arm},
            'Wrong no-query/no-upload extraction contract or unobserved resource override')
        require(steps[4]['env'] == steps[6]['env'] == {'CODEQL':'${{ steps.init.outputs.codeql-path }}'}, 'Wrong CLI forwarding')
        require(steps[7]['if']=='always()' and steps[7]['env']=={'OBSERVED_JOB_STATUS':'${{ job.status }}'}, 'Failure evidence not retained')
        require(steps[8]['if']=='always()' and steps[8]['with']=={
            'name':'extraction-'+arm,'path':'${{ runner.temp }}/extraction-results',
            'if-no-files-found':'error','retention-days':14}, 'Wrong artifact isolation')

def manifest(directory):
    result = {}
    for path in sorted(directory.rglob('*')):
        require(not path.is_symlink(), 'Symlink in retained artifacts')
        if path.is_file() and path != directory / 'final-manifest.json':
            result[path.relative_to(directory).as_posix()] = sha(path)
    return result

class Guard:
    def __init__(self):
        self.root = Path.cwd().resolve()
        self.config = self.root / PREFIX
        self.temp = Path(os.environ['RUNNER_TEMP']).resolve()
        self.out = self.temp / 'extraction-results'
        self.db = self.temp / 'extraction-db'
        self.arm = os.environ['EXTRACTION_ARM']
        require(self.arm in ('control', 'filtered'), 'Unknown arm')
        self.git_env = {k:v for k,v in os.environ.items() if not k.startswith('GIT_')}

    def git(self, *args):
        return subprocess.check_output(['git', '--no-replace-objects', *args], cwd=self.root, env=self.git_env, text=True).strip()

    def checked(self, name):
        path = self.root / safe_relative(name)
        require(not any(p.is_symlink() for p in [path, *path.parents] if p != self.root and self.root in [p, *p.parents]), 'Source path contains symlink')
        require(path.is_file(), 'Missing source file: ' + name)
        return path

    def write(self, name, data):
        path = self.out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')

    def resource(self):
        disk = shutil.disk_usage(self.root)
        return {'time_utc_epoch':time.time(), 'disk_total':disk.total, 'disk_used':disk.used, 'disk_free':disk.free}

    def environment(self):
        return {'image_os':os.environ.get('ImageOS'), 'image_version':os.environ.get('ImageVersion'),
                'os_release':Path('/etc/os-release').read_text(), 'architecture':platform.machine(),
                'extraction_env':{key:os.environ.get(key) for key in ENV_KEYS}}

    def scope(self):
        path = self.config / 'scope.json'
        require(sha(path) == SCOPE_SHA, 'Scope inventory changed')
        data = json.loads(path.read_text())
        scope_sets(data)
        for row in data['proposed_exclusions'] + data['previous_main_historical_must_retain'] + data['current_runtime_and_maintained_must_retain']:
            require(sha(self.checked(row['path'])) == row['sha256'], 'Changed scanned source ' + row['path'])
        filtered = ('name: Frozen snapshot capacity qualification\n'
                    '# Only exact newly added historical C/H copies; all prior-main files remain eligible.\npaths-ignore:\n' +
                    ''.join('  - ' + json.dumps(row['path']) + '\n' for row in data['proposed_exclusions']))
        require((self.config / 'cpp-filtered.yml').read_text() == filtered, 'Filtered config changed')
        require((self.config / 'cpp-control.yml').read_text() == 'name: Frozen snapshot capacity qualification\npaths-ignore: []\n', 'Control config changed')
        require(sha(self.checked(WORKFLOW)) == WORKFLOW_SHA, 'Reviewed workflow changed')
        require(sha(self.config/'expected-query-names.json') == EXPECTED_QUERIES_SHA, 'Expected default query names changed')
        for name,digest in QUERY_SHA.items():
            require(sha(self.config / 'queries' / name) == digest, 'Reviewed diagnostic query changed')
        require(not self.git('status', '--porcelain', '--untracked-files=no'), 'Tracked checkout changed')
        return data

    def unchanged(self):
        data = self.scope()
        before = json.loads((self.out / 'before.json').read_text())
        require(before['head'] == self.git('rev-parse', 'HEAD') and before['arm'] == self.arm, 'Head/arm changed')
        require(before['controllers'] == {p:sha(self.checked(p)) for p in sorted(ADDED)}, 'Diagnostic source changed')
        return data, before

    def run(self, name, command):
        start = self.resource()
        result = subprocess.run(command, text=True, capture_output=True)
        for label, content in [('stdout', result.stdout), ('stderr', result.stderr)]:
            path = self.out / 'commands' / (name + '.' + label)
            path.parent.mkdir(exist_ok=True)
            path.write_text(content)
        self.write('commands/' + name + '.json', {'argv':command, 'cwd':str(self.root), 'returncode':result.returncode,
            'before':start, 'after':self.resource(), **{s+'_sha256':sha(self.out/'commands'/(name+'.'+s)) for s in ('stdout','stderr')}})
        require(result.returncode == 0, 'Command failed: ' + name)
        return result.stdout

    def prepare(self):
        require(not self.out.exists(), 'Output already exists')
        self.out.mkdir()
        self.git('merge-base', '--is-ancestor', SOURCE, 'HEAD')
        require(set(self.git('diff', '--name-status', SOURCE, 'HEAD').splitlines()) == {'A\t'+p for p in ADDED}, 'Only exact new diagnostic files may differ')
        require(not self.git('status', '--porcelain', '--untracked-files=all'), 'Initial checkout must be clean')
        self.scope()
        require(os.environ.get('GITHUB_EVENT_NAME') == 'push' and os.environ.get('GITHUB_REF') == 'refs/heads/codex/codeql-extraction-followup', 'Wrong diagnostic branch/event')
        require(os.environ.get('CODEQL_OVERLAY_DATABASE_MODE') == 'none', 'Overlay is not allowed')
        require(self.environment()['image_version'] and self.environment()['image_os'], 'Runner image identity absent')
        self.write('before.json', {'source':SOURCE, 'head':self.git('rev-parse','HEAD'), 'tree':self.git('rev-parse','HEAD^{tree}'),
            'arm':self.arm, 'checkout_root':str(self.root),
            'controllers':{p:sha(self.checked(p)) for p in sorted(ADDED)}, 'environment':self.environment(), 'resources':self.resource()})
        shutil.copyfile(self.config/'scope.json', self.out/'scope.json')

    def bundle(self):
        self.unchanged()
        target = self.temp / 'extraction-bundle.tar.gz'
        require(not target.exists(), 'Bundle target already exists')
        with urllib.request.urlopen(BUNDLE_URL) as response, target.open('xb') as output:
            shutil.copyfileobj(response, output)
        self.write('bundle.json', {'url':BUNDLE_URL, 'sha256':sha(target), 'bytes':target.stat().st_size})
        require(sha(target) == BUNDLE_SHA, 'Official bundle digest mismatch')

    def initialized(self):
        data, before = self.unchanged()
        cli = str(Path(os.environ['CODEQL']).resolve())
        version = json.loads(self.run('codeql-version', [cli,'version','--format=json']))
        require(version['version'] == '2.27.1' and version['sha'] == CLI_SHA, 'Wrong CLI identity')
        temp = Path(os.environ.get('CODEQL_ACTION_TEMP', str(self.temp)))
        state_file, generated, suite = temp/'config', temp/'user-config.yaml', self.db/'cpp/temp/config-queries.qls'
        state = json.loads(state_file.read_text())
        validate_state(state, expected_config(data,self.arm))
        require(Path(state['codeQLCmd']).resolve() == Path(cli) and Path(state['dbLocation']).resolve() == self.db, 'Wrong executable/database')
        paths = json.loads(self.run('resolve-security-suite-only', [cli,'resolve','queries','--format=json',str(suite)]))
        queries = {}
        marker = '/qlpacks/codeql/cpp-queries/1.9.0/'
        for value in paths:
            require(marker in value, 'Wrong bundled query pack')
            key = 'codeql/cpp-queries/' + value.split(marker,1)[1]
            require(key not in queries, 'Duplicate resolved security query')
            p = Path(value)
            queries[key] = {'sha256':sha(p), 'compiled_sha256':sha(p.with_suffix('.qlx'))}
        require(len(queries) == 61 and set(queries) == set(json.loads((self.config/'expected-query-names.json').read_text())), 'Changed default61 suite')
        for name,p in [('action-config.json',state_file),('generated-config.yml',generated),('generated-suite.qls',suite)]:
            shutil.copyfile(p,self.out/name)
        library = Path(cli).parent/'qlpacks/codeql/cpp-all/12.1.1/qlpack.yml'
        require(library.is_file(), 'Wrong cpp-all version')
        self.write('initialized.json', {'source':SOURCE, 'head':before['head'], 'arm':self.arm, 'action_pin':ACTION,
            'scope_inventory_sha256':SCOPE_SHA, 'cli':cli, 'cli_sha256':sha(cli), 'cli_version':version,
            'query_sources':QUERY_SHA, 'security_queries':queries, 'action_config_sha256':sha(state_file),
            'suite_sha256':sha(suite), 'generated_config_sha256':sha(generated), 'cpp_all_metadata_sha256':sha(library),
            'resources':self.resource(), 'environment':self.environment()})
        (self.temp/'extraction-bundle.tar.gz').unlink()

    def collect(self):
        data, before = self.unchanged()
        init = json.loads((self.out/'initialized.json').read_text())
        cli = str(Path(os.environ['CODEQL']).resolve())
        require(cli == init['cli'] and sha(cli) == init['cli_sha256'], 'CLI changed')
        action_temp = Path(os.environ.get('CODEQL_ACTION_TEMP',str(self.temp)))
        for source,key in [(action_temp/'config','action_config_sha256'),(action_temp/'user-config.yaml','generated_config_sha256'),
                           (self.db/'cpp/temp/config-queries.qls','suite_sha256')]:
            require(sha(source) == init[key], 'Effective extraction configuration changed')
        require(not list(self.db.rglob('*.bqrs')), 'Unexpected security query results; extraction-only contract violated')
        metadata = self.db/'cpp/codeql-database.yml'
        require(metadata.is_file(), 'Database metadata absent')
        meta_text = metadata.read_text()
        validate_metadata(meta_text,before['head'],str(self.root))
        require(sha(Path(cli).parent/'qlpacks/codeql/cpp-all/12.1.1/qlpack.yml') == init['cpp_all_metadata_sha256'], 'C++ query library identity changed')
        shutil.copyfile(metadata,self.out/'codeql-database.yml')
        helper = self.temp/'extraction-query-pack'
        require(not helper.exists(), 'Helper directory exists')
        shutil.copytree(self.config/'queries',helper)
        qout = self.out/'queries';qout.mkdir()
        tables = {}
        for name in NAMES:
            query, bqrs, csv_path = helper/(name+'.ql'),qout/(name+'.bqrs'),qout/(name+'.csv')
            require(sha(query) == QUERY_SHA[name+'.ql'], 'Helper source changed')
            self.run(name+'-query',[cli,'query','run','--database='+str(self.db/'cpp'),
                '--search-path='+str(Path(cli).parent/'qlpacks'),'--threads=2','--ram=2048','--max-disk-cache=1024',
                '--common-caches='+str(self.temp/'extraction-query-cache'),'--output='+str(bqrs),str(query)])
            self.run(name+'-decode',[cli,'bqrs','decode','--format=csv','--result-set=#select','--output='+str(csv_path),str(bqrs)])
            tables[name] = {'bqrs_sha256':sha(bqrs), 'csv_sha256':sha(csv_path)}
        require(not list(self.db.rglob('*.bqrs')), 'Unexpected security query results appeared')
        require({name:sha(helper/name) for name in QUERY_SHA} == QUERY_SHA and sha(cli) == init['cli_sha256'], 'Query source or CLI changed during collection')
        self.unchanged()
        coverage = strict_coverage(data,(qout/'files.csv').read_bytes(),self.arm)
        self.write('collection.json', {'status':'COLLECTED','source':SOURCE,'head':before['head'],'arm':self.arm,
            'no_security_bqrs':True,'strict_coverage':coverage,'tables':tables,'environment_after':self.environment(),
            'resources':self.resource(), 'limits':'Distinct facts/body counts are not complete semantics; separate runners are not identical environments.'})
        require(coverage['status'] == 'PASS', 'Strict retained/excluded predicate failed; verdict and tables retained unchanged')

    def finish(self):
        self.out.mkdir(exist_ok=True)
        for source,name in [(self.db/'log','cluster-log'),(self.db/'cpp/log','cpp-log'),(self.db/'cpp/diagnostic','cpp-diagnostic')]:
            if source.exists():
                require(not any(p.is_symlink() for p in [source,*source.rglob('*')]), 'Symlink in raw log tree')
                shutil.copytree(source,self.out/'raw'/name,dirs_exist_ok=True)
        metadata=self.db/'cpp/codeql-database.yml'
        if metadata.is_file():shutil.copyfile(metadata,self.out/'codeql-database.yml')
        self.write('final-resources.json', {'resources':self.resource(),'observed_job_status':os.environ.get('OBSERVED_JOB_STATUS'),
            'arm':self.arm,'security_acceptance':False})
        self.write('final-manifest.json', {'status':'RETAINED-DIAGNOSTICS-NOT-SECURITY-ACCEPTANCE',
            'arm':self.arm,'artifacts':manifest(self.out)})

if __name__ == '__main__':
    require(len(sys.argv)==2 and sys.argv[1] in ('prepare','bundle','initialized','collect','finish'), 'Expected one reviewed operation')
    getattr(Guard(),sys.argv[1])()
