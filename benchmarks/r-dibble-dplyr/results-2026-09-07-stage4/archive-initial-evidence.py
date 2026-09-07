"""Copy completed initial Stage 4 evidence byte-for-byte into the repository."""
from pathlib import Path
import datetime
import hashlib
import json

source = Path('/private/tmp/dta-direct-stage4-validation')
target = Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(directory):
    root = source / directory
    manifest = json.loads((root / 'root-manifest.json').read_text())
    for name, entry in manifest.get('outputs', {}).items():
        require(digest(root / name) == entry['sha256'], f'Changed output: {root / name}')
    for name, sha in manifest.get('files', {}).items():
        require(digest(root / name) == sha, f'Changed output: {root / name}')
    for entry in manifest.get('memory_cases', []):
        require(digest(root / entry['file']) == entry['sha256'], f'Changed memory: {root / entry["file"]}')


directories = ['baseline-b259ad5', 'baseline-b259ad5-qualified', 'baseline-owned-double-ec10a6a',
               'candidate-7d56080-b259ad5', 'candidate-owned-double-7d56080',
               'comparison-atomic-7d56080', 'comparison-double-7d56080', 'root-acceptance-7d56080']
for directory in directories:
    if (source / directory / 'root-manifest.json').exists():
        verify(directory)
files = ['baseline-b259ad5-memory-retry-copy.json',
         'baseline-b259ad5-driver.log', 'baseline-b259ad5-memory-driver.log',
         'baseline-b259ad5-qualified-memory-driver.log',
         'baseline-owned-double-ec10a6a-driver.log', 'baseline-owned-double-ec10a6a-memory-driver.log',
         'candidate-7d56080-b259ad5-driver.log', 'candidate-7d56080-b259ad5-memory-driver.log',
         'candidate-owned-double-7d56080-driver.log', 'candidate-owned-double-7d56080-memory-driver.log',
         'comparison-atomic-7d56080.log', 'comparison-double-7d56080.log',
         'compare-atomic.py', 'compare-double.py', 'archive-initial-evidence.py',
         'development-atomic-driver-guards.log', 'development-atomic-provenance.log',
         'development-attribute-order.log']
pairs = []
for directory in directories:
    for path in sorted((source / directory).iterdir()):
        require(path.is_file(), f'Unexpected nested item: {path}')
        pairs.append((path, target / directory / path.name))
for name in files:
    pairs.append((source / name, target / name))
require(not (target / 'initial-evidence-index.json').exists(), 'Initial index already exists')
for original, copy in pairs:
    require(original.is_file(), f'Missing input: {original}')
    require(not copy.exists(), f'Refusing to overwrite: {copy}')
records = []
for original, copy in pairs:
    data = original.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    copy.parent.mkdir(parents=True, exist_ok=True)
    with copy.open('xb') as file:
        file.write(data)
    require(digest(original) == sha == digest(copy), f'Changed during copy: {original}')
    records.append({'original': str(original), 'copy': str(copy.relative_to(target)),
                    'sha256': sha, 'bytes': len(data)})
index = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'baseline_source': 'ec10a6ac34602f3bd691e8043019c1b479babda4',
         'candidate_source': '7d56080f3e97bc4d73a848e363d729767b9629c0',
         'atomic_runner_source': 'b259ad5a521dbb867a0b8563e3a0c2262e298671',
         'double_runner_source': 'ec10a6ac34602f3bd691e8043019c1b479babda4',
         'candidate_status': 'Correctness, selector allocation, writes and retained-memory checks passed. Initial read-performance candidate rejected: 43 atomic read cases exceed both10% and1ms. No prior-double read case crosses both thresholds. Further diagnosis and final qualification required.',
         'baseline_retry': 'baseline-b259ad5 operations passed; first memory R case passed but macOS time sysctl was sandbox-denied. Successful operation artifacts copied byte-for-byte to baseline-b259ad5-qualified; all30 memory cases then passed with read-only sysctl permission. Original evidence and separate retry-copy proof preserved.',
         'root_regression_scope': '219 pure R cases only; excludes historical18-case native names observer whose C source was not recovered.',
         'files': records}
with (target / 'initial-evidence-index.json').open('x') as file:
    json.dump(index, file, indent=2)
    file.write('\n')
print(f'Archived {len(records)} unchanged files, {sum(x["bytes"] for x in records)} bytes')
