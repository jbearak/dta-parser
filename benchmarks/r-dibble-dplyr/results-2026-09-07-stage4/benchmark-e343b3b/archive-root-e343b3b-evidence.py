"""Preserve Stage 4 root evidence without modifying original bytes or paths."""
from pathlib import Path
import datetime
import hashlib
import json

source = Path('/private/tmp/dta-direct-stage4-validation')
target = Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/benchmark-e343b3b')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise RuntimeError(message)


directories = [
    'baseline-confirmation-b259ad5', 'baseline-heap-7003a46',
    'candidate-e343b3b-b259ad5', 'candidate-owned-double-e343b3b',
    'candidate-heap-e343b3b-7003a46', 'comparison-atomic-e343b3b',
    'comparison-atomic-e343b3b-confirmation', 'comparison-double-e343b3b',
    'comparison-heap-e343b3b', 'root-acceptance-e343b3b', 'root-acceptance-976cc40',
    'fertility-e343b3b', 'fertility-e343b3b-retry', 'fertility-e343b3b-praise-diagnosis',
    'fertility-976cc40', 'heap-supplement-development-smoke',
    'heap-supplement-development-smoke-recovered-source',
    'heap-supplement-current-smoke', 'heap-supplement-cli-guards',
]
filenames = [
    'baseline-confirmation-b259ad5-operations-outer.log',
    'baseline-confirmation-b259ad5-verification.json', 'baseline-heap-7003a46-outer.log',
    'candidate-e343b3b-b259ad5-operations-outer.log',
    'candidate-e343b3b-b259ad5-memory-outer.log', 'candidate-e343b3b-operations-manifest.json',
    'candidate-owned-double-e343b3b-operations-outer.log',
    'candidate-owned-double-e343b3b-memory-outer.log',
    'candidate-owned-double-e343b3b-operations-manifest.json',
    'candidate-heap-e343b3b-7003a46-outer.log',
    'comparison-atomic-e343b3b-outer.log', 'comparison-atomic-e343b3b-confirmation-outer.log',
    'fertility-e343b3b-outer.log', 'fertility-e343b3b-retry-outer.log',
    'check-fertility-candidate.py', 'compare-atomic.py', 'compare-double.py', 'compare-heap.py',
    'archive-root-e343b3b-evidence.py', 'heap-supplement-cli-guards.py',
    'heap-supplement-metric-guards.json', 'heap-supplement-commit-receipt.json',
    'api-review-round10-heap-arithmetic-audit.json',
    'api-review-round10-heap-current-evidence-addendum.md',
    'api-review-round13-downstream-semantic-parity.md',
    'root-e343b3b-gate-log-verification.json', 'root-e343b3b-source-native-verification.json',
    'root-976cc40-source-verification.json',
]
pairs = []
for directory in directories:
    require((source / directory).is_dir(), f'Missing directory: {directory}')
    pairs += [(p, target / p.relative_to(source)) for p in sorted((source / directory).rglob('*')) if p.is_file()]
pairs += [(source / name, target / name) for name in filenames]
baseline = Path('/private/tmp/dta-direct-stage3-validation/resume-audit/fertility-stage2-baseline.log')
pairs.append((baseline, target / 'fertility-stage2-baseline.log'))
require(len({str(copy) for original, copy in pairs}) == len(pairs), 'Duplicate destinations')
require(not target.exists(), f'Refusing overwrite: {target}')
for original, copy in pairs:
    require(original.is_file() and not original.is_symlink(), f'Missing or symlink input: {original}')
    require(original.stat().st_size < 1000000, f'Unexpected large input: {original}')
records = []
for original, copy in pairs:
    data = original.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    copy.parent.mkdir(parents=True, exist_ok=True)
    with copy.open('xb') as out:
        out.write(data)
    require(digest(original) == sha == digest(copy), f'Changed evidence: {original}')
    records.append({'original': str(original), 'copy': str(copy.relative_to(target)),
                    'sha256': sha, 'bytes': len(data)})
index = {
    'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_sha': 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15',
    'package_tree': 'f12a2a1dd430636a33b7f6e953023d90d1ff2589',
    'baseline_source': 'ec10a6ac34602f3bd691e8043019c1b479babda4',
    'atomic_runner_source': 'b259ad5a521dbb867a0b8563e3a0c2262e298671',
    'double_runner_source': 'ec10a6ac34602f3bd691e8043019c1b479babda4',
    'heap_runner_source': '7003a46899ed508c4068e077e3aa1af7fff541f3',
    'status_at_archive': 'Full exact atomic/double/heap correctness, allocations and memory pass.15 atomic timing flags persist against both baselines; zero double flags. Read-performance disposition remains open.',
    'downstream': 'Both e343 strict drivers rejected a single18-byte testthat encouragement line. Separate reviewed read-only audit proves every other backend byte and outcome unchanged. Four baseline failures and two skips remain. This is isolated-library evidence, not the final required actual-renv test.',
    'heap_development': 'Development smokes use initial7d and smaller fixtures, not e343 qualification. Recovered old-wrapper source is explicitly retrospective and hash-matched. CLI stubs and their108 child logs are synthetic; final heap matrices are72 actual fresh R processes.',
    'prior_evidence': '../initial-evidence-index.json records original complete baseline and initial7d matrices; these bytes remain unchanged.',
    'files': records,
}
with (target / 'index.json').open('x') as out:
    json.dump(index, out, indent=2)
    out.write('\n')
print(f'Archived {len(records)} unchanged files, {sum(x["bytes"] for x in records)} bytes')
