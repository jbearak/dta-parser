"""Recheck completed paired evidence and produce the Stage 4 fix results draft."""
from pathlib import Path
import csv
import hashlib
import json

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
DATA = ROOT / 'root-c8ca0a4-performance'


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


qualification = json.loads((DATA / 'qualification.json').read_text())
require(len(qualification['commands']) == 13, 'Incomplete coordinator phases')
for command in qualification['commands']:
    require(command['exit_code'] == 0 and digest(Path(command['log'])) == command['log_sha256'],
            'Failed or changed coordinator phase')
for path, expected in qualification['executed_source_sha256'].items():
    require(digest(Path(path)) == expected, 'Executed source changed')
manifests = {}
for family in ['atomic', 'double', 'heap']:
    for mode in ['baseline', 'candidate']:
        directory = DATA / (family + '-' + mode)
        manifest = json.loads((directory / 'root-manifest.json').read_text())
        manifests[family + '-' + mode] = manifest
        for name, expected in manifest.get('files', {}).items():
            require(digest(directory / name) == expected, 'Changed atomic output')
        for name, entry in manifest.get('outputs', {}).items():
            require(digest(directory / name) == entry['sha256'] and
                    len(read_csv(directory / name)) == entry['rows'], 'Changed double output')
        for case in manifest.get('memory_cases', manifest.get('cases', [])):
            require(case['exit_code'] == 0 and digest(directory / case['file']) == case['sha256'],
                    'Changed memory case')
for family in ['atomic', 'double', 'heap']:
    directory = DATA / (family + '-comparison')
    derivation = json.loads((directory / 'derivation.json').read_text())
    for name, expected in derivation['files'].items():
        require(digest(directory / name) == expected, 'Changed derived result')

atomic = read_csv(DATA / 'atomic-comparison/operation-comparison.csv')
double = read_csv(DATA / 'double-comparison/operation-comparison.csv')
flags = json.loads((DATA / 'atomic-comparison/investigate.json').read_text())
double_flags = json.loads((DATA / 'double-comparison/investigate.json').read_text())
old_flags = json.loads((ROOT / 'comparison-atomic-e343b3b-confirmation/investigate.json').read_text())
key = lambda row: tuple(row[k] for k in ['kind', 'family', 'operation', 'rows'])
require({key(row) for row in flags} == {key(row) for row in old_flags}, 'New atomic timing case requires investigation')
require(len(flags) == 15 and not double_flags, 'Unexpected final timing flags')
selectors = [r for r in atomic if r['family'] == 'direct']
require(all(float(r['candidate_r_allocated_bytes']) < 1000000 for r in selectors), 'Selector allocation budget exceeded')
renames = [r for r in selectors if r['rows'] == '1000000' and r['operation'] == 'rename']
pipelines = [r for r in selectors if r['rows'] == '1000000' and r['operation'] == 'pipeline_five']
delegated = [r for r in atomic if r['rows'] == '1000000' and r['family'] == 'safe_delegation' and r['operation'] == 'pipeline_five']
heap = read_csv(DATA / 'heap-comparison/heap-comparison.csv')
require(len(heap) == 36, 'Incomplete paired heap cases')
retained = [int(r['candidate_retained_tracked_heap_bytes']) for r in heap]
residual = [int(r['candidate_excess_tracked_heap_bytes_after_drop_result']) for r in heap]
require(max(retained) < 1000000 and max(residual) < 1000000, 'Retained heap budget exceeded')
atomic_rss = [c['metrics']['maximum_resident_set_size'] for c in manifests['atomic-candidate']['memory_cases']]
double_rss = [c['maximum_resident_set_size_bytes'] for c in manifests['double-candidate']['memory_cases']]
summary = {'source': qualification['candidate_source'], 'baseline': qualification['baseline_source'],
           'runner': qualification['runner_source'], 'paired_atomic_operations': len(atomic),
           'paired_double_operations': len(double), 'atomic_flags': flags, 'double_flags': double_flags,
           'same_flag_cases_as_e343_confirmation': True, 'million_row_renames': renames,
           'million_row_direct_pipelines': pipelines, 'million_row_safe_delegated_pipelines': delegated,
           'candidate_retained_R_heap_bytes': [min(retained), max(retained)],
           'candidate_residual_R_heap_bytes': [min(residual), max(residual)],
           'candidate_atomic_whole_process_RSS_bytes': [min(atomic_rss), max(atomic_rss)],
           'candidate_double_whole_process_RSS_bytes': [min(double_rss), max(double_rss)],
           'raw_files': len([p for p in DATA.rglob('*') if p.is_file()]),
           'qualification_sha256': digest(DATA / 'qualification.json'),
           'summarizer_sha256': digest(Path(__file__))}
with (ROOT / 'c8ca0a4-performance-summary.json').open('x') as stream:
    json.dump(summary, stream, indent=2)
    stream.write('\n')

