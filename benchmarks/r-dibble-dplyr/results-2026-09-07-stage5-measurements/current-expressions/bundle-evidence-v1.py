"""Preserve an explicit evidence selection; verify without extracting tar paths."""
from pathlib import Path, PurePosixPath
import argparse
import gzip
import hashlib
import json
import shutil
import tarfile


def identity(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Expected a regular file: ' + str(path))
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return dict(bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=digest.hexdigest())


def check_file(path, expected):
    observed = identity(path)
    if any(observed[key] != expected[key] for key in observed):
        raise ValueError('File differs from selection: ' + str(path))


def check_selection(selection):
    seen = set()
    for row in selection['files']:
        name = row['path']
        path = PurePosixPath(name)
        if not name or path.is_absolute() or '..' in path.parts or str(path) != name:
            raise ValueError('Noncanonical member path')
        if name in seen or name in ('selection.json', 'records.tar.gz', 'bundle-evidence-v1.py', 'bundle-receipt.json'):
            raise ValueError('Duplicate or reserved member path')
        seen.add(name)
        if row['presentation'] not in ('plain', 'bundle'):
            raise ValueError('Unknown presentation')
        if not isinstance(row['bytes'], int) or row['bytes'] < 0:
            raise ValueError('Invalid member size')
        if not isinstance(row['mode'], str) or not 0 <= int(row['mode'], 8) <= 0o777:
            raise ValueError('Invalid member mode')
        if len(row['sha256']) != 64 or any(c not in '0123456789abcdef' for c in row['sha256']):
            raise ValueError('Invalid member digest')
    if not seen:
        raise ValueError('Empty selection')


def verify(folder):
    receipt_path = folder / 'bundle-receipt.json'
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text())
        check_file(folder / 'selection.json', receipt['selection'])
        check_file(folder / 'bundle-evidence-v1.py', receipt['recipe'])
        check_file(folder / 'records.tar.gz', receipt['archive'])
    selection = json.loads((folder / 'selection.json').read_text())
    check_selection(selection)
    bundled = {row['path']: row for row in selection['files'] if row['presentation'] == 'bundle'}
    plain = [row for row in selection['files'] if row['presentation'] == 'plain']
    for row in plain:
        check_file(folder / row['path'], row)
    seen = set()
    with tarfile.open(folder / 'records.tar.gz', 'r:gz') as archive:
        for member in archive:
            if member.name not in bundled or member.name in seen or not member.isfile():
                raise ValueError('Unexpected, duplicate or nonregular tar member')
            row = bundled[member.name]
            if member.size != row['bytes'] or member.mode != int(row['mode'], 8):
                raise ValueError('Tar member size or mode differs')
            digest = hashlib.sha256()
            total = 0
            with archive.extractfile(member) as stream:
                while block := stream.read(1024 * 1024):
                    total += len(block)
                    digest.update(block)
            if total != row['bytes'] or digest.hexdigest() != row['sha256']:
                raise ValueError('Tar member content differs')
            seen.add(member.name)
    if seen != set(bundled):
        raise ValueError('Missing tar members')
    expected = {row['path'] for row in plain} | {'selection.json', 'records.tar.gz', 'bundle-evidence-v1.py'}
    if (folder / 'bundle-receipt.json').exists():
        expected.add('bundle-receipt.json')
    actual = {str(path.relative_to(folder)) for path in folder.rglob('*') if path.is_file() or path.is_symlink()}
    if actual != expected:
        raise ValueError('Unexpected plain-file inventory')
    return dict(plain_files=len(plain), bundled_files=len(bundled),
                selected_bytes=sum(row['bytes'] for row in selection['files']))


def create(selection_path, output):
    if output.exists() or output.is_symlink():
        raise ValueError('Fresh destination required')
    selection_identity = identity(selection_path)
    recipe = Path(__file__).resolve()
    recipe_identity = identity(recipe)
    selection = json.loads(selection_path.read_text())
    check_selection(selection)
    for row in selection['files']:
        check_file(Path(row['source']), row)
    output.mkdir(parents=True)
    shutil.copy2(selection_path, output / 'selection.json')
    shutil.copy2(recipe, output / 'bundle-evidence-v1.py')
    with (output / 'records.tar.gz').open('xb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for row in selection['files']:
                    source = Path(row['source'])
                    check_file(source, row)
                    if row['presentation'] == 'plain':
                        target = output / row['path']
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source, target)
                    else:
                        member = tarfile.TarInfo(row['path'])
                        member.size = row['bytes']
                        member.mode = int(row['mode'], 8)
                        with source.open('rb') as stream:
                            archive.addfile(member, stream)
    for row in selection['files']:
        check_file(Path(row['source']), row)
    check_file(selection_path, selection_identity)
    check_file(output / 'selection.json', selection_identity)
    check_file(recipe, recipe_identity)
    check_file(output / 'bundle-evidence-v1.py', recipe_identity)
    counts = verify(output)
    receipt = dict(**counts, selection=selection_identity, recipe=recipe_identity,
                   archive=identity(output / 'records.tar.gz'),
                   scope='Explicit selected-byte and mode consistency. Tar contents are read without '
                         'filesystem extraction. No experiment rerun, authenticity assertion, '
                         'concurrent-mutation guarantee, or qualification of omitted runtime inputs.')
    with (output / 'bundle-receipt.json').open('x') as stream:
        json.dump(receipt, stream, indent=2)
        stream.write('\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('create')
    build.add_argument('selection', type=Path)
    build.add_argument('output', type=Path)
    audit = commands.add_parser('verify')
    audit.add_argument('output', type=Path)
    args = parser.parse_args()
    result = create(args.selection, args.output) if args.command == 'create' else verify(args.output)
    print(json.dumps(result))


if __name__ == '__main__':
    main()
