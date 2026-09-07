"""Bind two completed manifests and check every non-self recorded file digest.

Their historical writers recorded the empty SHA256 of their own open output.
This audit preserves those bytes, verifies the exact known self-entry, and
records each completed manifest's digest outside that manifest. It executes no
R, package, benchmark or historical audit code.
"""
import argparse
import hashlib
import json
from pathlib import Path


def sha(path):
    """Return a regular input file's digest without following a symbolic link."""
    if not path.is_file() or path.is_symlink():
        raise RuntimeError('Expected regular file: '+str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    """Read the retained manifests, reject unrelated discrepancies, then write."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.output.exists():
        raise RuntimeError('Output already exists: '+str(args.output))
    cases=[('diagnosis/root-probes-final/manifest.json','files',
            '2cf32127a3db35bb1a4254a704659ed7d9974f2c21714dca6dfabaddef19b2a4'),
           ('qualification/root-219/post-run-audit.json','raw_files',
            '97c6dfc382ab72817e134fc5164501ed534f6cc98f97b7f5f6a227eeb30d318c')]
    records=[]
    for relative,key,expected in cases:
        path=args.archive/relative
        if sha(path)!=expected:
            raise RuntimeError('Completed historical manifest differs: '+relative)
        entries=json.loads(path.read_text())[key]
        empty=hashlib.sha256(b'').hexdigest()
        if entries.get(path.name)!=empty:
            raise RuntimeError('Known self-output observation differs: '+relative)
        checked=[]
        for name,digest in entries.items():
            if name==path.name:
                continue
            part=Path(name)
            if part.is_absolute() or len(part.parts)!=1:
                raise RuntimeError('Unexpected file entry: '+name)
            actual=sha(path.parent/part)
            if actual!=digest:
                raise RuntimeError('Non-self input differs: '+str(path.parent/part))
            checked.append({'path':str((Path(relative).parent/part)), 'sha256':actual})
        records.append({'path':relative,'completed_sha256':expected,
                        'historical_self_entry':empty,'non_self_files':checked})
    result={'auditor_sha256':sha(Path(__file__).resolve()),'manifests':records,
            'non_self_file_count':sum(len(x['non_self_files']) for x in records),
            'scope':'Historical self entries observed an empty output in progress. All non-self digests match. Completed manifest bytes are bound here, without rewriting or rerunning any historical artifact.'}
    with args.output.open('x') as f:
        json.dump(result,f,indent=2);f.write('\n')
    print('PASS:',result['non_self_file_count'],'non-self files and two completed manifests')


if __name__=='__main__':
    main()
