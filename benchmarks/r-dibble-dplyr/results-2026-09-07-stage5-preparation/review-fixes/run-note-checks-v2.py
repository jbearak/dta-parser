"""Run version 2 note checks with retained bindings and a separate completion receipt."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def identity(path):
    try:
        resolved = path.resolve(strict=True)
        info = resolved.stat()
        return dict(path=str(path), resolved=str(resolved), bytes=info.st_size,
                    mode=oct(info.st_mode & 0o777),
                    sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())
    except (OSError, RuntimeError) as error:
        return dict(path=str(path), error=str(error))


def write(path, value):
    content = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    output = parser.parse_args().output.absolute()
    if output.exists() or output.is_symlink():
        raise RuntimeError('Fresh output required')
    here = Path(__file__).resolve().parent
    archive = here.parent
    minimum = archive / 'dta-direct-stage5-minimum-preflight'
    python = Path(sys.executable).resolve(strict=True)
    paths = [Path(__file__).resolve(), here / 'verify-note-consistency-v2.py',
             here / 'test-note-consistency-v2.py', here / 'verify-note-consistency.py', python, archive / 'README.md',
             archive / 'archive-preparation.py', archive / 'inclusion-manifest.json',
             archive / 'inclusion-receipt.json', minimum / 'SHA256SUMS',
             minimum / 'raw/dplyr-r46-minimum.md', minimum / 'dplyr-r46-minimum.md']
    before = [identity(path) for path in paths]
    output.mkdir(parents=True)
    write(output / 'inputs-before.json', dict(inputs=before, python=sys.version,
        scope='Version 2 note content/mode consistency and temporary corruption checks; includes the legacy mode-only acceptance witness. Named archive inputs, scripts and invoked Python executable are bound. Full Python and OS runtime closures are not frozen.'))
    commands = []
    status = 'failed'
    failure = None

    def changed_inputs():
        return [dict(before=old, after=identity(path)) for path, old in zip(paths, before)
                if identity(path) != old]

    try:
        if any('error' in row for row in before):
            raise RuntimeError('Missing or unreadable bound input')
        for label, arguments in [
            ('corruption-tests', [str(here / 'test-note-consistency-v2.py')]),
            ('current-note-check', [str(here / 'verify-note-consistency-v2.py'), str(archive)]),
        ]:
            if changed_inputs():
                raise RuntimeError('Bound input changed before ' + label)
            command = [str(python), '-B', *arguments]
            row = dict(label=label, command=command, exit_code=None)
            commands.append(row)
            with (output / (label + '.log')).open('x') as stream:
                row['exit_code'] = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT).returncode
            if row['exit_code'] or changed_inputs():
                raise RuntimeError('Check failed or bound input changed: ' + label)
        status = 'complete'
    except BaseException as error:
        failure = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        changes = changed_inputs()
        if changes:
            status = 'failed'
        write(output / 'execution-result.json', dict(status=status, failure=failure,
              commands=commands, changed_inputs=changes))
        files = [identity(path) for path in sorted(output.rglob('*')) if path.is_file()]
        write(output / 'output-manifest.json', dict(files=files,
              excluded_self='output-manifest.json', excluded_receipt='completed-receipt.json'))
        write(output / 'completed-receipt.json', dict(status=status, changed_inputs=changes,
              manifest=identity(output / 'output-manifest.json')))
    if status != 'complete':
        raise RuntimeError('Note qualification failed')


if __name__ == '__main__':
    main()
