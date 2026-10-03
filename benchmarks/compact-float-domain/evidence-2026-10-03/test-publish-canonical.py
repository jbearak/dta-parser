#!/usr/bin/env python3
"""Private synthetic failure gates for the canonical evidence publisher."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('canonical_publisher', HERE / 'publish-canonical-draft.py')
PUBLISH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLISH)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class PublicationGuards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.output = self.root / 'published'
        self.config_path = self.root / 'config.json'
        self.child = self.source / 'child.txt'
        self.child.write_text('synthetic observation 42\n')
        self.binary = self.source / 'private.bin'
        self.binary.write_bytes(b'\x00\xffsynthetic omitted data')
        receipt = dict(status='PASS', source='a' * 40,
                       artifacts={'child.txt': digest(self.child.read_bytes())},
                       private_sha256=digest(self.binary.read_bytes()))
        self.receipt = self.source / 'receipt.json'
        self.receipt.write_text(json.dumps(receipt))
        gate = dict(receipt={'root': 'evidence', 'path': 'receipt.json'},
                    receipt_sha256=digest(self.receipt.read_bytes()),
                    expect={'/status': 'PASS', '/source': {'pin': 'corrected'}},
                    expected_key_sets={'/artifacts': ['child.txt']},
                    publish_as='receipt.json',
                    bindings=[dict(file={'root': 'evidence', 'path': 'child.txt'},
                                   digest_pointer='/artifacts/child.txt', publish_as='child.txt')],
                    omitted_bindings=[dict(file={'root': 'evidence', 'path': 'private.bin'},
                                           digest_pointer='/private_sha256',
                                           artifact='omitted/private.bin',
                                           reason='Synthetic binary retained only for hash validation.')])
        groups = ['decisions', 'audits', 'timings', 'qualifications', 'structural',
                  'codegen', 'focused', 'historical_full_suite', 'integration', 'archive', 'final34']
        self.config = dict(schema_version=1, ready=True,
                           pins={name: 'a' * 40 for name in ('baseline', 'rejected', 'corrected', 'integrated')},
                           roots={'evidence': str(self.source), 'repository': str(self.source)},
                           groups={name: [copy.deepcopy(gate)] for name in groups},
                           files=[dict(file={'root': 'evidence', 'path': 'child.txt'},
                                       publish_as='child.txt', sha256=digest(self.child.read_bytes()),
                                       binding_scope='post-run-publication')])

    def run_publisher(self):
        self.config_path.write_text(json.dumps(self.config))
        with patch.object(sys, 'argv', ['publisher', str(self.config_path), str(self.output)]), \
                contextlib.redirect_stdout(io.StringIO()):
            PUBLISH.main()

    def fails(self, text):
        with self.assertRaisesRegex(RuntimeError, text):
            self.run_publisher()
        self.assertFalse(self.output.exists())

    def test_complete_bundle_and_publisher_source(self):
        self.run_publisher()
        manifest = json.loads((self.output / 'publication-manifest.json').read_text())
        actual = {str(p.relative_to(self.output)): digest(p.read_bytes())
                  for p in self.output.rglob('*') if p.is_file()
                  and p.name != 'publication-manifest.json'}
        self.assertEqual(manifest, actual)
        self.assertEqual((self.output / 'publish-canonical.py').read_bytes(),
                         (HERE / 'publish-canonical-draft.py').read_bytes())
        omitted = json.loads((self.output / 'omitted-artifacts.json').read_text())
        self.assertEqual(len(omitted), len(self.config['groups']))
        self.assertTrue(all(row['source_sha256'] == digest(self.binary.read_bytes()) for row in omitted))
        self.assertFalse((self.output / 'omitted/private.bin').exists())

    def test_pending_config_is_rejected(self):
        self.config['ready'] = False
        self.fails('Publication is pending')

    def test_incomplete_group_is_rejected(self):
        self.config['groups']['archive'] = []
        self.fails('Incomplete evidence-group')

    def test_wrong_pin_is_rejected(self):
        self.config['pins']['corrected'] = 'b' * 40
        self.fails('Gate mismatch')

    def test_changed_child_is_rejected(self):
        self.child.write_text('changed\n')
        self.fails('Changed evidence')

    def test_changed_omitted_binary_is_rejected(self):
        self.binary.write_bytes(b'changed omitted binary')
        self.fails('Changed evidence')

    def test_missing_omission_reason_is_rejected(self):
        self.config['groups']['decisions'][0]['omitted_bindings'][0]['reason'] = ' '
        self.fails('explicit scope reason')

    def test_incomplete_child_key_set_is_rejected(self):
        self.config['groups']['decisions'][0]['expected_key_sets']['/artifacts'] = []
        self.fails('Referenced-key set changed')

    def test_parent_escape_is_rejected(self):
        self.config['groups']['decisions'][0]['bindings'][0]['file']['path'] = '../child.txt'
        self.fails('Unsafe artifact name')

    def test_reserved_manifest_destination_is_rejected(self):
        self.config['groups']['decisions'][0]['publish_as'] = 'publication-manifest.json'
        self.fails('Reserved generated publication name')

    def test_text_only_queue_rejects_binary(self):
        self.config['groups']['decisions'][0]['bindings'].append(
            dict(file={'root': 'evidence', 'path': 'private.bin'},
                 digest_pointer='/private_sha256', publish_as='private.bin'))
        with self.assertRaises(UnicodeDecodeError):
            self.run_publisher()
        self.assertFalse(self.output.exists())

    def test_collection_must_declare_every_child(self):
        self.config['groups']['decisions'][0]['collections'] = [
            dict(digest_pointer='/artifacts', expected_names=['missing.txt'], root='evidence',
                 directory='unused', publish_prefix='children')]
        self.fails('Referenced-artifact set changed')

    def test_symlink_escape_is_rejected(self):
        outside = self.root / 'outside.txt'
        outside.write_text('outside\n')
        (self.source / 'escape.txt').symlink_to(outside)
        self.config['groups']['decisions'][0]['bindings'][0]['file']['path'] = 'escape.txt'
        self.fails('Artifact escapes')

    def test_direct_identity_value_and_digest_are_redacted(self):
        token = 'synthetic_identity_987'
        token_digest = digest(token.encode())
        identity = self.source / 'identity.json'
        identity.write_text(json.dumps({'environment': {'USER': {'value': token, 'sha256': token_digest}}}))
        original_digest = digest(identity.read_bytes())
        self.config['files'].append(dict(file={'root': 'evidence', 'path': 'identity.json'},
                                         publish_as='identity.json', sha256=original_digest,
                                         binding_scope='post-run-publication'))
        self.run_publisher()
        for file in self.output.rglob('*'):
            if file.is_file():
                text = file.read_text()
                self.assertNotIn(token, text)
                self.assertNotIn(token_digest, text)
        source_map = json.loads((self.output / 'publication-source-map.json').read_text())
        row = next(row for row in source_map if row['artifact'] == 'identity.json')
        self.assertEqual(row['source_sha256'], original_digest)
        self.assertNotEqual(row['source_sha256'], row['published_sha256'])

    def test_existing_destination_is_preserved(self):
        self.output.mkdir()
        marker = self.output / 'existing.txt'
        marker.write_text('keep\n')
        with self.assertRaisesRegex(RuntimeError, 'Refusing to replace'):
            self.run_publisher()
        self.assertEqual(marker.read_text(), 'keep\n')


if __name__ == '__main__':
    unittest.main()
