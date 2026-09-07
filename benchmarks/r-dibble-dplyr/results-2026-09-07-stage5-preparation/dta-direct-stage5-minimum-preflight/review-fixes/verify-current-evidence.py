"""Verify the current repository archive and its two research-doc files.

The separate receipt binds the index; it is not an external authenticity anchor.
Keep the repository idle while reading this snapshot.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat


ARCHIVE = 'benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/dta-direct-stage5-minimum-preflight'
DOCS = {'docs/research/dplyr-r46-minimum.md', 'docs/research/dplyr-r46-minimum-navigation.md'}
INDEX = ARCHIVE + '/current-archive-index.json'
RECEIPT = ARCHIVE + '/current-archive-receipt.json'
EXCLUDED = {INDEX, RECEIPT}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def identity(root, name):
    path = root/name
    for parent in [path, *path.parents]:
        if parent == root:
            break
        require(not parent.is_symlink(), 'Symlink in evidence path: ' + str(parent))
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode), 'Evidence must be a regular file: ' + name)
    return dict(path=name, bytes=info.st_size, mode=oct(info.st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def inventory(root):
    pending = [root/ARCHIVE]
    require(pending[0].is_dir() and not pending[0].is_symlink(), 'Archive must be a real directory')
    names = set(DOCS)
    while pending:
        with os.scandir(pending.pop()) as children:
            for child in children:
                mode = child.stat(follow_symlinks=False).st_mode
                require(stat.S_ISDIR(mode) or stat.S_ISREG(mode), 'Link or special archive entry: ' + child.path)
                path = Path(child.path)
                if stat.S_ISDIR(mode):
                    pending.append(path)
                else:
                    name = path.relative_to(root).as_posix()
                    if name not in EXCLUDED:
                        names.add(name)
    return [identity(root, name) for name in sorted(names)]


def verify(root):
    root = root.resolve(strict=True)
    receipt_identity = identity(root, RECEIPT)
    receipt = json.loads((root/RECEIPT).read_text())
    index_identity = identity(root, INDEX)
    require(receipt.get('status') == 'complete' and receipt.get('index') == index_identity,
            'Completed receipt does not bind the current index')
    index = json.loads((root/INDEX).read_text())
    require(index.get('excluded') == sorted(EXCLUDED), 'Unexpected index exclusion scope')
    files = index['files']
    names = [row['path'] for row in files]
    require(len(names) == len(set(names)), 'Duplicate indexed path')
    for name in names:
        path = PurePosixPath(name)
        require(name == path.as_posix() and not path.is_absolute() and '..' not in path.parts and
                (name.startswith(ARCHIVE + '/') or name in DOCS) and name not in EXCLUDED,
                'Out-of-scope or noncanonical indexed path: ' + name)
    require(sorted(files, key=lambda row: row['path']) == inventory(root), 'Current archive inventory or file identity mismatch')
    require(identity(root, INDEX) == index_identity and identity(root, RECEIPT) == receipt_identity,
            'Index or receipt changed during verification')
    return dict(status='pass', files=len(files), index_sha256=index_identity['sha256'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.repository), sort_keys=True))


if __name__ == '__main__':
    main()
