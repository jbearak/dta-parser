"""Setup failures must leave failed receipts without starting an R workload."""
import hashlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
REVISION = '1' * 40
TREE = '2' * 40


class SetupFailureTests(unittest.TestCase):
    def run_failure(self, installer, failure):
        script = HERE / ('install-expression-source.py' if installer else 'run-expression-checks.py')
        relative = 'r-package/dtatools/DESCRIPTION'
        content = b'Package: dtatools\nVersion: 0.0.0\n'
        if failure == 'dependency':
            content += b'Imports: codexSetupAbsentDependency\n'
        blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        commands = []

        def git_output(command, **kwargs):
            if 'archive' in command:
                archive(command, **kwargs)
                return b''
            commands.append(command)
            self.assertEqual(Path(command[0]).name, 'git')
            if 'show' in command:
                value = script.read_bytes()
            elif 'ls-tree' in command:
                selected_blob = '0' * 40 if failure == 'export' else blob
                value = f'100644 blob {selected_blob}\t{relative}\0'.encode()
            else:
                self.assertIn('rev-parse', command)
                value = ((REVISION if command[-1].endswith('^{commit}') else TREE) + '\n').encode()
            return value.decode() if kwargs.get('text') else value

        def archive(command, **kwargs):
            commands.append(command)
            self.assertEqual(Path(command[0]).name, 'git')
            self.assertIn('archive', command)
            if failure == 'archive':
                raise subprocess.CalledProcessError(17, command)
            destination = next(value.split('=', 1)[1] for value in command if value.startswith('--output='))
            with tarfile.open(destination, 'w') as bundle:
                member = tarfile.TarInfo('../escape' if failure == 'unsafe' else relative)
                member.size = len(content)
                member.mode = 0o644
                bundle.addfile(member, io.BytesIO(content))
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / 'output'
            arguments = [str(script), str(root), str(output), REVISION] if installer else [
                str(script), 'focused', str(root), REVISION, REVISION, str(root / 'library'), str(output)]
            with patch.object(sys, 'argv', arguments), \
                    patch.object(subprocess, 'check_output', side_effect=git_output), \
                    patch.object(subprocess, 'run', side_effect=archive):
                with self.assertRaises((RuntimeError, subprocess.CalledProcessError)):
                    runpy.run_path(str(script), run_name='__main__')
            self.assertTrue(output.is_dir())
            receipt_path = output / ('completed-receipt.json' if installer else 'receipt.json')
            self.assertTrue(receipt_path.is_file(), 'Setup failure left no receipt')
            receipt = json.loads(receipt_path.read_text())
            result = json.loads((output / 'execution-result.json').read_text())
            self.assertEqual(receipt['status'], 'failed')
            self.assertEqual(result['status'], 'failed')
            self.assertFalse(result['input_binding_complete'])
            self.assertIsNotNone(result['error'])
            manifest_path = Path(receipt['manifest']['path'])
            self.assertEqual(hashlib.sha256(manifest_path.read_bytes()).hexdigest(), receipt['manifest']['sha256'])
            manifest = json.loads(manifest_path.read_text())
            products = manifest['products']
            self.assertIn(str(output / 'execution-result.json'), [item['path'] for item in products])
            for item in products:
                path = Path(item['path'])
                self.assertEqual(path.stat().st_size, item['bytes'])
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), item['sha256'])
            self.assertFalse((root / 'escape').exists())
            self.assertTrue(all(Path(command[0]).name == 'git' for command in commands))
            self.assertEqual(result['commands' if installer else 'records'], [])

    def test_install_setup_failures_are_finalized(self):
        for failure in ('archive', 'unsafe', 'export', 'dependency'):
            with self.subTest(failure=failure):
                self.run_failure(True, failure)

    def test_check_setup_failures_are_finalized(self):
        for failure in ('archive', 'unsafe', 'export'):
            with self.subTest(failure=failure):
                self.run_failure(False, failure)


if __name__ == '__main__':
    unittest.main()
