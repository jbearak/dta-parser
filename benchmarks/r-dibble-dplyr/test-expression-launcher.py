"""Synthetic subprocess checks of the driver's actual gate and finalizer functions."""
import ast
import json
import os
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
TREE = ast.parse((HERE / 'run-expression-checks.py').read_text())
MAIN = next(node for node in TREE.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
PROTECTED = next(node for node in MAIN.body if isinstance(node, ast.Try) and node.finalbody)
BODY = PROTECTED.body
FUNCTIONS = [node for node in TREE.body if isinstance(node, (ast.Import, ast.ImportFrom)) or
             isinstance(node, ast.FunctionDef) and node.name != 'main']


def execute_nodes(nodes, namespace):
    module = ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[]))
    exec(compile(module, str(HERE / 'run-expression-checks.py'), 'exec'), namespace)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(os.environ['LAUNCHER_TEST_OUTPUT']) / self._testMethodName
        self.root.mkdir(parents=True, exist_ok=False)
        self.first = self.root / 'first'
        self.second = self.root / 'second'
        self.first.mkdir()
        self.second.mkdir()
        self.output = self.root / 'output'
        self.output.mkdir()
        self.package = self.root / 'package'
        self.package.mkdir()
        self.package_file = self.package / 'DESCRIPTION'
        self.package_file.write_text('Synthetic package fixture only\n')
        self.a = self.make_tool(self.first / 'gate', "printf 'selected-a:%s\\n' \"$1\"\n")
        self.b = self.make_tool(self.second / 'gate', "printf 'selected-b:%s\\n' \"$1\"\n")
        self.ns = {'__file__': str(HERE / 'run-expression-checks.py')}
        execute_nodes(FUNCTIONS, self.ns)
        self.discovery_path = str(self.first) + os.pathsep + str(self.second)
        self.tools = self.ns['resolve_tool_paths'](['gate'], self.discovery_path)

    def make_tool(self, path, body):
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)
        return path

    def prepare_gate(self, additional=()):
        ns = self.ns
        paths = {self.package_file, *self.tools.values(),
                 *(p.resolve(strict=True) for p in self.tools.values()), *additional}
        before = [ns['identity'](p) for p in sorted(paths)]
        ns.update(before=before, consumed=[], tool_invocations=self.tools,
                  discovery_path=self.discovery_path,
                  source=self.root, output=self.output, package_root=self.package,
                  package_inventory={self.package_file}, records=[], source_records=[],
                  environment={'PATH': str(self.second)},
                  args=type('Args', (), {'source_sha': 'synthetic-source', 'runner_sha': 'synthetic-runner'})())
        # Use the actual binding serialization and nested gate functions, without
        # invoking the production main, Git export, R or package qualification.
        start = next(i for i, n in enumerate(BODY) if isinstance(n, ast.Assign) and
                     any(isinstance(t, ast.Name) and t.id == 'bound_paths' for t in n.targets))
        execute_nodes([BODY[start], *BODY[start + 2:start + 4]], ns)
        execute_nodes([n for n in BODY if isinstance(n, ast.FunctionDef) and n.name in ('guard', 'run')], ns)
        wrapper = ast.parse("def finish(action):\n    status = 'failed'\n    changed = []\n    failure = None\n    input_binding_complete = True\n    try:\n        action()\n        status = 'complete'\n    except BaseException:\n        pass\n    finally:\n        pass\n")
        protected = next(n for n in wrapper.body[0].body if isinstance(n, ast.Try))
        protected.handlers = PROTECTED.handlers
        protected.finalbody = PROTECTED.finalbody
        execute_nodes(wrapper.body, ns)

    def finish(self):
        self.ns['finish'](lambda: self.ns['run']('synthetic', ['gate', 'payload']))

    def receipt(self):
        return json.loads((self.output / 'receipt.json').read_text())

    def assert_failed_before_spawn(self):
        with self.assertRaises(RuntimeError):
            self.finish()
        self.assertFalse((self.output / 'synthetic.log').exists())
        self.assertFalse((self.output / 'synthetic-command.json').exists())
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertTrue(self.receipt()['changed_inputs'])
        result = json.loads((self.output / 'execution-result.json').read_text())
        self.assertEqual(result['error']['type'], 'RuntimeError')
        self.assertTrue(result['input_binding_complete'])
        self.assertTrue(result['package_inventory_available'])

    def test_path_ambiguity_and_child_path_change_keep_selected_tool(self):
        self.prepare_gate()
        self.finish()
        record = json.loads((self.output / 'synthetic-command.json').read_text())
        self.assertEqual((self.output / 'synthetic.log').read_text(), 'selected-a:payload\n')
        self.assertEqual(record['command'], [str(self.a.resolve()), 'payload'])
        self.assertEqual(record['requested_command'], ['gate', 'payload'])
        self.assertEqual(record['environment_path'], str(self.second))
        selection = json.loads((self.output / 'tool-selection.json').read_text())
        self.assertEqual(selection['discovery_path'], self.discovery_path)
        self.assertEqual(selection['tools']['gate'], record['selected_tool'])
        self.assertEqual(record['selected_tool']['sha256'], self.ns['digest'](self.a))
        self.assertEqual(self.receipt()['status'], 'complete')

    def test_discovery_symlink_retarget_rejects_before_spawn(self):
        alias_dir = self.root / 'alias'
        alias_dir.mkdir()
        alias = alias_dir / 'gate'
        alias.symlink_to(self.a)
        self.discovery_path = str(alias_dir)
        self.tools = self.ns['resolve_tool_paths'](['gate'], self.discovery_path)
        self.prepare_gate()
        alias.unlink()
        alias.symlink_to(self.b)
        self.assert_failed_before_spawn()

    def test_symlink_invocation_basename_is_preserved(self):
        dispatcher = self.make_tool(self.first / 'multitool',
            'case "${0##*/}" in gate) printf "gate-role\\n";; '
            '*) printf "wrong-role\\n"; exit 64;; esac\n')
        self.a.unlink()
        self.a.symlink_to(dispatcher)
        self.tools = self.ns['resolve_tool_paths'](['gate'], self.discovery_path)
        self.prepare_gate()
        self.finish()
        record = json.loads((self.output / 'synthetic-command.json').read_text())
        self.assertEqual((self.output / 'synthetic.log').read_text(), 'gate-role\n')
        self.assertEqual(record['command'][0], str(self.a.absolute()))
        self.assertEqual(record['selected_tool']['resolved'], str(dispatcher.resolve()))
        self.assertEqual(self.receipt()['status'], 'complete')

    def test_changed_bound_tool_bytes_reject_before_spawn(self):
        self.prepare_gate()
        self.a.write_text('#!/bin/sh\nprintf changed\n')
        self.assert_failed_before_spawn()

    def test_changed_bound_tool_mode_rejects_before_spawn(self):
        self.prepare_gate()
        self.a.chmod(0o700)
        self.assert_failed_before_spawn()

    def test_missing_bound_tool_rejects_before_spawn(self):
        self.prepare_gate()
        self.a.unlink()
        self.assert_failed_before_spawn()

    def test_changed_selected_resolved_path_rejects_before_spawn(self):
        self.prepare_gate()
        self.a.unlink()
        self.a.symlink_to(self.b)
        self.assert_failed_before_spawn()

    def test_tool_changed_during_child_yields_failed_receipt(self):
        other = self.make_tool(self.first / 'other', 'exit 0\n')
        # The controlled path has no shell metacharacters; use the explicit path
        # only inside this retained synthetic fixture.
        self.a.write_text('#!/bin/sh\nprintf changed >> "' + str(other) + '"\nprintf ran\n')
        self.prepare_gate(additional=[other])
        with self.assertRaises(RuntimeError):
            self.finish()
        self.assertEqual((self.output / 'synthetic.log').read_text(), 'ran')
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertTrue(self.receipt()['changed_inputs'])
        self.assertEqual(len(self.ns['records']), 1)

    def test_unknown_top_level_name_is_rejected(self):
        self.prepare_gate()
        with self.assertRaisesRegex(RuntimeError, 'Unbound top-level tool'):
            self.ns['finish'](lambda: self.ns['run']('unknown', ['other']))
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertFalse((self.output / 'unknown.log').exists())

    def test_missing_discovery_tool_is_explicit(self):
        with self.assertRaisesRegex(RuntimeError, 'Required tool not found'):
            self.ns['resolve_tool_paths'](['absent'], self.discovery_path)


if __name__ == '__main__':
    unittest.main(verbosity=2)
