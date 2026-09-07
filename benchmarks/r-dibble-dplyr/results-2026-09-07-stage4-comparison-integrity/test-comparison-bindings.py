"""Exercise the additive identity auditor with tiny, explicitly synthetic inputs."""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def require(condition, message):
    """Reject failed guard expectations even when Python optimization is enabled."""
    if not condition:
        raise RuntimeError(message)


def sha(data):
    """Return the digest for synthetic bytes or a retained source identity."""
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    """Create or deliberately replace only a newly generated fixture record."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def fixtures(module, root):
    """Create a complete tiny protocol whose outputs are unrelated to real timings."""
    q = {'baseline_source': 'synthetic-baseline', 'candidate_source': 'synthetic-candidate',
         'runner_source': 'synthetic-runner', 'commands': [], 'executed_source_sha256': {}}
    metric = sha(b'synthetic metric verifier')
    q['executed_source_sha256'][module.METRIC_SOURCE] = metric
    for family, comparator in module.COMPARATORS.items():
        source = ('# synthetic comparator ' + family + '\n').encode()
        path = root / 'benchmark/source' / comparator
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source)
        key = module.ORIGINAL_ROOT + '/' + comparator
        q['executed_source_sha256'][key] = sha(source)
        q['commands'].append({'name': 'compare-' + family, 'exit_code': 0, 'command': ['synthetic-python', key]})
        derivation = {'deriver_sha256': sha(source), 'files': {}}
        for mode in ['baseline', 'candidate']:
            path = root / ('benchmark/' + family + '-' + mode + '/root-manifest.json')
            write_json(path, {'source_sha': q[mode + '_source'], 'runner_source_sha': q['runner_source'],
                             'mode': mode, 'runner_sha256': {'benchmarks/r-dibble-dplyr/run-heap-qualification.py': metric}})
            derivation[mode + '_manifest'] = module.ORIGINAL_DATA + '/' + family + '-' + mode + '/root-manifest.json'
            derivation[mode + '_manifest_sha256'] = sha(path.read_bytes())
        if family == 'heap':
            derivation['metric_verifier_sha256'] = metric
        directory = root / ('benchmark/' + family + '-comparison')
        directory.mkdir()
        for name in sorted(module.RESULTS[family]):
            raw = b'[]\n' if name.endswith('.json') else b'synthetic_value\n1\n'
            (directory / name).write_bytes(raw)
            derivation['files'][name] = sha(raw)
        write_json(directory / 'derivation.json', derivation)
    q['commands'] += [{'name': 'synthetic-phase-' + str(i), 'exit_code': 0} for i in range(10)]
    write_json(root / 'benchmark/qualification.json', q)


def child(auditor, historical, output, mode):
    """Check exact historical result-only loop and revised CLI on isolated fixtures."""
    spec = importlib.util.spec_from_file_location('binding_auditor', auditor)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tree = ast.parse(historical.read_text())
    candidates = [node for node in tree.body if isinstance(node, ast.For) and
                  any(isinstance(n, ast.Constant) and n.value == 'Changed derived result' for n in ast.walk(node))]
    require(len(candidates) == 1, 'Historical comparison loop was not uniquely identified')
    old_loop = compile(ast.Module(body=candidates, type_ignores=[]), str(historical), 'exec')
    cases = [('valid', None, None)]
    for family in module.COMPARATORS:
        for field in ['baseline_manifest_sha256', 'candidate_manifest_sha256', 'deriver_sha256']:
            cases.append((family + '-' + field, family, field))
        for field in ['baseline_manifest', 'candidate_manifest']:
            cases.append((family + '-' + field, family, field))
        cases.append((family + '-source-bytes', family, 'source-bytes'))
        cases.append((family + '-result-bytes', family, 'result-bytes'))
    cases += [('heap-metric', 'heap', 'metric_verifier_sha256'),
              ('heap-baseline-runner', 'heap', 'runner-baseline'),
              ('heap-candidate-runner', 'heap', 'runner-candidate'),
              ('missing-qualified-deriver', 'atomic', 'missing-qualified'),
              ('wrong-qualified-command', 'atomic', 'wrong-command'),
              ('inside-output', None, 'inside-output'), ('existing-output', None, 'existing-output')]
    results = []
    with tempfile.TemporaryDirectory(prefix='synthetic-comparison-bindings-') as tmp:
        tmp = Path(tmp)
        for name, family, field in cases:
            root = tmp / name
            root.mkdir()
            fixtures(module, root)
            receipt = tmp / (name + '.json')
            derivation_path = root / ('benchmark/' + str(family) + '-comparison/derivation.json')
            if family:
                d = json.loads(derivation_path.read_text())
                if field in d:
                    d[field] = '0' * 64 if field.endswith('sha256') else 'wrong-recorded-path'
                    write_json(derivation_path, d)
                elif field == 'source-bytes':
                    (root / 'benchmark/source' / module.COMPARATORS[family]).write_bytes(b'changed synthetic source\n')
                elif field == 'result-bytes':
                    result = sorted(d['files'])[0]
                    (derivation_path.parent / result).write_bytes(b'changed synthetic result\n')
                elif field.startswith('runner-'):
                    p = root / ('benchmark/heap-' + field.removeprefix('runner-') + '/root-manifest.json')
                    m = json.loads(p.read_text())
                    m['runner_sha256']['benchmarks/r-dibble-dplyr/run-heap-qualification.py'] = '0' * 64
                    write_json(p, m)
                    d[field.removeprefix('runner-') + '_manifest_sha256'] = sha(p.read_bytes())
                    write_json(derivation_path, d)
                else:
                    p = root / 'benchmark/qualification.json'
                    q = json.loads(p.read_text())
                    if field == 'missing-qualified':
                        del q['executed_source_sha256'][module.ORIGINAL_ROOT + '/' + module.COMPARATORS[family]]
                    elif field == 'wrong-command':
                        q['commands'][0]['command'][1] = 'different comparator'
                    write_json(p, q)
            if field == 'inside-output':
                receipt = root / 'forbidden.json'
            if field == 'existing-output':
                receipt.write_bytes(b'preserve existing output\n')
            old_accepts = None
            if field in ['baseline_manifest_sha256', 'candidate_manifest_sha256', 'deriver_sha256']:
                exec(old_loop, {'DATA': root / 'benchmark', 'json': json,
                                'digest': lambda p: sha(p.read_bytes()), 'require': require})
                old_accepts = True
            before = {str(p.relative_to(root)): sha(p.read_bytes()) for p in root.rglob('*') if p.is_file()}
            existing = receipt.read_bytes() if receipt.exists() else None
            command = [sys.executable] + (['-O'] if mode == 'dash-O' else []) + [str(auditor), str(root), str(receipt)]
            run = subprocess.run(command, capture_output=True, text=True)
            require((run.returncode == 0) == (name == 'valid'), 'Wrong result: ' + name + run.stderr)
            expected_errors = {
                'baseline_manifest_sha256': str(family) + ': baseline manifest hash mismatch',
                'candidate_manifest_sha256': str(family) + ': candidate manifest hash mismatch',
                'deriver_sha256': str(family) + ': deriver hash mismatch',
                'baseline_manifest': str(family) + ': baseline manifest path mismatch',
                'candidate_manifest': str(family) + ': candidate manifest path mismatch',
                'source-bytes': str(family) + ': comparator source hash mismatch',
                'result-bytes': str(family) + ': derived result hash mismatch:',
                'metric_verifier_sha256': 'heap: metric verifier hash mismatch',
                'runner-baseline': 'heap: baseline metric runner hash mismatch',
                'runner-candidate': 'heap: candidate metric runner hash mismatch',
                'missing-qualified': 'KeyError:',
                'wrong-command': 'atomic: qualified comparator command mismatch',
                'inside-output': 'Output must be outside the immutable archive',
                'existing-output': 'Output already exists',
            }
            if name != 'valid':
                require(expected_errors[field] in run.stderr, 'Wrong rejection diagnostic: ' + name + run.stderr)
            require(name == 'valid' or (receipt.read_bytes() == existing if existing is not None else not receipt.exists()),
                    'Rejected case created or changed output: ' + name)
            after = {str(p.relative_to(root)): sha(p.read_bytes()) for p in root.rglob('*') if p.is_file()}
            require(before == after, 'Auditor changed synthetic inputs: ' + name)
            results.append({'case': name, 'exit_code': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr,
                            'historical_exact_loop_admits_stale_identity': old_accepts,
                            'inputs_unchanged': True, 'rejected_output_preserved': name != 'valid'})
    write_json(output, {'scope': 'Synthetic guard tests only; no R, benchmarks, actual comparison edits, or report regeneration.',
                        'auditor_sha256': sha(auditor.read_bytes()), 'historical_source_sha256': sha(historical.read_bytes()),
                        'historical_loop_ast_sha256': sha(ast.dump(candidates[0], include_attributes=False).encode()),
                        'optimization': sys.flags.optimize, 'auditor_mode': mode,
                        'auditor_dash_O': mode == 'dash-O', 'auditor_PYTHONOPTIMIZE': os.environ.get('PYTHONOPTIMIZE'), 'cases': results})


def main():
    """Retain each Python-mode result and bind the executed test and auditor bytes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('auditor', type=Path)
    parser.add_argument('historical', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--child', action='store_true')
    parser.add_argument('--mode', choices=['default', 'dash-O', 'env-optimize'])
    args = parser.parse_args()
    if args.child:
        child(args.auditor, args.historical, args.output, args.mode)
        return
    args.output.mkdir()
    runs = []
    for mode in ['default', 'dash-O', 'env-optimize']:
        env = dict(os.environ)
        env.pop('PYTHONOPTIMIZE', None)
        if mode == 'env-optimize':
            env['PYTHONOPTIMIZE'] = '1'
        command = [sys.executable] + (['-O'] if mode == 'dash-O' else []) + [str(Path(__file__).resolve()),
                   str(args.auditor.resolve()), str(args.historical.resolve()), str(args.output / (mode + '.json')), '--child', '--mode', mode]
        run = subprocess.run(command, env=env, capture_output=True, text=True)
        require(run.returncode == 0, run.stderr)
        result = json.loads((args.output / (mode + '.json')).read_text())
        runs.append({'mode': mode, 'cases': len(result['cases']), 'sha256': sha((args.output / (mode + '.json')).read_bytes())})
    write_json(args.output / 'summary.json', {'test_sha256': sha(Path(__file__).read_bytes()),
                                            'auditor_sha256': sha(args.auditor.read_bytes()), 'runs': runs})
    print(json.dumps(runs))


if __name__ == '__main__':
    main()
