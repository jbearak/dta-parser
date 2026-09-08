from pathlib import Path
from datetime import datetime,timezone
import csv,hashlib,json,shlex,struct
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def check(row):assert ident(row['path'])==row,row['path']
def deps(p):
 t,sep,n=p.read_text().replace('\\\n',' ').partition(':');assert sep and t.strip()=='diagnostic';return sorted({str(Path(x).resolve()) for x in shlex.split(n)})
pins={'read-count-control-v1.c':'6a8e877c22228606c5a223cf276629ce94421f020dc355854b810aac70a6612d','read-count-control-v1.R':'fa4b27a88d55d808236403b4958ff3a1d9bcef9796ffb9be13b26dbfddbb1c88','read-count-control-v1.py':'01d124dc60c85649b813dc8b92b053066fecb2efa3c1f78cafa31b99614e64e6','build-read-count-control-v1.py':'2626d2cde41d8224668d1db6b76880851ea1ebfe73ca24fef1b3aaf8f578c5dd'}
for p,h in pins.items():assert ident(root/p)['sha256']==h
assert (root/'build-read-count-control-v1.py').read_text()==(root/'build-read-control-v5.py').read_text().replace('Usage: build-read-control-v5.py','Usage: build-read-count-control-v1.py').replace("source = ROOT / 'read-control-v1.c'","source = ROOT / 'read-count-control-v1.c'")
full=(root/'read-count-control-v1.R').read_text();tiny=(root/'read-count-tiny-check-v1.R').read_text();assert tiny.startswith(full.split('records <- states <- visits <- list()\n')[0]);assert 'bench::mark(' not in tiny and 'atomic_profile(' not in tiny
prior=json.loads((review/'read-control-final-preparation-review-01.json').read_text());check(prior['macho']['identity'])
for x in prior['sources']:
 if x['path'].endswith('read-control-v1.c'):check(x)
build=root/'native-read-count-control-build-v1-01';rp=build/'completed-receipt.json';receipt=json.loads(rp.read_text());assert receipt['accepted'] and receipt['changed_inputs']==[] and ident(rp)['sha256']=='13a64e286d65a0fc233ec5df24fc1fbe439ea13681f8ba51a938d303be320b08';check(receipt['manifest'])
products=json.loads((build/'manifest.json').read_text())['products'];inputs=json.loads((build/'inputs-before.json').read_text())['inputs'];preparation=json.loads((build/'preparation-inputs-before.json').read_text())['inputs']
assert len(products)==8 and len(inputs)==192
for x in products+inputs+preparation:check(x)
assert all(x in inputs for x in preparation)
headers=deps(build/'dependency-discovery.txt');assert headers==deps(build/'compiled-dependencies.txt') and set(headers)<={x['resolved'] for x in inputs}
e=json.loads((build/'execution-result.json').read_text());assert e['accepted'] and e['changed_inputs']==[] and e['error'] is None and len(e['commands'])==2 and all(x['returncode']==0 for x in e['commands']);assert not (build/'build.log').read_bytes() and not (build/'dependency-discovery.log').read_bytes()
# Retained Mach-O inspection only, with no loading/execution.
dll=build/'dta_read_control.so';b=dll.read_bytes();magic,cpu,sub,typ,ncmd,size,flags,res=struct.unpack_from('<8I',b);assert magic==0xfeedfacf and typ==6
pos=32;libraries=[];symtab=None
for _ in range(ncmd):
 cmd,n=struct.unpack_from('<II',b,pos);assert n>=8 and pos+n<=len(b)
 if cmd in (0xc,0x80000018,0x8000001f,0x20,0x80000023):
  off=struct.unpack_from('<I',b,pos+8)[0];libraries.append(b[pos+off:pos+n].split(b'\0',1)[0].decode())
 if cmd==2:symtab=struct.unpack_from('<4I',b,pos+8)
 pos+=n
assert pos==32+size and libraries==['/usr/lib/libSystem.B.dylib'] and symtab
symoff,nsyms,stroff,strsize=symtab;strings=b[stroff:stroff+strsize];undefined=[]
for i in range(nsyms):
 strx,t,section,desc,value=struct.unpack_from('<IBBHQ',b,symoff+16*i)
 if (t&0x0e)==0 and t&1:undefined.append(strings[strx:].split(b'\0',1)[0].decode())
