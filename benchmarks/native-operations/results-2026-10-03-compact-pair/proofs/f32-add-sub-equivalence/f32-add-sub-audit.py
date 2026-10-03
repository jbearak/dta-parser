from pathlib import Path
from fractions import Fraction
import hashlib,json,subprocess
P=Path('<work>/f32-add-sub-equivalence')
OUT=Path('<independent-audit-work>/f32-add-sub-audit.json')
def require(ok,message):
    if not ok:raise RuntimeError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def binary(bits,fb,eb,bias):
    sign=-1 if bits>>(fb+eb) else 1
    exponent=(bits>>fb)&((1<<eb)-1);mantissa=bits&((1<<fb)-1)
    require(exponent!=(1<<eb)-1,'finite rational witness')
    if exponent:mantissa|=1<<fb
    return sign*Fraction(mantissa)*Fraction(2)**((exponent-bias if exponent else 1-bias)-fb)
def value(record):return binary(int(record['bits'],16),23,8,127) if record['kind']==2 else Fraction(record['integer'])
def sign(record):return bool(int(record['bits'],16)>>31) if record['kind']==2 else record['integer']<0
def check_round(q,bits,fb,eb,bias,mode,zero_sign):
    maximum=((1<<eb)-1)<<fb;sgn=bool(bits>>(fb+eb));mag=bits&((1<<(fb+eb))-1)
    require(mag<=maximum,'NaN rational witness')
    max_value=binary(maximum-1,fb,eb,bias)
    if mag==maximum:
        require(sgn==(q<0),'infinity sign')
        threshold=max_value+Fraction(2)**((((1<<eb)-2)-bias)-fb-1)
        require((mode==0 and abs(q)>=threshold) or (mode==1 and sgn and abs(q)>max_value) or (mode==2 and not sgn and abs(q)>max_value),'overflow rounding')
        return None
    rounded=binary(bits,fb,eb,bias)
    if not q:
        require(mag==0 and sgn==zero_sign,'exact zero sign');return rounded
    if q==rounded:return rounded
    minimum=Fraction(2)**(1-bias-fb)
    if mag==0:lo,hi=-minimum,minimum
    else:
        def adjacent(delta):
            neighbor=bits+delta
            nmag=neighbor&((1<<(fb+eb))-1)
            if nmag==maximum:return (-1 if sgn else 1)*Fraction(2)**((((1<<eb)-2)-bias)+1)
            return binary(neighbor,fb,eb,bias)
        lo,hi=(adjacent(1),adjacent(-1)) if sgn else (adjacent(-1),adjacent(1))
    direction=mode if mode!=3 else (1 if q>0 else 2)
    if direction==0:
        low,high=(lo+rounded)/2,(hi+rounded)/2
        require(low<=q<=high,'nearest interval')
        if q in (low,high):require(bits%2==0,'ties-to-even')
    elif direction==1:require(rounded<=q<hi,'round down interval')
    else:require(lo<q<=rounded,'round up interval')
    return rounded
r=json.loads((P/'receipt.json').read_text())
require(r['before']==r['after'] and r['source_status']=='','source/compiler stability and clean recorded head')
for path,digest in r['before'].items():require(sha(path)==digest,'current bound file '+path)
root=Path('<repo>');source='r-package/dtatools/src/numeric-payload.c'
blob=subprocess.check_output(['git','show',r['source_head']+':'+source],cwd=root)
require(hashlib.sha256(blob).hexdigest()==r['before'][str(root/source)],'classifier source belongs to recorded Git head')
for name,record in r['functions'].items():require(record['text'] in blob.decode() and hashlib.sha256(record['text'].encode()).hexdigest()==record['sha256'],'exact classifier extraction')
require((P/'extracted-classifiers.h').read_text()=='/* Exact source extraction; see receipt.json. */\n'+'\n'.join(x['text'] for x in r['functions'].values()),'exact extracted header')
for v in r['variants']:
    require(sha(P/('probe-'+v['label']))==v['binary_sha256'],'binary hash')
    result=P/(v['label']+'-result.json')
    require(sha(result)==v['result_sha256'] and json.loads(result.read_text())==v['result'],'full result binding')
    require('-frounding-math' in v['command'] and '-ffp-contract=off' in v['command'],'rounding options')
