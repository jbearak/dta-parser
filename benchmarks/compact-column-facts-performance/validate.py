#!/usr/bin/env python3
"""Check published hashes, observation qualification and source bindings; no R."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    manifest = read(HERE / 'publication-manifest.json')
    for name, digest in manifest.items():
        require(sha(HERE / name) == digest, 'Publication hash differs: ' + name)
    require(set(manifest) == {str(path.relative_to(HERE)) for path in HERE.rglob('*')
            if path.is_file() and path.name != 'publication-manifest.json'
            and '__pycache__' not in path.parts}, 'Publication inventory differs')
    binding = read(HERE / 'source-bindings.json')
    build = read(HERE / 'evidence/candidate-build-receipt.json')
    require(build['exit_code'] == 0 and build['source_unchanged_during_build'], 'Build not qualified')
    require(len(build['source_inventory']) == binding['source_inventory_entries'] == 479,
            'Build source inventory differs')
    require(build['dll_sha256'] == binding['candidate_dll_sha256'], 'Candidate DLL differs')
    for name, digest in binding['candidate_changed_source_sha256'].items():
        require(build['source_inventory'][name] == digest and
                sha(ROOT / 'r-package/dtatools' / name) == digest, 'Runtime source differs: ' + name)
    for name, digest in binding['reusable_panel_sources'].items():
        require(sha(ROOT / name) == digest, 'Reused panel source differs: ' + name)
    provenance = read(HERE / 'publication-source-map.json')['artifacts']
    for name, item in provenance.items():
        require(sha(HERE / name) == item['public_sha256'], 'Publication provenance differs: ' + name)
    executed = HERE / binding['construction_controller']['executed_path']
    portable = HERE / binding['construction_controller']['portable_path']
    require(sha(executed) == binding['construction_controller']['executed_sha256'] and
            sha(portable) == binding['construction_controller']['portable_sha256'], 'Constructor controller differs')
    old = "default=Path('/private/tmp/dta-compact-float-facts/benchmarks/remaining-compact-kernels')"
    require(executed.read_text().count(old) == 1 and
            executed.read_text().replace(old, "default=HERE.parent / 'remaining-compact-kernels'") == portable.read_text(),
            'Unexpected portable controller change')
    panel = ROOT / 'benchmarks/remaining-compact-kernels'
    general = module('facts_general', panel / 'run.py')
    require(general.summarize(HERE / 'evidence/general', 6) ==
            read(HERE / 'evidence/general/balanced-summary.json'), 'General summary differs')
    general_receipt = read(HERE / 'evidence/general/balanced-run-receipt.json')
    require(general_receipt['exit_code'] == 0 and general_receipt['observations'] == 216 and
            general_receipt['library_before'] == general_receipt['library_after'], 'General binding differs')
    dense = module('facts_dense', panel / 'dense-run.py')
    constructor = module('facts_constructor', portable)
    dense_summary = read(HERE / 'evidence/dense/summary.json')
    construction = read(HERE / 'evidence/construction/summary.json')
    dense_count = constructor_count = 0
    for number in range(1, 7):
        for role in ('baseline', 'candidate'):
            dense_rows = rows(HERE / f'evidence/dense/{role}-round{number}.csv')
            dense.validate(dense_rows, number, ('compact', 'typed_double', 'ordinary_double'))
            dense_count += len(dense_rows)
            constructor_rows = rows(HERE / f'evidence/construction/{role}-round{number}.csv')
            constructor.validate(constructor_rows, number, role, 'measure')
            constructor_count += len(constructor_rows)
    require(dense_summary['status'] == 'PASS' and dense_summary['timed_observations'] == dense_count == 36 and
            dense_summary['before']['installed_packages'] == dense_summary['after']['installed_packages'], 'Dense binding differs')
    require(construction['status'] == 'PASS' and construction['before_after_equal'] and
            construction['observations'] == constructor_count == 72, 'Construction binding differs')
    for role in ('baseline', 'candidate'):
        dll = binding[role + '_dll_sha256']
        require(general_receipt['library_before'][role]['libs/dtatools.so'] == dll and
                dense_summary['before']['dlls'][role] == dll and
                construction['before']['builds'][role]['dll_sha256'] == dll, 'Panel DLL differs: ' + role)
    require(construction['before']['worker_sha256'] == sha(HERE / 'construction-worker.R') ==
            binding['construction_worker_sha256'] and construction['before']['controller_sha256'] == sha(executed),
            'Construction executed source differs')
    probe_cases = {}
    for name, expected in [('pair', 3216), ('dense', 2672), ('integer', 640)]:
        receipt = read(HERE / f'evidence/probes/{name}-receipt.json')
        records = rows(HERE / f'evidence/probes/{name}-cases.csv')
        require(receipt['exit_code'] == 0 and receipt['cases'] == len(records) == expected, 'Probe count differs: ' + name)
        for field in ('semantic_failure', 'semantic_failures', 'work_failure'):
            require(all(int(row.get(field, 0)) == 0 for row in records), 'Probe failure: ' + name + ' ' + field)
        for file, digest in receipt['source_sha256'].items():
            require(build['source_inventory']['src/' + file] == digest, 'Probe/runtime source differs: ' + file)
        probe_cases[name] = expected
    tests = rows(HERE / 'evidence/focused-tests.csv')
    require(len(tests) == 77 and sum(int(row['nb']) for row in tests) == 67212 and
            all(row['failed'] == row['warning'] == '0' and row['error'] == row['skipped'] == 'FALSE'
                for row in tests), 'Public regression record differs')
    require(sha(HERE / 'focused-tests.R') == binding['focused_runner_sha256'], 'Focused runner differs')
    metadata = read(HERE / 'evidence/probes/metadata-span-receipt.json')
    require(metadata['exit_code'] == 0 and metadata['stdout'].startswith('PASS:'), 'Span probe differs')
    for file, digest in metadata['source_sha256'].items():
        if file.endswith('/dtatools-internal.h') or file.endswith('/numeric-payload.c'):
            require(build['source_inventory']['src/' + Path(file).name] == digest, 'Span/runtime source differs')
    print(json.dumps(dict(status='PASS', publication_files=len(manifest), observations=216 + dense_count + constructor_count,
                         probe_cases=probe_cases, public_assertions=67212,
                         scope='Published hashes, original controller qualifications and source/DLL bindings only; no build, R process, probe execution or new timing.'), indent=2))


if __name__ == '__main__':
    main()