lines = ['# Stage 4 review fix qualification, 2026-09-07', '',
    'The fixed candidate passes the ownership, correctness, allocation and retained-heap gates. '
    'The fresh paired matrix retains the same twelve base-R element-read costs and three delegated-filter '
    'timing flags. Overall epic performance acceptance remains open; Stage 6 must resolve the filter paths.', '',
    f"Candidate `{summary['source']}`, package tree `f88005766aee9b9dd5827b33a3930feff6672008`, "
    'installed DLL MD5 `c655c59a09cbf1cd72a6f72e7e94758e`. '
    f"Baseline `{summary['baseline']}`. Both sides use runner `{summary['runner']}`. "
    'The two documented Python drivers have unchanged executable ASTs. All R workloads retain their original bytes.', '',
    'Thirteen coordinated phases completed without concurrent agent builds, tests or probes. '
    'Both sides ran all 206 atomic operations, 126 after-read selector checks and 18 write checks; '
    'the double matrix ran 46 operations, 30 after-read checks, six writes and four capture profiles per side. '
    'Seven iterations were used for timings. Separate memory runs comprised 30 atomic and six double '
    'processes per side, plus 36 retained-heap processes per side. Every raw memory log and derived '
    'comparison is hash-checked.', '',
    '## Retained-column operations', '',
    'Each table has one million rows and 16 columns. Every rename below allocates 84,056 R bytes. '
    'Supported direct selectors and pipelines stay below one million allocated R bytes, '
    'with no repeated scans of unchanged strings.', '',
    '| Column kind | Baseline rename, ms | Candidate rename, ms |',
    '| --- | ---: | ---: |']
for row in renames:
    lines.append(f"| {row['kind']} | {float(row['baseline_median_ms']):.3f} | {float(row['candidate_median_ms']):.3f} |")
direct_times = [float(r['candidate_median_ms']) for r in pipelines]
safe_times = [float(r['candidate_median_ms']) for r in delegated]
lines += ['', f"The direct five-operation column pipelines allocate 422,240 R bytes and take "
          f"{min(direct_times):.3f}–{max(direct_times):.3f} ms. Equally safe delegated pipelines allocate "
          f"98,248 bytes and take {min(safe_times):.3f}–{max(safe_times):.3f} ms. Delegation remains faster in this case.", '',
    'The independent constructor probe covers one, 100,000 and one million elements. Native counters '
    'record exactly one initial payload capture and zero additional capture on the first private write, '
    'with stable backing and unchanged borrowed input. The identical corrected probe fails on e343. '
    'Actual registered width-entry probes also release conversion temporaries for both the 1,000-element '
    'and single Latin-1-character cases. These are copy-counter and temporary-lifetime checks, not constructor '
    'timing or total R-allocation measurements.', '',
    '## Remaining timing findings', '',
    'These are the same 15 cases as the earlier e343 confirmation. Each exceeds both 10 percent and '
    'one millisecond against the fresh baseline. No new flagged case appears. The double matrix has no flags.', '',
    '| Column kind | Read operation | Baseline, ms | Candidate, ms |',
    '| --- | --- | ---: | ---: |']
for row in flags:
    lines.append(f"| {row['kind']} | {row['operation']} | {row['baseline_median_ms']:.3f} | {row['candidate_median_ms']:.3f} |")
lines += ['', 'All twelve element-read/coercion flags have unchanged cumulative R allocation. '
    'The three filters retain their Stage 6 owner and prior row-planning diagnosis. '
    'This source fix does not establish universal read parity or make those costs irreducible.', '',
    '## Memory and integrated checks', '',
    f"Across all 36 candidate heap cases, retained R header/vector heap is {min(retained):,} to {max(retained):,} bytes; "
    f"residual heap after dropping results is {min(residual):,} to {max(residual):,} bytes. "
    'Both stay below one million bytes. All five checkpoints were recomputed from the 72 paired raw logs; '
    'the inferred header size is 56 bytes on this host. This excludes native allocation and process RSS.', '',
    f"Whole-process candidate peak RSS ranges from {min(atomic_rss):,} to {max(atomic_rss):,} bytes for atomic cases "
    f"and {min(double_rss):,} to {max(double_rss):,} bytes for doubles. Those values include startup, fixture "
    'construction and validation; they are separate from operation allocation and retained heap.', '',
    'The fresh artifact passes the original 159 native assertions plus 15 readiness checks, 18 supplemental '
    'native atom cases and the rename allocation gate. The complete installed R suite records 16,445 passing '
    'assertions, zero failed/error/skipped results and four established warnings. The standard package check '
    'retains three warnings and two notes. Loopback-dependent coverage was completed with authorized access, '
    'including Haven without skips. Fresh core checks pass 278 tests, bridge checks pass 18; the 11 existing '
    'Cargo package warnings remain disclosed. Source/binary archives, NOTICE, roxygen and interoperability '
    'checks pass. Root independently checked all 1,950 source blobs/modes and all 27 crate members.', '',
    'All 219 historical pure-R behavior comparisons and exact RDS results match. The fresh isolated-library '
    'fertility check matches its complete baseline log: 499 tests, four known failed/errored blocks and two '
    'skips, without a Column reallocation warning. All 454 project files, Git state and existing output '
    'size/mtime remain unchanged. This is strict parity for c8; the earlier e343 footer-mismatch attempts '
    'remain historical failures. It does not replace the final actual fertility renv install/test/restore.', '',
    'Failed development and checker attempts remain preserved. Root corrected an integer-versus-double '
    'expected-count assertion in the constructor probe and a post-run parser that expected DLL_md5 where '
    'three historical fixtures print DLL. The latter audit rereads unchanged successful R outputs; it '
    'does not rewrite them or rerun their workloads. The original package fixture corrections and sandbox '
    'loopback skips are also recorded separately.', '',
    'Stages 5 through 9, the final absence/presence/minimum/current/load-order matrix, final performance '
    'acceptance and the actual fertility renv restoration obligation remain open. Issue #172 stays open.', '']
with (ROOT / 'c8ca0a4-results-draft.md').open('x') as stream:
    stream.write('\n'.join(lines))
print('Final summary and results draft written. Atomic flags: 15 existing cases; double flags: 0; all heap budgets pass.')
