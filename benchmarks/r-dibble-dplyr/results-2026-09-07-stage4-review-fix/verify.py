#!/usr/bin/env python3
"""Verify this archive's indexed bytes and Git-representable executable modes.

The default check is portable and reads only this archive. --originals also
compares retained execution files at their recorded absolute paths and requires
the original full Unix modes. Large external build products are checked only
with --external. No package code, benchmark, build or archived driver executes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import stat


def require(condition, message):
    """Fail under both normal and optimized Python when an invariant differs."""
    if not condition:
        raise RuntimeError(message)


def check_file(path, record, full_mode=False):
    """Check one regular file against its size, digest and recorded mode."""
    require(path.is_file() and not path.is_symlink(), f'Not a regular file: {path}')
    data = path.read_bytes()
    require(len(data) == record['bytes'], f'Size mismatch: {path}')
    require(hashlib.sha256(data).hexdigest() == record['sha256'],
            f'SHA256 mismatch: {path}')
    mode = stat.S_IMODE(path.stat().st_mode)
    expected = int(record['mode'], 8)
    require(bool(mode & 0o111) == bool(expected & 0o111),
            f'Executable-bit mismatch: {path}')
    if full_mode:
        require(mode == expected, f'Unix mode mismatch: {path}')


def main():
    """Check the exact archive inventory, then any explicitly requested inputs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--originals', action='store_true')
    parser.add_argument('--external', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    index = json.loads((root / 'index.json').read_text())
    records = index['files'] + index['authored_files']
    expected = {'index.json'}
    for record in records:
        relative = Path(record['path'])
        require(not relative.is_absolute() and '..' not in relative.parts,
                f'Unsafe archive path: {relative}')
        require(str(relative) not in expected, f'Duplicate archive path: {relative}')
        expected.add(str(relative))
        check_file(root / relative, record)
    actual = {str(path.relative_to(root)) for path in root.rglob('*')
              if path.is_file() or path.is_symlink()}
    require(actual == expected,
            f'Inventory differs: missing={sorted(expected - actual)}, '
            f'extra={sorted(actual - expected)}')
    if args.originals:
        for record in index['files']:
            check_file(Path(record['source_path']), record, full_mode=True)
    if args.external:
        for record in index['external_artifacts']:
            check_file(Path(record['path']), record, full_mode=True)
    print(f'PASS: {len(records)} indexed files plus index.json; '
          f'originals={args.originals}; external={args.external}')


if __name__ == '__main__':
    main()
