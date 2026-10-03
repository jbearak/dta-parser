from pathlib import Path
from fractions import Fraction
import hashlib,json,subprocess
P=Path('<work>/f32-equivalence')
OUT=Path('<independent-audit-work>/f32-equivalence-audit.json')
def require(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def binary(bits,fb,eb,bias):
    sign=-1 if bits>>(fb+eb) else 1
    exponent=(bits>>fb)&((1<<eb)-1); mantissa=bits&((1<<fb)-1)
    require(exponent!=(1<<eb)-1,'finite witness')
    if exponent:mantissa|=1<<fb
    return sign*Fraction(mantissa)*Fraction(2)**((exponent-bias if exponent else 1-bias)-fb)
def f32(bits):return binary(bits,23,8,127)
def value(record):return f32(int(record['bits'],16)) if record['kind']==2 else Fraction(record['integer'])
r=json.loads((P/'receipt.json').read_text())
require(r['before']==r['after'],'stable source/compiler/controller')
for path,digest in r['before'].items():require(sha(path)==digest,'current bound file '+path)
require(r['source_status']=='','clean recorded source')
root=Path('<repo>')
source='r-package/dtatools/src/numeric-payload.c'
blob=subprocess.check_output(['git','show',r['source_head']+':'+source],cwd=root)
require(hashlib.sha256(blob).hexdigest()==r['before'][str(root/source)],'classifier source belongs to recorded Git head')
text=blob.decode()
for name,record in r['functions'].items():
    require(record['text'] in text and hashlib.sha256(record['text'].encode()).hexdigest()==record['sha256'],'exact classifier extraction')
require((P/'extracted-classifiers.h').read_text()=='/* Exact source extraction; see receipt.json. */\n'+'\n'.join(x['text'] for x in r['functions'].values()),'extracted header identity')
for v in r['variants']:
    require(sha(P/('probe-'+v['label']))==v['binary_sha256'],'bound binary')
    result=P/(v['label']+'-result.json')
    require(sha(result)==v['result_sha256'] and json.loads(result.read_text())==v['result'],'bound full result')
    require('-frounding-math' in v['command'] and '-ffp-contract=off' in v['command'],'rounding compiler options')
require(r['variants'][0]['result']==r['variants'][1]['result'],'optimized/sanitizer identity')
a=r['variants'][0]['result']
require(a['checked']==36914944 and a['mismatches']==0 and a['column_checks']==19,'total coverage')
require(len(a['modes'])==4 and all(m['checked']==9228736 for m in a['modes']),'mode coverage')
for i,key in enumerate(('ambiguous_above','ambiguous_below','exact_boundary','strict_promotion')):
    require(sum(m['counts'][i] for m in a['modes'])==a[key],'counter sum '+key)
require(sum(a[k] for k in ('ambiguous_above','ambiguous_below','exact_boundary'))==a['equal_boundary'],'equality sum')
require(sum(m['columns'] for m in a['modes'])==19,'column sum')
limit=f32(0x7effffff);checks=[]
for index,mode in enumerate(a['modes']):
    expected=[('3f800002','bf800002'),('3f800002','bf800003'),('3f800003','bf800002'),('3f800002','bf800002')][index]
    require((mode['rounding_positive'],mode['rounding_negative'])==expected,'directed multiplication witness')
    require(mode['columns']==sum(bool(w['present']) for w in mode['witnesses'])+1,'one column model per present boundary and ordinary control')
    for w in mode['witnesses']:
        c=w['category'];require(bool(w['present'])==(mode['counts'][c]>0),'witness presence')
        if not w['present']:continue
        exact=value(w['x'])*value(w['y']); recorded=binary(int(w['exact_product'],16),52,11,1023)
        require(exact==recorded,'mathematically exact binary64 product')
        bits=int(w['rounded_product'],16);rounded=f32(bits);mag=bits&0x7fffffff
        lo=f32((bits-1) if exact>=0 else (bits+1));hi=f32((bits+1) if exact>=0 else (bits-1))
        if index==0:
            require(abs(exact-rounded)<=abs(exact-lo) and abs(exact-rounded)<=abs(exact-hi),'nearest rounding')
            if abs(exact-rounded) in (abs(exact-lo),abs(exact-hi)):require(bits%2==0,'ties to even')
        elif index==1 or (index==3 and exact>=0):require(rounded<=exact<hi,'down/toward-zero rounding')
        else:require(lo<exact<=rounded,'up/toward-zero rounding')
        delta=abs(exact)-limit
        require((c<3 and abs(rounded)==limit) or (c==3 and abs(rounded)>limit),'rounded boundary category')
        require((c in (0,3) and delta>0) or (c==1 and delta<0) or (c==2 and delta==0),'exact boundary category')
        checks.append(dict(mode=index,category=c,exact_product=str(exact),difference=str(delta)))
require(len(checks)==15,'rational witness count')
e=json.loads((P/'exact-witnesses.json').read_text())
require(e['result_sha256']==sha(P/'optimized-result.json') and e['script_sha256']==sha(P/'exact-witnesses.py'),'supplement binding')
require(len(e['checks'])==15,'supplement coverage')
report=dict(status='PASS',scope='Read-only independent artifact and exact-rational audit; no compiler or probe rerun',
    compared_pairs_per_binary=a['checked'],rounding_modes=4,column_models=19,rational_witnesses=checks,
    checks=['current source/controller/compiler hashes','exact classifier extraction and clean Git source binding',
    'optimized and sanitizer binary/result bindings and equality','per-mode coverage/counter sums and rounding witnesses',
    'independent exact products, correct rounding, and boundary categories for every witness'],
    limits=['Not exhaustive float-pair enumeration.','No production dispatch, ownership, reentry, ABI or cross-platform qualification.',
    'No floating exception-flag or performance equivalence claim.','This audit grants no new authorization or override of automatic review.'],
    artifacts={n:sha(P/n) for n in ('proof.md','receipt.json','probe.c','run.py','exact-witnesses.py','exact-witnesses.json')})
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(dict(status='PASS',pairs=a['checked'],witnesses=len(checks),columns=19)))
