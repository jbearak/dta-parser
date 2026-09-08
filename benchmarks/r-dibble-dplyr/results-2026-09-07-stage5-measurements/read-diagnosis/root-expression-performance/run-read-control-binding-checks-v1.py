"""Run the bounded artifact-binding tests with pre/post input identities."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def identity(path):
    resolved = path.resolve(strict=True)
    info = resolved.stat()
    return dict(path=str(path), resolved=str(resolved), bytes=info.st_size,
                mode=oct(info.st_mode & 0o777), sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())


def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)


def main():
    if len(sys.argv) != 2 or Path(sys.argv[1]).name != sys.argv[1] or sys.argv[1] in ('', '.', '..'):
        raise RuntimeError('Fresh direct output name required')
    output = ROOT / sys.argv[1]
    if output.exists() or output.is_symlink():
        raise RuntimeError('Fresh output required')
    python = Path(sys.executable).resolve(strict=True)
    paths = [Path(__file__).resolve(), python, ROOT / 'test-read-control-bindings-v1.py', ROOT / 'read-control-v2.py']
    before = [identity(path) for path in paths]
    output.mkdir()
    write(output / 'inputs-before.json', dict(inputs=before,
          scope='Eight temporary-file binding tests; no R, native controls or timings. Full Python/OS runtime closures are not frozen.'))
    command = [str(python), '-B', str(ROOT / 'test-read-control-bindings-v1.py')]
    result = None
    error = None
    try:
        if [identity(path) for path in paths] != before:
            raise RuntimeError('Test input changed before launch')
        with (output / 'tests.log').open('x') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT).returncode
    except BaseException as failure:
        error = repr(failure)
        raise
    finally:
        changes = []
        for path, old in zip(paths, before):
            try:
                now = identity(path)
            except (OSError, RuntimeError) as failure:
                changes.append(dict(path=str(path), error=str(failure)))
            else:
                if now != old:
                    changes.append(dict(path=str(path), current=now))
        accepted = result == 0 and not changes and error is None
        write(output / 'execution-result.json', dict(command=command, returncode=result,
              changed_inputs=changes, error=error, accepted=accepted))
        products = [identity(path) for path in sorted(output.iterdir()) if path.is_file()]
        write(output / 'manifest.json', dict(products=products, excluded_self='manifest.json',
              excluded_receipt='completed-receipt.json'))
        write(output / 'completed-receipt.json', dict(accepted=accepted,
              manifest=identity(output / 'manifest.json')))
    if not accepted:
        raise RuntimeError('Binding checks failed; inspect preserved records')


if __name__ == '__main__':
    main()
