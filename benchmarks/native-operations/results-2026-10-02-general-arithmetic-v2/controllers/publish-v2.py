"""Publish final arithmetic acceptance and the retained one-variable diagnostics.
Run from the repository root: publish-v2.py PRIVATE_WORK NEW_PUBLIC_DIRECTORY
"""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

work, output = [Path(x).resolve() for x in sys.argv[1:]]
repo = Path.cwd().resolve()
def require(ok, message):
    if not ok: raise RuntimeError(message)
def sha(data): return hashlib.sha256(data).hexdigest()
def load(path): return json.loads(path.read_text())
def json_bytes(value): return (json.dumps(value, indent=2, sort_keys=True)+'\n').encode()
require(not output.exists(), 'Output already exists')
timings = work/'acceptance-v2-timings'
before, after = [load(timings/f'provenance-{side}.json') for side in ('before','after')]
completion = load(timings/'completion.json')
require(completion['observations']==1224 and completion['rounds']==6 and completion['exact_results'] and completion['provenance_unchanged'] and completion['worker_runtime_unchanged'], 'Incomplete final acceptance')
require(all(before[k]==after[k] for k in ('builds','controllers','runtime')), 'Provenance changed')
spec=importlib.util.spec_from_file_location('general_records',repo/'benchmarks/native-operations/general-run.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
for name,expected in before['controllers'].items():
    require(sha((repo/'benchmarks/native-operations'/name).read_bytes())==expected, 'Controller changed')
for variant in ('baseline','candidate'):
    require(module.RECORDS.inventory(work/f'acceptance-v2-{variant}',variant)==before['builds'][variant], 'Build no longer verifies')
rows=list(csv.DictReader((timings/'raw.csv').open()))
for variant in ('baseline','candidate'):
    for round_number in range(1,7):
        module.validate_round([r for r in rows if r['variant']==variant and int(r['round'])==round_number],round_number,variant)
require(subprocess.run(['git','diff','--quiet',before['builds']['candidate']['receipt']['base_commit'],'--','r-package/dtatools']).returncode==0, 'Current package differs from measured candidate')
full=list(csv.DictReader((work/'acceptance-v2-full-tests.csv').open()))
totals={k:sum(int(r[k]) if k in ('passed','failed','warning') else r[k]=='TRUE' for r in full) for k in ('passed','failed','error','skipped','warning')}
require(totals['passed']>80000 and not any(totals[k] for k in ('failed','error','skipped')), 'Full suite failed or incomplete')
require('R package conformance: PASS' in (work/'acceptance-v2-conformance.log').read_text(), 'Conformance did not pass')
pending, mapping={},[]
replacements=[(str(work),'<work>'),(str(repo),'<repo>'),('<independent-audit-work>','<independent-audit-work>'),(str(Path.home()),'<user>')]
def queue(source, relative):
    raw=source.read_bytes(); text=raw.decode()
    for old,new in replacements: text=text.replace(old,new)
    text=re.sub(r'/(?:private/)?var/folders/[^\s"\'<>]+','<temporary>',text)
    require(not re.search(r'/(?:Users|home|private/tmp|tmp)/',text), 'Unmapped private path in '+relative)
    data=text.encode(); pending[relative]=data
    mapping.append(dict(artifact=relative,source_sha256=sha(raw),published_sha256=sha(data),transformation='none' if data==raw else 'private path substitution'))
def directory(source, relative):
    for path in sorted(source.iterdir()):
        if path.is_file(): queue(path, relative+'/'+path.name)
for path in sorted(timings.iterdir()):
    if path.is_file(): queue(path,'timings/'+path.name)
for variant in ('baseline','candidate'):
    for name in ('build-receipt.json','input-record.json','source.patch','build.log'):
        queue(work/f'acceptance-v2-{variant}'/name,f'builds/{variant}/{name}')
for name in ('general-run.py','general-worker.R','test-general-run.py','run.py'):
    queue(repo/'benchmarks/native-operations'/name,'controllers/'+name)
queue(Path(__file__),'controllers/publish-v2.py')
for suffix in ('full-tests.R','full-tests.csv','full-tests.log','conformance.log','qualification-baseline.csv','qualification-baseline.log','qualification-candidate.csv','qualification-candidate.log','controller-tests.log','controller-optimized-tests.log','python-tests.log','timing-controller.log','validation-binding.json'):
    queue(work/('acceptance-v2-'+suffix),'validation/'+suffix)
for label,folder in [('float-mask','float-mask-timings'),('integer-bounds','integer-bounds-timings'),('float-interval','float-interval-timings')]:
    directory(work/folder,'diagnostics/'+label+'/timings')
for label,folder in [('float-mask','float-nan-diagnostic'),('integer-bounds','integer-bounds-diagnostic'),('float-interval','float-interval-diagnostic')]:
    for name in ('general-run.py','general-worker.R'):
        queue(work/folder/name,'diagnostics/'+label+'/controllers/'+name)
for label,folder in [('float-mask','float-mask-prototype'),('integer-bounds','integer-bounds-final'),('float-interval','float-interval-prototype'),('negative-select','float-nan-prototype')]:
    for name in ('build-receipt.json','input-record.json','source.patch'):
        queue(work/folder/name,'diagnostics/'+label+'/build/'+name)
for name in ('float-nan-negative-diagnostic.json','float-mask-compiler-diagnostic.json','float-interval-compiler-diagnostic.json','post-run-runtime-supplement.json','integer-bounds-validation-binding.json','float-interval-validation-binding.json','float-interval-post-build-tests.patch','negative-select-loop-excerpt.json','masked-or-loop-excerpt.json','float-interval-loop-excerpt.json'):
    queue(work/name,'diagnostics/'+name)
# Every intermediate timing's baseline receipt is embedded in its provenance.
# Preserve the corresponding source-bound library receipt separately too.
for name in ('build-receipt.json','input-record.json','source.patch'):
    queue(work/'acceptance-candidate'/name,'diagnostics/typed-spans-v1-build/'+name)
validation=dict(candidate_commit=before['builds']['candidate']['receipt']['base_commit'],baseline_commit=before['builds']['baseline']['receipt']['base_commit'],candidate_receipt_sha256=before['builds']['candidate']['receipt_sha256'],candidate_dll_sha256=before['builds']['candidate']['installed']['libs/dtatools.so'],full_suite=totals,full_suite_observations_sha256=sha((work/'acceptance-v2-full-tests.csv').read_bytes()),qualification_cases_per_build=102,source_equals_measured_candidate=True,interpretation='Report all 34 operations and remaining typed/bare-double gaps. Intermediate diagnostic gains do not establish universal parity.')
pending['validation/source-binding.json']=json_bytes(validation)
pending['publication-source-map.json']=json_bytes(mapping)
pending['publication-manifest.json']=json_bytes({name:sha(data) for name,data in sorted(pending.items())})
output.mkdir(parents=True)
for name,data in pending.items():
    path=output/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
print('Published',len(pending),'source-bound artifacts')
