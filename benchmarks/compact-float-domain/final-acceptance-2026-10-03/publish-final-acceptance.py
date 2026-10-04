#!/usr/bin/env python3
"""Publish the audited final34 panel, leaving the original evidence unchanged.

Usage: publish-final-acceptance.py EVIDENCE BASELINE_BUILD CANDIDATE_BUILD OUTPUT
This publishes historical evidence with private paths replaced by placeholders.
Scripts containing placeholders require local path restoration before replay.
Package conformance is bound separately in the enclosing canonical-domain report.
"""
import hashlib
import json
from pathlib import Path
import re
import sys


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def read(path):
    return json.loads(path.read_text())


def main():
    need(len(sys.argv) == 5, __doc__)
    root, baseline, candidate, output = (Path(p).resolve() for p in sys.argv[1:])
    need(not output.exists(), 'Publication destination already exists')
    timing = root / 'acceptance-v1'
    audit = read(root / 'acceptance-independent-audit.json')
    need(audit['result'] == 'PASS' and audit['observations'] == 1224 and
         audit['qualification_observations'] == 204 and
         audit['qualification_timing_identity_verified'] is True, 'Complete audit required')
    need(sha((root / 'acceptance-independent-audit.py').read_bytes()) == audit['auditor_sha256'],
         'Auditor source changed')
    for name, digest in audit['artifacts'].items():
        matches = [p for p in (root / name, timing / name) if p.is_file()]
        need(len(matches) == 1 and sha(matches[0].read_bytes()) == digest,
             'Missing, ambiguous or changed audited artifact: ' + name)
    qualified = read(root / 'acceptance-qualification-completion.json')
    need(qualified['status'] == 'PASS' and qualified['total'] == 204, 'Complete qualification required')
    for name, digest in qualified['input_sha256'].items():
        need(sha(Path(name).read_bytes()) == digest, 'Qualification input changed')
    qualification_binding = read(root / 'acceptance-qualification-before.json')
    for name, digest in qualification_binding['controller_sha256'].items():
        need(sha(Path(name).read_bytes()) == digest, 'Qualified controller dependency changed')
    before = read(timing / 'provenance-before.json')
    after = read(timing / 'provenance-after.json')
    need(all(before[k] == after[k] for k in ('builds', 'controllers', 'runtime')), 'Timing binding changed')
    need(before['builds'] == qualification_binding['builds'] and
         before['runtime'] == qualification_binding['runtime'], 'Timing differs from qualification')
    for role, build in (('baseline', baseline), ('candidate', candidate)):
        record = before['builds'][role]
        need(record['receipt']['base_commit'] == audit['source_commits'][role], 'Measured commit changed')
        for name, digest in (('build-receipt.json', record['receipt_sha256']),
                             ('input-record.json', record['receipt']['input_record_sha256']),
                             ('source.patch', record['receipt']['source_patch_sha256']),
                             ('build.log', record['receipt']['build_log_sha256'])):
            need(sha((build / name).read_bytes()) == digest, 'Measured build receipt changed')
    description = read(root / 'final-panel-description.json')
    need(description['source_commits'] == audit['source_commits'] and len(description['results']) == 34,
         'Final description has wrong sources or cases')
    for name, digest in description['input_sha256'].items():
        path = timing / name if name == 'raw.csv' else root / name
        need(sha(path.read_bytes()) == digest, 'Final description input changed')

    guards = read(root / 'controller-guard-results.json')
    need(guards['status'] == 'PASS' and guards['candidate_commit'] == audit['source_commits']['candidate'] and
         len(guards['runs']) == 2 and all(run['exit_code'] == 0 and run['tests'] == 7 for run in guards['runs']),
         'Controller guard results missing or wrong source')
    for name, digest in guards['source_sha256'].items():
        need(sha((root / name).read_bytes()) == digest, 'Guarded controller source changed')
    described = read(root / 'final-panel-description-completion.json')
    need(described['status'] == 'PASS' and described['generator_sha256'] == sha((root / 'describe-final-panel.py').read_bytes()),
         'Description generator changed')
    need(described['inputs'] == description['input_sha256'] and
         set(described['outputs']) == {'final-panel-description.json', 'final-panel-table.md'},
         'Incomplete description input/output binding')
    for name, digest in described['outputs'].items():
        need(sha((root / name).read_bytes()) == digest, 'Generated description output changed')

    originals, pending, mapping, identities = {}, {}, [], set()
    def add(path, relative):
        need(relative not in originals, 'Repeated publication path')
        data = path.read_bytes()
        data.decode('utf-8')
        originals[relative] = (path, data)
    for path in sorted(timing.iterdir()):
        if path.is_file() and path.suffix in ('.csv', '.json', '.patch', '.log'):
            add(path, 'acceptance-v1/' + path.name)
    for name in ('general-run.py', 'general-worker.R', 'test-general-run.py', 'README.md'):
        add(root / 'acceptance-controller' / name, 'acceptance-controller/' + name)
    recorders = [Path(name) for name in qualification_binding['controller_sha256'] if Path(name).name == 'run.py']
    need(len(recorders) == 1 and sha(recorders[0].read_bytes()) == before['controllers']['run.py'],
         'Original recorder dependency missing or changed')
    add(recorders[0], 'acceptance-controller/dependencies/benchmarks/native-operations/run.py')
    for name in ('r-file-readers/record-builds.py', 'io-optimization/record-builds.py',
                 'r-file-readers/build-snapshot.py'):
        dependency = recorders[0].parent.parent / name
        need(str(dependency) in qualification_binding['controller_sha256'] and
             sha(dependency.read_bytes()) == qualification_binding['controller_sha256'][str(dependency)],
             'Missing transitive recorder dependency')
        add(dependency, 'acceptance-controller/dependencies/benchmarks/' + name)
    for role, build in (('baseline', baseline), ('candidate', candidate)):
        for name in ('build-receipt.json', 'input-record.json', 'source.patch', 'build.log'):
            add(build / name, 'builds/' + role + '/' + name)
        for suffix in ('csv', 'log'):
            name = f'acceptance-{role}-qualification.{suffix}'
            add(root / name, 'qualification/' + name)
    for name in ('acceptance-independent-audit.py', 'acceptance-independent-audit.json',
                 'acceptance-qualification-completion.json', 'acceptance-qualification-before.json',
                 'acceptance-qualification-after.json', 'qualify-acceptance.py',
                 'run-qualified-acceptance.py', 'timing-preflight.json', 'timing-qualification-binding.json',
                 'describe-final-panel.py', 'final-panel-description.json', 'final-panel-table.md',
                 'final-panel-description-completion.json', 'controller-guard-results.json'):
        add(root / name, 'validation/' + name)
    add(Path(__file__).resolve(), 'publish-final-acceptance.py')

    def redact_identity(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('LOGNAME', 'USER'):
                    need(isinstance(item, dict) and set(item) == {'value', 'sha256'},
                         'Unexpected identity schema')
                    for field in ('value', 'sha256'):
                        need(isinstance(item[field], str), 'Non-string identity')
                        if item[field] and item[field] != '<private>':
                            identities.add(item[field])
                        item[field] = '<private>'
                else:
                    redact_identity(item)
        elif isinstance(value, list):
            for item in value:
                redact_identity(item)

    replacements = sorted([(str(root), '<evidence>'), (str(baseline), '<baseline-build>'),
                           (str(candidate), '<candidate-build>'), (str(Path.home()), '<user>')],
                          key=lambda pair: len(pair[0]), reverse=True)
    # Build path patterns without embedding private-looking source literals in
    # this publisher; its own published copy remains byte-for-byte reproducible.
    slash = chr(47)
    temp_pattern = slash + r'(?:private' + slash + r')?tmp' + slash + r'([^/\s\"\'<>]+)'
    transient_pattern = slash + r'(?:private' + slash + r')?var' + slash + 'folders' + slash + r'[^\s\"\'<>]+'
    leftover_pattern = slash + r'(?:Users|home|private' + slash + r'tmp|tmp)' + slash
    for relative, (path, original) in originals.items():
        text = original.decode()
        if path.suffix == '.json':
            value = json.loads(text)
            redact_identity(value)
            text = encoded(value).decode()
        for old, new in replacements:
            text = text.replace(old, new)
        text = re.sub(temp_pattern, r'<private-work>/\1', text)
        text = re.sub(transient_pattern, '<temporary>', text)
        need(not re.search(leftover_pattern, text), 'Unmapped private path: ' + relative)
        public = text.encode()
        pending[relative] = public
        mapping.append({'artifact': relative, 'source_sha256': sha(original),
                        'published_sha256': sha(public),
                        'transformation': 'none' if public == original else 'private path/identity redaction or JSON formatting'})
    for relative, data in pending.items():
        text = data.decode()
        for identity in identities:
            need(not re.search(r'(?<![\w])' + re.escape(identity) + r'(?![\w])', text),
                 'Unredacted identity in ' + relative)
    need(pending['publish-final-acceptance.py'] == Path(__file__).read_bytes(),
         'Publisher redacted itself; preserve functional rules')
    pending['README.md'] = ("# Final public-operation acceptance evidence\n\n"
        "This directory contains the final 34-case timing panel, its untimed qualification, "
        "independent audit, complete recorded controller dependencies, generated descriptive "
        "statistics, and build receipts and logs. Package conformance belongs to the enclosing "
        "canonical-domain report and its separately bound combined-source validation.\n\n"
        "These are historical evidence snapshots. Private paths and direct identity fields "
        "are replaced by placeholders. Redaction can also affect path or regular-expression "
        "literals in historical scripts; restore those paths before replay. The source map "
        "records both original and published hashes. The manifest binds the final public bytes.\n\n"
        "The private pre-build command/environment record, DLLs and complete source copies "
        "are not included. Their original hashes remain in the receipts. Source commits and "
        "full inventories are recorded, and the independent audit checked the actual local "
        "source, installed library and runtime before publication. There are no user data "
        "files in this panel; the worker constructs its deterministic inputs.\n").encode()
    pending['publication-source-map.json'] = encoded(mapping)
    pending['publication-manifest.json'] = encoded({name: sha(data) for name, data in sorted(pending.items())})
    output.mkdir(parents=True)
    for name, data in pending.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(json.dumps({'status': 'PASS', 'artifacts': len(pending), 'mapped_sources': len(mapping)}))


if __name__ == '__main__':
    main()
