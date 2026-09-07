"""Current prose and saved derivation review; no R/benchmark/prototype execution."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
REPO=Path('/private/tmp/dta-direct-stage5')
OUT=Path(__file__).with_suffix('.json')
def identity(path):
    path=Path(path); resolved=path.resolve(strict=True); st=resolved.stat()
    return dict(path=str(path),resolved=str(resolved),bytes=st.st_size,mode=oct(st.st_mode&0o777),sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())

assert (ROOT/'verify-read-disposition-v1.py').read_text().replace("output = ROOT / 'read-disposition-verification-01'","output = ROOT / 'read-disposition-verification-02'")==(ROOT/'verify-read-disposition-v2.py').read_text()
assert identity(ROOT/'verify-read-disposition-v2.py')['sha256']=='160844713f670e7a259d72a5b918b62647428a96f51943a78a0cd2dbb2792121'
snapshot_root=ROOT/'read-disposition-prose-v1-postrun-snapshot'
snapshot=json.loads((snapshot_root/'snapshot-verification.json').read_text())
assert 'Post-run snapshot' in snapshot['scope'] and len(snapshot['files'])==3
original_inputs=json.loads((ROOT/'read-disposition-verification-01/inputs-before.json').read_text())['inputs']
original_by_path={r['path']:r for r in original_inputs}
snapshots={r['original']:r for r in snapshot['files']}
for original,row in snapshots.items():
    actual=identity(row['snapshot']); recorded=original_by_path[original]
    assert all(actual[k]==row[k]==recorded[k] for k in ('bytes','mode','sha256')) and row['matches_v1_before']
run_records=[]
for version,pin in [('01','9d16c8eba32b12afc87c11d9680bb25182e7591e2b5964accef95e833c950f46'),('02','6a206719d9c1b7f0cffc1bd8e19847dd0bdd3570558f2781a3ee1f413a5d964a')]:
    folder=ROOT/('read-disposition-verification-'+version); receipt_path=folder/'completed-receipt.json'
    receipt_id=identity(receipt_path);assert receipt_id['sha256']==pin
    receipt=json.loads(receipt_path.read_text());assert receipt['accepted'] and receipt['changed_inputs']==[] and receipt['manifest']==identity(folder/'manifest.json')
    products=json.loads((folder/'manifest.json').read_text())['products'];assert len(products)==3 and all(identity(r['path'])==r for r in products)
    assert {str(p) for p in folder.iterdir()}=={r['path'] for r in products}|{str(folder/'manifest.json'),str(receipt_path)}
    inputs=json.loads((folder/'inputs-before.json').read_text())['inputs'];assert len(inputs)==41
    for row in inputs:
        if version=='01' and row['path'] in snapshots:
            actual=identity(snapshots[row['path']]['snapshot']);assert all(actual[k]==row[k] for k in ('bytes','mode','sha256'))
        else:assert identity(row['path'])==row
    result=json.loads((folder/'execution-result.json').read_text());assert result['accepted'] and result['changed_inputs']==[] and result['error'] is None
    run_records.append(dict(version=version,receipt=receipt_id,products=3,inputs=41,scope='Original v1 prose resolved to explicitly post-run snapshots' if version=='01' else 'All inputs match current exact files'))

prep_path=Path('/private/tmp/dta-direct-stage5-read-cost-preparation.inputs.json');prep=json.loads(prep_path.read_text())
assert len(prep['inputs'])==27
for row in prep['inputs']:
    actual=identity(row['path']);assert actual['bytes']==row['bytes'] and actual['sha256']==row['sha256']
derived=json.loads((ROOT/'read-disposition-verification-02/derivation.json').read_text())
for row in derived['package_comparisons']:
    a=subprocess.check_output(['git','show',row['a2']+':'+row['path']],cwd=REPO)
    b=subprocess.check_output(['git','show',row['c8']+':'+row['path']],cwd=REPO)
    assert a==b==(REPO/row['path']).read_bytes() and hashlib.sha256(a).hexdigest()==row['sha256']
cases=json.loads((ROOT/'atomic-read-repeat-v2-root-assessment-01.json').read_text())['comparisons']
for row in derived['residual_reads']:
    repeated=[r for r in cases if r['kind']==row['kind'] and r['operation']==row['operation'] and r['case']=='read-repeat' and r['rows']==1000000]
    minimum=[r for r in cases if r['kind']==row['kind'] and r['operation']==row['operation'] and r['case']=='read-minimum']
    assert len(repeated)==3 and len(minimum)==1 and all(r['flag'] for r in repeated+minimum)
    assert row['delta_min_ms']==min(r['delta_ms'] for r in repeated) and row['delta_max_ms']==max(r['delta_ms'] for r in repeated) and row['minimum_delta_ms']==minimum[0]['delta_ms']
for row in derived['controls']:
    comparisons=json.loads((ROOT/row['assessment']).read_text())['comparisons']
    matches=[r for r in comparisons if r['rows']==1000000 and r['operation']==row['operation']]
    assert row['delta_min_ms']==min(r['delta_ms'] for r in matches) and row['delta_max_ms']==max(r['delta_ms'] for r in matches)

note=REPO/'docs/research/stage5-base-r-read-costs.md'; text=note.read_text()
assert 'a method registered through\n`R_set_altrep_Coerce_method` is invoked by `coerceVector` through `ALTREP_COERCE`' in text
assert '50 series and 350 raw samples per source' in (REPO/'docs/plans/dibble-result-performance-progress.md').read_text()
for row in derived['residual_reads']:
    numeric=f"| {row['delta_min_ms']:.3f}–{row['delta_max_ms']:.3f} | {row['minimum_delta_ms']:.3f} |"
    assert numeric in text,numeric
assert subprocess.check_output(['git','diff','--name-only','--','r-package/dtatools'],cwd=REPO)==b''
assert subprocess.check_output(['git','diff','--name-only'],cwd=REPO).decode().splitlines()==['docs/plans/dibble-result-performance-progress.md','docs/plans/dibble-result-performance.md']
assert subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=REPO).decode().splitlines()==['docs/research/stage5-base-r-read-costs.md']
assert subprocess.run(['git','diff','--check'],cwd=REPO,capture_output=True).returncode==0
docs=['docs/plans/dibble-result-performance-progress.md','docs/plans/dibble-result-performance.md','docs/research/stage5-base-r-read-costs.md']
report=dict(status='clear',reviewer_source=identity(__file__),docs=[identity(REPO/p) for p in docs],derivation_runs=run_records,
 snapshot_record=identity(snapshot_root/'snapshot-verification.json'),historical_preparation_inputs=27,source_comparisons=derived['package_comparisons'],residual_rows_recalculated=12,control_ranges_recalculated=8,
 package_diff_empty=True,findings_resolved=['Coerce registration setter distinguished from invoked ALTREP_COERCE method.','Full expression counts explicitly per source.'],
 scope='Actual three-file prose diff, current 41-input derivation and original post-run prose snapshots, exact pinned source/recorded arithmetic review. No production changes or experiments.',
 limits=['Primary R copies are reading references, not attestation of complete installed R build inputs.','Future Coerce hook/backing redesign remains unimplemented and unqualified; no isolated getter, irreducibility or overall acceptance claim.','Publication links target the separately prepared measurements archive; publish/merge that archive before these links become final repository navigation.','Remote PR/CI/provenance publication status remains owned by root and was not independently rechecked.'])
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps({'status':'clear','docs':3,'current_derivation_inputs':41,'original_snapshots':3,'historical_preparation_inputs':27,'residual_rows':12,'control_ranges':8,'package_diff_empty':True}))
