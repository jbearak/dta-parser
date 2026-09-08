"""Copy explicitly selected, completed host evidence into a fresh archive."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parent
ORIGIN = ROOT / 'implementation'
SELECTION = ROOT / 'combined-host-selection-v1.json'
README = ROOT / 'combined-host-README-v1.md'
SOURCE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
PINS = {
    'candidate-combined-01/completed-receipt.json': 'fe4d3dfdeba63d6401becb4f7f41383812b7545383c86a4c0abf17b3c290a38e',
    'full-combined-01/receipt.json': 'a8901fe26df3acdecaa4d1a151aa6f0d9f9f654a7f09bccdcb8fa7d6d5352cec',
    'rust-combined-01/receipt.json': 'd919155ad571711c265212474c82dd706046c3f437d26ba134626ba72e211b68',
    'package-combined-01/receipt.json': 'a015a466e8de2d0314bf28b49eb29a5533b423e17de4839944aa3f43297a892d',
    'native-combined-01/receipt.json': 'dd931f0abc8781478bac62e71dc349124432fa4eceaebf7c7c70735261e76b35',
}


def identity(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('Expected a regular source file: ' + str(path))
    data = path.read_bytes()
    return dict(bytes=len(data), mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(data).hexdigest())


def matches(path, expected):
    actual = identity(path)
    if any(actual[key] != expected[key] for key in actual):
        raise RuntimeError('Changed selected record: ' + str(path))


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def main():
    if len(sys.argv) != 2:
        raise RuntimeError('Expected a fresh archive destination')
    output = Path(sys.argv[1]).absolute()
    if output.exists() or output.is_symlink():
        raise RuntimeError('Refusing an existing destination')
    selection = json.loads(SELECTION.read_text())
    if selection['source'] != SOURCE or len(selection['files']) != 150:
        raise RuntimeError('Unexpected source or selection size')
    gate_products = {}
    for relative, digest in PINS.items():
        receipt_path = ORIGIN / relative
        observed = identity(receipt_path)
        if observed['sha256'] != digest:
            raise RuntimeError('Changed pinned receipt: ' + relative)
        receipt = json.loads(receipt_path.read_text())
        if receipt['status'] != 'complete' or receipt.get('changed_inputs', receipt.get('changed_bound_inputs')):
            raise RuntimeError('Gate did not complete with unchanged inputs')
        if receipt.get('source_sha', receipt.get('revision')) != SOURCE:
            raise RuntimeError('Wrong gate source')
        manifest_path = Path(receipt['manifest']['path'])
        matches(manifest_path, receipt['manifest'])
        products = json.loads(manifest_path.read_text())['products']
        gate_products.update({item['path']: item for item in products})
        gate_products[str(receipt_path)] = observed
        gate_products[str(manifest_path)] = receipt['manifest']
    rows = selection['files']
    seen = set()
    gate_count = 0
    for row in rows:
        relative = Path(row['path'])
        if relative.is_absolute() or '..' in relative.parts or relative in seen:
            raise RuntimeError('Unsafe or duplicate archive path')
        seen.add(relative)
        source = ORIGIN / relative
        if row['source'] != str(source):
            raise RuntimeError('Unexpected selected source')
        matches(source, row)
        if relative.parts[0] not in ('api-review', 'semantics-review'):
            if str(source) not in gate_products:
                raise RuntimeError('Gate file is absent from completed receipt or manifest')
            matches(source, gate_products[str(source)])
            gate_count += 1
    if gate_count != 116:
        raise RuntimeError('Unexpected selected gate count')
    wrappers = [(Path(__file__).resolve(), 'archive-combined-host-v1.py'),
                (SELECTION, 'selection.json'), (README, 'README.md')]
    additions = [dict(source=str(path), path=name, **identity(path))
                 for path, name in wrappers]
    if seen.intersection(Path(row['path']) for row in additions):
        raise RuntimeError('Archive wrapper collides with selection')
    all_rows = rows + additions
    output.mkdir(parents=True)
    for row in all_rows:
        source = Path(row['source'])
        target = output / row['path']
        matches(source, row)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        matches(target, row)
    for row in all_rows:
        matches(Path(row['source']), row)
        matches(output / row['path'], row)
    write(output / 'inclusion-manifest.json', dict(
        source=SOURCE, package_tree=selection['package_tree'], files=all_rows,
        scope='Selected original host gates and reviews, plus archive wrappers. '
              'Idle-file byte/mode consistency only. No workload rerun, full original '
              'input revalidation, complete replay bundle, or concurrent-mutation guarantee.'))
    write(output / 'inclusion-receipt.json', dict(
        files=len(all_rows), selected_gate_files=gate_count,
        manifest=identity(output / 'inclusion-manifest.json')))
    print(json.dumps(dict(files=len(all_rows) + 2,
                          copied_bytes=sum(row['bytes'] for row in all_rows),
                          receipt=identity(output / 'inclusion-receipt.json'))))


if __name__ == '__main__':
    main()
