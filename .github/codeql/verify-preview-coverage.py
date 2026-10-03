#!/usr/bin/env python3
"""Check a private preview's separately decoded source-file coverage.

This is an observed extraction gate, not an assumption about include filtering.
It does not run CodeQL, change a configuration, or upload results.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path, PurePosixPath

SOURCE = '531600a2c451d42bfaaf42e8d7f69006c6af06af'
BASE = '049a6bbf0f4f31edf586abcfce514ee182e272ee'
INVENTORY_SHA256 = '3a778322505098fdae7c673849ecd2c911bd4f7a0b55b1f504e19dee75f5ff02'
QUERY = '''/**
 * @name Private preview extracted source paths
 * @description Lists extracted files under the source root for a separate coverage check.
 * @kind table
 * @id dta/private-preview-extracted-paths
 */
import cpp

from File f
where exists(f.getRelativePath()) and f.fromSource()
select f.getRelativePath()
'''

def require(ok, message):
    if not ok:
        raise ValueError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def safe_relative(value):
    require(isinstance(value, str) and bool(value), 'Empty/non-string source path')
    require(not value.startswith('/') and '\\' not in value and ':' not in value,
            'Source path must use repository-relative POSIX form')
    require(all(part not in ('', '.', '..') for part in value.split('/')),
            'Noncanonical source path')
    require(not any(ord(c) < 32 for c in value), 'Control character in source path')
    require(str(PurePosixPath(value)) == value, 'Changed source path normalization')
    return value

def expected(inventory):
    require(inventory['status'] == 'PASS' and inventory['source_commit'] == SOURCE
            and inventory['baseline_commit'] == BASE, 'Wrong source inventory pins')
    excluded = [safe_relative(r['path']) for r in inventory['proposed_exclusions']]
    old = [safe_relative(r['path']) for r in inventory['previous_main_historical_must_retain']]
    active = [safe_relative(r['path']) for r in inventory['current_runtime_and_maintained_must_retain']]
    require(len(excluded) == len(set(excluded)) == 117, 'Wrong/duplicate exclusion population')
    require(len(old) == len(set(old)) == 43, 'Wrong/duplicate previous-main population')
    require(len(active) == len(set(active)) == 73, 'Wrong/duplicate active population')
    kept = set(old) | set(active)
    require(len(kept) == 116 and not kept.intersection(excluded), 'Overlapping coverage sets')
    require(inventory['previous_main_historical_blobs_unchanged'] is True,
            'Previously scanned historical source changed')
    require(set(inventory['unchanged_runtime_inc_headers']).issubset(kept), 'Runtime INC not retained')
    return set(excluded), kept, set(old), set(active)

def read_csv(data):
    # CLI: codeql bqrs decode --format=csv --no-titles --result-set='#select'.
    # No entity labels or URI-to-path inference is needed: QL selects strings.
    rows = list(csv.reader(io.StringIO(data.decode('utf-8')), strict=True))
    require(bool(rows), 'No extracted paths decoded')
    require(all(len(row) == 1 for row in rows), 'Expected exactly one path column without titles')
    paths = [safe_relative(row[0]) for row in rows]
    require(len(paths) == len(set(paths)), 'Duplicate extracted path')
    return set(paths)

def compare(inventory, observed):
    excluded, kept, old, active = expected(inventory)
    missing = sorted(kept - observed)
    leaked = sorted(excluded & observed)
    extras = sorted(observed - kept - excluded)
    return {
        'status': 'PASS' if not missing and not leaked else 'FAIL',
        'source_commit': SOURCE, 'baseline_commit': BASE,
        'excluded_expected': len(excluded), 'excluded_observed': leaked,
        'retained_expected': len(kept), 'retained_missing': missing,
        'previous_main_historical_expected': len(old),
        'previous_main_historical_missing': sorted(old - observed),
        'runtime_and_maintained_expected': len(active),
        'runtime_and_maintained_missing': sorted(active - observed),
        'extracted_relative_path_count': len(observed),
        'other_extracted_relative_paths': extras,
        'all_observed_relative_paths': sorted(observed),
        'scope': ('Separate extraction-presence check only. Original 61 default-suite queries '
                  'must be independently checked unchanged and complete. File presence is not '
                  'a proof that all preprocessor branches or function bodies were analyzed. '
                  'Missing retained files or present exclusions are failures requiring diagnosis, '
                  'not permission to widen exclusions or weaken this check.'),
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--query', type=Path, required=True)
    parser.add_argument('--bqrs', type=Path, required=True)
    parser.add_argument('--decoded-csv', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.inventory.read_bytes()
    require(sha(raw) == INVENTORY_SHA256, 'Frozen source inventory hash mismatch')
    query = args.query.read_bytes()
    require(query == QUERY.encode(), 'Supplemental coverage query changed')
    bqrs = args.bqrs.read_bytes()
    require(bool(bqrs), 'Empty BQRS source')
    decoded = args.decoded_csv.read_bytes()
    report = compare(json.loads(raw), read_csv(decoded))
    report['inputs'] = {
        'inventory_sha256': sha(raw), 'query_sha256': sha(query),
        'bqrs_sha256': sha(bqrs), 'decoded_csv_sha256': sha(decoded),
        'verifier_sha256': sha(Path(__file__).read_bytes()),
    }
    report['decode_binding_limit'] = ('This verifier binds the supplied BQRS and CSV bytes; '
        'the runner must retain exact query-run/decode command, status and input/output hashes '
        'to bind their derivation to the analyzed database. It does not independently decode BQRS.')
    with args.output.open('x') as f:
        json.dump(report, f, indent=2, sort_keys=True)
        f.write('\n')
    require(report['status'] == 'PASS', 'Extraction coverage failed; inspect output receipt')
    print('PASS: 117 excluded files absent; all 116 retained files present')

if __name__ == '__main__':
    main()
