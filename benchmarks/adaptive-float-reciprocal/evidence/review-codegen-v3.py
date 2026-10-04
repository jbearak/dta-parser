from pathlib import Path
import json,hashlib,subprocess,os,shlex
w=Path(__file__).parent;b=w/'candidate-v3';o=w/'codegen-v3';r=json.loads((b/'build-receipt.json').read_text());c=json.loads((o/'binding.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(v,label):
 if not v: raise RuntimeError(label)
require(c['source_commit']==r['base_commit']=='2ec57f24a14a646ae67fd2e0af4fb8ef1c549f52','commit')
require(c['build_receipt_sha256']==sha(b/'build-receipt.json'),'receipt')
require(c['installed_dll_sha256']==sha(b/'library/dtatools/libs/dtatools.so'),'DLL')
require(c['built_object_sha256']==sha(b/'build/src/numeric-payload.o'),'object')
for n,h in c['artifact_sha256'].items(): require(sha(o/n)==h,n)
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
for n,h in c['consumed_numeric_source_sha256'].items():
 require(sha(b/'build/src'/n)==h,n)
 data=subprocess.check_output(['git','--no-replace-objects','show',c['source_commit']+':r-package/dtatools/src/'+n],cwd='<measured-source>',env=env)
 require(hashlib.sha256(data).hexdigest()==h,n+' Git')
require(c['actual_build_command'] in (b/'build.log').read_text().splitlines(),'build command')
a=shlex.split(c['actual_build_command']);q=list(c['remark_command']);require(q[-3:]==['-Rpass=loop-vectorize','-Rpass-missed=loop-vectorize','-Rpass-analysis=loop-vectorize'],'remark flags');q=q[:-3];q[0]=a[0];q[q.index('-o')+1]='numeric-payload.o';require(a==q,'flags equality')
remarks=(o/'remarks.log').read_text();lines=[x for x in remarks.splitlines() if 'numeric-arithmetic-float-reciprocal.h:83:' in x and 'vectorized loop (vectorization width: 16' in x];require(len(lines)==2,'two preparation loops width16')
def contains(v,s):
 if isinstance(v,dict): return any(contains(x,s) for x in v.values())
 if isinstance(v,list): return any(contains(x,s) for x in v)
 return v==s
require(contains(r,c['installed_dll_sha256']),'receipt DLL')
rec={'status':'PASS','source_commit':c['source_commit'],'binding_sha256':sha(o/'binding.json'),'build_receipt_sha256':sha(b/'build-receipt.json'),'installed_dll_sha256':c['installed_dll_sha256'],'built_object_sha256':c['built_object_sha256'],'verified_numeric_source_files':len(c['consumed_numeric_source_sha256']),'verified_artifacts':len(c['artifact_sha256']),'checks':['current installed DLL equals clean receipt and codegen record','current built object and all saved artifacts equal record','consumed numeric files equal immutable Git blobs','actual release compile command equals build log','remark command differs only in output/compiler absolute path and diagnostic flags','both preparation loops report width16 vectorization'],'scope':'Post-run independent hash/source/flags replay. No recompilation, R execution or fresh disassembly; no timing inference. Original record does not bind disassembler/clang executable hashes.'}
(w/'codegen-v3-independent-review.json').write_text(json.dumps(rec,indent=2)+'\n');print('PASS codegen v3')
