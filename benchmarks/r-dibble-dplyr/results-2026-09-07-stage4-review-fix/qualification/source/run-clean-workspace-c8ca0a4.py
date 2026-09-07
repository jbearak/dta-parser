"""Rerun the five core gates with complete per-command clean input proofs."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import stat
import subprocess
import time

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'workspace-c8ca0a4'
OUTPUT = HERE / 'workspace-gates-c8ca0a4'
REVISION = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'


def require(condition, message):
    """Stop before using an input that fails its declared identity."""
    if not condition:
        raise RuntimeError(message)


def git(*args):
    """Read exact Git output, rejecting command failures."""
    return subprocess.run(['git', *args], cwd=SOURCE, check=True,
                          capture_output=True).stdout


def digest(data):
    """Return a byte identity for source and execution records."""
    return hashlib.sha256(data).hexdigest()


def snapshot():
    """Bind every tracked source byte and reject every extra working file."""
    require(git('rev-parse', 'HEAD').decode().strip() == REVISION, 'Wrong HEAD')
    status = git('status', '--porcelain=v1', '--untracked-files=all', '--ignored')
    require(not status, 'Unclean source, including ignored files: ' + status.decode())
    rows = []
    for entry in git('ls-tree', '-r', '-z', 'HEAD').split(b'\0'):
        if not entry:
            continue
        fields, name = entry.split(b'\t', 1)
        mode, kind, blob = fields.decode().split()
        path = name.decode()
        file = SOURCE / path
        require(kind == 'blob' and mode in ('100644', '100755', '120000'), 'Unsupported entry')
        info = file.lstat()
        if mode == '120000':
            require(stat.S_ISLNK(info.st_mode), 'Changed symlink type')
            data = os.readlink(file).encode()
        else:
            require(stat.S_ISREG(info.st_mode), 'Changed regular file type')
            actual_mode = '100755' if info.st_mode & 0o111 else '100644'
            require(actual_mode == mode, 'Changed mode: ' + path)
            data = file.read_bytes()
        actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        require(actual_blob == blob, 'Changed source bytes: ' + path)
        rows.append({'path': path, 'mode': mode, 'blob': blob,
                     'bytes': len(data), 'sha256': digest(data)})
    encoded = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()
    return {'source_sha': REVISION, 'source_tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
            'package_tree': git('rev-parse', 'HEAD:r-package/dtatools').decode().strip(),
            'workspace_inputs': rows, 'workspace_inputs_sha256': digest(encoded),
            'clean_status_including_ignored': status.decode(),
            'manifest_objects': {path: git('rev-parse', 'HEAD:' + path).decode().strip()
                                 for path in ('Cargo.toml', 'Cargo.lock', 'r-package/dtatools/src/dta-tools')}}


def write_json(path, value):
    """Create an evidence record once without overwriting prior attempts."""
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


require(not OUTPUT.exists(), 'Output already exists')
initial = snapshot()
OUTPUT.mkdir()
write_json(OUTPUT / 'initial-inputs.json', initial)
environment = os.environ.copy()
environment['CARGO_TARGET_DIR'] = str(HERE / 'workspace-target-c8ca0a4')
environment['RUSTDOCFLAGS'] = '-D warnings'
require(not Path(environment['CARGO_TARGET_DIR']).exists(), 'Target directory already exists')
versions = {tool: subprocess.run(args, check=True, capture_output=True, text=True).stdout
            for tool, args in [('cargo', ['cargo', '-vV']), ('rustc', ['rustc', '-vV'])]}
commands = [
    ('fmt', ['cargo', 'fmt', '--all', '--', '--check']),
    ('clippy', ['cargo', 'clippy', '--workspace', '--all-targets', '--locked', '--offline', '--', '-D', 'warnings']),
    ('tests', ['cargo', 'test', '--workspace', '--all-targets', '--locked', '--offline']),
    ('doc', ['cargo', 'doc', '--workspace', '--locked', '--offline', '--no-deps']),
    ('package', ['cargo', 'package', '-p', 'dta-tools', '--locked', '--offline']),
]
manifest = {'source_sha': REVISION, 'source_directory': str(SOURCE),
            'driver_sha256': digest(Path(__file__).read_bytes()), 'versions': versions,
            'environment': {key: environment.get(key) for key in
                            ('CARGO_TARGET_DIR', 'CARGO_HOME', 'RUSTUP_TOOLCHAIN', 'RUSTFLAGS', 'RUSTDOCFLAGS')},
            'source_inputs_sha256': initial['workspace_inputs_sha256'], 'commands': [],
            'disposition': 'Fresh final-source supplemental qualification; historical reuse proof is preserved separately.'}
for name, command in commands:
    before = snapshot()
    require(before == initial, 'Inputs changed before ' + name)
    write_json(OUTPUT / (name + '-before.json'), before)
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    timer = time.monotonic()
    log = OUTPUT / (name + '.log')
    with log.open('xb') as stream:
        process = subprocess.run(command, cwd=SOURCE, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    after = snapshot()
    write_json(OUTPUT / (name + '-after.json'), after)
    record = {'name': name, 'command': command, 'started_utc': start,
              'elapsed_seconds': time.monotonic() - timer, 'exit_code': process.returncode,
              'before_sha256': digest((OUTPUT / (name + '-before.json')).read_bytes()),
              'after_sha256': digest((OUTPUT / (name + '-after.json')).read_bytes()),
              'log_sha256': digest(log.read_bytes()), 'log_bytes': log.stat().st_size,
              'inputs_identical': before == after == initial}
    manifest['commands'].append(record)
    write_json(OUTPUT / (name + '-result.json'), record)
    print(name, process.returncode, round(record['elapsed_seconds'], 3), flush=True)
    require(process.returncode == 0, 'Gate failed: ' + name)
    require(after == initial, 'Inputs changed after ' + name)
final = snapshot()
write_json(OUTPUT / 'final-inputs.json', final)
require(final == initial, 'Final source changed')
write_json(OUTPUT / 'manifest.json', manifest)
print('All five clean exact-source workspace gates passed', flush=True)
