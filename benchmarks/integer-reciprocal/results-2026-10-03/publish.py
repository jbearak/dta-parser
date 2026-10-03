#!/usr/bin/env python3
"""Package already audited reciprocal evidence; do not rerun measurements.

Usage: publish.py EVIDENCE BASELINE_BUILD MEASURED_REPOSITORY OUTPUT
The original evidence is read-only. Public copies remove local paths and user
identity values/digests. Original whole-file hashes remain in the source map.
This packages evidence; the recorded independent audits establish its claims.
"""
import hashlib
import json
from pathlib import Path
import re
import sys


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def redact_identities(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ('LOGNAME', 'USER'):
                require(isinstance(item, dict) and set(item) == {'value', 'sha256'} and
                        all(isinstance(v, str) for v in item.values()),
                        'Unexpected identity schema')
                item['value'] = item['sha256'] = '<private>'
            else:
                redact_identities(item)
    elif isinstance(value, list):
        for item in value:
            redact_identities(item)


def main():
    work, baseline, measured_repo, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
    require(not output.exists(), 'Publication destination already exists')
    pending, mapping = {}, []

    def read(name):
        return json.loads((work / name).read_text())

    def bound(path, expected):
        require(hashlib.sha256(path.read_bytes()).hexdigest() == expected,
                'Audited artifact changed: ' + str(path))

    for name, observations in (('screen-v1', 432), ('acceptance-v1', 1224)):
        audit = read(name.split('-')[0] + '-independent-audit.json')
        require(audit['result'] == 'PASS' and audit['observations'] == observations,
                'Independent timing audit failed')
        for relative, expected in audit['artifacts'].items():
            bound(work / name / relative, expected)
        completion = read(name + '/completion.json')
        require(completion['observations'] == observations and completion['rounds'] == 6,
                'Incomplete measured matrix')
        require(all(completion[k] is True for k in ('exact_results', 'missing_cache_matches',
                    'typed_missing_mutation_checked', 'source_state_unchanged',
                    'provenance_unchanged', 'worker_runtime_unchanged')), 'Failed measured gate')
        before, after = (read(name + '/provenance-' + side + '.json') for side in ('before', 'after'))
        require(all(before[k] == after[k] for k in ('builds', 'controllers', 'runtime')),
                'Changed measured source/runtime/controllers')
        require({role: b['receipt']['base_commit'] for role, b in before['builds'].items()} == {
            'baseline': '7003eba901671797ee91fffc97f08e28a1f7f515',
            'candidate': '3a02e6d13309441366a7a727fdc934f424ce66c6'}, 'Wrong measured sources')
        controller = 'diagnostic-controller' if name == 'screen-v1' else 'acceptance-controller'
        for filename in ('general-run.py', 'general-worker.R'):
            bound(work / controller / filename, before['controllers'][filename])
        for role, build in (('baseline', baseline), ('candidate', work / 'candidate-final')):
            record = before['builds'][role]
            bound(build / 'build-receipt.json', record['receipt_sha256'])
            bound(build / 'input-record.json', record['receipt']['input_record_sha256'])
            bound(build / 'source.patch', record['receipt']['source_patch_sha256'])
    qualification = read('qualification-binding.json')
    require(qualification['status'] == 'PASS' and
            qualification['commit'] == '3a02e6d13309441366a7a727fdc934f424ce66c6',
            'Full qualification failed or has wrong source')
    for name, expected in qualification['input_sha256'].items():
        bound(Path(name), expected)
    for prefix, cases in (('screen', 72), ('acceptance', 204)):
        qualified = read(prefix + '-qualification-completion.json')
        require(qualified['status'] == 'PASS' and qualified['total'] == cases,
                'Incomplete no-clock qualification')
        for name, expected in qualified['input_sha256'].items():
            bound(Path(name), expected)
        qualification_before = read(prefix + '-qualification-before.json')
        for name, expected in qualification_before['controller_sha256'].items():
            bound(Path(name), expected)
    archive = read('candidate-conformance.json')
    require(archive['source_commit'] == '2c4669dbc8920680323e5ea2fae4bd4840c753cc' and
            all(archive[k] is True for k in ('checked_source_matches_clean_export',
                'clean_export_matches_source_commit', 'exact_packaged_source_inventory',
                'expected_hashes_from_committed_blobs', 'repository_environment_overrides_removed',
                'required_conformance_passed')), 'Retained archive binding failed')
    bound(work / 'candidate-conformance.tar.gz', archive['source_archive_sha256'])
    bound(work / 'candidate-final-reciprocal-loop.asm',
          read('candidate-final-codegen-binding.json')['excerpt_sha256'])
    for stage, expected_exit in (('baseline-final-red', 1), ('candidate-final-counts', 0)):
        bound(work / stage / 'receipt.json',
              qualification['structural_probes'][stage]['receipt_sha256'])
        probe = read(stage + '/receipt.json')
        for name, key in (('work-count.py', 'controller_sha256'), ('work-count.c', 'probe_sha256')):
            bound(measured_repo / 'benchmarks/integer-reciprocal' / name, probe[key])
        require(probe['exit_code'] == expected_exit and probe['require_proved'] is True,
                'Structural red/green gate changed')
        for name in ('work-count.csv', 'work-count.log', 'source.patch'):
            bound(work / stage / name, probe['artifact_sha256'][name])

    replacements = [(str(work), '<work>'), (str(baseline), '<baseline-build>'),
                    (str(measured_repo), '<measured-repository>'), (str(Path.home()), '<user>')]

    def queue(source, relative):
        original = source.read_bytes()
        text = original.decode()
        if source.suffix == '.json':
            value = json.loads(text)
            redact_identities(value)
            text = encoded(value).decode()
        for old, new in replacements:
            text = text.replace(old, new)
        text = re.sub(r'/(?:private/)?tmp/([^/\s\"\'<>]+)', r'<private-work>/\1', text)
        text = re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+', '<temporary>', text)
        require(not re.search(r'/(?:Users|home|private/tmp|tmp)/', text), 'Unmapped path: ' + relative)
        require(relative not in pending, 'Repeated publication path')
        public = text.encode()
        pending[relative] = public
        mapping.append(dict(artifact=relative, source_sha256=hashlib.sha256(original).hexdigest(),
                            published_sha256=hashlib.sha256(public).hexdigest(),
                            transformation='none' if original == public else 'private paths/identity redaction or JSON formatting'))

    for stage, controller in (('screen-v1', 'diagnostic-controller'), ('acceptance-v1', 'acceptance-controller')):
        for path in sorted((work / stage).iterdir()):
            if path.suffix in ('.csv', '.json', '.patch'):
                queue(path, stage + '/' + path.name)
        for name in ('general-run.py', 'general-worker.R', 'test-general-run.py', 'README.md'):
            queue(work / controller / name, controller + '/' + name)
    for role, build in (('baseline', baseline), ('candidate', work / 'candidate-final')):
        for name in ('build-receipt.json', 'input-record.json', 'source.patch'):
            queue(build / name, 'builds/' + role + '/' + name)
    for prefix in ('screen', 'acceptance'):
        for role in ('baseline', 'candidate'):
            queue(work / f'{prefix}-{role}-qualification.csv', f'qualification/{prefix}-{role}.csv')
        for name in (f'{prefix}-qualification-completion.json', f'{prefix}-independent-audit.py',
                     f'{prefix}-independent-audit.json'):
            queue(work / name, 'validation/' + name)
        for phase in ('before', 'after'):
            name = f'{prefix}-qualification-{phase}.json'
            queue(work / name, 'validation/' + name)
    for name in ('qualification-binding.json', 'full-final.csv', 'full-final.R',
                 'candidate-conformance.json', 'candidate-conformance.log',
                 'candidate-final-codegen-binding.json', 'candidate-final-reciprocal-loop.asm',
                 'scalar-control-codegen.json', 'compare-scalar-codegen.py',
                 'acceptance-control-inspection.json', 'incremental-build-binding.json'):
        queue(work / name, 'validation/' + name)
    for stage in ('baseline-final-red', 'candidate-final-counts'):
        for name in ('work-count.csv', 'work-count.log', 'receipt.json', 'source.patch'):
            queue(work / stage / name, 'work-count/' + stage + '/' + name)
    for name in ('work-count.py', 'work-count.c'):
        queue(measured_repo / 'benchmarks/integer-reciprocal' / name, 'work-count/controllers/' + name)
    queue(Path(__file__).resolve(), 'publish.py')
    pending['publication-source-map.json'] = encoded(mapping)
    pending['publication-manifest.json'] = encoded({k: hashlib.sha256(v).hexdigest() for k, v in sorted(pending.items())})
    output.mkdir(parents=True)
    for name, data in pending.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(f'Published {len(pending)} artifacts; originals unchanged')


if __name__ == '__main__':
    main()
