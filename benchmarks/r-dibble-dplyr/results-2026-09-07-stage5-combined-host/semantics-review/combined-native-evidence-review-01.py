from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,subprocess,tarfile,csv,itertools,re
root=Path('/private/tmp/dta-direct-stage5-validation/implementation');folder=root/'native-combined-01';review=Path(__file__).parent;repo=Path('/private/tmp/dta-direct-stage5');source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
receipt=ident(folder/'receipt.json');assert receipt['sha256']=='dd931f0abc8781478bac62e71dc349124432fa4eceaebf7c7c70735261e76b35'
r=json.loads((folder/'receipt.json').read_text());m=json.loads((folder/'manifest.json').read_text());b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
assert r['status']==e['status']=='complete' and not r['changed_inputs'] and not e['changed_inputs']
assert r['source_sha']==r['runner_sha']==b['source_sha']==b['runner_sha']==source
assert r['manifest']==ident(folder/'manifest.json')
for row in m['products']:assert ident(row['path'])==row,row['path']
assert len({x['path'] for x in m['products']})==len(m['products'])
assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-{str(folder/'manifest.json'),str(folder/'receipt.json')}
for row in b['inputs']:assert ident(row['path'])==row,row['path']
assert len({x['path'] for x in b['inputs']})==len(b['inputs'])
assert [x['label'] for x in e['records']]==['preflight','native','native-atoms','rename'] and all(x['exit_code']==0 for x in e['records'])
for command in e['records']:
 assert command==json.loads((folder/(command['label']+'-command.json')).read_text())
 assert command['log']==ident(command['log']['path'])
entries={}
for item in git('ls-tree','-r','-z',source).split(b'\0'):
 if not item:continue
 meta,name=item.split(b'\t',1);mode,kind,sha=meta.decode().split();assert kind=='blob';entries[name.decode()]=(mode,sha)
seen=set()
with tarfile.open(folder/'source.tar') as tar:
 for member in tar:
  assert member.isfile() or member.isdir()
  if not member.isfile():continue
  assert member.name in entries and member.name not in seen;seen.add(member.name)
  mode,sha=entries[member.name];payload=tar.extractfile(member).read()
  assert hashlib.sha1(b'blob '+str(len(payload)).encode()+b'\0'+payload).hexdigest()==sha
  assert (folder/'source'/member.name).read_bytes()==payload
assert seen==set(entries)
inputs={x['path']:x for x in b['inputs']}
assert str(folder/'source.tar') in inputs
source_scripts=['benchmarks/r-reference-mutation/run.R','benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R','benchmarks/r-dibble-dplyr/check-rename-allocation.R','benchmarks/r-dibble-dplyr/run-expression-checks.py']
for name in source_scripts:
 assert (folder/'source'/name).read_bytes()==git('show',source+':'+name)
for name in source_scripts[:4]:assert (folder/'source'/name).read_bytes()==git('show','f622f1ddba04b2bb7ac07415faccf2b417aab0e6:'+name)
for name in ['benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R']:
 assert str(repo/name) in inputs and (repo/name).read_bytes()==(folder/'source'/name).read_bytes()
session=(folder/'atoms/owned-native-atoms-session.txt').read_text();assert 'source '+source in session and 'runner_revision ea031bec2df4d6711f1214b5dd3d00ebf029b3f1' in session
for name in ['benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R']:assert name+' '+ident(repo/name)['sha256'] in session
native=(folder/'native.log').read_text();pairs=[x.split('\t') for x in native.splitlines()];assert all(len(x)==2 for x in pairs);metrics=dict(pairs);assert len(metrics)==len(pairs)
assert metrics['benchmark_source_sha']==source and metrics['benchmark_source_state']=='clean' and metrics['existing_payload_copy_detected']=='false'
assert metrics['rows']=='5000000' and metrics['repetitions']=='100'
mdpairs=re.findall(r'^\| `([^`]+)` \| ([^|]+) \|$',(folder/'native.md').read_text(),re.M);assert mdpairs==[tuple(x) for x in pairs]
rows=list(csv.DictReader((folder/'atoms/owned-native-atoms.csv').open()));assert len(rows)==18
assert {(x['kind'],int(x['rows']),x['operation']) for x in rows}==set(itertools.product(['integer','factor','ordered'],[100000,1000000],['first_shared','subsequent_private','full_replacement']))
for x in rows:
 n=int(x['rows']);op=x['operation'];v={k:float(y) for k,y in x.items() if k not in ['kind','rows','operation']}
 assert v['owned_capture']==v['compact_copy']==v['old_journal']==v['native_scratch_allocated']==0 and v['staged_new']==4
 assert v['mutation_target_copy']==(n*4 if op=='first_shared' else 0)
 assert v['r_allocated_bytes']==v['r_largest_allocation_bytes']==(0 if op=='subsequent_private' else n*4+48)
