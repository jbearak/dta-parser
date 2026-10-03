#!/usr/bin/env python3
"""Bind the separately qualified main integration; do not replace timings."""
from collections import Counter
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=Path('<repo>')
COMMIT='dbcf75cbfe589b5ac2a78166d1e436faa7bbb896'
MAIN='20ec12cebcce0afa6981c82a59686fa055975b6f'
MEASURED='af9f76e3eb3b0b0328ec6609ddb017d42edb3c9d'
ARITHMETIC=['src/numeric-arithmetic-general.h','src/numeric-arithmetic-pair.h',
            'src/numeric-arithmetic-pair-float.h','tests/testthat/test-native-arithmetic-kernels.R',
            'tests/testthat/test-native-arithmetic-parity.R']


def need(ok,label):
    if not ok:
        raise RuntimeError(label)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    path=ROOT/'benchmarks/native-operations/run.py'
    spec=importlib.util.spec_from_file_location('integration_records',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    inventory=module.inventory(HERE/'integration-candidate','candidate')
    need(inventory['receipt']['base_commit']==COMMIT,'Wrong integration commit')
    need((HERE/'integration-candidate/source.patch').read_bytes()==b'','Integration is not a clean build')
    package=ROOT/'r-package/dtatools'
    current={str(p.relative_to(package)):sha(p) for p in package.rglob('*') if p.is_file()}
    need(current==inventory['source'],'Current package differs from integrated build')
    measured_inventory=module.inventory(HERE/'acceptance-candidate','candidate')
    measured=measured_inventory['receipt']
    need(measured['base_commit']==MEASURED,'Wrong measured candidate commit')
    for name in ARITHMETIC:
        need(inventory['source'][name]==measured['source_inventory'][name],'Measured arithmetic runtime or tests changed')
    delta=subprocess.check_output(['git','diff','--name-only',MAIN,COMMIT,'--','r-package/dtatools'],cwd=ROOT,text=True).splitlines()
    need(set(delta)=={'r-package/dtatools/'+name for name in ARITHMETIC+['tools/native-test-manifest.json']},
         'Unexpected PR package delta')
    qualified=list(csv.DictReader((HERE/'integration-qualification.csv').open()))
    original=list(csv.DictReader((HERE/'acceptance-candidate-qualification.csv').open()))
    need(len(qualified)==102 and qualified==original,'Integrated no-clock qualification differs')
    observations=list(csv.DictReader((HERE/'integration-full-tests.csv').open()))
    totals={key:sum(int(row[key]) if key in ('passed','failed','warning') else row[key]=='TRUE' for row in observations)
            for key in ('passed','failed','error','skipped','warning')}
    need(totals['passed']>=98134 and not any(totals[key] for key in ('failed','error','skipped')),'Integrated suite failed/incomplete')
    manifest=json.loads((package/'tools/native-test-manifest.json').read_text())
    for entry in [*manifest['helpers'],*manifest['fixtures'],*(item for f in manifest['families'] for item in f['files'])]:
        need(sha(package/entry['path'])==entry['sha256'],'Manifest file mismatch')
    seen=Counter(); observed={}
    for row in observations:
        key=(row['file'],row['test']);seen[key]+=1
        observed[key+(seen[key],)]=row
    blocks=[b for f in manifest['families'] for b in f['blocks']]
    need(len(blocks)==len(observations),'Wrong integrated manifest coverage')
    for b in blocks:
        row=observed[b['file'],b['test'],b.get('occurrence',1)]
        need(int(row['passed'])>=b['min_pass'],'Integrated assertion minimum')
        if b['skip']=='forbid':
            need(int(row['warning'])==b['warnings'],'Integrated warning policy')
    conformance=json.loads((HERE/'integration-conformance.json').read_text())
    need(conformance['source_commit']==COMMIT and conformance['required_conformance_passed'] and
         conformance['clean_export_matches_source_commit'] and conformance['checked_source_matches_clean_export'] and
         conformance['exact_packaged_source_inventory'] and conformance['expected_hashes_from_committed_blobs'],
         'Conformance archive source binding failed')
    need(sha(HERE/'integration-conformance.tar.gz')==conformance['source_archive_sha256'],'Checked archive changed')
    paths=[Path(__file__).resolve(),HERE/'integration-full-tests.csv',HERE/'integration-full-tests.log',
           HERE/'integration-qualification.csv',HERE/'integration-qualification.log',
           HERE/'integration-conformance.log',HERE/'integration-conformance.json',
           HERE/'integration-conformance-gate.sh',HERE/'validate-conformance-archive.py']
    report=dict(status='PASS',source_commit=COMMIT,integrated_main=MAIN,measured_candidate=MEASURED,
                integration_build=inventory,source_equals_clean_build=True,
                arithmetic_runtime_and_tests_equal_measured=ARITHMETIC,
                package_delta_from_main=delta,full_suite=dict(totals=totals,blocks=len(blocks)),
                qualification=dict(rows=102,equals_measured_candidate=True),
                conformance_archive=conformance,
                scope='Separate main integration correctness and source-archive qualification. Not a new timing run; other merged package implementation changes are not presented as measured.',
                input_sha256={str(path):sha(path) for path in paths})
    (HERE/'integration-binding.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(status='PASS',totals=totals,blocks=len(blocks),qualification=102)))


if __name__=='__main__':
    main()
