"""Optional post-transport byte splitting of the already verified canonical archive.

Invoke only if publication needs parts. This neither rebuilds the archive nor
changes evidence selection. Each part is 79 MiB or smaller, strictly under 80 MiB.
"""
from pathlib import Path
import datetime
import hashlib
import json
import stat
import sys

PART_BYTES = 79 * 1024 * 1024
BLOCK_BYTES = 1024 * 1024


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def fact(path):
    p = Path(path)
    st = p.lstat()
    require(stat.S_ISREG(st.st_mode), 'Expected regular file: ' + str(p))
    with p.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(path=str(p), resolved=str(p.resolve(strict=True)), bytes=st.st_size,
                mode=oct(stat.S_IMODE(st.st_mode)), sha256=digest)


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n')


def main():
    require(len(sys.argv) == 4, 'Usage: split.py TRANSPORT_RESULT VERIFIED_STREAM_RESULT FRESH_PARTS_DIRECTORY')
    transport_path, verified_path, output = [Path(p).absolute() for p in sys.argv[1:]]
    require(not output.exists() and not output.is_symlink(), 'Fresh parts directory required')
    attempt = output.with_name(output.name + '-split-attempt.json')
    require(not attempt.exists() and not attempt.is_symlink(), 'Existing split attempt')
    inputs = [fact(Path(__file__).resolve()), fact(transport_path), fact(verified_path)]
    record = dict(status='running', inputs=inputs, output=str(output),
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    write(attempt, record)
    try:
        transport = json.loads(transport_path.read_text())
        verified = json.loads(verified_path.read_text())
        require(transport['status'] == 'complete' and verified['accepted'] is True,
                'Completed transport and independent archive verification required')
        archive = Path(transport['archive']['path'])
        original = fact(archive)
        require(original == transport['archive'], 'Canonical archive differs from accepted transport')
        require(original['sha256'] == verified['archive_sha256'] and
                original['bytes'] == verified['compressed_bytes'], 'Verification binds a different archive')
        require(verified['selection_sha256'] == transport['selection']['sha256'] and
                verified['members'] == transport['members'] and
                verified['uncompressed_bytes'] == transport['uncompressed_bytes'],
                'Verification and transport selection facts differ')
        require(original['bytes'] > PART_BYTES, 'Archive needs no multi-part representation at this part size')
        inputs.append(original)
        output.mkdir()
        parts = []
        with archive.open('rb') as source:
            index = 1
            while True:
                first = source.read(min(BLOCK_BYTES, PART_BYTES))
                if not first:
                    break
                require(index <= 999, 'Three-digit publication part limit exceeded')
                part = output / ('records.tar.gz.part%03d' % index)
                written = len(first)
                with part.open('xb') as target:
                    target.write(first)
                    while written < PART_BYTES:
                        block = source.read(min(BLOCK_BYTES, PART_BYTES - written))
                        if not block:
                            break
                        target.write(block)
                        written += len(block)
                item = fact(part)
                require(0 < item['bytes'] <= PART_BYTES < 80 * 1024 * 1024, 'Invalid part size')
                parts.append(dict(name=part.name, **item))
                index += 1
        require(len(parts) >= 2 and sum(x['bytes'] for x in parts) == original['bytes'], 'Incomplete split')
        # Compare concatenated part bytes directly with the unchanged canonical file.
        joined_hash = hashlib.sha256()
        with archive.open('rb') as canonical:
            for item in parts:
                part_hash = hashlib.sha256()
                with Path(item['path']).open('rb') as stream:
                    while block := stream.read(BLOCK_BYTES):
                        require(canonical.read(len(block)) == block, 'Part concatenation differs from canonical archive')
                        joined_hash.update(block)
                        part_hash.update(block)
                require(part_hash.hexdigest() == item['sha256'], 'Part changed during verification')
            require(canonical.read(1) == b'', 'Canonical archive has unmatched trailing bytes')
        require(joined_hash.hexdigest() == original['sha256'], 'Concatenated digest differs')
        for before in inputs:
            require(fact(before['path']) == before, 'Archive or split input changed')
        manifest = dict(status='complete', archive_name='records.tar.gz', archive=original,
                        transport=inputs[1], independent_verifier_result=inputs[2],
                        part_bytes=PART_BYTES, parts=parts, concatenation_sha256=joined_hash.hexdigest(),
                        concatenation_compared_byte_for_byte=True,
                        scope='Publication representation only. Canonical archive and evidence selection unchanged.')
        write(output / 'archive-parts.json', manifest)
        record.update(status='complete', manifest=fact(output / 'archive-parts.json'),
                      parts=len(parts), compressed_bytes=original['bytes'],
                      archive_sha256=original['sha256'])
    except BaseException as error:
        record.update(status='failed', error=dict(type=type(error).__name__, message=str(error)))
        raise
    finally:
        record['completed_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        record['retained_names'] = sorted(p.name for p in output.iterdir()) if output.is_dir() else []
        attempt.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({k:record[k] for k in ('status', 'parts', 'compressed_bytes', 'archive_sha256')}))


if __name__ == '__main__':
    main()
