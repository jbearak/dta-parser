from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,shlex,struct
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def check(row): assert ident(row['path'])==row,row['path']
def dep(p):
 target,sep,names=p.read_text().replace('\\\n',' ').partition(':');assert sep and target.strip()=='diagnostic'
 return sorted({str(Path(x).resolve(strict=True)) for x in shlex.split(names)})
old=json.loads((review/'read-control-preparation-review-01.json').read_text())
for row in old['inputs']:
 if row['path'].endswith(('.R','.c')): assert ident(row['path'])==dict(path=row['path'],resolved=str(Path(row['path']).resolve()),**{k:row[k] for k in ['bytes','mode','sha256']})
results=[]
for i in range(1,6):
 d=root/f'native-read-control-build-v{i}-01';receipt=d/'completed-receipt.json';r=json.loads(receipt.read_text());check(r['manifest'])
 m=json.loads((d/'manifest.json').read_text());e=json.loads((d/'execution-result.json').read_text())
 assert r['accepted']==e['accepted']==(i==5) and r['changed_inputs']==e['changed_inputs']==[]
 assert (e['error'] is None)==(i==5)
 for product in m['products']:check(product)
 assert {p.name for p in d.iterdir() if p.is_file()}=={Path(x['path']).name for x in m['products']}|{'manifest.json','completed-receipt.json'}
 inputs=[]
 for name in ('inputs-before.json','preparation-inputs-before.json'):
  p=d/name
  if p.exists():
   rows=json.loads(p.read_text())['inputs']
   for row in rows:check(row)
   inputs.append(dict(name=name,count=len(rows)))
 if i==5:
  assert ident(receipt)['sha256']=='a90771dd5c644160a2afe0bcce66f9bbf8d381ffe1d0987b5e1470125624cd74'
  assert len(m['products'])==8 and all(x['returncode']==0 for x in e['commands'])
  assert not (d/'build.log').read_bytes() and not (d/'dependency-discovery.log').read_bytes()
  before=json.loads((d/'inputs-before.json').read_text())['inputs']; assert len(before)==192
  prepare=json.loads((d/'preparation-inputs-before.json').read_text())['inputs']
  for row in prepare: assert row in before
  discovered=dep(d/'dependency-discovery.txt');assert discovered==dep(d/'compiled-dependencies.txt')
  assert set(discovered)<=set(x['resolved'] for x in before)
  compile=e['commands'][1]['command']; assert '-nostdlib' not in compile and '--ld-path=/Library/Developer/CommandLineTools/usr/bin/ld' in compile
  assert '-Wno-cast-function-type-mismatch' in compile and '-Werror' in compile and '-isysroot' in compile
  for suffix in ('/libclang_rt.osx.a','/SDKSettings.json','/libSystem.tbd'):
   assert any(x['path'].endswith(suffix) for x in before),suffix
 results.append(dict(version=i,receipt=ident(receipt),accepted=r['accepted'],inputs=inputs,products=len(m['products']),commands=e['commands'],error=e['error']))
d=root/'read-control-binding-checks-01';rec=d/'completed-receipt.json';r=json.loads(rec.read_text());assert r['accepted'] and ident(rec)['sha256']=='f2963685ea6aa2c2c9c17b258c8087fa6101a9d971fa93c2e3bb0e48cb8d8471';check(r['manifest'])
products=json.loads((d/'manifest.json').read_text())['products'];assert len(products)==3
for x in products:check(x)
inputs=json.loads((d/'inputs-before.json').read_text())['inputs'];assert len(inputs)==4
for x in inputs:check(x)
e=json.loads((d/'execution-result.json').read_text());assert e['accepted'] and e['returncode']==0 and e['changed_inputs']==[] and e['error'] is None
log=(d/'tests.log').read_text();assert log.count(' ... ok')==8 and 'Ran 8 tests' in log and log.rstrip().endswith('OK')
# Read the Mach-O load commands and symbol table; do not execute or load the DLL.
p=root/'native-read-control-build-v5-01/dta_read_control.so';b=p.read_bytes();magic,cpu,sub,typ,ncmd,sizeofcmds,flags,reserved=struct.unpack_from('<8I',b)
assert magic==0xfeedfacf and typ==6
pos=32;libraries=[];symtab=None
for _ in range(ncmd):
 cmd,size=struct.unpack_from('<II',b,pos);assert size>=8 and pos+size<=len(b)
 if cmd in (0xc,0x80000018,0x8000001f,0x20,0x80000023):
  off=struct.unpack_from('<I',b,pos+8)[0];assert off<size;libraries.append(b[pos+off:pos+size].split(b'\0',1)[0].decode())
 if cmd==2:symtab=struct.unpack_from('<4I',b,pos+8)
 pos+=size
