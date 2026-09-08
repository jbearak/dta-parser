from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,csv,difflib
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path(__file__).parent;source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
prep=json.loads((review/'atomic-read-setup-preparation-review-01.json').read_text())
for x in prep['sources']:assert ident(x['path'])==x
runs=[];before_inputs=None
for mode in ['cold','warm']:
 name='candidate-a2d8b6a-read-setup-'+mode+'-01';p=root/name;rid=ident(root/(name+'-receipt.json'));r=json.loads(Path(rid['path']).read_text());m=json.loads((p/'manifest.json').read_text());b=json.loads((p/'inputs-before.json').read_text());e=json.loads((p/'execution-result.json').read_text())
 assert r['manifest']==ident(p/'manifest.json') and not r['changed_inputs'] and not e['changed_inputs'] and e['integrity_error'] is None
 expected=1 if mode=='cold' else 0;assert e['returncode']==r['returncode']==expected and r['accepted']==(mode=='warm') and e['namespace_coverage']==(mode=='warm')
 for x in m['products']:assert ident(x['path'])==x
 assert {x['path'] for x in m['products']}|{str(p/'manifest.json')}=={str(x) for x in p.iterdir()}
 for x in b['inputs']:assert ident(x['path'])==x
 assert b['source']==b['runner_source']==source and b['mode']=='candidate' and b['case_set']==('cold' if mode=='cold' else 'rename')
 if before_inputs is None:before_inputs=b['inputs']
 else:assert before_inputs==b['inputs']
 bound={x['resolved'] for x in b['inputs']}
 ns=list(csv.DictReader((p/'namespaces.tsv').open(),delimiter='\t'))
 for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 metrics=list(csv.DictReader((p/'fork-metrics.csv').open()));assert len(metrics)==1;metrics={k:float(v) for k,v in metrics[0].items()}
 assert metrics['r_allocated_bytes']==(2191016 if mode=='cold' else 83192) and metrics['r_largest_allocation_bytes']==(82104 if mode=='cold' else 40112)
 assert all(v==0 for k,v in metrics.items() if k.startswith('native_') or k.startswith('validation_'))
 text=(p/'execution.log').read_text()
 if mode=='cold':assert 'metrics[["r_allocated_bytes"]] < 1e+06 is not TRUE' in text and 'Execution halted' in text
 else:assert 'PASS allocation-only first-case probe rename' in text and rid['sha256']=='79b928f65b9b0b3db1ec9ebd07937a5391ec99d70c176c82fe11204db4139b15'
 runs.append(dict(mode=mode,receipt=rid,products=len(m['products']),inputs=len(b['inputs']),exit_code=expected,original_accepted=r['accepted'],original_namespace_coverage=e['namespace_coverage'],independent_retained_namespace_coverage=True,metrics=metrics))
r1=(root/'atomic-read-repeat-v1.R').read_text();r2=(root/'atomic-read-repeat-v2.R').read_text();addition='''    # The original selector phase warmed rename before the later read phase.
    # Restore that independent tiny-fixture warm-up outside all measurements.
    invisible(dplyr::rename(atomic_fixture(kind, 4L), changed = c01))
''';assert r2.replace(addition,'')==r1 and r2.count(addition)==1
p1=(root/'atomic-read-repeat-v1.py').read_text();p2=(root/'atomic-read-repeat-v2.py').read_text();expected=p1.replace('atomic-read-repeat-v1.R','atomic-read-repeat-v2.R').replace('The minimum case changes only table width to one column.','The original independent four-row rename warm-up is restored before each measured fixture, outside profiling and timing. The minimum case changes only measured table width to one column.');assert p2==expected;compile(p2,str(root/'atomic-read-repeat-v2.py'),'exec')
assert 'PASS both retained modes, 80 source/result facts' in (review/'atomic-read-setup-record-reader-01.log').read_text()
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='setup_probe_evidence_and_v2_source_clear',reviewer_script=ident(__file__),runs=runs,identical_probe_input_records=len(before_inputs),reader=[ident(review/n) for n in ['atomic-read-setup-record-reader-01.R','atomic-read-setup-record-reader-01.log','atomic-read-setup-states-01.csv']],v2_sources=[ident(root/n) for n in ['atomic-read-repeat-v2.R','atomic-read-repeat-v2.py']],actual_diffs={extension:''.join(difflib.unified_diff((root/('atomic-read-repeat-v1.'+extension)).read_text().splitlines(True),(root/('atomic-read-repeat-v2.'+extension)).read_text().splitlines(True))) for extension in ['R','py']},assessment='Both diagnostic records retain unchanged identical48,241-file input bindings and complete output manifests. Cold reproduces the unchanged less-than1MB selector allocation predicate failure with2,191,016R bytes/largest82,104; independent4row rename setup passes with83,192/largest40,112. Native copy/scratch/scan counters are zero in both. Own retained-state reader confirms all80 facts preserve8unexposed depth-one backings across before/read/profile/pre-timing/source/result observations. These results support restoring omitted independent rename warm-up for the selected read driver. Actual v2 R diff adds only that independent tiny-fixture warm-up before each measured fixture; Python changes only R filename and precise scope prose. All operation/oracle/profile/state/timing/gate logic remains unchanged.',limits=['Cold remains accepted=false, exit1, namespace_coverage=false in its original completion record. The reviewer separately validates its already-retained namespace paths; this does not relabel the failed run as passed. Warm remains accepted=true.','Common timing omission reproduced the gate; contrast identifies an effect of the complete independent rename setup, not an exclusive JIT/dispatch/metadata/internal allocation cause. Raw allocation events were not retained by the unchanged profiler.','The v2 source is cleared for future coordinated execution only. Both earlier v1 preparation and its failed run remain historical; no v2 workload ran during review.','No new measurement, profiler, native call, fixture construction or test executed. Independent R only read saved state facts. Detailed owned/outcome/historical comparison and overall acceptance remain pending.'])
with (review/'atomic-read-setup-evidence-v2-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],probe_runs=2,inputs_per_run=len(before_inputs),state_facts=80,cold_bytes=2191016,warm_bytes=83192)))
