"""Exercise the check runner's complete source setup with synthetic Git children.

The tiny export intentionally has an invalid blob, stopping before any package
or runtime discovery. No real Git, R, compiler or package workload is launched.
"""
import ast
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
DRIVER = Path(os.environ.get('SOURCE_GIT_TEST_DRIVER', HERE / 'run-expression-checks.py'))


class SourceGitTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(os.environ['SOURCE_GIT_TEST_OUTPUT']) / self._testMethodName
        self.root.mkdir(parents=True, exist_ok=False)
        self.output = self.root / 'output'
        self.first, self.second = self.root / 'first', self.root / 'second'
        self.first.mkdir()
        self.second.mkdir()
        self.trace = self.root / 'trace.txt'
        fixture = self.root / 'fixture.tar'
        payload = b'Package: synthetic\nVersion: 0.0.0\n'
        with tarfile.open(fixture, 'w') as archive:
            entry = tarfile.TarInfo('r-package/dtatools/DESCRIPTION')
            entry.mode, entry.size = 0o644, len(payload)
            archive.addfile(entry, io.BytesIO(payload))
        self.a = self.make_git(self.first / 'dispatcher', 'A', fixture)
        self.alias = self.first / 'git'
        self.alias.symlink_to(self.a)
        self.b = self.make_git(self.second / 'git', 'B', fixture)
        self.search_path = str(self.first) + os.pathsep + str(self.second)
        tree = ast.parse(DRIVER.read_text())
        nodes = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom, ast.FunctionDef))]
        self.ns = {'__file__': str(DRIVER)}
        exec(compile(ast.Module(body=nodes, type_ignores=[]), str(DRIVER), 'exec'), self.ns)

    def make_git(self, path, tag, fixture):
        path.write_text(
            '#!/bin/sh\nset -eu\n'
            'case "${0##*/}" in git) ;; *) exit 64;; esac\n'
            "printf '%s:%s\\n' " + shlex.quote(tag) + ' "$3" >> ' + shlex.quote(str(self.trace)) + '\n'
            'case "$3" in\n'
            'show) /bin/cat ' + shlex.quote(str(DRIVER)) + ';;\n'
            "rev-parse) printf 'synthetic-tree\\n';;\n"
            'archive) destination=${5#--output=}; /bin/cp ' + shlex.quote(str(fixture)) + ' "$destination";;\n'
            "ls-tree) printf '100644 blob 0000000000000000000000000000000000000000\\tr-package/dtatools/DESCRIPTION\\0';;\n"
            '*) exit 65;;\nesac\n')
        path.chmod(0o755)
        return path

    def invoke(self, expected, after_binding=None, after_first=None):
        write = self.ns['write']
        original = subprocess.check_output
        seen = []

        def write_hook(path, value):
            write(path, value)
            if path.name == 'source-tool-selection.json' and after_binding is not None:
                after_binding()

        def output_hook(command, **kwargs):
            seen.append(list(command))
            result = original(command, **kwargs)
            if len(seen) == 1 and after_first is not None:
                after_first()
            return result

        self.ns['write'] = write_hook
        arguments = [str(DRIVER), 'focused', str(self.root), 'source', 'runner',
                     str(self.root / 'library'), str(self.output)]
        with patch.dict(os.environ, {'PATH': self.search_path}), patch.object(sys, 'argv', arguments), \
                patch.object(subprocess, 'check_output', side_effect=output_hook):
            with self.assertRaisesRegex((RuntimeError, subprocess.CalledProcessError), expected):
                self.ns['main']()
        return seen

    def records(self):
        receipt = json.loads((self.output / 'receipt.json').read_text())
        result = json.loads((self.output / 'execution-result.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(result['status'], 'failed')
        self.assertFalse(result['input_binding_complete'])
        self.assertEqual(result['records'], [])
        self.assertFalse((self.output / 'preflight.log').exists())
        return receipt, json.loads((self.output / 'source-git-commands.json').read_text())

    def test_path_change_keeps_initial_git_and_invocation_basename(self):
        self.invoke('Source export differs from Git',
                    after_first=lambda: os.environ.__setitem__('PATH', str(self.second)))
        self.assertEqual(self.trace.read_text().splitlines(),
                         ['A:show', 'A:rev-parse', 'A:rev-parse', 'A:archive', 'A:ls-tree'])
        receipt, records = self.records()
        self.assertEqual(len(records), 5)
        self.assertEqual([r['exit_code'] for r in records], [0] * 5)
        self.assertEqual({r['command'][0] for r in records}, {str(self.alias)})
        self.assertEqual(records[0]['environment_path'], self.search_path)
        self.assertEqual({r['environment_path'] for r in records[1:]}, {str(self.second)})
        selected = json.loads((self.output / 'source-tool-selection.json').read_text())
        self.assertEqual(selected['discovery_path'], self.search_path)
        self.assertEqual(selected['tools']['git']['path'], str(self.alias))
        self.assertEqual(selected['tools']['git']['resolved'], str(self.a))
        self.assertEqual({r['path'] for r in selected['inputs']}, {str(self.alias), str(self.a)})
        self.assertFalse(receipt['changed_inputs'])

    def test_alias_retarget_after_binding_rejects_before_first_git(self):
        def change():
            self.alias.unlink()
            self.alias.symlink_to(self.b)
        self.invoke('Selected tool changed', after_binding=change)
        receipt, records = self.records()
        self.assertEqual(records, [])
        self.assertTrue(receipt['changed_inputs'])
        self.assertFalse(self.trace.exists())

    def test_canonical_bytes_change_rejects_before_first_git(self):
        self.invoke('Selected tool changed',
                    after_binding=lambda: self.a.write_text('#!/bin/sh\nexit 17\n'))
        receipt, records = self.records()
        self.assertEqual(records, [])
        self.assertTrue(receipt['changed_inputs'])
        self.assertFalse(self.trace.exists())

    def test_git_change_during_first_command_retains_failure(self):
        self.invoke('Source Git binding changed',
                    after_first=lambda: self.a.chmod(0o700))
        receipt, records = self.records()
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['exit_code'], 0)
        self.assertTrue(receipt['changed_inputs'])
        self.assertEqual(self.trace.read_text().splitlines(), ['A:show'])

    def test_failing_git_retains_command_exit_and_failed_receipt(self):
        self.a.write_text('#!/bin/sh\nexit 17\n')
        self.invoke('returned non-zero exit status 17')
        receipt, records = self.records()
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['exit_code'], 17)
        self.assertEqual(records[0]['error']['type'], 'CalledProcessError')
        self.assertFalse(receipt['changed_inputs'])

    def test_missing_git_retains_failed_setup_receipt(self):
        self.search_path = str(self.root / 'absent')
        self.invoke('Required tool not found: git')
        receipt, records = self.records()
        self.assertEqual(records, [])
        self.assertFalse(receipt['changed_inputs'])
        self.assertFalse((self.output / 'source-tool-selection.json').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
