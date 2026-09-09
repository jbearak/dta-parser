"""Launch the reviewed Stage7 memory wrapper sequentially with selected source records."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def identity(path):
    path = Path(path)
    return dict(path=str(path), resolved=str(path.resolve(strict=True)),
                bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_sha')
    parser.add_argument('installation', type=Path)
    parser.add_argument('receipt_sha')
    parser.add_argument('output', type=Path)
    parser.add_argument('--predecessor', action='store_true')
    args = parser.parse_args()
    p = Path(__file__).resolve().parent
    python = '/opt/homebrew/Cellar/python@3.14/3.14.7/bin/python3.14'
    if args.predecessor and args.source_sha != '4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c':
        raise RuntimeError('Fixed reference requires exact predecessor')
    routes = ['public', 'predecessor_safe_reference'] if args.predecessor else ['public']
    paths = [Path(__file__).resolve(), python, sys.executable, p / 'run-memory-v2.py',
             p / 'memory-v2.R', p / 'entry-v2.R', p / 'README-memory-v2.md',
             *sorted((p / 'support-v2').iterdir()), '/opt/homebrew/bin/git',
             '/opt/homebrew/Cellar/r/4.6.1/bin/Rscript', '/usr/bin/time',
             args.installation / 'completed-receipt.json']
    selected = [identity(path) for path in paths]
    args.output.mkdir(parents=True, exist_ok=False)
    commands = []
    for workload in ['group_modify_identity', 'group_nest', 'nest_by']:
        for rows in [100000, 1000000]:
            for route in (routes if rows == 100000 else list(reversed(routes))):
                commands.append([python, '-I', '-B', str(p / 'run-memory-v2.py'),
                    '/Users/jmb/repos/dta-parser', 'f3b8b984c6a9ea5a0f062eee70e392bb567e5042',
                    str(args.installation), args.source_sha,
                    str(args.output / (str(rows) + '-' + workload + '-' + route)),
                    '--receipt-sha256', args.receipt_sha, '--rows', str(rows),
                    '--script', str(p / 'memory-v2.R'), '--routes', route, '--workload', workload])
    write(args.output / 'launch.json', dict(commands=commands, selected=selected,
        python_invocation=sys.orig_argv, PATH=os.environ.get('PATH'), started_utc=now(),
        scope='Sequential quiet-window memory cases; each reviewed wrapper binds its own accepted installation and runtime. '
              'This outer record binds selected launch sources/endpoints, not complete Python or child image closure. '
              'Predecessor public memory is read-only and retains its known foreign-write defect.'))
    records, error = [], None
    try:
        for index, command in enumerate(commands):
            if [identity(path) for path in paths] != selected:
                raise RuntimeError('Selected batch inputs changed')
            record = dict(command=command, started_utc=now(), returncode=None, error=None)
            write(args.output / (str(index) + '-before.json'), record)
            try:
                record['returncode'] = subprocess.run(command).returncode
            except BaseException as failure:
                record['error'] = dict(type=type(failure).__name__, message=str(failure))
                raise
            finally:
                record['completed_utc'] = now()
                records.append(record)
                write(args.output / (str(index) + '-result.json'), record)
            if record['returncode']:
                raise RuntimeError('Memory case failed; partial products retained')
            print('Completed memory case', index + 1, 'of', len(commands), flush=True)
    except BaseException as failure:
        error = dict(type=type(failure).__name__, message=str(failure))
        raise
    finally:
        final_identity_error = None
        try:
            unchanged = [identity(path) for path in paths] == selected
        except BaseException as failure:
            unchanged = False
            final_identity_error = dict(type=type(failure).__name__, message=str(failure))
        write(args.output / 'result.json', dict(records=records, error=error,
            final_identity_error=final_identity_error,
            inputs_unchanged=unchanged, finished_utc=now(),
            status='complete' if error is None and unchanged and len(records) == len(commands) else 'failed'))
    if not unchanged:
        raise RuntimeError('Selected batch inputs changed')


if __name__ == '__main__':
    main()
