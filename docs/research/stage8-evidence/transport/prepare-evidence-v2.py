"""Select and transport retained Stage8 records; never rerun their workloads."""
from pathlib import Path, PurePosixPath
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
import re
import stat
import tarfile

V = Path('/private/tmp/dta-direct-stage8-validation')
P = V / 'publication-preparation'
ROOT_MAP = Path('/private/tmp/dta-direct-stage8-performance-preparation-01/root-artifact-selection-01.json')
ROOT_SHA = '1b351cdf6a4184966105964ce094ac2df071f30bf6f250ca67bfebba4f97d16f'
SELECTION = P / 'evidence-selection-02.json'
OUTPUT = P / 'bundle-02'

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def fact(path):
    p = Path(path)
    st = p.lstat()
    require(stat.S_ISREG(st.st_mode), 'Selected input is not a regular file: ' + str(p))
    r = p.resolve(strict=True)
    return dict(path=str(p), resolved=str(r), bytes=st.st_size,
                mode=oct(stat.S_IMODE(st.st_mode)), sha256=sha(p.read_bytes()))

def member(path):
    p = PurePosixPath(path)
    require(p.is_absolute() and '..' not in p.parts and str(p).startswith('/private/tmp/'), 'Invalid selected source path')
    return 'records/' + str(p.relative_to('/private/tmp'))

def validate(entries):
    paths, members = set(), set()
    for row in entries:
        require(set(['path','resolved','bytes','mode','sha256','member']).issubset(row), 'Incomplete identity')
        require(isinstance(row['bytes'],int) and not isinstance(row['bytes'],bool) and row['bytes'] >= 0, 'Invalid byte count')
        require(isinstance(row['sha256'],str) and re.fullmatch('[0-9a-f]{64}',row['sha256']) is not None, 'Invalid digest')
        require(isinstance(row['mode'],str) and re.fullmatch('0o[0-7]{3,4}',row['mode']) is not None, 'Invalid mode')
        require(row['member'] == member(row['path']), 'Incorrect archive member')
        require(row['path'] not in paths and row['member'] not in members, 'Duplicate selected path/member')
        require(PurePosixPath(row['resolved']).is_absolute(), 'Invalid resolved path')
        paths.add(row['path']); members.add(row['member'])
    require(bool(entries), 'Empty selection')

def select():
    root_fact = fact(ROOT_MAP)
    require(root_fact['sha256'] == ROOT_SHA, 'Root handoff map changed')
    root = json.loads(ROOT_MAP.read_text())
    require(len(root['files']) == root['file_count'], 'Root selection count differs')
    selected = {}
    def add(path, category, expected=None):
        row = fact(path)
        if expected:
            require(all(row[k] == expected[k] for k in ['path','resolved','bytes','sha256']), 'Root selected bytes changed: '+str(path))
        row['member'] = member(row['path'])
        if row['path'] in selected:
            require(all(selected[row['path']][k] == row[k] for k in ['resolved','bytes','mode','sha256','member']), 'Conflicting selected identity')
            selected[row['path']]['categories'] = sorted(set(selected[row['path']]['categories'] + [category]))
        else:
            row['categories'] = [category]
            selected[row['path']] = row
    for row in root['files']:
        add(row['path'], 'root-selected-record', row)
    add(ROOT_MAP, 'root-handoff-map', root_fact)

    def add_tree(path, category, excluded=()):
        p = Path(path)
        require(p.is_dir(), 'Missing selected directory: '+str(p))
        for child in sorted(p.rglob('*')):
            if child.is_file() and not any(part in excluded for part in child.relative_to(p).parts):
                add(child,category)

    def add_run(name):
        d = V / name
        require(d.is_dir(), 'Missing selected run: '+name)
        excluded = {'inputs-before.json','inputs-after.json','source.tar'}
        for f in sorted(d.iterdir()):
            if f.is_file() and f.name not in excluded and not f.name.endswith(('.tar.gz','.tgz')):
                add(f,'parent-selected-run')
        for child in ['input-sources','atoms']:
            if (d/child).is_dir(): add_tree(d/child,'executed-draft-or-atom-record')

    for name in [
        'predecessor-af0bed0b-01','candidate-8ffa5ac5-01','candidate-cf317730-01',
        'join-predecessor-af0bed0b-03','binding-predecessor-af0bed0b-02',
        'join-candidate-cf317730-01','binding-candidate-cf317730-01',
        'join-copied-control-04','join-copied-control-05','join-copied-control-06',
        'binding-copied-control-02','binding-copied-control-03','binding-copied-control-04',
        'finalizer-copied-control-02','retention-regression-predecessor-01',
        'focused-8ffa5ac5-01','focused-cf317730-01',
        'history-alignment-predecessor-01','history-alignment-candidate-01',
        'native-cf317730-01','full-cf317730-01','package-cf317730-01',
        'linkage-cf317730-host-01','linkage-cf317730-binary-01']:
        add_run(name)
    for name in ['first-candidate-source-03','history-lifetime-correction-source-01','gate-preparation']:
        add_tree(V/name,'source-or-launch-preparation')
    for name in ['first-candidate-commit-01.json','history-lifetime-correction-commit-01.json',
                 'rust-reuse-cf317730-01.json','rust-reuse-cf317730-02.json']:
        add(V/name,'source-identity-or-correction')
    add_tree(V/'api-review','api-review',excluded=('integration-sources',))
    add_tree(V/'semantics-review','semantic-review',excluded=('input-sources',))
    for base in [V/'candidate-cf317730-01/export/r-package/dtatools', V/'package-cf317730-01/source/r-package/dtatools']:
        require(base.is_dir(), 'Missing intended source attribution directory: '+str(base))
        for rel in ['DESCRIPTION','NAMESPACE','README.md','inst/NOTICE']:
            add(base/rel,'selected-source-attribution')
    for rel in ['dtatools.Rcheck/00check.log','dtatools.Rcheck/00install.out','dtatools.Rcheck/tests/testthat.Rout',
                'binary/library/dtatools/NOTICE','binary/library/dtatools/DESCRIPTION','binary/library/dtatools/NAMESPACE']:
        add(V/'package-cf317730-01'/rel,'package-detail')
    add(Path(__file__),'selection-collector')
    for path in [P/'prepare-evidence-v1.py', P/'evidence-selection-01.json', P/'test-evidence-guard-v1.py', P/'guard-normal-01.json', P/'guard-optimized-01.json', P/'test-evidence-guard-v2.py', P/'guard-normal-02.json', P/'guard-optimized-02.json', P/'prepare-evidence-v1-to-v2.patch', Path('/private/tmp/dta-direct-stage8-performance-preparation-01/root-artifact-selection-addendum-01.json'), Path('/private/tmp/dta-direct-stage8-performance-preparation-01/stage8-performance-disposition-draft-03.md')]:
        add(path,'publication-correction-or-guard')
    rows = sorted(selected.values(),key=lambda x:x['member'])
    validate(rows)
    record = dict(status='frozen-selected-evidence', created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  source='cf317730d3110568c72862719424e01c2876141b', root_map=root_fact,
                  count=len(rows), bytes=sum(x['bytes'] for x in rows), files=rows,
                  scope=['Original selected bytes and observed regular-file modes, mapped to archive members without rewriting original paths.',
                         'Source and endpoint manifests are retained; complete live before/after dependency inventories, runtime images, installed DLL/RDB files, package tarballs and full Git archives remain local.',
                         'This is transport verification, not another semantic/runtime execution or complete portable replay closure.',
                         'Prepared and failed records keep their original names/status. Their presence does not turn them into accepted runs.'])
    require(fact(ROOT_MAP)==root_fact,'Root map changed during selection')
    with SELECTION.open('x') as stream: stream.write(json.dumps(record,indent=2)+'\n')
    print(json.dumps(dict(selection=str(SELECTION), count=record['count'], bytes=record['bytes'],sha256=fact(SELECTION)['sha256'])))

