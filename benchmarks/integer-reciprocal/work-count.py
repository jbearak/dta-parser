#!/usr/bin/env python3
"""Exercise actual arithmetic headers with mocked allocation and span boundaries.

This records structural work, not performance. Production text is copied only
to a private temporary header and receives explicit counters at existing work
sites; the source hashes and modified temporary text are retained in evidence.
"""
import argparse
from collections import Counter
import csv
import hashlib
import io
import json
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = ROOT / 'r-package/dtatools/src'

def expected_cases(modes=(0, 1, 2, 3)):
    cases = [(1000000, kind, pattern, (1.01).hex(), 0, 0)
             for kind in range(3) for pattern in range(2)]
    cases += [(length, 1, 2, (1.0).hex(), 0, 0)
              for length in (16383, 16384, 16385, 1000000)]
    scalars = [0.0, -0.0, 1.01, -1.01, float.fromhex('0x1.fffffep126'),
               -float.fromhex('0x1.fffffep126'), float.fromhex('0x1p127'),
               float.fromhex('0x1.fffffffffffffp1022'), float.fromhex('0x1.fffffffffffffp1023')]
    cases += [(128, kind, 3, scalar.hex(), legacy, 7)
              for kind in range(3) for legacy in range(2) for scalar in scalars]
    cases = [(0, *case, modes[0]) for case in cases]
    cases += [(facts, 129, kind, pattern, scalar.hex(), legacy, 7, mode)
              for mode in modes for facts in (0, 4) for kind in range(3)
              for legacy in range(2) for pattern in (0, 3, 4, 5)
              for scalar in (1.01, -1.01, -0.0)]
    return Counter(cases)

def validate_case_matrix(text, modes=(0, 1, 2, 3)):
    rows = list(csv.DictReader(io.StringIO(text)))
    actual = Counter((int(row['facts']), int(row['length']), int(row['kind']), int(row['pattern']),
                      float.fromhex(row['scalar']).hex(), int(row['legacy']), int(row['chunk']))
                     + (int(row['rounding']),)
                     for row in rows)
    if len(modes) != 4 or len(set(modes)) != 4 or len(rows) != 640 or actual != expected_cases(modes):
        raise RuntimeError('Incomplete, duplicated or changed 640-case reciprocal matrix')

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
    internal = (SRC / 'dtatools-internal.h').read_text()
    sources['dtatools-internal.h'] = hashlib.sha256(internal.encode()).hexdigest()
    payload = (SRC / 'numeric-payload.c').read_text()
    sources['numeric-payload.c'] = hashlib.sha256(payload.encode()).hexdigest()
    arithmetic = (SRC / 'numeric-arithmetic.h').read_text()
    policy_start = arithmetic.index('typedef struct {\n    double minimum;')
    policy_end = arithmetic.index('/* Missing-bearing same-width', policy_start)
    common = arithmetic[policy_start:policy_end]
    common += '\n' + function(internal, 'numeric_strict_modern_float')
    common += '\n' + function(internal, 'numeric_float_bounds_known')
    common += '\n' + function(internal, 'numeric_zero_count_known')
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
    general = replace_once(general, '                if ((int) (MODE) == NUMERIC_FLOAT) {',
        '                if ((int) (MODE) == NUMERIC_FLOAT) {                   \\\n                    fit_rows++;')
    general_path.write_text(general)
    reciprocal_path = args.output / 'numeric-arithmetic-integer-reciprocal.h'
    reciprocal = reciprocal_path.read_text()
    continuation = chr(92) + '\n'
    if 'const int known_zeros' in reciprocal:
        reciprocal = replace_once(reciprocal, '    for (size_t start = 0;',
            '    integer_cached_rows += known_zeros ? (size_t) length : 0;\n    for (size_t start = 0;')
        reciprocal = replace_once(reciprocal, '                unsigned zero = !(ZERO_FREE) && source == 0;',
            '                if (!(ZERO_FREE)) integer_zero_test_rows++; ' + continuation +
            '                unsigned zero = !(ZERO_FREE) && source == 0;')
        reciprocal = replace_once(reciprocal, '                if (!(KNOWN)) zero_count += zero;',
            '                if (!(KNOWN)) { integer_zero_reduction_rows++; zero_count += zero; }')
    else:
        reciprocal = replace_once(reciprocal, '                unsigned zero = source == 0;',
            '                integer_zero_test_rows++; ' + continuation +
            '                unsigned zero = source == 0;')
        reciprocal = replace_once(reciprocal, '                zero_count += zero;',
            '                integer_zero_reduction_rows++; ' + continuation +
            '                zero_count += zero;')
    reciprocal_path.write_text(reciprocal)
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
    print(run.stderr, end='')
    witnesses = re.findall(r'^ROUNDING,([0-3]),([0-9]+),PASS$', run.stderr, re.M)
    if len(witnesses) != 4 or [int(item[0]) for item in witnesses] != list(range(4)):
        raise RuntimeError('Incomplete verified rounding witnesses')
    validate_case_matrix(run.stdout, [int(item[1]) for item in witnesses])
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
        'rounding_witnesses': witnesses, 'cases': 640,
        'scope': 'Actual general result/preflight/producer headers under four verified rounding modes. Exact zero facts and unknown controls cover zero-free, zero-only, tag-only and mixed integer lanes, modern/legacy bytes and seven-row spans. Allocation and R reader boundaries mocked. No timing or ownership proof.'}
    (args.output / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    raise SystemExit(run.returncode)

if __name__ == '__main__':
    main()
