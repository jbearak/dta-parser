import hashlib,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
names={'previous':('candidate-v1','candidate-codegen-binding.json','candidate-otool.txt'),
       'final':('candidate-all-missing-v1','all-missing-candidate-codegen-binding.json','all-missing-candidate-otool.txt')}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def need(c,m):
 if not c:raise RuntimeError(m)
def extract(path):
 text=path.read_text();label='_arithmetic_long_float_add_exact:\n';need(text.count(label)==1,'Function label ambiguity')
 body=text.split(label,1)[1];body=re.split(r'^_[^\n]+:\n',body,maxsplit=1,flags=re.M)[0]
 rows=[]
 for line in body.splitlines():
  match=re.fullmatch(r'([0-9a-f]{16})\t([^\t]+)(?:\t(.*))?',line)
  need(match is not None,'Unexpected disassembly line: '+line)
  rows.append((int(match[1],16),match[2],match[3] or ''))
 start=rows[0][0];end=rows[-1][0]+4;out=[];branches=0;pages=0
 for address,op,arg in rows:
  if op=='b' or op.startswith('b.') or op in ('cbz','cbnz','tbz','tbnz'):
   m=re.search(r'0x([0-9a-f]+)$',arg);need(m is not None,'Unexpected branch format')
   target=int(m[1],16);need(start<=target<end,'External branch not allowed in this comparison')
   arg=arg[:m.start()]+'relative:'+hex(target-start);branches+=1
  if op=='adrp':
   m=re.fullmatch(r'(x\d+), \d+ ; (0x[0-9a-f]+)',arg);need(m is not None,'Unexpected page reference')
   arg=m[1]+', absolute-page:'+m[2];pages+=1
  out.append(op+'\t'+arg)
 return body,out,dict(start=hex(start),end=hex(end),instructions=len(rows),internal_branch_targets=branches,page_references=pages,
                     vector_adds=sum(op=='fadd.2d' for _,op,_ in rows),vector_loads=sum(op in ('ld1.2d','ld1.4s','ldp') for _,op,_ in rows))
records={};normalized={}
for role,(build,receipt_name,dump_name) in names.items():
 binding=json.loads((HERE/receipt_name).read_text());dump=HERE/dump_name;dll=HERE/build/'library/dtatools/libs/dtatools.so'
 need(sha(dump)==binding['output_sha256'],'Disassembly changed');need(sha(dll)==binding['dll_sha256'],'Bound DLL changed')
 need(sha(HERE/build/'build-receipt.json')==binding['build_receipt_sha256'],'Build receipt changed')
 body,normalized[role],facts=extract(dump)
 (HERE/(role+'-exact-loop.txt')).write_text(body)
 records[role]=dict(binding_sha256=sha(HERE/receipt_name),dump_sha256=sha(dump),dll_sha256=sha(dll),commit=binding['commit'],facts=facts)
need(normalized['previous']==normalized['final'],'Exact helper instructions differ after relocation normalization')
need(records['previous']['facts']['vector_adds']>0,'No vector addition remains')
record=dict(status='PASS',controller_sha256=sha(Path(__file__)),inputs=records,scope='Exact helper instruction text comparison only. Internal branch targets become function-relative; ADRP compares its resolved absolute target page. Registers, other operands, comments and all other instructions remain exact. Existing fresh DLL-extraction bindings and both current DLL/build receipt hashes are rechecked. Caller layout, surrounding instructions and performance are not proved equal.',equal_instruction_count=len(normalized['final']))
(HERE/'exact-loop-comparison.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
print('PASS',record['equal_instruction_count'],'exact helper instructions agree modulo recorded relocation normalization')
