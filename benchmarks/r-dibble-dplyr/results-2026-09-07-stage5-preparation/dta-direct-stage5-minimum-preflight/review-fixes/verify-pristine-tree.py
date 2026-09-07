"""Check a fresh pre-build extraction against a hash-pinned source archive.

This is a new read-only replay guard. It was not used in the historical study.
Only canonical regular-file/directory archives are supported; links and special
members are rejected rather than followed. Nothing is extracted or executed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(stream):
    result = hashlib.sha256()
    while block := stream.read(1024 * 1024):
        result.update(block)
    return result.hexdigest()


def file_digest(path):
    with path.open('rb') as stream:
        return digest(stream)


def inventory(root):
    require(root.is_dir() and not root.is_symlink(), 'Tree must be a real directory')
    entries = {}
    pending = [root]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as children:
            for child in children:
                path = Path(child.path)
                details = child.stat(follow_symlinks=False)
                mode = details.st_mode
                require(stat.S_ISREG(mode) or stat.S_ISDIR(mode),
                        'Link or special filesystem entry: ' + str(path))
                relative = path.relative_to(root).as_posix()
                entries[relative] = dict(kind='file' if stat.S_ISREG(mode) else 'directory',
                    mode=mode & 0o777, bytes=details.st_size if stat.S_ISREG(mode) else None)
                if stat.S_ISDIR(mode):
                    pending.append(path)
    return entries


def verify(archive, tree, expected_sha256):
    require(re.fullmatch('[0-9a-f]{64}', expected_sha256) is not None,
            'Expected a full lowercase archive SHA-256')
    require(archive.is_file() and not archive.is_symlink(), 'Archive must be a regular file')
    require(file_digest(archive) == expected_sha256, 'Archive SHA-256 mismatch')
    expected = {}
    explicit = set()
    with tarfile.open(archive) as source:
        for member in source:
            raw = member.name.rstrip('/') if member.isdir() else member.name
            name = PurePosixPath(raw)
            require(raw and not name.is_absolute() and '..' not in name.parts and
                    raw == name.as_posix() and raw != '.', 'Unsafe or noncanonical archive path: ' + member.name)
            require(raw not in explicit, 'Duplicate archive member: ' + raw)
            require(member.isfile() or member.isdir(), 'Unsupported archive member: ' + raw)
            explicit.add(raw)
            if raw in expected:
                require(expected[raw]['kind'] == 'directory' and member.isdir(),
                        'Archive file/directory conflict: ' + raw)
            expected[raw] = dict(kind='file' if member.isfile() else 'directory',
                mode=member.mode & 0o777, bytes=member.size if member.isfile() else None)
            if member.isfile():
                with source.extractfile(member) as stream:
                    expected[raw]['sha256'] = digest(stream)
            for parent in name.parents:
                if parent == PurePosixPath('.'):
                    continue
                key = parent.as_posix()
                require(key not in expected or expected[key]['kind'] == 'directory',
                        'Archive file/directory conflict: ' + key)
                expected.setdefault(key, dict(kind='directory', mode=None, bytes=None))
    actual = inventory(tree)
    require(set(actual) == set(expected), 'Tree inventory mismatch: ' +
            repr(sorted(set(actual).symmetric_difference(expected))))
    for name, item in expected.items():
        observed = actual[name]
        require(item['kind'] == observed['kind'], 'Entry type mismatch: ' + name)
        require(item['mode'] is None or item['mode'] == observed['mode'], 'Entry mode mismatch: ' + name)
        if item['kind'] == 'file':
            require(item['bytes'] == observed['bytes'] and file_digest(tree/name) == item['sha256'],
                    'File content mismatch: ' + name)
    require(inventory(tree) == actual, 'Tree inventory or metadata changed during verification')
    require(file_digest(archive) == expected_sha256, 'Archive changed during verification')
    return dict(status='pass', archive_sha256=expected_sha256,
        files=sum(item['kind'] == 'file' for item in expected.values()),
        directories=sum(item['kind'] == 'directory' for item in expected.values()),
        scope='New pre-build archive/tree equality check; no runtime/build qualification or historical strengthening.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('tree', type=Path)
    parser.add_argument('archive_sha256')
    args = parser.parse_args()
    print(json.dumps(verify(args.archive, args.tree, args.archive_sha256), sort_keys=True))


if __name__ == '__main__':
    main()
