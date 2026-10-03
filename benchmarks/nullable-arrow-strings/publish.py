"""Publish text evidence from a completed, source-bound nullable reader run."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('evidence', 'baseline', 'candidate', 'audit', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    evidence, baseline, candidate, audit, output = (
        getattr(args, name).resolve() for name in ('evidence', 'baseline', 'candidate', 'audit', 'output'))
    paired = evidence / 'paired-v1'
    completion = json.loads((paired / 'completion.json').read_text())
    require(completion['observations'] == 504 and completion['bindings_unchanged']
            and completion['full_results_exact'] and completion['raw_encoding_exact'],
            'Complete qualified paired results required')
    for name, expected in completion['artifacts'].items():
        require(sha((paired / name).read_bytes()) == expected, 'Changed timing artifact: ' + name)
    audit_record = json.loads(audit.with_suffix('.json').read_text())
    require(audit_record['status'] == 'PASS' and audit_record['observations'] == 504
            and audit_record['artifacts']['raw.csv'] == completion['artifacts']['raw.csv'],
            'Independent audit does not match the run')
    before = json.loads((paired / 'binding-before.json').read_text())
    require(all(sha(Path(path).read_bytes()) == expected
                for path, expected in before['controllers'].items()), 'A measured controller changed')
    full = list(csv.DictReader((evidence / 'full-v2.csv').open()))
    require(all(row['failed'] == '0' and row['error'] == 'FALSE' and row['skipped'] == 'FALSE'
                for row in full), 'Full installed suite did not pass')
    conformance = json.loads((evidence / 'conformance-v2.json').read_text())
    require(conformance['required_conformance_passed'], 'Required conformance did not pass')
    output.mkdir(parents=True, exist_ok=False)
    substitutions = {
        str(baseline): '<baseline-build>', str(candidate): '<candidate-build>',
        str(evidence): '<private-evidence>', str(audit.parent): '<independent-audit>',
        '/private/tmp/dta-nullable-string-bulk': '<candidate-checkout>',
        '/private/tmp/dta-architecture-audit-20261002/nullable-string-probe': '<discovery-fixtures>',
        '/private/tmp/dta-arrow-gc-pressure-20261002': '<baseline-evidence>',
        '/Users/jmb': '<user-home>',
    }
    source_map = {}

    def publish(source, relative):
        original = source.read_bytes()
        value, location = original.decode('utf-8'), str(source)
        for old, new in sorted(substitutions.items(), key=lambda item: -len(item[0])):
            value, location = value.replace(old, new), location.replace(old, new)
        value = re.sub(r'/private/var/folders/[^\s"\)\]]+', '<private-temp>', value)
        data = value.encode('utf-8')
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        source_map[relative] = dict(source=location, original_sha256=sha(original),
                                    published_sha256=sha(data))

    for path in sorted(paired.iterdir()):
        if path.suffix in ('.csv', '.json') or path.suffix == '.log' and path.stat().st_size:
            publish(path, 'timings/' + path.name)
    for label, build in (('baseline', baseline), ('candidate', candidate)):
        require(sha((build / 'build-receipt.json').read_bytes()) ==
                before['builds'][label]['receipt_sha256'], 'Build receipt changed: ' + label)
        for name in ('build-receipt.json', 'input-record.json', 'build.log'):
            publish(build / name, f'builds/{label}/' + name)
    for path in before['controllers']:
        relative = Path(path).parts
        relative = '/'.join(relative[relative.index('benchmarks') + 1:])
        publish(Path(path), 'controllers/' + relative)
    for extension in ('.py', '.json'):
        publish(audit.with_suffix(extension), 'validation/independent-paired-audit' + extension)
    for name in ('full-tests.R', 'full-v2.csv', 'full-v2.log', 'conformance-v2.log',
                 'conformance-v2.json', 'conformance-v2-binding-validation.log',
                 'focused-hardened-observations.csv', 'focused-hardened.log',
                 'rust-all.log', 'controller-tests.log', 'controller-tests-optimized.log',
                 'manifest-refresh.log', 'manifest-tests-hardened.log'):
        publish(evidence / name, 'validation/' + name)
    for path in sorted((evidence / 'candidate-qualification-v2').iterdir()):
        if path.suffix in ('.csv', '.json') or path.suffix == '.log' and path.stat().st_size:
            publish(path, 'qualification/' + path.name)
    baseline_commit = before['builds']['baseline']['receipt']['base_commit']
    candidate_commit = before['builds']['candidate']['receipt']['base_commit']
    repository = Path(__file__).resolve().parents[2]
    patch = subprocess.check_output(['git', 'diff', baseline_commit, candidate_commit,
                                    '--', 'r-package/dtatools'], cwd=repository)
    (evidence / 'measured-package.patch').write_bytes(patch)
    publish(evidence / 'measured-package.patch', 'validation/measured-package.patch')
    write_json(output / 'validation/source-binding.json', dict(
        baseline_commit=baseline_commit, measured_candidate_commit=candidate_commit,
        paired_observations=504, rounds=6,
        full_suite=dict(assertions=sum(int(row['passed']) for row in full), blocks=len(full),
                        warnings=sum(int(row['warning']) for row in full)),
        conformance_source_matches_clean_export=conformance['checked_source_matches_clean_export'],
        conformance_packaged_files=len(conformance['verified_files']),
        scope='Timings and full installed tests use the exact clean candidate build. The standalone Rust tests were run on identical production source before test-only hardening. Later main integrations, if any, are qualified separately.'))
    write_json(output / 'publication-source-map.json', source_map)
    manifest = {str(path.relative_to(output)): dict(sha256=sha(path.read_bytes()), bytes=path.stat().st_size)
        for path in sorted(output.rglob('*')) if path.is_file() and path.name != 'publication-manifest.json'}
    write_json(output / 'publication-manifest.json', dict(files=manifest,
        scope='Text evidence; empty worker logs and large fixture/library binaries are omitted. Every worker CSV is retained. Original and published hashes bind private-path substitutions.'))
    print('Published', len(manifest), 'artifacts', flush=True)


if __name__ == '__main__':
    main()
