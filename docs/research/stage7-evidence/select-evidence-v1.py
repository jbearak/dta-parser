"""Copy a declared subset of already-qualified evidence, never rerun workloads.
Original receipt/manifest identities validate selected products. Full endpoint
inventories, dependency images, raw states/profiles and binaries stay local.
"""
from pathlib import Path
import hashlib, json, shutil
V=Path('/private/tmp/dta-direct-stage7-validation')
P=Path('/private/tmp/dta-direct-stage7-performance-preparation-01')
H=Path('/private/tmp/dta-direct-stage7-memory-history-diagnosis-01')
D=Path('/private/tmp/dta-direct-stage7/docs/research/stage7-evidence')
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
for name,label in [('root-performance-predecessor-4d07-v2-01','timing-predecessor'),('root-performance-a0485ac7-v2-01','timing-a048')]: run(V/name,label,True)
for batch,label in [('root-memory-predecessor-4d07-v2-01','memory-predecessor'),('root-memory-a0485ac7-v2-01','memory-a048')]:
    b=V/batch
    for f in sorted(b.iterdir()):
        if f.is_file(): cp(f,Path('runs')/label/f.name,'batch_record')
        elif f.is_dir(): run(f,str(Path(label)/f.name))
for name,label in [('root-memory-history-96b9c3c7-01','installed500-96'),('root-memory-history-a0485ac7-01','installed500-a048')]: run(V/name,label)
for name,label in [('predecessor-4d07d656-01','predecessor-4d07'),('candidate-a0485ac7-01','candidate-a048'),('candidate-96b9c3c7-01','candidate-96')]:
    p=V/'implementation'/name
    r=json.loads((p/'completed-receipt.json').read_text());m=p/'output-manifest.json'
    if digest(m)!=r['manifest']['sha256']: raise ValueError('install manifest mismatch')
    manifest={x['path']:x for x in json.loads(m.read_text())['products']}
    for f in sorted(p.iterdir()):
        if f.is_file() and f.name not in ['inputs-before.json','source.tar']:
            cp(f,Path('installations')/label/f.name,'selected_install_record',manifest.get(str(f)))
for name in ['root-performance-predecessor-4d07-v2-01-assessment.json','root-performance-a0485ac7-v2-01-assessment.json','root-memory-predecessor-4d07-v2-01-assessment.json','root-memory-a0485ac7-v2-01-assessment.json']:
    cp(V/name,Path('assessments')/name,'post_run_assessment')
for name in ['root-installed-history-assessment-01.json','root-installed-a048-history-assessment-01.json']:
    cp(H/name,Path('assessments')/name,'post_run_assessment')
for name in ['assess-performance-v2.py','assess-memory-v2.py','compare-performance-v1.py','run-memory-batch-v2.py','README-memory-v2.md']:
    cp(P/name,Path('assessment-sources')/name,'selected_assessment_or_batch_source')
cp(V/'root-performance-comparison-a0485ac7-01/result.json',Path('comparison-result.json'),'post_run_comparison')
# Actual input-to-copy mapping retains duplicate original paths for deduplicated source bytes.
summary=dict(scope='Selected exact copies only; not a full runtime/dependency/output archive or a relocatable replay.',excluded=['full inputs-before/after arrays','dependency and runtime images','source and binary tarballs','installed DLL payloads','raw Rprofmem profiles','raw native-state tables','full ordinary output graphs'],files=index)
(D/'index.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(dict(records=len(index),files=len([x for x in D.rglob('*') if x.is_file()]),bytes=sum(x.stat().st_size for x in D.rglob('*') if x.is_file()),sources=len(sources))))
