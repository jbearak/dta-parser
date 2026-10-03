#!/usr/bin/env python3
"""Exercise actual arithmetic headers with mocked allocation and span boundaries.

This records structural work, not performance. Production text is copied only
to a private temporary header and receives explicit counters at existing work
sites; the source hashes and modified temporary text are retained in evidence.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = ROOT / 'r-package/dtatools/src'

def function(text, name):
    start = text.index('static ', text.index(name + '(') - 30)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError('Instrumentation site is not unique: ' + old)
    return text.replace(old, new)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--require-proved', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = {}
    for path in SRC.glob('numeric-arithmetic*.h'):
        data = path.read_bytes()
        sources[path.name] = hashlib.sha256(data).hexdigest()
        (args.output / path.name).write_bytes(data)
    payload = (SRC / 'numeric-payload.c').read_text()
    sources['numeric-payload.c'] = hashlib.sha256(payload.encode()).hexdigest()
    arithmetic = (SRC / 'numeric-arithmetic.h').read_text()
    policy_start = arithmetic.index('typedef struct {\n    double minimum;')
    policy_end = arithmetic.index('/* Missing-bearing same-width', policy_start)
    common = arithmetic[policy_start:policy_end]
    common += '\n' + function(payload, 'numeric_float_observed_limit')
    common += '\n' + function(payload, 'scalar_arithmetic_result_valid').replace(
        'scalar_arithmetic_result_valid', 'uncounted_result_valid')
    common += '\nstatic int scalar_arithmetic_result_valid(double value) {\n'
    common += '  result_checks[phase]++; return uncounted_result_valid(value);\n}\n'
    common += '\n' + function((SRC / 'numeric-arithmetic-integer.h').read_text(), 'arithmetic_integer_missing')
    for name in ('arithmetic_scale_float_invalid_modern', 'arithmetic_scale_float_invalid_legacy'):
        common += '\n' + function((SRC / 'numeric-arithmetic-scale.h').read_text(), name)
    (args.output / 'production-common.h').write_text(common)
    general_path = args.output / 'numeric-arithmetic-general.h'
    general = general_path.read_text()
    general = replace_once(general, '            double xv = arithmetic_general_load_##X',
        '            general_rows[phase]++;                              \\\n            double xv = arithmetic_general_load_##X')
    general = replace_once(general, '        return (double) value >= source->policy.minimum',
        '        integer_loads[phase]++;                                    \\\n        return (double) value >= source->policy.minimum')
    general = replace_once(general, '                if ((MODE) == NUMERIC_FLOAT) {',
        '                if ((MODE) == NUMERIC_FLOAT) {                   \\\n                    fit_rows++;')
    general_path.write_text(general)
    executable = args.output / 'work-count'
    compiler = Path(shutil.which('cc')).resolve()
    command = [str(compiler), '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror',
        '-Wno-unused-function', '-I', str(args.output), str(HERE / 'work-count.c'),
        '-lm', '-o', str(executable)]
    subprocess.run(command, check=True)
    run = subprocess.run([str(executable)] + (['require-proved'] if args.require_proved else []),
        text=True, capture_output=True)
    (args.output / 'work-count.csv').write_text(run.stdout)
    (args.output / 'work-count.log').write_text(run.stderr)
    patch = subprocess.check_output(['git', 'diff', 'HEAD', '--binary', '--', 'r-package/dtatools/src'], cwd=ROOT)
    (args.output / 'source.patch').write_bytes(patch)
    record = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'working_tree_status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
        'source_patch_sha256': hashlib.sha256(patch).hexdigest(),
        'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'compiler_version': subprocess.check_output([str(compiler), '--version'], text=True),
        'source_sha256': sources, 'controller_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'probe_sha256': hashlib.sha256((HERE / 'work-count.c').read_bytes()).hexdigest(),
        'command': command, 'require_proved': args.require_proved, 'exit_code': run.returncode,
        'artifact_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in args.output.iterdir() if p.is_file() and p.name != 'receipt.json'},
        'scope': 'Actual general result/preflight/producer headers; allocation, R reader and retained-span boundaries mocked. No timing or ownership proof.'}
    (args.output / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(run.stdout, end='')
    print(run.stderr, end='')
    raise SystemExit(run.returncode)

if __name__ == '__main__':
    main()