require(r['variants'][0]['result']==r['variants'][1]['result'],'optimized/UBSan identity')
a=r['variants'][0]['result'];require(a['checked']==70004784 and a['mismatches']==0 and a['column_checks']==38,'total coverage')
require(len(a['modes'])==8 and all(m['checked']==8750598 for m in a['modes']),'operation/mode coverage')
for i,key in enumerate(('ambiguous_above','ambiguous_below','exact_boundary','strict_promotion')):require(sum(m['counts'][i] for m in a['modes'])==a[key],'counter sum '+key)
require(sum(a[k] for k in ('ambiguous_above','ambiguous_below','exact_boundary'))==a['equal_boundary'],'equality count')
require(sum(m['columns'] for m in a['modes'])==38,'column count')
limit=binary(0x7effffff,23,8,127);checks=[]
for index,m in enumerate(a['modes']):
    mode=index%4;op='+' if index<4 else '-'
    require(m['operation']==op,'operation order')
    expected=[('3f800000','bf800000'),('3f800000','bf800001'),('3f800001','bf800000'),('3f800000','bf800000')][mode]
    require((m['rounding_positive'],m['rounding_negative'])==expected,'actual arithmetic rounding-mode witnesses')
    require(m['columns']==sum(bool(w['present']) for w in m['witnesses'])+1,'boundary/ordinary column models')
    for w in m['witnesses']:require(bool(w['present'])==(m['counts'][w['category']]>0),'witness presence')
    records=[w for w in m['witnesses'] if w['present']]+m['oracle_witnesses']
    mode_checks=[]
    for w in records:
        x,y=value(w['x']),value(w['y']);q=x+y if op=='+' else x-y
        sx,sy=sign(w['x']),sign(w['y'])^(op=='-')
        zero_sign=sx if not x and not y and sx==sy else mode==1
        dbits,fbits=int(w['binary64_result'],16),int(w['binary32_result'],16)
        d=check_round(q,dbits,52,11,1023,mode,zero_sign)
        check_round(q,fbits,23,8,127,mode,zero_sign)
        check_round(d,fbits,23,8,127,mode,bool(dbits>>63))
        promoted=abs(d)>limit;mag=fbits&0x7fffffff
        if 'encoded_bits' in w:
            require(w['missing']==0 and w['kind']==(3 if promoted else 2),'binary64-first storage decision')
            require(int(w['encoded_bits'],16)==(dbits if promoted else fbits),'encoded exact result')
        if 'category' in w:
            c=w['category'];delta=abs(d)-limit
            require((c<3 and mag==0x7effffff) or (c==3 and mag>0x7effffff),'rounded boundary category')
            require((c in (0,3) and delta>0) or (c==1 and delta<0) or (c==2 and delta==0),'binary64 boundary category')
        mode_checks.append(dict(binary64_inexact=d!=q,exact_above_but_binary64_fits=abs(q)>limit and not promoted,zero=q==0))
    require(any(c['zero'] for c in mode_checks) and any(c['binary64_inexact'] for c in mode_checks),'zero and rounded-binary64 witness coverage')
    checks.extend(mode_checks)
require(len(checks)==814 and any(c['exact_above_but_binary64_fits'] for c in checks),'all rational witnesses and storage distinction')
e=json.loads((P/'exact-witnesses.json').read_text())
require(e['result_sha256']==sha(P/'optimized-result.json') and e['script_sha256']==sha(P/'exact-witnesses.py'),'author rational supplement binding')
require(sum(len(x['checks']) for x in e['records'])==814,'supplement coverage')
report=dict(status='PASS',scope='Independent artifact and adjacent-representable-value rational audit; no compiler or probe rerun',pairs_per_binary=a['checked'],operation_modes=8,column_models=38,rational_witnesses=len(checks),checksum=a['checksum'],
 checks=['current source/controller/compiler hashes and clean Git classifier source','exact classifier extraction','optimized/UBSan binary and full result identity','per-operation/per-mode counts and signed arithmetic rounding witnesses','independent rational direct and nested p53/p24 rounding by neighboring-representable intervals','binary64-first fit/promotion, exact zero signs and full encoded output bits for saved witnesses'],
 limits=['Not exhaustive pair enumeration.','Producer and whole-column logic are standalone models, not integrated package paths.','No dispatch/ownership/reentry/ABI/cross-platform/floating-exception/performance claim.'],
 artifacts={n:sha(P/n) for n in ['proof-draft.md','receipt.json','probe.c','run.py','exact-witnesses.py','exact-witnesses.json']})
OUT.write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','pairs_per_binary','operation_modes','column_models','rational_witnesses','checksum']}))
