#!/usr/bin/env python3
"""Publish a complete grouping run and bind each sanitized artifact to its source."""
import argparse
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import statistics

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('grouping_run', HERE / 'run.py')
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read_rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    if not __debug__:
        raise RuntimeError('Publication validation requires Python assertions; run without -O')
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'candidate', 'results', 'validation', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--development', type=Path)
    parser.add_argument('--integration', type=Path)
    args = parser.parse_args()
    args = {name: value.resolve() for name, value in vars(args).items() if value is not None}
    out = args['output']
    if out.exists():
        raise RuntimeError('publication destination already exists')
    results = args['results']
    completion = json.loads((results / 'completion.json').read_text())
    protocol = json.loads((results / 'protocol.json').read_text())
    before = json.loads((results / 'provenance-before.json').read_text())
    after = json.loads((results / 'provenance-after.json').read_text())
    rounds = protocol['rounds']
    assert rounds >= 6 and rounds % 6 == 0
    assert completion['observations'] == 2 * rounds * len(RUN.EXPECTED)
    assert completion['exact_results'] and completion['provenance_unchanged']
    assert before['builds'] == after['builds'] and before['controllers'] == after['controllers']
    assert RUN.NATIVE.digest(results / 'source.patch') == completion['source_patch_sha256']
    builds = {name: args[name] for name in ('baseline', 'candidate')}
    for name, build in builds.items():
        assert RUN.NATIVE.inventory(build, name) == before['builds'][name]
        assert not (build / 'source.patch').read_text().strip()
    for relative, digest in before['controllers'].items():
        assert RUN.NATIVE.digest(HERE.parent / relative) == digest
    rows = []
    for round_number in range(1, rounds + 1):
        for variant in builds:
            batch = read_rows(results / f'{round_number:02}-{variant}.csv')
            RUN.validate_round(batch, round_number, variant)
            rows.extend(dict(variant=variant, **row) for row in batch)
    key = lambda row: (int(row['round']), row['variant'], *(row[k] for k in RUN.FIELDS))
    assert sorted(rows, key=key) == sorted(read_rows(results / 'raw.csv'), key=key)
    RUN.validate_balance(rows, rounds)
    groups = RUN.validate_results(rows)
    summaries = read_rows(results / 'summary.csv')
    assert len(summaries) == len(RUN.EXPECTED)
    assert len({tuple(row[k] for k in RUN.FIELDS) for row in summaries}) == len(RUN.EXPECTED)
    for summary in summaries:
        batch = groups[tuple(summary[k] for k in RUN.FIELDS)]
        for variant in builds:
            selected = [row for row in batch if row['variant'] == variant]
            for metric in ('cpu_seconds', 'elapsed_seconds'):
                expected = statistics.median(float(row[metric]) / int(row['iterations']) for row in selected)
                assert math.isclose(float(summary[variant + '_' + metric]), expected, rel_tol=1e-12)
            expected = statistics.median(float(row['peak_vcell_bytes']) for row in selected)
            assert float(summary[variant + '_peak_vcell_bytes']) == expected
        assert math.isclose(float(summary['cpu_speedup']),
            float(summary['baseline_cpu_seconds']) / float(summary['candidate_cpu_seconds']), rel_tol=1e-12)
        assert int(summary['key_cache_bytes']) == 8 * int(summary['n']) * int(summary['key_count'])
    # The acceptance-focused suite ran the same clean install as the timings.
    validation = args['validation']
    binding = json.loads((validation / 'validation-binding.json').read_text())
    candidate = before['builds']['candidate']
    assert binding['candidate_receipt_sha256'] == candidate['receipt_sha256']
    assert binding['candidate_package_sources'] == candidate['source']
    assert binding['candidate_dll_sha256'] == candidate['installed']['libs/dtatools.so']
    focused = read_rows(validation / 'acceptance-focused.csv')
    assert sum(int(row['passed']) for row in focused) > 0
    assert all(row['failed'] == '0' and row['error'] == 'FALSE' and row['skipped'] == 'FALSE'
               for row in focused)
    for variant in builds:
        batch = read_rows(validation / f'{variant}-benchmark-qualification.csv')
        assert len(batch) == len(RUN.EXPECTED)
        assert all(row['phase'] == 'qualification' and row['iterations'] == '0' for row in batch)
    pending, source_map = {}, []
    replacements = [(str(HERE.parents[1]), '<repo>'),
                    (str(Path.home()), '<home>')]
    replacements.extend((str(path), '<' + name + '>') for name, path in args.items())
    replacements.sort(key=lambda pair: len(pair[0]), reverse=True)

    def sanitize(raw):
        text = raw.decode()
        for original, replacement in replacements:
            text = text.replace(original, replacement)
        text = re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+', '<temporary>', text)
        if re.search(r'/(?:Users|home|private/tmp|tmp)/', text):
            raise RuntimeError('unmapped private path in publication')
        return text.encode()

    def queue(source, destination, expected=None):
        raw = source.read_bytes()
        if expected is not None:
            assert sha(raw) == expected
        assert destination not in pending
        assert len(raw) <= 2_000_000
        sanitized = sanitize(raw)
        pending[destination] = sanitized
        source_map.append(dict(artifact=destination, source_sha256=sha(raw),
            published_sha256=sha(sanitized), transformation='private path substitution' if raw != sanitized else 'none'))

    for path in sorted(results.iterdir()):
        if path.is_file():
            queue(path, 'timings/' + path.name)
    for variant, build in builds.items():
        receipt = before['builds'][variant]['receipt']
        expected = {'build-receipt.json': before['builds'][variant]['receipt_sha256'],
                    'input-record.json': receipt['input_record_sha256'],
                    'source.patch': receipt['source_patch_sha256'], 'build.log': receipt['build_log_sha256']}
        for name, digest in expected.items():
            queue(build / name, f'builds/{variant}/{name}', digest)
    for name, digest in binding['artifacts'].items():
        assert Path(name).name == name
        queue(validation / name, 'validation/' + name, digest)
    queue(validation / 'validation-binding.json', 'validation/validation-binding.json')
    queue(Path(__file__).resolve(), 'publication-controller.py')
    pending['publication-source-map.json'] = (json.dumps(source_map, indent=2, sort_keys=True) + '\n').encode()
    pending['publication-manifest.json'] = (json.dumps({name: sha(data) for name, data in sorted(pending.items())},
                                                     indent=2, sort_keys=True) + '\n').encode()
    out.mkdir(parents=True)
    for name, data in pending.items():
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print('Published', len(rows), 'qualified observations')


if __name__ == '__main__':
    main()
