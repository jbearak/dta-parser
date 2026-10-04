#!/usr/bin/env python3
"""PRIVATE DRAFT. Prepare dependencies, then trace actual active C compilation.

This file has not been run. It performs no CodeQL operation itself. The workflow
must place prebuild before init and build between manual init and finalization.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time
import urllib.request

SOURCE = '531600a2c451d42bfaaf42e8d7f69006c6af06af'
BUNDLE_URL = 'https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.1/codeql-bundle-linux64.tar.gz'
BUNDLE_SHA = '1d380f79896ededc654c7b21fafb3360136f1aeb678ad4df4df9af3910c6b815'
HERE = Path(__file__).resolve().parent
PACKAGE = Path('r-package/dtatools')
SDK = {
    'stplugin.c': 'ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d',
    'stplugin.h': '0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b',
}
STRUCTURAL = ('integer-reciprocal', 'long-float-addition',
              'compact-float-domain', 'retained-arithmetic-polling')
FIXTURES = ('initial-capture-userdb.c', 'numeric-bytecode-probe.c',
            'numeric-size-userdb.c')


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def git(root, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    return subprocess.check_output(['git', '--no-replace-objects', *args], cwd=root, env=env)


def verify_source(root, scope):
    require(scope['source'] == SOURCE, 'Wrong source pin')
    require(git(root, 'rev-parse', SOURCE + '^{tree}').decode().strip() == scope['source_tree'], 'Wrong source tree')
    groups = ('active_translation_units', 'active_headers', 'historical_prior_main_43', 'historical_new_117')
    require([len(scope[k]) for k in groups] == [51, 22, 43, 117], 'Scope count changed')
    records = [r for group in groups for r in scope[group]]
    require(len({r['path'] for r in records}) == 233, 'Duplicate scope path')
    # Classify every currently tracked C/C++ source/header/include fragment.
    # The historical labels remain in their original records for attribution;
    # new manual policy is separately declared in active-scope.json.
    extensions = {'.c', '.cc', '.cpp', '.cxx', '.c++', '.h', '.hh', '.hpp', '.hxx', '.h++', '.inc'}
    current = [p.decode() for p in git(root, 'ls-files', '-z').split(b'\0') if p]
    current_c = {p for p in current if Path(p).suffix.lower() in extensions}
    require(current_c == {r['path'] for r in records}, 'Unclassified or removed tracked C/C++/H/inc source')
    for row in records:
        path = root / row['path']
        require(path.is_file() and not path.is_symlink(), 'Missing/nonregular source: ' + row['path'])
        require(sha(path) == row['sha256'], 'Source bytes changed: ' + row['path'])
        require(git(root, 'rev-parse', SOURCE + ':' + row['path']).decode().strip() == row['git_blob'], 'Source blob changed')
    # Bind all original tracked package/build-driver inputs, not only C/H scope.
    tracked = git(root, 'ls-tree', '-r', '-z', SOURCE).split(b'\0')
    paths = []
    for entry in tracked:
        if not entry:
            continue
        _, raw_path = entry.split(b'\t', 1)
        name = raw_path.decode()
        if name.startswith('r-package/dtatools/') or (name.startswith('benchmarks/') and name.endswith(('.py', '.c', '.h')) and '/evidence' not in name and '/results-' not in name):
            paths.append(name)
    require(not git(root, 'diff', '--no-ext-diff', '--name-only', SOURCE, '--', *paths), 'Tracked build inputs differ from source pin')
    package_c = sorted(str(p.relative_to(root)) for p in (root / PACKAGE / 'src').glob('*.c'))
    expected = sorted(r['path'] for r in scope['active_translation_units'] if r['path'].startswith(str(PACKAGE / 'src') + '/'))
    require(package_c == expected and len(expected) == 41, 'Unexpected package C source inventory')
    return {name: sha(root / name) for name in paths}


class Recorder:
    def __init__(self, work, phase):
        self.work, self.phase = work, phase
        self.commands = work / 'commands'
        self.commands.mkdir(exist_ok=True)

    def run(self, label, argv, cwd, extra_env=None):
        identifier = self.phase + '-' + label
        require(re.fullmatch(r'[a-z0-9-]+', identifier), 'Unsafe command label')
        prefix = self.commands / identifier
        require(not prefix.with_suffix('.json').exists(), 'Command receipt already exists')
        # Preserve tracer state. Record selected nonsecret facts, not the environment.
        env = os.environ.copy()
        env.update(R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null',
                   R_MAKEVARS_USER='/dev/null', R_MAKEVARS_SITE='/dev/null',
                   RUSTUP_TOOLCHAIN='1.98.0', CARGO_NET_OFFLINE='true')
        env.update(extra_env or {})
        before = time.time()
        with prefix.with_suffix('.stdout').open('wb') as stdout, prefix.with_suffix('.stderr').open('wb') as stderr:
            result = subprocess.run([str(x) for x in argv], cwd=cwd, env=env, stdout=stdout, stderr=stderr)
        record = dict(argv=[str(x) for x in argv], cwd=str(cwd), returncode=result.returncode,
                      before=before, after=time.time(), stdout_sha256=sha(prefix.with_suffix('.stdout')),
                      stderr_sha256=sha(prefix.with_suffix('.stderr')),
                      tracing_variable_names=sorted(k for k in env if k.startswith(('CODEQL_', 'SEMMLE_'))),
                      environment_policy='Inherited live environment; no tracer-variable filtering. Only declared R/Cargo controls overridden.')
        save(prefix.with_suffix('.json'), record)
        require(result.returncode == 0, 'Command failed: ' + identifier)
        return identifier, prefix.with_suffix('.stdout').read_text()


def immutable_archive(work):
    pre = json.loads((work / 'prebuild.json').read_text())
    require(sha(Path(pre['rust_archive'])) == pre['rust_archive_sha256'], 'Prebuilt Rust archive changed')
    require(sha(Path(pre['makevars'])) == pre['makevars_sha256'], 'Generated Makevars changed')
    return pre


def bundle(work):
    require((work / 'prebuild.json').is_file(), 'Dependency preparation must complete first')
    target = work / 'official-codeql-bundle.tar.gz'
    with urllib.request.urlopen(BUNDLE_URL, timeout=120) as response, target.open('xb') as output:
        shutil.copyfileobj(response, output)
    require(sha(target) == BUNDLE_SHA, 'Official bundle digest differs')
    save(work / 'bundle.json', dict(url=BUNDLE_URL, sha256=BUNDLE_SHA, bytes=target.stat().st_size))


def prebuild(root, work, scope):
    require(not work.exists(), 'Work directory must be fresh')
    work.mkdir(parents=True)
    initial = verify_source(root, scope)
    for key in ('CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'INCLUDE', 'CPPFLAGS'):
        require(not os.environ.get(key), 'Undeclared global include/preprocessor override: ' + key)
    record = Recorder(work, 'prebuild')
    package = root / PACKAGE
    src = package / 'src'
    require(not list(src.glob('*.o')) and not list(src.glob('*.so')), 'Package C outputs must be absent before preparation')
    record.run('r-version', ['R', '--version'], root)
    record.run('rust-version', ['rustc', '--version'], root)
    _, version = record.run('r-semantic-version', ['Rscript', '--vanilla', '-e', 'cat(as.character(getRversion()))'], root)
    require(version.strip() == '4.6.0', 'Unexpected R version')
    record.run('configure', ['sh', 'configure'], package)
    makevars = src / 'Makevars'
    matches = re.findall(r'^RUST_TARGET_DIR\s*=\s*(rust/target/[0-9a-f]+)\s*$', makevars.read_text(), re.M)
    require(len(matches) == 1, 'Ambiguous configured Rust namespace')
    relative_archive = matches[0] + '/release/libdtatools_r.a'
    # Explicit target uses the unchanged package recipe without compiling C.
    record.run('rust-archive', ['make', '-f', 'Makevars', relative_archive], src)
    archive = src / relative_archive
    require(archive.is_file(), 'Rust archive absent')
    require(not list(src.glob('*.o')) and not list(src.glob('*.so')), 'Unexpected C build before CodeQL init')
    _, include_text = record.run('r-include', ['Rscript', '--vanilla', '-e', 'cat(normalizePath(R.home("include")))'], root)
    include = Path(include_text.strip()).resolve(strict=True)
    r_headers = {str(p.relative_to(include)): sha(p) for p in sorted(include.rglob('*.h')) if p.is_file()}
    require({'R.h', 'Rinternals.h', 'Rversion.h', 'R_ext/Altrep.h'} <= set(r_headers), 'Incomplete installed R headers')
    sdk_dir = work / 'stata-sdk'
    sdk_dir.mkdir()
    sdk = {}
    for name, digest in SDK.items():
        url = 'https://www.stata.com/plugins/' + name
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(1024 * 1024 + 1)
        require(len(data) <= 1024 * 1024 and hashlib.sha256(data).hexdigest() == digest, 'Official SPI bytes differ: ' + name)
        (sdk_dir / name).write_bytes(data)
        sdk[name] = dict(url=url, sha256=digest, bytes=len(data))
    require(initial == verify_source(root, scope), 'Source changed during preparation')
    save(work / 'prebuild.json', dict(schema=1, source=SOURCE, head=git(root, 'rev-parse', 'HEAD').decode().strip(),
         root=str(root), work=str(work), scope_sha256=sha(HERE / 'active-scope.json'), controller_sha256=sha(Path(__file__)),
         source_sha256=initial, rust_archive=str(archive), rust_archive_sha256=sha(archive),
         makevars=str(makevars), makevars_sha256=sha(makevars), r_include=str(include), r_headers_sha256=r_headers,
         sdk=sdk, no_package_c_objects_before_init=True,
         scope='Dependency preparation only, before manual CodeQL initialization; not extraction or security acceptance.'))


def r_compile_commands(text, cwd, expected):
    found = {}
    for line in text.splitlines():
        try:
            argv = shlex.split(line)
        except ValueError:
            continue
        if '-c' not in argv:
            continue
        sources = [str((cwd / token).resolve()) for token in argv if token.endswith('.c')]
        for source in sources:
            if source in expected:
                require(source not in found, 'Duplicate C compilation in R transcript')
                found[source] = argv
    require(set(found) == set(expected), 'R transcript does not contain the exact intended C compilations')
    return found


def build(root, work, scope):
    pre = immutable_archive(work)
    require(pre['root'] == str(root) and pre['source'] == SOURCE, 'Preparation belongs to another source')
    require(pre['controller_sha256'] == sha(Path(__file__)) and pre['scope_sha256'] == sha(HERE / 'active-scope.json'), 'Draft changed since preparation')
    require(pre['source_sha256'] == verify_source(root, scope), 'Source changed since preparation')
    # Workflow order and collector-verified actual manual Compilation records,
    # not the mere presence of a CODEQL_* variable, establish tracing.
    record = Recorder(work, 'build')
    src = root / PACKAGE / 'src'
    units = []
    mappings = []
    package_rows = [r for r in scope['active_translation_units'] if r['path'].startswith(str(PACKAGE / 'src') + '/')]
    require(not list(src.glob('*.o')) and not list(src.glob('*.so')), 'Cached package C outputs would suppress extraction')
    argv = ['R', 'CMD', 'SHLIB', '-o', 'dtatools.so'] + [Path(r['path']).name for r in package_rows]
    command_id, stdout = record.run('package', argv, src)
    stderr = (work / 'commands' / (command_id + '.stderr')).read_text()
    require(re.search(r'(?im)^.*\bcargo\s+(?:\+\S+\s+)?build\b', stdout + '\n' + stderr) is None,
            'Cargo unexpectedly ran during traced package C build')
    expected = {str(root / r['path']) for r in package_rows}
    actual = r_compile_commands(stdout, src, expected)
    for row in package_rows:
        units.append(dict(path=row['path'], sha256=row['sha256'], original_source=str(root / row['path']),
                          command_id=command_id, cwd=str(src), compiler_command=actual[str(root / row['path'])],
                          compile_success_basis='Exact transcript invocation and successful make group; collector also requires normal manual Compilation record.'))
    immutable_archive(work)
    # Existing strict drivers compile original C against freshly derived headers.
    for name in STRUCTURAL:
        folder = root / 'benchmarks' / name
        output = work / ('probe-' + name)
        command = ['python3', str(folder / 'work-count.py'), '--output', str(output), '--require-proved']
        if name != 'integer-reciprocal':
            command += ['--root', str(root), '--commit', SOURCE]
        command_id, _ = record.run(name, command, root)
        receipt = json.loads((output / 'receipt.json').read_text())
        require(receipt['exit_code'] == 0, 'Existing structural driver failed')
        original = folder / 'work-count.c'
        units.append(dict(path=str(original.relative_to(root)), sha256=sha(original), original_source=str(original),
                          command_id=command_id, cwd=receipt.get('cwd', str(root)), compiler_command=receipt['command'],
                          driver_receipt=str(output / 'receipt.json'), driver_receipt_sha256=sha(output / 'receipt.json')))
        inputs = receipt['source_sha256']
        for header in sorted(output.glob('*.h')):
            relative = 'r-package/dtatools/src/' + header.name
            same = relative in pre['source_sha256'] and sha(header) == pre['source_sha256'][relative]
            mappings.append(dict(path=str(header), sha256=sha(header), source_path=relative if relative in pre['source_sha256'] else None,
                                 mapping_kind='byte-identical-current-header' if same else 'instrumented-or-extracted-current-source',
                                 source_inputs=inputs, driver_receipt=str(output / 'receipt.json'),
                                 limitation='Derived diagnostic path; never counted as a production-header body.'))
    cc = shutil.which('cc')
    require(cc, 'C compiler absent')
    scalar = root / 'benchmarks/scalar-float-blocks/test-kernel.c'
    scalar_out = work / 'scalar-test-kernel'
    scalar_command = [cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I', str(src), str(scalar), '-lm', '-o', str(scalar_out)]
    command_id, _ = record.run('scalar', scalar_command, root)
    units.append(dict(path=str(scalar.relative_to(root)), sha256=sha(scalar), original_source=str(scalar), command_id=command_id,
                      cwd=str(root), compiler_command=scalar_command, compile_only=True))
    # Direct original-source R compilation preserves tracing and source attribution.
    direct = [('materialization', root / 'benchmarks/compact-materialization/probe.c')]
    direct += [(Path(name).stem, root / PACKAGE / 'tests/testthat/fixtures' / name) for name in FIXTURES]
    for label, original in direct:
        folder = work / label
        folder.mkdir()
        require(not original.with_suffix('.o').exists(), 'Cached standalone R object exists')
        command_id, stdout = record.run(label, ['R', 'CMD', 'SHLIB', '-o', str(folder / (label + '.so')), str(original)], folder)
        actual = r_compile_commands(stdout, folder, {str(original)})
        units.append(dict(path=str(original.relative_to(root)), sha256=sha(original), original_source=str(original), command_id=command_id,
                          cwd=str(folder), compiler_command=actual[str(original)], compile_only=True))
    plugin = root / 'benchmarks/reader-cpu-scaling'
    output = work / 'cpuclock.plugin'
    command_id, _ = record.run('cpuclock', ['python3', str(plugin / 'build-plugin.py'), '--sdk', str(work / 'stata-sdk'),
                                          '--output', str(output), '--compiler', cc], root)
    plugin_receipt = json.loads(output.with_suffix('.json').read_text())
    original = plugin / 'cpuclock.c'
    # This is the exact compile command constructed by the immutable driver.
    compiler_command = [cc, *plugin_receipt['flags'], '-I', str(work / 'stata-sdk'), str(work / 'stata-sdk/stplugin.c'), str(original), '-o', str(output)]
    units.append(dict(path=str(original.relative_to(root)), sha256=sha(original), original_source=str(original), command_id=command_id,
                      cwd=str(root), compiler_command=compiler_command, driver_receipt=str(output.with_suffix('.json')),
                      driver_receipt_sha256=sha(output.with_suffix('.json'))))
    wanted = {r['path'] for r in scope['active_translation_units']}
    require(len(units) == 51 and {r['path'] for r in units} == wanted, 'Incomplete or duplicate active compilation ledger')
    immutable_archive(work)
    require(pre['source_sha256'] == verify_source(root, scope), 'Original tracked source changed during compilation')
    save(work / 'build.json', dict(schema=1, status='COMPILED-NOT-EXTRACTION-ACCEPTED', source=SOURCE, head=pre['head'], root=str(root),
         prebuild_sha256=sha(work / 'prebuild.json'), translation_units=units, generated_header_maps=mappings,
         external_compilation=[dict(path=str(work / 'stata-sdk/stplugin.c'), sha256=SDK['stplugin.c'], role='Pinned SDK support; not one of active51')],
         rust_archive_before_after_equal=True, original_source_before_after_equal=True,
         cargo_build_absent_from_package_transcript=True,
         scope='Successful real C build ledger only. Collector must independently verify manual extraction, includes, bodies and type witnesses.'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('prebuild', 'bundle', 'build'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    root, work = args.root.resolve(), args.work.resolve()
    scope = json.loads((HERE / 'active-scope.json').read_text())
    if args.phase == 'bundle':
        bundle(work)
    else:
        (prebuild if args.phase == 'prebuild' else build)(root, work, scope)


if __name__ == '__main__':
    main()
