#!/usr/bin/env python3
"""Check preserved compact-pair qualification records without R or private paths.

This post-publication check does not rerun the benchmark, package tests or
private source-archive verification. Historical scripts remain unchanged.
"""
import csv
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ARCHIVE = HERE / 'results-2026-10-03-compact-pair'
FIELDS = ['file', 'test', 'passed', 'failed', 'error', 'skipped', 'warning']


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def load(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def suite_totals(path, expected):
    with path.open(newline='') as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == FIELDS, 'Malformed suite columns')
        rows = list(reader)
    require(bool(rows), 'Empty suite')
    totals = dict.fromkeys(FIELDS[2:], 0)
    for row in rows:
        require(set(row) == set(FIELDS) and row['file'] and row['test'],
                'Malformed suite row')
        for key in ('passed', 'failed', 'warning'):
            value = row[key]
            require(isinstance(value, str) and re.fullmatch(r'[0-9]+', value),
                    'Malformed suite count: ' + key)
            totals[key] += int(value)
        for key in ('error', 'skipped'):
            require(row[key] in ('TRUE', 'FALSE'), 'Malformed suite status: ' + key)
            totals[key] += row[key] == 'TRUE'
    require(not any(totals[key] for key in ('failed', 'error', 'skipped')),
            'Suite failed or skipped')
    require({'blocks': len(rows), 'totals': totals} == expected,
            'Suite differs from its binding')
    return {'blocks': len(rows), 'totals': totals}


def receipt_source(inventory):
    source = inventory['source']
    require(source == inventory['receipt']['source_inventory'],
            'Receipt/source inventory mismatch')
    return source


def verify(archive=ARCHIVE):
    manifest = load(archive / 'publication-manifest.json')
    files = {str(path.relative_to(archive)) for path in archive.rglob('*') if path.is_file()}
    require(files == set(manifest) | {'publication-manifest.json'},
            'Publication inventory changed')
    for name, digest in manifest.items():
        require(sha(archive / name) == digest, 'Artifact hash mismatch: ' + name)
    measured = load(archive / 'validation/validation-binding.json')
    integrated = load(archive / 'integration/validation/integration-binding.json')
    require(measured['status'] == integrated['status'] == 'PASS', 'Missing PASS binding')
    before = load(archive / 'timings/provenance-before.json')
    after = load(archive / 'timings/provenance-after.json')
    require(before['builds'] == after['builds'] == measured['builds'],
            'Measured build identities differ')
    for role in ('baseline', 'candidate'):
        require(measured['builds'][role]['receipt'] ==
                load(archive / 'builds' / role / 'build-receipt.json'),
                'Measured receipt differs')
        receipt_source(measured['builds'][role])
    candidate = measured['builds']['candidate']
    require(integrated['measured_candidate'] == candidate['receipt']['base_commit'],
            'Integration names another measured candidate')
    integration = integrated['integration_build']
    require(integration['receipt'] == load(archive / 'integration/build/build-receipt.json'),
            'Integrated receipt differs')
    original_source, integrated_source = receipt_source(candidate), receipt_source(integration)
    for name in integrated['arithmetic_runtime_and_tests_equal_measured']:
        require(original_source[name] == integrated_source[name], 'Arithmetic source changed')
    conformance = load(archive / 'integration/validation/integration-conformance.json')
    require(conformance == integrated['conformance_archive'] and
            conformance['source_commit'] == integrated['source_commit'] and
            all(conformance[key] is True for key in ('required_conformance_passed',
                'checked_source_matches_clean_export', 'clean_export_matches_source_commit',
                'exact_packaged_source_inventory', 'expected_hashes_from_committed_blobs')),
            'Conformance binding differs')
    log = (archive / 'integration/validation/integration-conformance.log').read_text()
    require(any(line.startswith('R package conformance: PASS (') for line in log.splitlines()),
            'Required conformance PASS marker absent')
    return {
        'scope': 'Post-publication integrity, strict suite status/count parsing and recorded source equality. No new package, archive or performance execution.',
        'publication_manifest_sha256': sha(archive / 'publication-manifest.json'),
        'measured_suite': suite_totals(archive / 'validation/full-tests.csv', measured['full_suite']),
        'integrated_suite': suite_totals(archive / 'integration/validation/integration-full-tests.csv',
                                       integrated['full_suite']),
        'receipt_source_fields_equal': True,
        'status': 'PASS',
    }


if __name__ == '__main__':
    print(json.dumps(verify(), indent=2, sort_keys=True))