assert 'Passed all 18 native integer/factor allocation and isolation cases.' in (folder/'native-atoms.log').read_text()
rename=[int(x) for x in re.findall(r': (\d+) bytes',(folder/'rename.log').read_text())];assert rename==[0,0,40056,80112] and all(x<800000 for x in rename)
reader=(review/'combined-native-record-reader-02.log').read_text();assert 'PASS retained provenance files' in reader
# A full static walk includes function bodies and loop sites, not execution counts.
assert re.search(r'38\s+174\s+17',reader)
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_exact_native_evidence_clear',source=source,runner=source,package_tree='b08c77d91bdce67032f13aced90c29d068d6e95a',reviewer_script=ident(__file__),receipt=receipt,manifest=ident(folder/'manifest.json'),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),inputs=len(b['inputs']),input_bytes=sum(x['bytes'] for x in b['inputs']),source_archive=ident(folder/'source.tar'),source_archive_files=len(entries),commands={x['label']:x['exit_code'] for x in e['records']},native_metric_fields=len(metrics),native_static_ast_counts=dict(stopifnot_call_sites=38,assertion_expressions_including_function_bodies=174,capacity_readiness_call_sites_including_loop_bodies=17),native_atoms=dict(cases=18,rows=[100000,1000000],kinds=['integer','factor','ordered'],first_shared_target_copy='4 bytes per row; R allocation exactly payload+48',subsequent_private='same backing and zero target copy/R allocation',full_replacement='new backing, no old payload copy; R allocation payload+48'),rename=dict(rows=100000,threshold_bytes=10000,typed_largest=0,typed_recorded_total=0,dibble_largest=40056,dibble_recorded_total=80112,each_dibble_budget_strictly_below=800000),reader=[ident(review/'combined-native-record-reader-02.R'),ident(review/'combined-native-record-reader-02.log')],assessment='All four commands completed successfully on exact combined a2 installed package and source-bound drivers. Every declared input and completed output was independently rehashed; exact output scope and source archive Git blob identities match. Native source assertions and capacity/private readiness checks remain unchanged from Stage4. The 18 atom allocation/isolation cases and thresholded rename budgets pass. Installed package file MD5 provenance, DLL and host runtime were independently read and checked. The atom command ran from ea031 worktree; its two script bytes equal a2 and both worktree inputs are bound before and after execution, so its separately recorded runner_revision is accurate.',limits=['Reference driver assertion objects, alias snapshots and temporary Rprofmem event files are not retained; successful unchanged source-bound execution supports those checks, not independent replay of their object values. Numeric logs and Markdown match exactly; no timing comparison or overall performance acceptance is made.','Full static AST counts include helper function bodies and timed-loop readiness sites, and are not dynamic assertion execution counts. Earlier 159/15 shorthand is not reused.','Reference allocation records use Rprofmem threshold 1000; rename threshold 10000; atom profiling is unthresholded. Native counters overlap by their defined categories and are not total RSS or total process allocations.','Host R4.6.1/macOS aarch64 only. Visible R/site/library/tool files are bound, while external OS dylibs, SDK and full Python closure are excluded per original scope. Native generation interrupt handshake is separately covered by combined full tests; this native allocation gate is not a new SIGINT run.','First reviewer AST reader failed on missing formal arguments before any evidence change; second reader handles missing syntax nodes. Both sources/logs retained. No tests, native calls, profiling or benchmark workloads were rerun.'])
with (review/'combined-native-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps({k:result[k] for k in ['status','products','inputs','source_archive_files','native_metric_fields']}))
