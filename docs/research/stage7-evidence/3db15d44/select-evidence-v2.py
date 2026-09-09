"""Copy a declared subset of already-qualified evidence, never rerun workloads.
Original receipt/manifest identities validate selected products. Full endpoint
inventories, dependency images, raw states/profiles and binaries stay local.
"""
from pathlib import Path
import argparse, hashlib, json, shutil
V=Path('/private/tmp/dta-direct-stage7-validation')
P=Path('/private/tmp/dta-direct-stage7-performance-preparation-01')
H=Path('/private/tmp/dta-direct-stage7-memory-history-diagnosis-01')
D=Path('/private/tmp/dta-direct-stage7/docs/research/stage7-evidence/3db15d44')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('highcard_selection', type=Path)
args=parser.parse_args()
selection=json.loads(args.highcard_selection.read_text())
if selection['candidate']!='3db15d44f2b557f5282fb7a30fd59c7980a4484c': raise ValueError('Unexpected selected source')
if D.exists(): raise SystemExit('Fresh destination required')
D.mkdir()
index=[]; sources={}
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def cp(p, rel, category, bound=None):
    data=p.read_bytes(); sha=hashlib.sha256(data).hexdigest()
    if bound is not None:
        if sha!=bound['sha256'] or len(data)!=bound['bytes']: raise ValueError(f'product mismatch: {p}')
    q=D/rel; q.parent.mkdir(parents=True,exist_ok=True)
    if q.exists() and q.read_bytes()!=data: raise ValueError(f'collision: {q}')
    q.write_bytes(data)
    index.append(dict(original=str(p),copy=str(rel),category=category,bytes=len(data),sha256=sha,original_mode=oct(p.stat().st_mode&0o777),product_bound=bound is not None))
    return q
common=['result.json','products.json','receipt.json','command-before.json','command-result.json','runtime.txt','runtime-coverage.json','namespaces.tsv','dlls.tsv','accepted-input-identities.json','installation-comparison.json','source-exports.json','runner.log','whole-child-rss.json']
def run(p, label, timing=False):
    receipt=json.loads((p/'receipt.json').read_text())
    m=p/'products.json'
    if digest(m)!=receipt['products']['sha256']: raise ValueError('manifest mismatch')
    manifest={x['path']:x for x in json.loads(m.read_text())['products']}
    for name in common:
        f=p/name
        if f.exists(): cp(f,Path('runs')/label/name,'run_record',manifest.get(str(f)))
    for f in sorted((p/'source').rglob('*')):
        if not f.is_file(): continue
        sha=digest(f)
        if sha not in sources: sources[sha]=Path('sources')/sha/f.name
        cp(f,sources[sha],'executed_source',manifest[str(f)])
    for f in sorted((p/'results').iterdir()):
        keep=f.name in ['operations.csv','heap.csv','validation.csv','session.txt'] or f.name.endswith('-times.csv')
        if keep: cp(f,Path('runs')/label/'results'/f.name,'raw_timing_or_heap',manifest[str(f)])
# The historical predecessor/a048 selection remains at the parent evidence path.
run(V/'root-performance-3db15d44-v2-01','timing-3db',True)
b=V/'root-memory-3db15d44-v2-01'
for f in sorted(b.iterdir()):
    if f.is_file(): cp(f,Path('runs/memory-3db')/f.name,'batch_record')
    elif f.is_dir(): run(f,str(Path('memory-3db')/f.name))
run(V/'root-memory-history-3db15d44-01','installed500-3db')
for row in selection['runs']:
    root=V/row['name']
    if digest(root/'receipt.json')!=row['receipt_sha256']: raise ValueError('Highcard receipt mismatch')
    run(root,str(Path('highcard')/row['name']),True)
for row in selection['assessments']:
    f=Path(row['path'])
    if digest(f)!=row['sha256']: raise ValueError('Highcard assessment mismatch')
    cp(f,Path('assessments/highcard')/f.name,'post_run_assessment')
cp(args.highcard_selection,Path('highcard-selection.json'),'declared_selection')
p=V/'implementation/candidate-3db15d44-01'
r=json.loads((p/'completed-receipt.json').read_text()); m=p/'output-manifest.json'
if digest(m)!=r['manifest']['sha256']: raise ValueError('install manifest mismatch')
manifest={x['path']:x for x in json.loads(m.read_text())['products']}
for f in sorted(p.iterdir()):
    if f.is_file() and f.name not in ['inputs-before.json','source.tar']:
        cp(f,Path('installations/candidate-3db')/f.name,'selected_install_record',manifest.get(str(f)))
for name in ['root-performance-3db15d44-v2-01-assessment.json','root-memory-3db15d44-v2-01-assessment.json']:
    cp(V/name,Path('assessments')/name,'post_run_assessment')
cp(H/'root-installed-3db15d44-history-assessment-01.json',Path('assessments/root-installed-3db15d44-history-assessment-01.json'),'post_run_assessment')
comparison=V/'root-performance-comparison-3db15d44-01'
for name in ['result.json','comparisons.csv']:
    cp(comparison/name,Path('comparison')/name,'post_run_comparison')
for name in ['assess-performance-v2.py','assess-memory-v2.py','compare-performance-v1.py','run-memory-batch-v2.py']:
    cp(P/name,Path('assessment-sources')/name,'selected_assessment_or_batch_source')
for row in selection['sources']:
    f=Path(row['path'])
    if digest(f)!=row['sha256']: raise ValueError('Selected source mismatch')
    cp(f,Path('assessment-sources/highcard')/f.name,'selected_highcard_source')
summary=dict(scope='Additive selected exact3db copies; historical predecessor/a048 remain in parent. Not a full runtime/dependency/output archive or relocatable replay.',excluded=['full inputs-before/after arrays','dependency and runtime images','source and binary tarballs','installed DLL payloads','raw Rprofmem profiles','raw native-state tables','full ordinary output graphs and highcard schemas'],files=index)
(D/'index.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(dict(records=len(index),files=len([x for x in D.rglob('*') if x.is_file()]),bytes=sum(x.stat().st_size for x in D.rglob('*') if x.is_file()),sources=len(sources))))
