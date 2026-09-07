"""Run new guard tests and one fresh extraction check with retained bindings.

This does not run R, build packages or repeat the historical version study.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile


def identity(path):
    resolved = path.resolve(strict=True)
    info = resolved.stat()
    return dict(path=str(path), resolved=str(resolved), bytes=info.st_size,
        mode=oct(info.st_mode & 0o777), sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())


def write(path, value):
    content = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(content)


def changes(records):
    result = []
    for row in records:
        try:
            observed = identity(Path(row['path']))
        except (OSError, RuntimeError) as error:
            result.append(dict(path=row['path'], error=str(error)))
        else:
            if observed != row:
                result.append(dict(path=row['path'], current=observed))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('archive_sha256')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise RuntimeError('Fresh output required')
    here = Path(__file__).resolve().parent
    sources = [here/name for name in ['run-checks.py', 'test-verify-pristine-tree.py', 'verify-pristine-tree.py', 'verify-current-evidence.py', 'test-verify-current-evidence.py']]
    python = str(Path(sys.executable).resolve(strict=True))
    before = [identity(path) for path in sources + [Path(python), args.archive]]
    if before[-1]['sha256'] != args.archive_sha256:
        raise RuntimeError('Pinned source archive does not match')
    args.output.mkdir(parents=True)
    write(args.output/'inputs-before.json', dict(inputs=before, python=sys.version,
        archive_sha256=args.archive_sha256,
        scope='New synthetic guard tests and fresh dplyr source extraction check. Exact scripts, Python executable and archive are bound; full Python/OS runtime closures are not frozen.'))
    commands = []
    status = 'failed'
    failure = None

    def run(label, command):
        if changes(before):
            raise RuntimeError('Bound inputs changed before ' + label)
        with (args.output/(label+'.log')).open('x') as stream:
            code = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT).returncode
        commands.append(dict(label=label, command=command, exit_code=code))
        if code or changes(before):
            raise RuntimeError('Check failed or inputs changed: ' + label)

    try:
        run('synthetic', [python, '-B', str(here/'test-verify-pristine-tree.py')])
        run('current-index-synthetic', [python, '-B', str(here/'test-verify-current-evidence.py')])
        tree = args.output/'fresh-extraction'
        tree.mkdir()
        with tarfile.open(args.archive) as archive:
            for member in archive.getmembers():
                raw = member.name.rstrip('/') if member.isdir() else member.name
                path = PurePosixPath(raw)
                if not raw or path.is_absolute() or '..' in path.parts or raw != path.as_posix() or raw == '.' or not (member.isfile() or member.isdir()):
                    raise RuntimeError('Only canonical files/directories can be extracted')
            archive.extractall(tree, filter='data')
            # The safe extraction filter removes group-write bits and directory
            # modes. Restore the pinned archive modes only in this fresh tree.
            for member in archive.getmembers():
                (tree/member.name).chmod(member.mode & 0o777)
        run('fresh-source', [python, '-B', str(here/'verify-pristine-tree.py'),
            str(args.archive), str(tree), args.archive_sha256])
        status = 'complete'
    except BaseException as error:
        failure = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        changed = changes(before)
        if changed:
            status = 'failed'
        write(args.output/'execution-result.json', dict(status=status, failure=failure,
            commands=commands, changed_inputs=changed))
        files = [identity(path) for path in sorted(args.output.rglob('*')) if path.is_file()
            and path not in (args.output/'output-manifest.json', args.output/'completed-receipt.json')]
        write(args.output/'output-manifest.json', dict(files=files,
            excluded_self='output-manifest.json', excluded_receipt='completed-receipt.json'))
        write(args.output/'completed-receipt.json', dict(status=status, changed_inputs=changed,
            manifest=identity(args.output/'output-manifest.json')))
    if status != 'complete':
        raise RuntimeError('Guard qualification failed')


if __name__ == '__main__':
    main()
