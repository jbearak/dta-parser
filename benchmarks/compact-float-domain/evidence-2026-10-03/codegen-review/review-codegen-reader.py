import hashlib, importlib.util, json, os, re, shlex, subprocess
from pathlib import Path
P=Path('<evidence>'); R=Path('<repository>'); B=P/'candidate-final-v1'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def need(v,m):
 if not v: raise RuntimeError(m)
a=json.loads((P/'candidate-codegen-binding.json').read_text()); b=json.loads((P/'release-remarks-v1/binding.json').read_text())
pin='452ac7232ef6e47c398bcd22c7bb2800b55932c3'
need(a['status']==b['status']=='PASS' and a['commit']==b['source_commit']==pin,'pins')
spec=importlib.util.spec_from_file_location('records',R/'benchmarks/native-operations/run.py'); mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
i=mod.inventory(B,'baseline');need(i['receipt']['base_commit']==pin and i['receipt_sha256']==a['build_receipt_sha256']==b['build_receipt_sha256'],'build')
need(sha(P/'bind-codegen.py')==a['controller_sha256'] and sha(P/'compile-remarks.py')==b['controller_sha256'],'controllers')
need(sha(R/'benchmarks/native-operations/run.py')==a['recorder_sha256'],'recorder')
need(sha(a['command'][0])==a['disassembler_sha256'] and sha(a['command'][-1])==a['dll_sha256'],'installed extraction inputs')
need(sha(P/'candidate-otool.txt')==a['output_sha256'],'extraction')
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
for rel,h in a['source'].items():
 need(sha(B/'source'/rel)==h,'source hash')
 need(hashlib.sha256(subprocess.check_output(['git','--no-replace-objects','show',pin+':r-package/dtatools/'+rel],cwd=R,env=env)).hexdigest()==h,'immutable source')
for name,h in b['source_sha256'].items():
 need(sha(Path(b['cwd'])/name)==h,'consumed source')
 source=B/'source/src'/name
 need(source.exists() and sha(source)==h,'consumed versus exported source')
for name,h in b['artifacts'].items():need(sha(P/'release-remarks-v1'/name)==h,'remarks artifact')
need(sha(b['diagnostic_command'][0])==b['compiler_sha256'],'compiler')
original=shlex.split(b['actual_build_command']); diagnostic=b['diagnostic_command']
need(original[1:original.index('-o')]==diagnostic[1:diagnostic.index('-o')],'release flags')
need(diagnostic[diagnostic.index('-o')+2:]==['-Rpass=loop-vectorize','-Rpass-missed=loop-vectorize','-Rpass-analysis=loop-vectorize'],'only diagnostic flags added')
need((B/'build.log').read_text().splitlines().count(b['actual_build_command'])==1,'actual compile record')
remarks=(P/'release-remarks-v1/remarks.log').read_text()
for line in (121,123,127,129):need(re.search(r'pair-long-float.h:'+str(line)+r':13: remark: vectorized loop \(vectorization width: 4, interleaved count: 4\)',remarks),'canonical vectorization')
for line in (77,79,81,86,88,90):need(re.search(r'pair-long-float.h:'+str(line)+r':13: remark: vectorized loop \(vectorization width: 4,',remarks),'fallback vectorization')
asm=(P/'candidate-otool.txt').read_text();loop=asm[asm.index('0000000000195680'):asm.index('00000000001957b4')]
for token in ['fcmge.4s','fcvtl','fadd.2d','bit.16b','stp\tq','subs\tx14, x14, #0x10']:need(token in loop,'representative SIMD loop')
record=dict(status='PASS',commit=pin,build_receipt_sha256=i['receipt_sha256'],source_headers=len(a['source']),consumed_sources=len(b['source_sha256']),canonical_vectorized_lines=[121,123,127,129],unknown_fallback_vectorized_lines=[77,79,81,86,88,90],representative_installed_loop='0x195680-0x1957b0',scope='Independent current binding replay and representative installed SIMD inspection; no cross-compiler or timing claim.',artifacts={n:sha(P/n) for n in ['candidate-codegen-binding.json','release-remarks-v1/binding.json','review-codegen-reader.py']})
(P/'reader-codegen-independent-review.json').write_text(json.dumps(record,indent=2)+'\n');print('PASS',len(a['source']),len(b['source_sha256']))