assert pos==32+sizeofcmds and libraries==['/usr/lib/libSystem.B.dylib'] and symtab
symoff,nsyms,stroff,strsize=symtab;strings=b[stroff:stroff+strsize];undefined=[]
for i in range(nsyms):
 strx,typ,sect,desc,value=struct.unpack_from('<IBBHQ',b,symoff+16*i)
 if (typ&0x0e)==0 and typ&1:
  undefined.append(strings[strx:].split(b'\0',1)[0].decode())
assert '_DATAPTR_RO' in undefined and '_STRING_ELT' in undefined and '_R_registerRoutines' in undefined
sources=[root/n for n in ['read-control-v1.c','read-control-v1.R','read-control-v2.py','build-read-control-v1.py','build-read-control-v2.py','build-read-control-v3.py','build-read-control-v4.py','build-read-control-v5.py','test-read-control-bindings-v1.py','run-read-control-binding-checks-v1.py']]
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='final_control_preparation_clear',reviewer_script=ident(__file__),sources=[ident(p) for p in sources],builds=results,accepted_build_input_count=192,accepted_build_product_count=8,matched_compiler_header_paths=discovered,macho=dict(identity=ident(p),load_libraries=libraries,undefined_external_symbols=undefined,method='Read-only Python struct decoding of retained Mach-O header/load commands and nlist_64; no DLL load or execution.'),binding_checks=dict(receipt=ident(rec),bound_inputs=inputs,products=products,test_methods=8,rerun=False),assessment=[
'Actual final builder v5 and runtime v2 were read in full, along with both bounded test sources and all five build logs/command records. C/R bytes are unchanged from the reviewed public API scan and eight-control harness.',
'Runtime freezes receipt and manifest identities before parse; validates consumed JSON payload bytes/hash and full path identity; reads build-input JSON against its manifest product; retains accepted product/input records; requires final runtime inventory to match them; checks those same identities immediately before launch and in finalization. It cannot silently replace validated old build identities with newly observed changed identities.',
'Eight retained temporary-file tests pass with exact runner/test/runtime/Python input binding and three retained products. Tests cover unchanged JSON, changed artifacts, changed JSON before parse, changed mode, missing path, duplicate path, identical bytes at a changed resolved path and deleted-input change detection. These are helper guard tests, not an executed full R runtime integration test.',
'Build v5 binds explicit SDK settings, all discovered consumed headers, compiler/linker, libSystem SDK stubs and compiler RT archive before compile. Actual -MD dependencies equal discovery. The narrow cast warning exemption applies to standard R DL_FUNC registration casts while -Werror remains. Explicit --ld-path replaces a deprecated clang option; successful build/logs are clean.',
'Retained Mach-O load commands name only libSystem.B.dylib; no second libR is linked. Public R API references remain undefined for resolution against the running R process. Full compiler/OS dynamic library and Python closures remain outside the declared input contract.',
'Four original builds remain failed: v1 missing stdlib.h without explicit SDK, v2 deprecated -fuse-ld path rejected by Werror, v3 R registration cast warning rejected by Werror, and v4 macOS requires libSystem for a dylib. Their receipts/products were rehashed unchanged. V1 failed before writing an input inventory; its current source is observed, not retroactively bound as executed. V2 through v4 retained their preparation/final inventories.',
'The earlier v1 source review remains historical and was held from execution approval after the accepted-build rebinding gap was reported. This final review covers the actual v2 runtime and v5 successful build and supersedes v1 preparation assumptions only for those components.',
'No R process, control loop, native workload, benchmark, profile, build or test rerun was performed by this reviewer. Runtime source and successful build are clear for the coordinated bounded run; actual runtime outputs and their interpretations still require review.'
],limits='Preparation and retained build/guard evidence review only. No timing, performance acceptance, full-matrix or exclusive-cause claim. No active reviewer workload remains.')
with (review/'read-control-final-preparation-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],build_inputs=192,build_products=8,tests=8,failed_builds=4,loaded_libraries=libraries,report=ident(review/'read-control-final-preparation-review-01.json'))))
