"""Build pinned dependencies in a new clean-R library, preserving each step."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
STUDY = Path('/private/tmp/dta-direct-stage5-minimum-preflight')
R_INSTALL = STUDY / 'r460-clean-install'
OLD_LIBS = [STUDY / 'r460-clean-dplyr-libraries/1.2.1', STUDY / 'r460-clean-dependencies']

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            h.update(block)
    return h.hexdigest()

def identity(path):
    target = path.resolve(strict=True)
    stat = target.stat()
    return dict(path=str(path), resolved=str(target), bytes=stat.st_size,
                mode=oct(stat.st_mode & 0o777), sha256=sha(target))

def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def unchanged(records):
    differences = [item['path'] for item in records if identity(Path(item['path'])) != item]
    if differences:
        raise RuntimeError('Bound inputs changed: ' + repr(differences))

def main():
    output = ROOT / 'dependency-build'
    receipt = ROOT / 'dependency-build-receipt.json'
    if any(path.exists() or path.is_symlink() for path in (output, receipt)):
        raise RuntimeError('Fresh dependency-build and receipt required')
    plan = json.loads((ROOT / 'dependency-plan.json').read_text())
    downloads = json.loads((ROOT / 'source-downloads-receipt.json').read_text())
    if downloads['errors']:
        raise RuntimeError('Source downloads were incomplete')
    sources = {item['package']: item for item in downloads['records']}
    for name in plan['install_order']:
        if sha(Path(sources[name]['archive'])) != sources[name]['sha256']:
            raise RuntimeError('Source archive changed: ' + name)
    historical = json.loads((STUDY / 'manifests/final-installed-files.json').read_text())
    for relative, expected in historical.items():
        if sha(STUDY / relative) != expected:
            raise RuntimeError('Qualified clean installation changed: ' + relative)
    tools = {}
    for name in ['clang', 'cc', 'c++', 'make', 'sh', 'sed', 'tar', 'ar', 'ranlib', 'ld', 'xcrun', 'pkg-config', 'perl']:
        path = shutil.which(name)
        if path is None:
            raise RuntimeError('Missing build tool ' + name)
        tools[name] = Path(path).resolve(strict=True)
    compiler = Path(subprocess.check_output(['/usr/bin/xcrun', '--find', 'clang'], text=True).strip())
    icu_pkgconfig = '/opt/homebrew/Cellar/icu4c@78/78.3/lib/pkgconfig'
    query_env = dict(os.environ, PKG_CONFIG_PATH=icu_pkgconfig)
    icu = Path(subprocess.check_output([str(tools['pkg-config']), '--variable=prefix', 'icu-uc'], env=query_env, text=True).strip()).resolve(strict=True)
    inputs = {Path(__file__).resolve(), ROOT / 'dependency-plan.json',
              ROOT / 'source-downloads-receipt.json', STUDY / 'manifests/final-installed-files.json', compiler}
    inputs.update(tools.values())
    for directory in [R_INSTALL, *OLD_LIBS, ROOT / 'source-downloads', ROOT / 'host-descriptions', icu]:
        inputs.update(path for path in directory.rglob('*') if path.is_file())
    before = [identity(path) for path in sorted(inputs)]
    output.mkdir()
    library = output / 'library'
    library.mkdir()
    (output / 'temp').mkdir()
    env = dict(os.environ)
    cleared = ['R_HOME', 'R_ARCH', 'R_DEFAULT_PACKAGES', 'DYLD_INSERT_LIBRARIES',
               'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH',
               'DYLD_FALLBACK_FRAMEWORK_PATH']
    for name in cleared:
        env.pop(name, None)
    overrides = dict(R_LIBS=os.pathsep.join(map(str, [library, *OLD_LIBS])),
                     R_LIBS_SITE=os.pathsep.join(map(str, OLD_LIBS)),
                     R_LIBS_USER=str(output / 'nonexistent-user-library'),
                     R_MAKEVARS_USER='/dev/null', R_ENVIRON_USER='/dev/null',
                     R_PROFILE_USER='/dev/null', MAKEFLAGS='-j4', TMPDIR=str(output / 'temp'),
                     PKG_CONFIG_PATH=icu_pkgconfig)
    env.update(overrides)
    write(output / 'inputs-before.json', dict(inputs=before, utc=now(),
          environment_overrides=overrides, cleared_environment_keys=cleared,
          tools={name: str(path) for name, path in tools.items()}, icu=str(icu),
          scope='Clean R and prior dependencies, exact archives, compiler/tool binaries, ICU tree. '
                'SDK/OS binaries and complete Python/tool runtime closures are not frozen. '
                'Each later dependency install binds the earlier generated library separately.'))
    results = []
    status = 'failed'
    changed = []
    try:
        for name in plan['install_order']:
            if (library / name).exists():
                raise RuntimeError('Refusing existing package ' + name)
            prior = [identity(path) for path in sorted(library.rglob('*')) if path.is_file()]
            command = [str(R_INSTALL / 'bin/R'), 'CMD', 'INSTALL',
                       '--library=' + str(library), sources[name]['archive']]
            write(output / (name + '-inputs.json'), dict(prior_library=prior,
                  source=sources[name], command=command, started_utc=now()))
            with (output / (name + '.log')).open('x') as log:
                result = subprocess.run(command, cwd=output, env=env,
                                        stdout=log, stderr=subprocess.STDOUT).returncode
            unchanged(prior)
            item = dict(package=name, returncode=result, completed_utc=now(),
                        log=identity(output / (name + '.log')))
            write(output / (name + '-result.json'), item)
            results.append(item)
            print(name, result, flush=True)
            if result:
                raise RuntimeError('Dependency install failed: ' + name)
        status = 'complete'
    finally:
        changed = [item['path'] for item in before if identity(Path(item['path'])) != item]
        write(output / 'execution-result.json', dict(status=status, results=results,
              changed_inputs=changed, completed_utc=now()))
        write(output / 'installed-files.json', dict(files=[identity(path) for path in
              sorted(library.rglob('*')) if path.is_file()]))
        products = [identity(path) for path in sorted(output.rglob('*')) if path.is_file()]
        manifest = output / 'output-manifest.json'
        write(manifest, dict(products=products, excluded_self=str(manifest)))
        write(receipt, dict(status=status, changed_inputs=changed, manifest=identity(manifest)))
    if status != 'complete' or changed:
        raise RuntimeError('Dependency setup failed; inspect preserved receipt')

if __name__ == '__main__':
    main()
