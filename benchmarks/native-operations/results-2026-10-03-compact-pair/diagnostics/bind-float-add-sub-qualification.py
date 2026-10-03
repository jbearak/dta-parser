#!/usr/bin/env python3
"""Bind untimed compact-sum qualification and emitted-loop evidence."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('<repo>')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise RuntimeError(message)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    candidate = HERE / 'float-add-sub-prototype'
    receipt = json.loads((candidate / 'build-receipt.json').read_text())
    differences = [name for name, expected in receipt['source_inventory'].items()
                   if sha(ROOT / 'r-package/dtatools' / name) != expected]
    require(differences == ['tools/native-test-manifest.json'], 'Unexpected package source difference')
    builds = {'baseline': HERE / 'float-product-prototype', 'candidate': candidate}
    controllers = {'original': ROOT / 'benchmarks/native-operations/general-run.py',
                   'screen': HERE / 'float-add-sub-diagnostic/general-run.py'}
    gates = {name: load('qualification_' + name, path) for name, path in controllers.items()}
    evidence = {}
    qualification_rows = {}
    for variant, build in builds.items():
        current_receipt = json.loads((build / 'build-receipt.json').read_text())
        dll = build / 'library/dtatools/libs/dtatools.so'
        require(sha(dll) == current_receipt['installed_inventory']['libs/dtatools.so'], 'DLL changed')
        focused = HERE / ('float-add-sub-' + variant + '-focused.csv')
        rows = list(csv.DictReader(focused.open()))
        total = {key: sum(int(row[key]) if row[key].isdigit() else int(row[key] == 'TRUE') for row in rows)
                 for key in ('passed', 'failed', 'error', 'skipped', 'warning')}
        require(total == dict(passed=53147, failed=0, error=0, skipped=0, warning=0), 'Focused checks failed')
        entry = {'build_commit': current_receipt['base_commit'], 'build_receipt_sha256': sha(build / 'build-receipt.json'),
                 'dll_sha256': sha(dll), 'focused': dict(totals=total, results_sha256=sha(focused)), 'qualification': {}}
        for label, gate in gates.items():
            filename = 'float-add-sub-' + ('diagnostic-' if label == 'screen' else '') + variant + '-qualification.csv'
            path = HERE / filename
            observations = list(csv.DictReader(path.open()))
            keys = [tuple(row[key] for key in gate.FIELDS) for row in observations]
            require(len(set(keys)) == len(keys) and set(keys) == gate.EXPECTED, 'Wrong qualification matrix')
            for row in observations:
                require(row['cpu'] == 'NA' and row['wall'] == 'NA' and row['iterations'] == '1', 'Qualification contains timings')
                require(row['native_calls'] == ('0' if row['representation'] == 'ordinary' else '1'), 'Wrong native route')
                require(int(row['n']) == 1000000, 'Wrong population')
                for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
                    require(row[prefix + '_before'] == row[prefix + '_after'], 'Source state changed')
                for key in ('result_sha256', 'missing_sha256', 'input_sha256', 'y_sha256'):
                    require(re.fullmatch('[0-9a-f]{64}', row[key]), 'Invalid semantic hash')
            qualification_rows[variant, label] = observations
            entry['qualification'][label] = {'rows': len(observations), 'sha256': sha(path)}
        evidence[variant] = entry
    for label in gates:
        require(qualification_rows['baseline', label] == qualification_rows['candidate', label], 'Builds disagree on qualification')
    assembly = HERE / 'float-add-sub-disassembly.txt'
    text = assembly.read_text().split('_arithmetic_general_produce:\n', 1)[1]
    text = re.split(r'^_\w+:', text, flags=re.M)[0]
    rows = []
    for line in text.splitlines():
        match = re.match(r'\s*([0-9a-f]+)\s+(.*)', line)
        if match:
            rows.append((int(match[1], 16), match[2]))
    ranges = {'+': (0x1a8680, 0x1a8838, 'fadd.4s'),
              '-': (0x1a2270, 0x1a242c, 'fsub.4s'),
              '*': (0x1a6f2c, 0x1a70e4, 'fmul.4s')}
    loops = {}
    for operation, (start, end, instruction) in ranges.items():
        selected = [(address, code) for address, code in rows if start <= address <= end]
        body = '\n'.join(code for _, code in selected)
        require(len(selected) == (end - start) // 4 + 1, 'Incomplete vector loop')
        require(body.count(instruction) == 4 and 'scvtf.4s' in body and 'sshll.4s' in body,
                'Expected binary32 arithmetic and exact int16 conversion absent')
        require('usra.4s' in body and 'umax.4s' in body and '#0x10' in selected[-2][1], 'Missing policy/range/vector-width evidence')
        require(not re.search(r'\bfcvt|\.[24]d\b', body), 'Unexpected binary64 lane conversion')
        loops[operation] = {'start': hex(start), 'end': hex(end), 'rows_per_iteration': 16,
                            'instruction_count': len(selected), 'instructions': [code for _, code in selected]}
    paths = [Path(__file__).resolve(), ROOT / 'scripts/refresh-r-native-manifest.py', ROOT / 'scripts/test_native_manifest.py',
             ROOT / 'r-package/dtatools/tools/native-test-manifest.json',
             Path('<prior-arithmetic-work>/float-interval-focused.R')]
    for path in controllers.values():
        paths.extend([path, path.with_name('general-worker.R')])
    paths.extend(HERE / 'float-add-sub-diagnostic' / name for name in ('test-general-run.py',))
    paths.extend(HERE / name for name in ('float-add-sub-manifest.log', 'float-add-sub-manifest-tests.log',
                 'float-add-sub-controller-tests.log', 'float-add-sub-controller-tests-optimized.log'))
    report = {'status': 'PASS', 'scope': 'Untimed qualification only; both focused runs use the same current f689 test sources against separately bound54d/f689 packages.',
              'current_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'current_source_difference_from_build': differences, 'variants': evidence,
              'input_sha256': {str(path): sha(path) for path in paths},
              'compiler': {'function': 'arithmetic_general_produce', 'loop_input': 'signed int16 and missing-capable modern binary32 spans',
                           'disassembly_sha256': sha(assembly), 'disassembler_sha256': sha(Path('/Library/Developer/CommandLineTools/usr/bin/otool')),
                           'loops': loops,
                           'limits': 'Static intended-mechanism evidence, not a speed attribution or complete public-call instruction trace. Floating exception flags are not part of this output contract.'}}
    target = HERE / 'float-add-sub-validation-binding.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'receipt': str(target), 'focused_each': 53147, 'original_cases_each': 102, 'screen_cases_each': 54}))


if __name__ == '__main__':
    main()
