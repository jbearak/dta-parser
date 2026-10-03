"""Publish a completed general arithmetic screen with source and byte bindings.

Usage from the repository root: publish.py PRIVATE_WORK PUBLIC_OUTPUT
"""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

work, output = [Path(value).resolve() for value in sys.argv[1:]]
repo = Path.cwd().resolve()
require = lambda condition, message: None if condition else (_ for _ in ()).throw(RuntimeError(message))
sha = lambda raw: hashlib.sha256(raw).hexdigest()
load = lambda path: json.loads(path.read_text())
json_bytes = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
require(not output.exists(), 'Publication output already exists')
timings = work / 'timings'
before, after = [load(timings / ('provenance-' + side + '.json')) for side in ('before', 'after')]
completion = load(timings / 'completion.json')
require(completion['observations'] == 1224 and completion['rounds'] == 6 and completion['exact_results'] and completion['provenance_unchanged'], 'Incomplete acceptance screen')
require(before['builds'] == after['builds'] and before['controllers'] == after['controllers'], 'Provenance changed')
spec = importlib.util.spec_from_file_location('general_records', repo/'benchmarks/native-operations/general-run.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for name, expected in before['controllers'].items():
    require(sha((repo/'benchmarks/native-operations'/name).read_bytes()) == expected, 'Timing controller changed')
for variant in ('baseline', 'candidate'):
    require(module.RECORDS.inventory(work/('acceptance-'+variant), variant) == before['builds'][variant], 'Build receipt no longer validates')
rows = list(csv.DictReader((timings/'raw.csv').open()))
for variant in ('baseline', 'candidate'):
    for round_number in range(1, 7):
        batch = [row for row in rows if row['variant'] == variant and int(row['round']) == round_number]
        module.validate_round(batch, round_number, variant)
require(subprocess.run(['git','diff','--quiet',before['builds']['candidate']['receipt']['base_commit'],'--','r-package/dtatools']).returncode == 0, 'Current package differs from measured runtime')
pending, mapping = {}, []
replacements = [(str(work), '<work>'), (str(repo), '<repo>'), (str(Path.home()), '<user>')]
def queue(source, relative):
    raw = source.read_bytes()
    text = raw.decode()
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r'/(?:private/)?var/folders/[^\s"\'<>]+', '<temporary>', text)
    require(not re.search(r'/(?:Users|home|private/tmp|tmp)/',text), 'Unmapped private path in '+relative)
    data = text.encode()
    pending[relative] = data
    mapping.append(dict(artifact=relative, source_sha256=sha(raw), published_sha256=sha(data), transformation='none' if data==raw else 'private path substitution'))
for path in sorted(timings.iterdir()):
    if path.is_file(): queue(path, 'timings/'+path.name)
for variant in ('baseline','candidate'):
    for name in ('build-receipt.json','input-record.json','source.patch','build.log'):
        queue(work/('acceptance-'+variant)/name, 'builds/'+variant+'/'+name)
for name in ('general-run.py','general-worker.R','test-general-run.py'):
    queue(repo/'benchmarks/native-operations'/name, 'controllers/'+name)
queue(Path(__file__), 'controllers/publish.py')
for name in ('acceptance-full-tests.csv','acceptance-full-tests.log','qualification-baseline.csv','qualification-baseline.log','qualification-candidate.csv','qualification-candidate.log','controller-tests.log','controller-optimized-tests.log','timing-controller.log','independent-audit.json'):
    queue(work/name, 'validation/'+name)
queue(work/'corrected/manifest-python-tests.log','validation/manifest-python-tests.log')
validation = dict(candidate_commit=before['builds']['candidate']['receipt']['base_commit'],
    candidate_receipt_sha256=before['builds']['candidate']['receipt_sha256'],
    candidate_dll_sha256=before['builds']['candidate']['installed']['libs/dtatools.so'],
    full_suite=dict(passed=64804, failed=0, error=0, skipped=0, warning=7,
        observations_sha256=sha((work/'acceptance-full-tests.csv').read_bytes()),
        log_sha256=sha((work/'acceptance-full-tests.log').read_bytes())),
    qualification=dict(cases_per_build=102, values_storage_missing_source=True),
    source_equals_measured_candidate=True,
    interpretation='Intermediate candidate; five of the eight original cases still exceed the local 1.5x typed-double CPU target. No universal parity claim.')
pending['validation/source-binding.json'] = json_bytes(validation)
pending['publication-source-map.json'] = json_bytes(mapping)
pending['publication-manifest.json'] = json_bytes({name:sha(data) for name,data in sorted(pending.items())})
output.mkdir(parents=True)
for name,data in pending.items():
    path=output/name
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data)
print('Published', len(pending), 'source-bound artifacts')
