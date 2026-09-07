from pathlib import Path
from datetime import datetime,timezone
import csv,hashlib,json,subprocess,re
root=Path('/private/tmp/dta-direct-stage5-validation');p=root/'root-expression-performance';repo=Path('/private/tmp/dta-direct-stage5');out=root/'implementation/semantics-review'
def identity(p):
 p=Path(p);b=p.read_bytes();return dict(path=str(p),resolved=str(p.resolve(strict=True)),bytes=len(b),mode=oct(p.stat().st_mode&0o777),sha256=hashlib.sha256(b).hexdigest())
def match(p,x):
 n=identity(p);assert all(n[k]==x[k] for k in ['bytes','mode','sha256']),str(p)
 return n
records=[]
for version,pin in [(1,'9d16c8eba32b12afc87c11d9680bb25182e7591e2b5964accef95e833c950f46'),(2,'6a206719d9c1b7f0cffc1bd8e19847dd0bdd3570558f2781a3ee1f413a5d964a')]:
 folder=p/f'read-disposition-verification-{version:02}';rc=identity(folder/'completed-receipt.json');assert rc['sha256']==pin
 receipt=json.loads((folder/'completed-receipt.json').read_text());assert receipt['accepted'] and not receipt['changed_inputs'];match(receipt['manifest']['path'],receipt['manifest'])
 products=json.loads((folder/'manifest.json').read_text())['products'];assert len(products)==3
 for product in products:match(product['path'],product)
 inputs=json.loads((folder/'inputs-before.json').read_text())['inputs'];assert len(inputs)==41
 if version==1:
  snap=p/'read-disposition-prose-v1-postrun-snapshot';saved=json.loads((snap/'snapshot-verification.json').read_text())['files'];maps={r['original']:r for r in saved};assert len(maps)==3
  for x in inputs:
   if x['path'] in maps:
    z=maps[x['path']];match(z['snapshot'],x);assert z['matches_v1_before'] and all(z[k]==x[k] for k in ['bytes','mode','sha256'])
   else:assert identity(x['path'])==x,x['path']
 else:
  for x in inputs:assert identity(x['path'])==x,x['path']
 records.append(dict(version=version,receipt=rc,input_count=len(inputs),products=len(products)))
assert (p/'verify-read-disposition-v2.py').read_text().replace('read-disposition-verification-02','read-disposition-verification-01')==(p/'verify-read-disposition-v1.py').read_text()
prep=json.loads(Path('/private/tmp/dta-direct-stage5-read-cost-preparation.inputs.json').read_text());assert len(prep['inputs'])==27
for x in prep['inputs']:
 n=identity(x['path']);assert n['bytes']==x['bytes'] and n['sha256']==x['sha256']
derivation=json.loads((p/'read-disposition-verification-02/derivation.json').read_text());assert len(derivation['residual_reads'])==12
for x in derivation['package_comparisons']:
 a=subprocess.check_output(['git','show',x['a2']+':'+x['path']],cwd=repo);b=subprocess.check_output(['git','show',x['c8']+':'+x['path']],cwd=repo)
 assert a==b==(repo/x['path']).read_bytes() and hashlib.sha256(a).hexdigest()==x['sha256']
research=repo/'docs/research/stage5-base-r-read-costs.md';text=research.read_text()
table=[x for x in text.splitlines() if x.startswith('| ')][2:];assert len(table)==12
for line,x in zip(table,derivation['residual_reads']):
 assert f"{x['delta_min_ms']:.3f}–{x['delta_max_ms']:.3f}" in line and f"{x['minimum_delta_ms']:.3f}" in line
cases=json.loads((p/'atomic-read-repeat-v2-root-assessment-01.json').read_text())['comparisons']
for x in derivation['residual_reads']:
 repeated=[r for r in cases if r['case']=='read-repeat' and r['rows']==1000000 and r['kind']==x['kind'] and r['operation']==x['operation']]
 minimum=[r for r in cases if r['case']=='read-minimum' and r['kind']==x['kind'] and r['operation']==x['operation']]
 assert len(repeated)==3 and len(minimum)==1 and all(r['flag'] for r in repeated+minimum)
 assert (min(r['delta_ms'] for r in repeated),max(r['delta_ms'] for r in repeated),minimum[0]['delta_ms'])==(x['delta_min_ms'],x['delta_max_ms'],x['minimum_delta_ms'])
