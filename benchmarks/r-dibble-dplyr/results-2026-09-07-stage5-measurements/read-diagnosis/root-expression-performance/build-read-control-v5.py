"""Build a separate public-API diagnostic DLL with exact source/header bindings."""
from pathlib import Path
import hashlib
import json
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
CLANG = Path('/Library/Developer/CommandLineTools/usr/bin/clang')
LD = Path('/Library/Developer/CommandLineTools/usr/bin/ld')
HEADERS = Path('/opt/homebrew/Cellar/r/4.6.1/lib/R/include')
SDK = Path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk').resolve(strict=True)


def identity(path):
    resolved = path.resolve(strict=True)
    st = resolved.stat()
    return dict(path=str(path), resolved=str(resolved), bytes=st.st_size,
                mode=oct(st.st_mode & 0o777), sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())


def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)


def changes(rows):
    found = []
    for row in rows:
        try:
            now = identity(Path(row['path']))
        except (OSError, RuntimeError) as error:
            found.append(dict(path=row['path'], error=str(error)))
        else:
            if now != row:
                found.append(dict(path=row['path'], current=now))
    return found


def dependencies(text):
    target, separator, names = text.replace('\\\n', ' ').partition(':')
    if not separator or target.strip() != 'diagnostic':
        raise RuntimeError('Unexpected compiler dependency format')
    return sorted({Path(name).resolve(strict=True) for name in shlex.split(names)})


def main():
    if len(sys.argv) != 2 or Path(sys.argv[1]).name != sys.argv[1] or sys.argv[1] in ('', '.', '..'):
        raise RuntimeError('Usage: build-read-control-v5.py NEW_OUTPUT_NAME')
    output = ROOT / sys.argv[1]
    if output.exists() or output.is_symlink():
        raise RuntimeError('Fresh build output required')
    output.mkdir()
    source = ROOT / 'read-control-v1.c'
    command_prefix = [str(CLANG), '-O2', '-fPIC', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-cast-function-type-mismatch', '-isysroot', str(SDK), '-I', str(HEADERS)]
    before = []
    commands = []
    error = None
    accepted = False
    try:
        link_inputs = [*sorted((SDK / 'usr/lib').glob('libSystem*.tbd')), *sorted((SDK / 'usr/lib/system').glob('*.tbd')), Path('/Library/Developer/CommandLineTools/usr/lib/clang/21/lib/darwin/libclang_rt.osx.a')]
        before = [identity(path) for path in [Path(__file__).resolve(), Path(sys.executable).resolve(), source, CLANG, LD, SDK / 'SDKSettings.json', *link_inputs]]
        write(output / 'preparation-inputs-before.json', dict(inputs=before, sdk=str(SDK)))
        command = [*command_prefix, '-M', '-MT', 'diagnostic', str(source)]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        commands.append(dict(command=command, returncode=result.returncode))
        (output / 'dependency-discovery.txt').write_text(result.stdout)
        (output / 'dependency-discovery.log').write_text(result.stderr)
        if result.returncode or changes(before):
            raise RuntimeError('Header discovery failed or bound preparation input changed')
        headers = dependencies(result.stdout)
        before = [identity(path) for path in sorted({*(Path(row['path']) for row in before), *headers})]
        write(output / 'inputs-before.json', dict(inputs=before,
            scope='Compiler, linker, exact C source, Python executable and all compiler-reported consumed headers are bound. This separate DLL uses unresolved public R API symbols from the existing process. The SDK libSystem stubs and compiler runtime archive are also bound; the macOS linker requires libSystem for a dylib. No second libR is linked. Full compiler/OS runtime closures are not frozen.'))
        command = [*command_prefix, '-dynamiclib', '--ld-path=' + str(LD), '-Wl,-undefined,dynamic_lookup',
                   '-MD', '-MF', str(output / 'compiled-dependencies.txt'), '-MT', 'diagnostic',
                   str(source), '-o', str(output / 'dta_read_control.so')]
        if changes(before):
            raise RuntimeError('Bound input changed before compilation')
        with (output / 'build.log').open('x') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        commands.append(dict(command=command, returncode=result.returncode))
        if result.returncode or changes(before):
            raise RuntimeError('Compile/link failed or bound input changed')
        if dependencies((output / 'compiled-dependencies.txt').read_text()) != headers:
            raise RuntimeError('Compile consumed a different header set')
        accepted = True
    except BaseException as failure:
        error = repr(failure)
        raise
    finally:
        changed = changes(before)
        accepted = accepted and not changed
        write(output / 'execution-result.json', dict(accepted=accepted, commands=commands,
              changed_inputs=changed, error=error))
        products = [identity(path) for path in sorted(output.iterdir()) if path.is_file()]
        write(output / 'manifest.json', dict(products=products, excluded_self='manifest.json',
              excluded_receipt='completed-receipt.json'))
        write(output / 'completed-receipt.json', dict(accepted=accepted, changed_inputs=changed,
              manifest=identity(output / 'manifest.json')))
    if not accepted:
        raise RuntimeError('Native control build not accepted')


if __name__ == '__main__':
    main()
