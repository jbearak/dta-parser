"""Check the two current note copies against preserved preparation records.

Keep the archive idle. This checks six named inputs, not a full inventory or
concurrent-mutation monitor, and does not retroactively strengthen the recipe.
"""
import argparse
import hashlib
import json
from pathlib import Path
import stat


MINIMUM = 'dta-direct-stage5-minimum-preflight/'
RAW = MINIMUM + 'raw/dplyr-r46-minimum.md'
PROMOTED = MINIMUM + 'dplyr-r46-minimum.md'
PINS = {
    'archive-preparation.py': '2fee5f6e3c735d8ef38ec3cd33cba6f7b99be4b370f441d118fbcd3cbc0f098e',
    'inclusion-manifest.json': '16c6a85bc7c83b119a80a1cd51f85f74ff4bda5e19c4d4964e6b105a16bf0ff1',
    'inclusion-receipt.json': 'df46d88b02411236e1721d17f0dd53c3c012750466dcbb8f4fd470b244ddbfdc',
    MINIMUM + 'SHA256SUMS': 'd1afb744bdca3f77a2e249a55b3a0c8cc9ba31319a7879f879740937e7646162',
}
INPUTS = [*PINS, RAW, PROMOTED]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read(root, name):
    path = root / name
    for parent in [path, *path.parents]:
        if parent == root:
            break
        require(not parent.is_symlink(), 'Symlink in note evidence: ' + name)
    require(stat.S_ISREG(path.lstat().st_mode), 'Expected regular file: ' + name)
    return path.read_bytes()


def verify(root):
    root = root.resolve(strict=True)
    contents = {name: read(root, name) for name in INPUTS}
    hashes = {name: hashlib.sha256(value).hexdigest() for name, value in contents.items()}
    for name, expected in PINS.items():
        require(hashes[name] == expected, 'Pinned preparation record changed: ' + name)
    checksum_rows = [line.split('  ', 1) for line in contents[MINIMUM + 'SHA256SUMS'].decode().splitlines()]
    note_hashes = [digest for digest, name in checksum_rows if name == 'raw/dplyr-r46-minimum.md']
    require(len(note_hashes) == 1, 'Expected one raw-note checksum entry')
    manifest = json.loads(contents['inclusion-manifest.json'])
    receipt = json.loads(contents['inclusion-receipt.json'])
    require(receipt['manifest_sha256'] == hashes['inclusion-manifest.json'] and
            receipt['files'] == len(manifest['files']), 'Inclusion receipt mismatch')
    for name in (RAW, PROMOTED):
        require(hashes[name] == note_hashes[0], 'Note differs from pinned preview: ' + name)
        rows = [row for row in manifest['files'] if row['destination'] == name]
        require(len(rows) == 1 and rows[0]['sha256'] == hashes[name] and
                rows[0]['bytes'] == len(contents[name]), 'Inclusion note record mismatch: ' + name)
    require(all(read(root, name) == contents[name] for name in INPUTS),
            'Named input changed during check')
    return dict(status='pass', inputs=len(INPUTS), note_sha256=note_hashes[0],
                scope='Current note consistency; no historical experiment or recipe rerun')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    print(json.dumps(verify(parser.parse_args().archive), sort_keys=True))