for x in derivation['controls']:
 rows=[r for r in json.loads((p/x['assessment']).read_text())['comparisons'] if r['rows']==1000000 and r['operation']==x['operation']]
 assert min(r['delta_ms'] for r in rows)==x['delta_min_ms'] and max(r['delta_ms'] for r in rows)==x['delta_max_ms']
gc=sum(int(r['gc_count']) for source in ['baseline-ec10','candidate-a2d8b6a'] for i in range(1,4) for r in csv.DictReader((p/f'{source}-read-count-control-v1-{i:02}/read-count-control.csv').open()));assert gc==36
assert 'through `ALTREP_COERCE`' in text
progress=(repo/'docs/plans/dibble-result-performance-progress.md').read_text();assert '50 series and 350 raw samples per source' in progress
assert subprocess.check_output(['git','diff','--name-only','--','r-package/dtatools'],cwd=repo)==b''
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='corrected_read_disposition_clear',script=identity(__file__),prose=[identity(repo/n) for n in ['docs/research/stage5-base-r-read-costs.md','docs/plans/dibble-result-performance.md','docs/plans/dibble-result-performance-progress.md']],verification_records=records,verified_primary_preparation_inputs=27,derivation=derivation,total_count_gc_events=gc,assessment=[
'Actual corrected prose diff and new research note read. Coerce setter wording now distinguishes method registration from coerceVector invocation through ALTREP_COERCE. Expression50series/350samples explicitly per source. Original three prose bytes match historical verification01 inputs in the explicitly post-run snapshot; verification02 binds current corrected text. Both original receipts/products remain unchanged.',
'All41 inputs and three products of verification02 match actual identities; verification01 inputs match except intentionally corrected original prose paths, whose exact old bytes/modes are preserved in the labeled post-run snapshot. Driver v2 changes only fresh output name. This derivation is saved-assessment/current-source checking, not new raw measurement or causal decomposition.',
'All27 preparation inputs match. Direct Git reads independently confirm c8/a2/current owned-columns.h and original atomic helper/runner equality. Actual retained primary coerce.c, mean.R and Altrep.h plus current owned header inspected: cached rooted pointer getters, existing pointer/region/No_NA registrations, character/default missingness Elt loops, OBJECT anyNA missing-mask evaluation, factor direct-code coercion, ordinary logical subset before mean, and public absence of missing-mask/Mean hooks support the qualified source claims.',
'Generic ALTREP_COERCE precedes logical ordinary coercion loops; hook success copies attributes afterward while ordinary copies before. Source therefore supports an unproved entry point for two logical coercion cases, not an accepted equivalent hook or fix for factor coercion/missingness. Rooting, callbacks/tracing, arbitrary attributes and isolation remain proof obligations; no production prototype was introduced.',
'All twelve table ranges/minimum deltas independently recompute from saved repeated assessments and round correctly. Eight control ranges agree with saved source-specific comparison rows. The six count CSVs contain36GC events, retained with filter_gc false. Previous detailed raw/state/allocation reviews remain separately bound.',
'Final host/minimum/expression/write/memory/native counts match previously independently cleared exact-a2 records. Read controls are bounded to four operation/type pairs and stock hostR4.6.1, not cleanR4.6.0 performance or an installed-R build attestation. Twelve read costs remain unwaived; three filter flags still require Stage6 fixes/paired qualification. No overall acceptance or irreducibility is asserted.',
'Archive links intentionally target the planned measurements PR destination and must land before this prose is published. External PR review/CI/merge facts remain root-owned. Progress inclusion-status sentence reflects an earlier checkpoint and can be updated once final staged archive review completes; it is not a gate waiver.'
],limits='Read-only source, Git blob, input/product identity and saved arithmetic audit. No R/test/build/profile/benchmark/derivation runner rerun, package mutation or external status inference.')
with (out/'read-disposition-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],report=identity(out/'read-disposition-review-01.json'))))
