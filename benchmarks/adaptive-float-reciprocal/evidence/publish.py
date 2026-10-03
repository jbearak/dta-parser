#!/usr/bin/env python3
"""Publish the accepted adaptive experiment and separately retained rejection."""
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

WORK = Path(__file__).resolve().parent
FINAL = Path('<integrated-work>')
REPO = Path('<integrated-source>')
MEASURED_REPO = Path('<measured-source>')
BASE_BUILD = Path('<baseline-build>')
BASE = 'f219bf72bbc882cc4c090ded870470ab9c5e2099'
REJECTED = '2a89fd6f5af9d60fce5020688fd917238a27f441'
ACCEPTED = '2ec57f24a14a646ae67fd2e0af4fb8ef1c549f52'
INTEGRATED = 'a93716003b553626e120a97fba0991ef73334b26'


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def bound(path, expected):
    require(sha(path) == expected, 'Changed bound artifact: ' + str(path))


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def identities(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ('USER', 'LOGNAME'):
                require(isinstance(item, dict) and set(item) == {'value', 'sha256'} and
                        all(isinstance(v, str) for v in item.values()), 'Unexpected identity schema')
                item['value'] = item['sha256'] = '<private>'
            else:
                identities(item)
    elif isinstance(value, list):
        for item in value:
            identities(item)


def main():
    output = Path(sys.argv[1]).resolve()
    require(not output.exists(), 'Publication destination exists')
    stages = [('rejected', '', REJECTED, 'candidate-v2'),
              ('accepted', 'hybrid-', ACCEPTED, 'candidate-v3')]
    for label, prefix, commit, build_name in stages:
        audit = read(WORK / (prefix + 'independent-audit.json'))
        require(audit['status'] == 'PASS' and audit['observations'] == 216 and
                audit['qualification_observations'] == 36 and audit['summaries'] == 9 and
                audit['source_commits'] == {'baseline': BASE, 'candidate': commit}, 'Wrong timing audit')
        bound(WORK / (prefix + 'independent-audit.py'), audit['audit_sha256'])
        for name, digest in audit['artifact_sha256'].items():
            bound(WORK / name, digest)
        controller = WORK / (prefix + 'controller')
        controllers = {name: controller / file for name, file in (
            ('controller', 'run.py'), ('worker', 'worker.R'), ('validation', 'core.py'),
            ('protocol_tests', 'test-run.py'))}
        controllers.update(build_validation=MEASURED_REPO / 'benchmarks/native-operations/run.py',
                           build_recorder=MEASURED_REPO / 'benchmarks/r-file-readers/record-builds.py',
                           build_recorder_parent=MEASURED_REPO / 'benchmarks/io-optimization/record-builds.py')
        for stage, count in (('screen-v1', 216), ('qualification-v1', 36)):
            directory = WORK / (prefix + stage)
            before = read(directory / 'provenance-before.json')
            require(before == read(directory / 'provenance-after.json'), 'Changed stage identities')
            complete = read(directory / 'completion.json')
            require(complete['observations'] == count and complete['exact_results'] is True and
                    complete['provenance_unchanged'] is True, 'Incomplete measured stage')
            for name, digest in complete['artifacts'].items():
                bound(directory / name, digest)
            require({r: b['receipt']['base_commit'] for r, b in before['builds'].items()} ==
                    {'baseline': BASE, 'candidate': commit}, 'Wrong measured source roles')
            require(set(before['controllers']) == set(controllers), 'Unknown controller dependency')
            for name, digest in before['controllers'].items():
                bound(controllers[name], digest)
            for role, build in (('baseline', BASE_BUILD), ('candidate', WORK / build_name)):
                b = before['builds'][role]
                for name, digest in (('build-receipt.json', b['receipt_sha256']),
                                     ('input-record.json', b['receipt']['input_record_sha256']),
                                     ('source.patch', b['receipt']['source_patch_sha256'])):
                    bound(build / name, digest)

    qualification = read(WORK / 'hybrid-qualification-binding.json')
    require(qualification['source_commit'] == ACCEPTED, 'Wrong focused source')
    bound(WORK / 'bind-hybrid-qualification.py', qualification['binder_sha256'])
    for name, digest in qualification['exact_source_sha256'].items():
        bound(MEASURED_REPO / name, digest)
    for role, record in qualification['focused'].items():
        require(record['assertions'] == 36009 and record['blocks'] == 34, 'Wrong focused totals')
        for suffix in ('csv', 'log'):
            bound(WORK / ('hybrid-' + role + '-focused-v1.' + suffix), record[suffix + '_sha256'])
        rows = list(csv.DictReader((WORK / ('hybrid-' + role + '-focused-v1.csv')).open()))
        require(len(rows) == 34 and len({(r['file'], r['test']) for r in rows}) == 34, 'Focused matrix changed')
        require(all(re.fullmatch(r'[0-9]+', r['passed']) and r['failed'] == r['warning'] == '0' and
                    r['error'] == r['skipped'] == 'FALSE' for r in rows), 'Focused failure')
        require(sum(int(r['passed']) for r in rows) == 36009, 'Focused count changed')
    for directory, controller, commit, status, failures in (
            ('hybrid-red-v2', 'hybrid-probe-source-v2', REJECTED, 'EXPECTED_RED', 292),
            ('hybrid-green-v1', 'hybrid-probe-source-v3', ACCEPTED, 'PASS', 0)):
        receipt = read(WORK / directory / 'receipt.json')
        require(receipt['commit'] == commit and receipt['status'] == status and
                receipt['matrix_cases'] == 1980 and receipt['semantic_failures'] == 0 and
                receipt['work_failures'] == failures and receipt['source_before_after_equal'] is True,
                'Wrong structural stage')
        for name, digest in receipt['artifact_sha256'].items():
            bound(WORK / directory / name, digest)
        bound(WORK / controller / 'work-count.py', receipt['controller_sha256'])
        bound(WORK / controller / 'work-count.c', receipt['probe_sha256'])
    codegen = read(WORK / 'codegen-v3-independent-review.json')
    require(codegen['status'] == 'PASS' and codegen['source_commit'] == ACCEPTED, 'Codegen review failed')
    bound(WORK / 'codegen-v3/binding.json', codegen['binding_sha256'])
    bound(WORK / 'candidate-v3/library/dtatools/libs/dtatools.so', codegen['installed_dll_sha256'])
    for name, digest in read(WORK / 'codegen-v3/binding.json')['artifact_sha256'].items():
        bound(WORK / 'codegen-v3' / name, digest)

    archive = read(FINAL / 'conformance.json')
    require(archive['source_commit'] == INTEGRATED and all(archive[k] is True for k in (
        'checked_source_matches_clean_export', 'clean_export_matches_source_commit',
        'exact_packaged_source_inventory', 'expected_hashes_from_committed_blobs',
        'repository_environment_overrides_removed', 'required_conformance_passed')), 'Archive gate failed')
    bound(FINAL / 'conformance.tar.gz', archive['source_archive_sha256'])
    integration = read(FINAL / 'integration-binding.json')
    require(integration['status'] == 'PASS' and integration['source_commit'] == INTEGRATED and
            integration['measured_header_commit'] == ACCEPTED, 'Integration gate failed')
    for name, digest in integration['artifact_sha256'].items():
        bound(FINAL / name, digest)

    pending, mapping = {}, []
    replacements = sorted([(str(WORK), '<measured-work>'), (str(FINAL), '<integrated-work>'),
        (str(BASE_BUILD), '<baseline-build>'), (str(REPO), '<integrated-source>'),
        (str(MEASURED_REPO), '<measured-source>'), (str(Path.home()), '<user>')],
        key=lambda pair: len(pair[0]), reverse=True)
    def queue(path, name):
        original = path.read_bytes()
        text = original.decode()
        if path.suffix == '.json':
            value = json.loads(text)
            identities(value)
            text = encoded(value).decode()
        for old, new in replacements:
            text = text.replace(old, new)
        text = re.sub(r'/(?:private/)?tmp/([^/\s\"\'<>]+)', r'<private-work>/\1', text)
        text = re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+', '<temporary>', text)
        scan = text.replace('/(?:Users|home|private/tmp|tmp)/', '<path-pattern>')
        require(not re.search(r'/(?:Users|home|private/tmp|tmp)/', scan), 'Unmapped private path: ' + name)
        require(name not in pending, 'Repeated publication destination')
        public = text.encode()
        pending[name] = public
        mapping.append(dict(artifact=name, source_sha256=hashlib.sha256(original).hexdigest(),
                            published_sha256=hashlib.sha256(public).hexdigest(),
                            transformation='none' if original == public else 'private paths/identity redaction or JSON formatting'))

    for label, prefix, _, build_name in stages:
        for stage in ('screen-v1', 'qualification-v1'):
            for path in sorted((WORK / (prefix + stage)).iterdir()):
                if path.suffix in ('.csv', '.json', '.patch'):
                    queue(path, label + '/' + stage + '/' + path.name)
        for path in sorted((WORK / (prefix + 'controller')).iterdir()):
            if path.suffix in ('.py', '.R'):
                queue(path, label + '/controller/' + path.name)
        for suffix in ('.py', '.json'):
            queue(WORK / (prefix + 'independent-audit' + suffix), label + '/independent-audit' + suffix)
        for name in ('build-receipt.json', 'input-record.json', 'source.patch'):
            queue(WORK / build_name / name, label + '/build/' + name)
    for name in ('build-receipt.json', 'input-record.json', 'source.patch'):
        queue(BASE_BUILD / name, 'baseline-build/' + name)
    for name, path in (
            ('build_validation.py', 'benchmarks/native-operations/run.py'),
            ('build_recorder.py', 'benchmarks/r-file-readers/record-builds.py'),
            ('build_recorder_parent.py', 'benchmarks/io-optimization/record-builds.py')):
        queue(MEASURED_REPO / path, 'recorders/' + name)
    for name in ('hybrid-qualification-binding.json', 'bind-hybrid-qualification.py',
                 'hybrid-baseline-focused-v1.csv', 'hybrid-candidate-focused-v1.csv',
                 'hybrid-control-normalization-root.json', 'codegen-v3-independent-review.json',
                 'review-codegen-v3.py'):
        queue(WORK / name, name)
    for directory in ('hybrid-red-v2', 'hybrid-green-v1'):
        for name in ('receipt.json', 'work-count.csv', 'work-count.log', 'source.patch'):
            queue(WORK / directory / name, 'structural/' + directory + '/' + name)
    for directory in ('hybrid-probe-source-v2', 'hybrid-probe-source-v3'):
        for name in ('work-count.py', 'work-count.c'):
            queue(WORK / directory / name, 'structural/' + directory + '/' + name)
    for name in ('binding.json', 'remarks.log'):
        queue(WORK / 'codegen-v3' / name, 'codegen/' + name)
    for name in ('integration-binding.json', 'bind-integration.py', 'integration-focused.csv', 'focused-source.R',
                 'conformance.json', 'conformance-command.json', 'conformance.log',
                 'conformance-testthat.Rout', 'run-conformance.py', 'conformance-gate.sh',
                 'validate-conformance-archive.py'):
        queue(FINAL / name, 'integration/' + name)
    queue(Path(__file__), 'publish.py')
    pending['publication-source-map.json'] = encoded(mapping)
    pending['publication-manifest.json'] = encoded({name: hashlib.sha256(data).hexdigest()
                                                   for name, data in sorted(pending.items())})
    output.mkdir(parents=True)
    for name, data in pending.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print('Published', len(pending), 'artifacts; originals unchanged')


if __name__ == '__main__':
    main()
