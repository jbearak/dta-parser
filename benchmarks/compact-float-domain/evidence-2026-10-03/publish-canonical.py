#!/usr/bin/env python3
"""Private canonical-domain publication draft. Requires an explicitly frozen config.

Usage: publish-canonical-draft.py CONFIG.json NEW_OUTPUT
The configuration names completed evidence only. Nothing is discovered from a
running experiment. Historical controllers are redacted snapshots; restoring
private paths and regex literals may be required before replay. This script
itself constructs its privacy patterns dynamically and is copied unchanged.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def load(path):
    return json.loads(path.read_text())


def at(value, pointer):
    need(pointer.startswith('/'), 'Expected explicit JSON pointer')
    for part in pointer[1:].split('/'):
        part = part.replace('~1', '/').replace('~0', '~')
        value = value[int(part)] if isinstance(value, list) else value[part]
    return value


def relative(name):
    need(isinstance(name, str) and name != '', 'Missing artifact name')
    path = PurePosixPath(name)
    need(not path.is_absolute() and all(x not in ('', '.', '..') for x in name.split('/')),
         'Unsafe artifact name: ' + name)
    return path


def main():
    need(len(sys.argv) == 3, __doc__)
    config_path, output = (Path(x).resolve() for x in sys.argv[1:])
    config = load(config_path)
    need(config['schema_version'] == 1 and config['ready'] is True,
         'Publication is pending; complete and review every source/audit/decision gate first')
    need(not output.exists(), 'Refusing to replace a publication')
    pin_names = {'baseline', 'rejected', 'corrected', 'integrated'}
    need(set(config['pins']) == pin_names and all(re.fullmatch(r'[0-9a-f]{40}', x)
         for x in config['pins'].values()), 'Missing exact source pins')
    roots = {k: Path(v).resolve(strict=True) for k, v in config['roots'].items()}
    need(set(roots) >= {'evidence', 'repository'}, 'Missing evidence/repository roots')
    originals = {}
    omitted = []
    generated_names = {'publication-manifest.json', 'publication-source-map.json',
                       'omitted-artifacts.json'}

    def path(spec):
        need(set(spec) == {'root', 'path'}, 'Unexpected path specification')
        candidate = roots[spec['root']].joinpath(*relative(spec['path']).parts)
        resolved = candidate.resolve(strict=True)
        need(resolved.is_relative_to(roots[spec['root']]) and resolved.is_file(),
             'Artifact escapes its declared root')
        return resolved

    def want(value):
        if isinstance(value, dict) and set(value) == {'pin'}:
            return config['pins'][value['pin']]
        return value

    def bound(file, digest):
        need(isinstance(digest, str) and re.fullmatch(r'[0-9a-f]{64}', digest),
             'Unfrozen artifact digest')
        data = file.read_bytes()
        need(sha(data) == digest, 'Changed evidence: ' + str(file))
        return data

    def queue(file, name, digest=None):
        relative(name)
        need(name not in generated_names, 'Reserved generated publication name: ' + name)
        data = bound(file, digest) if digest is not None else file.read_bytes()
        data.decode('utf-8')  # No binaries, fixtures, private archives or DLLs enter this bundle.
        if name in originals:
            need(originals[name] == (file, data), 'Conflicting publication destination: ' + name)
            return  # A shared child was independently checked through another receipt.
        originals[name] = (file, data)

    required_groups = {'decisions', 'audits', 'timings', 'qualifications', 'structural',
                       'codegen', 'focused', 'historical_full_suite', 'integration',
                       'archive', 'final34'}
    groups = config['groups']
    need(set(groups) == required_groups and all(groups[g] for g in required_groups),
         'Incomplete evidence-group inventory')
    # Each group gate has exact, independently reviewed expected fields plus
    # hash-bound children. A PASS label by itself is explicitly insufficient.
    for group, gates in groups.items():
        for gate in gates:
            file = path(gate['receipt'])
            receipt = json.loads(bound(file, gate['receipt_sha256']))
            need(len(gate['expect']) >= 2 and gate['bindings'], 'Incomplete gate: ' + group)
            for pointer, expected in gate['expect'].items():
                need(at(receipt, pointer) == want(expected), 'Gate mismatch: ' + group + pointer)
            # Absolute-key hash maps use explicit file bindings below. Validate
            # the entire key set without treating receipt keys as local paths.
            for pointer, names in gate.get('expected_key_sets', {}).items():
                values = at(receipt, pointer)
                need(isinstance(values, dict) and len(names) == len(set(names)) and
                     set(values) == set(names), 'Referenced-key set changed: ' + pointer)
            queue(file, gate['publish_as'], gate['receipt_sha256'])
            for child in gate['bindings']:
                queue(path(child['file']), child['publish_as'], at(receipt, child['digest_pointer']))
            for child in gate.get('omitted_bindings', []):
                name = child['artifact']
                relative(name)
                need(isinstance(child['reason'], str) and child['reason'].strip(),
                     'Omitted artifact needs an explicit scope reason')
                digest = at(receipt, child['digest_pointer'])
                bound(path(child['file']), digest)
                omitted.append(dict(group=group, artifact=name, source_sha256=digest,
                                    reason=child['reason']))
            # Receipt artifact maps are validated in full. Every child must be
            # published or explicitly omitted with its source hash and reason.
            for collection in gate.get('collections', []):
                values = at(receipt, collection['digest_pointer'])
                need(isinstance(values, dict) and values, 'Empty referenced-artifact set')
                need(set(values) == set(collection['expected_names']), 'Referenced-artifact set changed')
                omissions = collection.get('omit', {})
                need(set(omissions) <= set(values), 'Unknown omitted child')
                for name, digest in values.items():
                    relative(name)
                    spec = {'root': collection['root'],
                            'path': collection['directory'].rstrip('/') + '/' + name}
                    child_path = path(spec)
                    if name in omissions:
                        need(isinstance(omissions[name], str) and omissions[name].strip(),
                             'Omitted artifact needs an explicit scope reason')
                        bound(child_path, digest)
                        omitted.append(dict(group=group, artifact=name, source_sha256=digest,
                                            reason=omissions[name]))
                    else:
                        queue(child_path, collection['publish_prefix'].rstrip('/') + '/' + name, digest)

    # Unreferenced logs, maintained controllers, and the final report must have
    # explicit frozen hashes. The config labels when that binding is post-run.
    need(config['files'], 'No declared controller/report/auxiliary inventory')
    for item in config['files']:
        need(item['binding_scope'] in ('recorded-before-run', 'recorded-after-run',
             'immutable-source', 'post-run-publication'), 'Missing artifact binding scope')
        queue(path(item['file']), item['publish_as'], item['sha256'])
    queue(config_path, 'publication-config.json')
    queue(Path(__file__).resolve(), 'publish-canonical.py')

    identities = set()
    def identity(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('USER', 'LOGNAME'):
                    need(isinstance(item, dict) and set(item) == {'value', 'sha256'} and
                         all(isinstance(x, str) for x in item.values()), 'Unknown identity schema')
                    for token in item.values():
                        if token and not (token.startswith('<') and token.endswith('>')):
                            identities.add(token)
                    item['value'] = item['sha256'] = '<private>'
                else:
                    identity(item)
        elif isinstance(value, list):
            for item in value:
                identity(item)

    replacements = [(str(v), '<' + k + '>') for k, v in roots.items()]
    replacements.append((str(Path.home()), '<user>'))
    replacements.sort(key=lambda x: len(x[0]), reverse=True)
    slash = chr(47)
    temporary = slash + r'(?:private' + slash + r')?tmp' + slash + r'([^/\s"\'<>]+)'
    transient = slash + r'(?:private' + slash + r')?var' + slash + 'folders' + slash + r'[^\s"\'<>]+'
    private = slash + r'(?:Users|home|private' + slash + r'tmp|tmp)' + slash
    pending, mapping = {}, []
    for name, (file, original) in originals.items():
        text = original.decode()
        if file.suffix == '.json':
            value = json.loads(text)
            identity(value)
            text = encoded(value).decode()
        for old, new in replacements:
            text = text.replace(old, new)
        text = re.sub(temporary, r'<private-work>/\1', text)
        text = re.sub(transient, '<temporary>', text)
        need(not re.search(private, text), 'Unmapped private path: ' + name)
        pending[name] = text.encode()
        mapping.append(dict(artifact=name, source_sha256=sha(original),
                            published_sha256=sha(pending[name]),
                            transformation='none' if original == pending[name] else
                            'private paths/identity redaction or JSON formatting'))
    for name, data in pending.items():
        for token in identities:
            need(not re.search(r'(?<![\w])' + re.escape(token) + r'(?![\w])', data.decode()),
                 'Direct identity value or digest remains: ' + name)
    need(pending['publish-canonical.py'] == Path(__file__).read_bytes(),
         'Publisher redacted itself; preserve functional rules')
    pending['omitted-artifacts.json'] = encoded(omitted)
    pending['publication-source-map.json'] = encoded(mapping)
    pending['publication-manifest.json'] = encoded({n: sha(d) for n, d in sorted(pending.items())})
    output.mkdir(parents=True)
    for name, data in pending.items():
        destination = output.joinpath(*relative(name).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print(json.dumps(dict(status='PASS', artifacts=len(pending), mapped_sources=len(mapping),
                         omitted_children=len(omitted))))


if __name__ == '__main__':
    main()
