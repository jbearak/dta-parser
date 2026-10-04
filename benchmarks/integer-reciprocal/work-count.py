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
    cases = [(0, *case, modes[0], -1, 0) for case in cases]
    cases += [(facts, 129, kind, pattern, scalar.hex(), legacy, 7, mode, -1, 0)
              for mode in modes for facts in (0, 4) for kind in range(3)
              for legacy in range(2) for pattern in (0, 3, 4, 5)
              for scalar in (1.01, -1.01, -0.0)]
    lookup_scalars = [0.0, -0.0, 1.01, -1.01, float.fromhex('0x1p-1074'),
                      -float.fromhex('0x1p-1074'), float.fromhex('0x1.fffffep126'),
                      -float.fromhex('0x1.fffffep126'), float.fromhex('0x1.fffffffffffffp1022'),
                      -float.fromhex('0x1.fffffffffffffp1022')]
    cases += [(facts, 256 if kind == 0 else 65536, kind, 6, scalar.hex(), legacy, 4093,
               mode, destination, 1)
              for mode in modes for facts in (0, 4) for kind in range(2)
              for legacy in range(2) for destination in (3, 4) for scalar in lookup_scalars]
    cases += [(facts, length, kind, 6, (1.01).hex(), legacy, 4093, mode, destination, 0)
              for mode in modes for facts in (0, 4) for kind in range(2)
              for legacy in range(2) for destination in (3, 4)
              for length in (262143, 262144, 262145)]
    return Counter(cases)

def validate_case_matrix(text, modes=(0, 1, 2, 3)):
    rows = list(csv.DictReader(io.StringIO(text)))
    actual = Counter((int(row['facts']), int(row['length']), int(row['kind']), int(row['pattern']),
                      float.fromhex(row['scalar']).hex(), int(row['legacy']), int(row['chunk']))
                     + (int(row['rounding']), int(row['minimum_kind']), int(row['direct']))
                     for row in rows)
    if len(modes) != 4 or len(set(modes)) != 4 or len(rows) != 1472 or actual != expected_cases(modes):
        raise RuntimeError('Incomplete, duplicated or changed 1472-case reciprocal matrix')

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
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--commit')
    parser.add_argument('--source-commit', help='Read production headers from immutable Git blobs')
    parser.add_argument('--optimization', choices=('O1', 'O3'), default='O1')
    args = parser.parse_args()
    root = args.root.resolve()
    src = root / 'r-package/dtatools/src'
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    if args.commit and subprocess.check_output(['git', 'rev-parse', args.commit], cwd=root, text=True).strip() != commit:
        raise RuntimeError('Requested commit does not match source HEAD')
    source_commit = subprocess.check_output(['git', 'rev-parse', args.source_commit], cwd=root, text=True).strip() if args.source_commit else None
    def source_bytes(name):
        if source_commit:
            return subprocess.check_output(['git', 'show', source_commit + ':r-package/dtatools/src/' + name], cwd=root)
        return (src / name).read_bytes()
    def source_text(name):
        return source_bytes(name).decode()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = {}
    if source_commit:
        paths = subprocess.check_output(['git', 'ls-tree', '--name-only', source_commit, 'r-package/dtatools/src/'], cwd=root, text=True).splitlines()
        names = [Path(path).name for path in paths if Path(path).name.startswith('numeric-arithmetic') and path.endswith('.h')]
    else:
        names = [path.name for path in src.glob('numeric-arithmetic*.h')]
    for name in names:
        data = source_bytes(name)
        sources[name] = hashlib.sha256(data).hexdigest()
        (args.output / name).write_bytes(data)
    internal = source_text('dtatools-internal.h')
    sources['dtatools-internal.h'] = hashlib.sha256(internal.encode()).hexdigest()
    payload = source_text('numeric-payload.c')
    sources['numeric-payload.c'] = hashlib.sha256(payload.encode()).hexdigest()
    arithmetic = source_text('numeric-arithmetic.h')
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
    common += '\n' + function(source_text('numeric-arithmetic-integer.h'), 'arithmetic_integer_missing')
    for name in ('arithmetic_scale_float_invalid_modern', 'arithmetic_scale_float_invalid_legacy'):
        common += '\n' + function(source_text('numeric-arithmetic-scale.h'), name)
    has_lookup = 'INTEGER_RECIPROCAL_LOOKUP_ROW_LOOP' in source_text('numeric-arithmetic-integer-reciprocal.h')
    if has_lookup:
        common += '\n#define HAVE_INTEGER_LOOKUP_KERNEL 1\n'
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
        reciprocal = replace_once(reciprocal, '\n    for (size_t start = 0;',
            '\n    integer_cached_rows += known_zeros ? (size_t) length : 0;\n    for (size_t start = 0;')
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
    reciprocal = replace_once(reciprocal, 'TARGET result = (TARGET) (scalar / (double) denominator);',
        'TARGET result = (TARGET) (integer_row_divisions++, scalar / (double) denominator);')
    if has_lookup:
        reciprocal = replace_once(reciprocal, '                CODE bits = (CODE) i;',
            '                lookup_table_entries++; ' + continuation +
            '                CODE bits = (CODE) i;')
        reciprocal = replace_once(reciprocal, ': (TARGET) (scalar / (double) source);',
            ': (TARGET) (lookup_table_divisions++, scalar / (double) source);')
        reciprocal = replace_once(reciprocal, '                target[i] = table[code];',
            '                lookup_rows++; integer_cached_rows += !!(KNOWN); ' + continuation +
            '                target[i] = table[code];')
        reciprocal = replace_once(reciprocal, 'if (!(KNOWN)) zero_count += code == 0;',
            'if (!(KNOWN)) { integer_zero_test_rows++; integer_zero_reduction_rows++; zero_count += code == 0; }')
    reciprocal_path.write_text(reciprocal)
    executable = args.output / 'work-count'
    compiler = Path(shutil.which('cc')).resolve()
    command = [str(compiler), '-std=c11', '-' + args.optimization, '-Wall', '-Wextra', '-Werror',
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
    patch = b'' if source_commit else subprocess.check_output(['git', 'diff', 'HEAD', '--binary', '--', 'r-package/dtatools/src'], cwd=root)
    (args.output / 'source.patch').write_bytes(patch)
    record = {'commit': commit, 'source_commit': source_commit, 'cwd': str(root),
        'working_tree_status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True),
        'source_patch_sha256': hashlib.sha256(patch).hexdigest(),
        'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'compiler_version': subprocess.check_output([str(compiler), '--version'], text=True),
        'source_sha256': sources, 'controller_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'probe_sha256': hashlib.sha256((HERE / 'work-count.c').read_bytes()).hexdigest(),
        'command': command, 'require_proved': args.require_proved, 'exit_code': run.returncode,
        'artifact_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in args.output.iterdir() if p.is_file() and p.name != 'receipt.json'},
        'rounding_witnesses': witnesses, 'cases': 1472, 'has_lookup': has_lookup,
        'scope': 'Actual general result/preflight/producer headers under four verified rounding modes. 640 retained fallback/domain cases; 640 direct BYTE/INT producer cases cover every physical code, both destinations, modern/legacy policies, signed zeros, subnormals and magnitude endpoints; 192 actual general-result cases exercise both sides of the 262144 admission threshold. Exact-zero and unknown controls and bounded spans included. Allocation and R reader boundaries mocked. No timing or ownership proof.'}
    (args.output / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    raise SystemExit(run.returncode)

if __name__ == '__main__':
    main()
