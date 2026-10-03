"""Independent final34 audit replay/publication/description review; no measurements."""
import ast,csv,hashlib,json,math,re,statistics
from pathlib import Path
E=Path('<final34_evidence>')
PUBLIC=Path('<final34_public>')
REPLAY=Path('<private-work>/dta-native-final-acceptance-public-reader-review')
BASE=Path('<private-work>/dta-native-integration-final-evidence/combined-build')
CANDIDATE=Path('<evidence>/final-combined-build')
RECORDER=Path('<recorder_repository>')
OLD=Path('<private-work>/dta-integer-reciprocal-evidence/acceptance-controller')
D=E/'acceptance-controller'
def need(v,m):
 if not v:raise RuntimeError(m)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def inventory(p):return {str(x.relative_to(p)):sha(x) for x in p.rglob('*') if x.is_file()}
def close(a,b):return math.isclose(a,b,rel_tol=1e-12,abs_tol=1e-14)
# Replay the reviewed original auditor while changing only its destination.
# __file__ stays the exact original so its own recorded source hash is unchanged.
original=E/'acceptance-independent-audit.py'
source=original.read_text();tree=ast.parse(source)
assignments=[n for n in tree.body if isinstance(n,ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='OUT']
need(len(assignments)==1,'Ambiguous audit output override')
assignments[0].value=ast.Call(func=ast.Name(id='Path',ctx=ast.Load()),args=[ast.Constant(str(E/'reader-audit-replay.json'))],keywords=[])
ast.fix_missing_locations(tree)
original_receipt=(E/'acceptance-independent-audit.json').read_bytes()
exec(compile(tree,str(original),'exec'),{'__file__':str(original),'__name__':'__main__'})
need((E/'reader-audit-replay.json').read_bytes()==original_receipt,'Independent audit replay differs')
need((E/'acceptance-independent-audit.json').read_bytes()==original_receipt,'Original audit changed')
# The measurement worker remains identical to the earlier accepted panel.
need((D/'general-worker.R').read_bytes()==(OLD/'general-worker.R').read_bytes(),'Measurement worker changed')
old=(OLD/'general-run.py').read_text()
changes=[
 ('Check the integer-reciprocal producer against the unchanged original 34-case panel.','Check the combined accepted runtime against the unchanged original 34-case panel.'),
 ("RECORDS_PATH = Path('<recorder_repository>/benchmarks/native-operations/run.py')\n", "RECORDS_PATH = Path('<recorder_repository>/benchmarks/native-operations/run.py')\nRECORDER_DEPENDENCIES = tuple(RECORDS_PATH.parent.parent / name for name in (\n    'r-file-readers/record-builds.py', 'io-optimization/record-builds.py',\n    'r-file-readers/build-snapshot.py'))\n"),
 ('3a02e6d13309441366a7a727fdc934f424ce66c6','3eadb244253fb817d5773b01b11cb36c284f3a1d'),
 ('Unexpected diagnostic source commits','Unexpected committed acceptance sources'),
 ('Original 34-case arithmetic acceptance panel after the integer reciprocal range proof','Original 34-case arithmetic acceptance panel after the combined accepted follow-ups'),
 ('Long is only the original long+float addition case; long reciprocal remains in the separate432 screen.','Long is only the original long+float addition case; this panel retains the original scope.')]
for a,b in changes:
 need(old.count(a)==1,'Controller adaptation is not unique')
 old=old.replace(a,b)
need(old==(D/'general-run.py').read_text(),'Controller changed beyond reviewed pins/prose/dependency declarations')
# Independently recompute every description value from the qualified raw rows.
raw=list(csv.DictReader((E/'acceptance-v1/raw.csv').open()))
keys=('width','missing','operation')
idx={tuple(r[k] for k in keys)+(r['variant'],r['representation'],int(r['round'])):r for r in raw}
need(len(idx)==len(raw)==1224,'Description input cardinality')
description=read(E/'final-panel-description.json');audit=read(E/'reader-audit-replay.json')
need(description['source_commits']==audit['source_commits'],'Description source mismatch')
cases=sorted({tuple(r[k] for k in keys) for r in raw});need(len(cases)==34,'Description matrix')
expected=[]
for case in cases:
 costs={(role,rep,n):float(idx[case+(role,rep,n)]['cpu'])/int(idx[case+(role,rep,n)]['iterations']) for role in ('baseline','candidate') for rep in ('compact','typed_double','ordinary') for n in range(1,7)}
 med={(role,rep):statistics.median(costs[role,rep,n] for n in range(1,7)) for role in ('baseline','candidate') for rep in ('compact','typed_double','ordinary')}
 row=dict(zip(keys,case));row.update(baseline_cpu_ms=med['baseline','compact']*1000,candidate_cpu_ms=med['candidate','compact']*1000,direct_speedup=med['baseline','compact']/med['candidate','compact'],paired_speedup=statistics.median(costs['baseline','compact',n]/costs['candidate','compact',n] for n in range(1,7)))
 for rep in ('typed_double','ordinary'):
  norm=[costs['candidate','compact',n]/costs['baseline','compact',n]*costs['baseline',rep,n]/costs['candidate',rep,n] for n in range(1,7)]
  row[rep+'_ratio']=med['candidate','compact']/med['candidate',rep]
  row[rep+'_paired_ratio']=statistics.median(costs['candidate','compact',n]/costs['candidate',rep,n] for n in range(1,7))
  row[rep+'_control_normalized_cost']=statistics.median(norm);row[rep+'_normalized_slower_rounds']=sum(v>1 for v in norm);row[rep+'_normalized_round_costs']=norm
 expected.append(row)
need(len(description['results'])==len(expected),'Description result count')
for actual,wanted in zip(description['results'],expected):
 need(set(actual)==set(wanted),'Description field set')
 for k,v in wanted.items():
  a=actual[k]
  need(all(close(x,y) for x,y in zip(a,v)) and len(a)==len(v) if isinstance(v,list) else close(a,v) if isinstance(v,float) else a==v,'Description statistic '+k)
counts={rep:{'at_most_1_10':sum(r[rep+'_ratio']<=1.10 for r in expected),'at_most_1_50':sum(r[rep+'_ratio']<=1.50 for r in expected),'range':[min(r[rep+'_ratio'] for r in expected),max(r[rep+'_ratio'] for r in expected)]} for rep in ('typed_double','ordinary')}
need(description['counts']==counts,'Descriptive threshold counts')
table=(E/'final-panel-table.md').read_text().splitlines();need(len(table)==36,'Table cardinality')
for line,r in zip(table[2:],expected):
 values=[r['width'],'yes' if r['missing']=='TRUE' else 'no',r['operation'],*(f'{r[k]:.3f}' for k in ('candidate_cpu_ms','direct_speedup','paired_speedup','typed_double_ratio','ordinary_ratio'))]
 need(line=='| '+' | '.join(values)+' |','Table differs from independently calculated values')
# Publisher replay must reproduce the complete existing bundle byte for byte.
a,b=inventory(PUBLIC),inventory(REPLAY);need(a==b,'Public publisher replay differs')
manifest=read(PUBLIC/'publication-manifest.json');need(manifest=={p:h for p,h in a.items() if p!='publication-manifest.json'},'Incomplete public manifest')
source_map=read(PUBLIC/'publication-source-map.json')
need(len(source_map)==66 and len({x['artifact'] for x in source_map})==66,'Source map cardinality')
need(set(x['artifact'] for x in source_map)==set(a)-{'README.md','publication-manifest.json','publication-source-map.json'},'Source map coverage')
def original_path(name):
 if name.startswith('acceptance-v1/'):return E/name
 if name.startswith('acceptance-controller/dependencies/'):return RECORDER/name.removeprefix('acceptance-controller/dependencies/')
 if name.startswith('acceptance-controller/'):return E/name
 if name.startswith('builds/baseline/'):return BASE/name.removeprefix('builds/baseline/')
 if name.startswith('builds/candidate/'):return CANDIDATE/name.removeprefix('builds/candidate/')
 if name.startswith(('qualification/','validation/')):return E/Path(name).name
 if name=='publish-final-acceptance.py':return E/name
 raise RuntimeError('Unknown publication original '+name)
identities=set()
def scan_identity(value,redacted=False):
 if isinstance(value,dict):
  for k,v in value.items():
   if k in ('USER','LOGNAME'):
    need(isinstance(v,dict) and set(v)=={'value','sha256'},'Unexpected identity schema')
    if redacted:need(v=={'value':'<private>','sha256':'<private>'},'Exposed identity field')
    else:identities.update(x for x in v.values() if x and x!='<private>')
   else:scan_identity(v,redacted)
 elif isinstance(value,list):
  for v in value:scan_identity(v,redacted)
for item in source_map:
 name=item['artifact'];origin=original_path(name)
 need(sha(origin)==item['source_sha256'] and a[name]==item['published_sha256'],'Original/public mapping mismatch')
 need(item['transformation']==('none' if origin.read_bytes()==(PUBLIC/name).read_bytes() else 'private path/identity redaction or JSON formatting'),'Transformation label mismatch')
 if origin.suffix=='.json':scan_identity(read(origin))
for name in a:
 text=(PUBLIC/name).read_text()
 need(not re.search(r'/(?:Users|home|private/tmp|tmp)/',text),'Private path in '+name)
 for token in identities:need(not re.search(r'(?<![\w])'+re.escape(token)+r'(?![\w])',text),'Identity value or direct digest in '+name)
 if name.endswith('.json'):scan_identity(json.loads(text),True)
need((PUBLIC/'publish-final-acceptance.py').read_bytes()==(E/'publish-final-acceptance.py').read_bytes(),'Publisher source changed by redaction')
report=dict(status='PASS',source_commits=audit['source_commits'],observations=1224,qualification_observations=204,summary_rows=68,description_cases=34,published_artifacts=len(a),source_map_entries=len(source_map),audit_replay_byte_identical=True,measurement_worker_unchanged=True,controller_delta='Only exact candidate pin, prose and transitive-recorder dependency declaration; original measurement flow unchanged.',full_current_source_installed_runtime_replay=True,all_description_statistics_and_table_recomputed=True,publication_replay_byte_identical=True,original_public_hash_mapping_verified=True,direct_identity_values_and_hashes_removed=True,original_whole_artifact_hashes_preserved=True,counts=counts,reviewer_script_sha256=sha(Path(__file__)),auditor_sha256=sha(original),publisher_sha256=sha(E/'publish-final-acceptance.py'),original_audit_sha256=sha(E/'acceptance-independent-audit.json'),description_sha256=sha(E/'final-panel-description.json'),public_manifest_sha256=sha(PUBLIC/'publication-manifest.json'),public_source_map_sha256=sha(PUBLIC/'publication-source-map.json'),scope='No new measurement. Replayed reviewed audit with only its output destination redirected through an AST assignment; original auditor bytes and evidence unchanged. Full current inventories/runtime, matrix/orders/semantics/counts, medians and description statistics rechecked. Public bundle reproduced independently and checked for private paths/direct identity values and digests. Package conformance remains separately bound by final integration.')
(E/'reader-publication-review.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({'status':'PASS','artifacts':len(a),'observations':1224,'counts':counts}))