assert {'_DATAPTR_RO','_INTEGER_ELT','_LOGICAL_ELT','_R_registerRoutines'}<=set(undefined)
expected_build=[ident(rp),receipt['manifest'],*products,*inputs];all_inputs={};runs=[];common=None
for label,pin in [('baseline-ec10','8a68e63121b4f908dacbba79e9fafc1eb6e75d5293342e0704b83a01914cbce4'),('candidate-a2d8b6a','259cbd153f9cdfd42b7008c723bcfd2b24c640ed5277d1f385a5bde6c28b3d90')]:
 name=label+'-read-count-tiny-01';d=root/name;recpath=root/(name+'-receipt.json');rec=json.loads(recpath.read_text());ib=json.loads((d/'inputs-before.json').read_text());m=json.loads((d/'manifest.json').read_text())
 assert ident(recpath)['sha256']==pin and rec['accepted'] and rec['returncode']==0 and rec['changed_inputs']==[] and rec['integrity_error'] is None and rec['namespace_coverage'] and rec['dll_coverage'];check(rec['manifest'])
 for x in m['products']:check(x)
 assert len(m['products'])==7 and {p.name for p in d.iterdir() if p.is_file()}=={Path(x['path']).name for x in m['products']}|{'manifest.json'}
 index={x['path']:x for x in ib['inputs']};assert len(index)==len(ib['inputs'])
 for x in expected_build:assert index[x['path']]==x
 for x in ib['inputs']:
  if x['path'] in all_inputs:assert all_inputs[x['path']]==x
  all_inputs[x['path']]=x
 source='ec10a6ac34602f3bd691e8043019c1b479babda4' if label=='baseline-ec10' else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9';assert ib['source']==source and ib['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
 assert ib['command'][2]==str(root/'read-count-tiny-check-v1.R') and ib['command'][-1]==str(dll)
 bound={x['resolved'] for x in ib['inputs']};ns=list(csv.DictReader((d/'namespaces.tsv').open(),delimiter='\t'));package=Path(next(x['path'] for x in ns if x['name']=='dtatools')).resolve()
 for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve()) in bound
 for x in csv.DictReader((d/'dlls.tsv').open(),delimiter='\t'):
  if x['name']=='base' and x['path']=='base':continue
  assert str(Path(x['path']).resolve()) in bound
 nonpackage={k:v for k,v in index.items() if not Path(k).is_relative_to(package)}
 if common is None:common=nonpackage
 else:assert common==nonpackage
 log=(d/'execution.log').read_text();assert log.count('Checking tiny nonmissing control')==24 and log.rstrip().endswith('PASS 24 untimed logical/factor/ordered correctness cases; no profiling or timing')
 assert not any(p.name.startswith('raw-timing') for p in d.iterdir())
 runs.append(dict(name=name,receipt=ident(recpath),inputs=len(index),products=len(m['products']),source=source,command=ib['command']))
for x in all_inputs.values():check(x)
records=list(csv.DictReader((review/'read-count-tiny-records-01.csv').open()));assert len(records)==48
assert 'PASS 48 saved tiny count records' in (review/'read-count-tiny-record-reader-01.log').read_text()
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='count_control_preparation_clear',reviewer_script=ident(__file__),sources=[ident(root/x) for x in [*pins,'read-count-tiny-check-v1.R','read-count-tiny-check-v1.py','read-count-control-preparation.md']],build=dict(receipt=ident(rp),products=products,inputs=192,discovered_equals_consumed_headers=headers,dll=ident(dll),macho_libraries=libraries,undefined_symbols=undefined),tiny_runs=runs,distinct_runtime_inputs=len(all_inputs),exact_common_nonpackage_inputs=len(common),tiny_records=records,saved_reader=[ident(review/x) for x in ['read-count-tiny-record-reader-01.R','read-count-tiny-record-reader-01.log','read-count-tiny-records-01.csv']],assessment=[
'Actual new C/R sources, runtime/builder deltas, exact tiny-prefix drivers and preparation note read. The original character control C/DLL remain unchanged. Count builder differs from accepted character v5 only in C source path/usage; runtime preserves accepted-build, source, namespace/DLL and before/after identity guards with only driver/scope changes.',
'C accepts LGLSXP or INTSXP of at most one million values. Rooted LOGICAL_ELT/INTEGER_ELT full loops count values unequal to their NA sentinel. The read-only DATAPTR_RO int pointer is rooted, never escapes and is not used across allocation/callback/write. Count fits exact R integer range. The separate visit loop returns protected two-element REAL count/visits and counts its own iterations only.',
'R tests logical/factor/ordered ordinary and table columns with empty/nonmissing/all-NA/mixed cases, preserving type, factor levels/class, label and values. The independent logical-pattern oracle yields exact integer counts. Both exact-source tiny runs pass24 combinations each; independent saved-RDS-only reading confirms48 saved counts/types/attributes identical across sources.',
'Actual build receipt and all192 inputs/eight products match. Compiler/header dependency discovery equals consumed -MD headers; explicit SDK/linker, libSystem stubs/compilerRT and cast-warning scope are inherited unchanged. Read-only Mach-O inspection finds only libSystem linkage and unresolved public R APIs, with no second libR.',
'Both tiny runs retain seven products, exact installed sources, common runtime/helper/build identities and namespace/DLL coverage. Their prefix is byte-identical to the new measurement driver before the large-loop marker and includes no profiling/timing call. The measurement driver remains unexecuted at review.',
'Planned measured scope is24 series: three kinds, two row sizes, four methods, one column and original25-percent-NA fixtures. Public table and pre-extracted sum(!is.na) retain the same whole expression; native pointer/element methods are matched full scans that return the same count. Their allocation cost is not equivalent to the whole public R expression and must not be used as such.',
'All setup, independent ordinary reference, tiny correctness, native visit counting, metadata/backing checks and GC are outside bench timing. Seven raw sample seconds, numeric millisecond medians, GC/allocation summaries and source states will be saved; raw Rprofmem events and per-timed-call native counters remain outside retained scope.',
'Preparation note correctly limits preceding character evidence and this extension. These controls test logical/factor/ordered nonmissing counts; they cannot alone attribute mean/coercion/other open reads, isolate a getter latency or establish exclusive cause, irreducibility or Stage5 acceptance.'
],limits='Source, accepted-build and retained tiny-output audit only. Reviewer ran only a saved-RDS reader, not a constructor/native-control loop, build, profile, test rerun or benchmark. Actual timed outputs and interpretation still require independent audit.')
with (review/'read-count-preparation-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],build_inputs=192,build_products=8,tiny_cases=48,distinct_inputs=len(all_inputs),common_inputs=len(common),report=ident(review/'read-count-preparation-review-01.json'))))
