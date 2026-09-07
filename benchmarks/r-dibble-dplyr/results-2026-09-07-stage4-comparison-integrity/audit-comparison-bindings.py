"""Bind archived Stage 4 comparison results to their qualified input identities.

This additive check reads the existing archive without rerunning its summarizer,
comparators, R workloads, or benchmarks. Historical absolute paths are identity
labels only; all actual reads remain inside the supplied archive.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

ORIGINAL_ROOT = '/private/tmp/dta-direct-stage4-validation'
ORIGINAL_DATA = ORIGINAL_ROOT + '/root-c8ca0a4-performance'
METRIC_SOURCE = '/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/run-heap-qualification.py'
COMPARATORS = {'atomic': 'compare-atomic.py', 'double': 'compare-double.py',
               'heap': 'compare-heap-c8ca0a4.py'}
RESULTS = {'atomic': {'operation-comparison.csv', 'memory-comparison.csv', 'investigate.json'},
           'double': {'operation-comparison.csv', 'memory-comparison.csv', 'investigate.json'},
           'heap': {'heap-comparison.csv'}}


def require(condition, message):
    """Fail closed independently of Python optimization flags."""
    if not condition:
        raise RuntimeError(message)


def digest(data):
    """Hash the exact bytes consumed by this audit."""
    return hashlib.sha256(data).hexdigest()


def read_input(archive, relative, seen):
    """Read a contained regular file and retain its exact input identity."""
    path = archive / relative
    require(not path.is_symlink() and path.is_file(), 'Missing or nonregular input: ' + relative)
    require(path.resolve().is_relative_to(archive), 'Escaping input: ' + relative)
    data = path.read_bytes()
    observed = digest(data)
    require(relative not in seen or seen[relative] == observed, 'Input changed during audit: ' + relative)
    seen[relative] = observed
    return data


def audit(archive):
    """Check all nine manifest/comparator bindings before consuming result tables.

    Qualified comparator hashes are independently checked against their archived
    source bytes. Heap's metric-verifier hash is also tied to the qualified
    runtime record and both heap manifests. This is identity verification, not
    an independent recomputation of timings or every comparator formula.
    """
    archive = archive.resolve()
    seen = {}
    qualification = json.loads(read_input(archive, 'benchmark/qualification.json', seen))
    qualified_sources = qualification['executed_source_sha256']
    require(len(qualification['commands']) == 13 and
            all(c['exit_code'] == 0 for c in qualification['commands']), 'Incomplete or failed qualification')
    records = {}
    for family, comparator in COMPARATORS.items():
        prefix = 'benchmark/' + family
        derivation = json.loads(read_input(archive, prefix + '-comparison/derivation.json', seen))
        record = {}
        manifests = {}
        for mode in ['baseline', 'candidate']:
            relative = prefix + '-' + mode + '/root-manifest.json'
            raw = read_input(archive, relative, seen)
            expected_path = ORIGINAL_DATA + '/' + family + '-' + mode + '/root-manifest.json'
            require(derivation[mode + '_manifest'] == expected_path,
                    family + ': ' + mode + ' manifest path mismatch')
            require(derivation[mode + '_manifest_sha256'] == digest(raw),
                    family + ': ' + mode + ' manifest hash mismatch')
            manifest = json.loads(raw)
            require(manifest['source_sha'] == qualification[mode + '_source'] and
                    manifest['runner_source_sha'] == qualification['runner_source'] and
                    manifest['mode'] == mode, family + ': ' + mode + ' source labels mismatch')
            manifests[mode] = manifest
            record[mode + '_manifest_sha256'] = digest(raw)
        source_key = ORIGINAL_ROOT + '/' + comparator
        qualified_hash = qualified_sources[source_key]
        source = read_input(archive, 'benchmark/source/' + comparator, seen)
        require(digest(source) == qualified_hash, family + ': comparator source hash mismatch')
        require(derivation['deriver_sha256'] == qualified_hash, family + ': deriver hash mismatch')
        commands = [c for c in qualification['commands'] if c['name'] == 'compare-' + family]
        require(len(commands) == 1 and commands[0]['command'][1] == source_key,
                family + ': qualified comparator command mismatch')
        record['deriver_sha256'] = qualified_hash
        if family == 'heap':
            metric_hash = qualified_sources[METRIC_SOURCE]
            require(derivation['metric_verifier_sha256'] == metric_hash, 'heap: metric verifier hash mismatch')
            for mode, manifest in manifests.items():
                require(manifest['runner_sha256']['benchmarks/r-dibble-dplyr/run-heap-qualification.py'] == metric_hash,
                        'heap: ' + mode + ' metric runner hash mismatch')
            record['metric_verifier_sha256'] = metric_hash
        require(set(derivation['files']) == RESULTS[family], family + ': comparison file set mismatch')
        records[family] = record
    # No comparison output is read until every family has passed its bindings.
    for family in COMPARATORS:
        prefix = 'benchmark/' + family + '-comparison/'
        derivation = json.loads(read_input(archive, prefix + 'derivation.json', seen))
        rows = {}
        for name, expected in derivation['files'].items():
            raw = read_input(archive, prefix + name, seen)
            require(digest(raw) == expected, family + ': derived result hash mismatch: ' + name)
            if name.endswith('.csv'):
                rows[name] = len(list(csv.DictReader(io.StringIO(raw.decode('utf-8')))))
            else:
                rows[name] = len(json.loads(raw))
        records[family]['result_rows'] = rows
        records[family]['result_sha256'] = derivation['files']
    # Close the observation interval for every consumed input before returning.
    for relative in list(seen):
        read_input(archive, relative, seen)
    return {'scope': 'Fresh additive comparison identity audit; no historical file rewrite, new measurement, or broad performance acceptance.',
            'candidate_source': qualification['candidate_source'], 'baseline_source': qualification['baseline_source'],
            'runner_source': qualification['runner_source'], 'comparisons': records, 'inputs_sha256': seen}


def main():
    """Write one exclusive receipt outside the archive only after a complete audit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    archive, output = args.archive.resolve(), args.output.resolve()
    require(not output.is_relative_to(archive), 'Output must be outside the immutable archive')
    require(not output.exists(), 'Output already exists')
    result = audit(archive)
    result['auditor_sha256'] = digest(Path(__file__).read_bytes())
    with output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print('PASS: nine manifest/comparator bindings, heap verifier, and seven result files')


if __name__ == '__main__':
    main()
