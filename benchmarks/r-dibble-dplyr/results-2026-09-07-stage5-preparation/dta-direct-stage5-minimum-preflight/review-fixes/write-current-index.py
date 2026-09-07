"""Create a new current-copy index and separate receipt, without overwriting either."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys


spec = importlib.util.spec_from_file_location('current_evidence', Path(__file__).with_name('verify-current-evidence.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    root = parser.parse_args().repository.resolve(strict=True)
    guard.require(all(not (root/name).exists() and not (root/name).is_symlink() for name in guard.EXCLUDED),
                  'Fresh index and receipt paths required')
    files = guard.inventory(root)
    guard.require(files == guard.inventory(root), 'Current evidence changed before index creation')
    write(root/guard.INDEX, dict(files=files, excluded=sorted(guard.EXCLUDED),
        scope='Current repository inclusion bytes and observed modes. Historical records remain unchanged. Generated fresh source trees and other original external artifacts remain outside this selective archive.'))
    write(root/guard.RECEIPT, dict(status='complete', index=guard.identity(root, guard.INDEX),
        files=len(files), python_executable=str(Path(sys.executable).resolve()),
        scope='Separate current-index completion binding; no historical or runtime qualification claim.'))
    print(json.dumps(guard.verify(root), sort_keys=True))


if __name__ == '__main__':
    main()