def build_payload():
    before = fact(SELECTION)
    selection_bytes = SELECTION.read_bytes()
    require(len(selection_bytes)==before['bytes'] and sha(selection_bytes)==before['sha256'], 'Selection changed during initial read')
    data = json.loads(selection_bytes); rows = data['files']; validate(rows)
    require(len(rows)==data['count'] and sum(x['bytes'] for x in rows)==data['bytes'],'Selection totals differ')
    OUTPUT.mkdir(exist_ok=False)
    archive = OUTPUT/'records.tar.gz'
    with archive.open('wb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0,compresslevel=6) as gz, tarfile.open(fileobj=gz,mode='w|',format=tarfile.PAX_FORMAT) as tar:
        for row in rows:
            p=Path(row['path']); expected={k:row[k] for k in ['path','resolved','bytes','mode','sha256']}
            require(fact(p)==expected,'Selected input changed before copy: '+str(p))
            payload=p.read_bytes();require(len(payload)==row['bytes'] and sha(payload)==row['sha256'],'Selected copy changed')
            info=tarfile.TarInfo(row['member']);info.size=len(payload);info.mode=int(row['mode'],8);info.mtime=0
            tar.addfile(info,io.BytesIO(payload))
            require(fact(p)==expected,'Selected input changed after copy: '+str(p))
    with tarfile.open(archive,'r:gz') as tar:
        actual=tar.getmembers();require([m.name for m in actual]==[x['member'] for x in rows],'Archive exact membership differs')
        for m,row in zip(actual,rows):
            require(m.isfile() and m.size==row['bytes'] and m.mode==int(row['mode'],8),'Archive type/size/mode differs')
            require(sha(tar.extractfile(m).read())==row['sha256'],'Archive bytes differ')
    require(fact(SELECTION)==before,'Selection changed during archive build')
    (OUTPUT/'selection.json').write_bytes(selection_bytes)
    result=dict(status='complete', archive=fact(archive), selection=fact(OUTPUT/'selection.json'),
                members=len(rows), uncompressed_bytes=data['bytes'],scope='Exact selected archive membership/type/mode/bytes verified. No workload rerun, extraction or dependency-image replay.')
    (OUTPUT/'transport-result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))

def build():
    attempt_path=OUTPUT.with_name(OUTPUT.name+'-build-attempt.json')
    record=dict(status='running', source=fact(__file__), selection_path=str(SELECTION), output=str(OUTPUT), started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    with attempt_path.open('x') as stream: stream.write(json.dumps(record,indent=2)+'\n')
    try:
        build_payload()
        record['status']='complete'
    except BaseException as exc:
        record.update(status='failed', error=dict(type=type(exc).__name__,message=str(exc)))
        raise
    finally:
        record['completed_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        record['retained_output_names']=sorted(x.name for x in OUTPUT.iterdir()) if OUTPUT.is_dir() else []
        attempt_path.write_text(json.dumps(record,indent=2)+'\n')

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['select','build']);a=p.parse_args()
    select() if a.action=='select' else build()

if __name__=='__main__': main()
