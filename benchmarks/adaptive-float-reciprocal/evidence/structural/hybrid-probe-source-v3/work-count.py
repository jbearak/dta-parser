#!/usr/bin/env python3
"""Private adaptive dense reciprocal work probe against immutable source. No timings."""
import argparse
import csv
import io
import re
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = Path('<private-work>/dta-float-reciprocal-blocks')
DEFAULT_COMMIT = '50e448283231cde1432fa6b30d5d3f6bd0441618'

def function(text, name):
    start = text.index('static ', text.index(name + '(') - 30)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
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
    parser.add_argument('--source-root', type=Path, default=DEFAULT_ROOT)
    parser.add_argument('--source-commit', default=DEFAULT_COMMIT)
    args = parser.parse_args()
    if re.fullmatch(r"[0-9a-f]{40}", args.source_commit) is None:
        raise RuntimeError("Expected a full immutable source commit")
    root = args.source_root.resolve()
    src = root / 'r-package/dtatools/src'
    controller_before = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    probe_before = hashlib.sha256((HERE / 'work-count.c').read_bytes()).hexdigest()
    env = {k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
    def git(*parts):
        return subprocess.check_output(['git', '--no-replace-objects', *parts], cwd=root, env=env)
    if git('rev-parse', 'HEAD').decode().strip() != args.source_commit:
        raise RuntimeError('Source HEAD differs from the requested full commit')
    if args.output.exists():
        raise RuntimeError('Refuse to replace an existing evidence directory')
    args.output.mkdir(parents=True)
    sources = {}
    for path in src.glob('numeric-arithmetic*.h'):
        data = path.read_bytes()
        if data != git('show', args.source_commit + ':r-package/dtatools/src/' + path.name):
            raise RuntimeError('Source header differs from its committed blob: ' + path.name)
        sources[path.name] = hashlib.sha256(data).hexdigest()
        (args.output / path.name).write_bytes(data)
    payload = (src / 'numeric-payload.c').read_text()
    if payload.encode() != git('show', args.source_commit + ':r-package/dtatools/src/numeric-payload.c'):
        raise RuntimeError('Payload source differs from its committed blob')
    sources['numeric-payload.c'] = hashlib.sha256(payload.encode()).hexdigest()
    arithmetic = (src / 'numeric-arithmetic.h').read_text()
    policy_start = arithmetic.index('typedef struct {\n    double minimum;')
    policy_end = arithmetic.index('/* Missing-bearing same-width', policy_start)
    common = arithmetic[policy_start:policy_end]
    common += '\n' + function(payload, 'numeric_float_observed_limit')
    common += '\n' + function(payload, 'scalar_arithmetic_result_valid').replace(
        'scalar_arithmetic_result_valid', 'uncounted_result_valid')
    common += '\nstatic int scalar_arithmetic_result_valid(double value) {\n'
    common += '  result_checks[phase]++; return uncounted_result_valid(value);\n}\n'
    common += '\n' + function((src / 'numeric-arithmetic-integer.h').read_text(), 'arithmetic_integer_missing')
    for name in ('arithmetic_scale_float_invalid_modern', 'arithmetic_scale_float_invalid_legacy'):
        common += '\n' + function((src / 'numeric-arithmetic-scale.h').read_text(), name)
    (args.output / 'production-common.h').write_text(common)
    general_path = args.output / 'numeric-arithmetic-general.h'
    general = general_path.read_text()
    continuation = chr(92) + '\n'
    general = replace_once(general, '            double xv = arithmetic_general_load_##X',
        '            general_rows[phase]++; ' + continuation + '            double xv = arithmetic_general_load_##X')
    general = replace_once(general, '        return (double) value >= source->policy.minimum',
        '        integer_loads[phase]++; ' + continuation + '        return (double) value >= source->policy.minimum')
    general = replace_once(general, '                if ((MODE) == NUMERIC_FLOAT) {',
        '                if ((MODE) == NUMERIC_FLOAT) { ' + continuation + '                    fit_rows++;')
    load_site = '    float value;\n    memcpy(&value, raw + index * sizeof(value), sizeof(value));'
    if general.count(load_site) != 2:
        raise RuntimeError('Float loader instrumentation sites changed')
    general = general.replace(load_site, '    float_loads++;\n' + load_site)
    general_path.write_text(general)
    reciprocal_path = args.output / 'numeric-arithmetic-float-reciprocal.h'
    if reciprocal_path.exists():
        reciprocal = reciprocal_path.read_text()
        reciprocal = replace_once(reciprocal, '    float source;\n    memcpy(&source, &magnitude, sizeof(source));',
            '    reciprocal_threshold_calls++;\n    float source;\n    memcpy(&source, &magnitude, sizeof(source));')
        reciprocal = replace_once(reciprocal, '    uint32_t minimum = UINT32_MAX, maximum = 0;',
            '    reciprocal_proof_rows += count;\n    uint32_t minimum = UINT32_MAX, maximum = 0;')
        if 'arithmetic_float_reciprocal_prepare_block(' in reciprocal:
            reciprocal = replace_once(reciprocal, '    uint32_t minimum = UINT32_MAX;\n',
                '    reciprocal_prepare_rows += count;\n    reciprocal_scratch_bytes += count * (sizeof(float) + sizeof(unsigned char));\n    uint32_t minimum = UINT32_MAX;\n')
            reciprocal = replace_once(reciprocal, '                            target[i] = (TYPE) (MISSING);',
                '                            reciprocal_fill_rows++, target[i] = (TYPE) (MISSING);')
            if 'int prepared_block = PREPARED && !ordinary;' in reciprocal:
                reciprocal = replace_once(reciprocal, '                            target[i] = (TYPE) (scalar / (double) source);',
                    '                            reciprocal_fast_rows++; ' + continuation +
                    '                            target[i] = (TYPE) (scalar / (double) source);')
                reciprocal = replace_once(reciprocal, '                            double quotient = scalar / (double) prepared[i - block];',
                    '                            reciprocal_prepared_rows++; reciprocal_prepared_divisions++; ' + continuation +
                    '                            double quotient = scalar / (double) prepared[i - block];')
            else:
                reciprocal = replace_once(reciprocal, '                            double quotient = scalar / (double) source;',
                    '                            if (PREPARED) { reciprocal_prepared_rows++; reciprocal_prepared_divisions++; } else reciprocal_fast_rows++; ' + continuation +
                    '                            double quotient = scalar / (double) source;')
            if 'arithmetic_float_reciprocal_fill_missing(' in reciprocal:
                for value in ('0x1p127f', 'NA_REAL'):
                    old='for (size_t i = 0; i < count; i++) target[i] = '+value+';'
                    reciprocal=replace_once(reciprocal,old,
                        'for (size_t i = 0; i < count; i++) reciprocal_all_missing_rows++, target[i] = '+value+';')

        else:
            reciprocal = replace_once(reciprocal, '                        target[i] = (TYPE) (scalar / (double) source);',
                '                        reciprocal_fast_rows++; ' + continuation +
                '                        target[i] = (TYPE) (scalar / (double) source);')
        reciprocal = replace_once(reciprocal, '                    double source = LOAD(raw, i, column);',
            '                    reciprocal_exact_rows++; ' + continuation +
            '                    double source = LOAD(raw, i, column);')
        reciprocal = replace_once(reciprocal, '                    if (NARROW) {',
            '                    if (NARROW) { ' + continuation +
            '                        reciprocal_fit_rows++;')
        reciprocal_path.write_text(reciprocal)
    executable = args.output / 'work-count'
    compiler = Path(shutil.which('cc')).resolve()
    compiler_before = hashlib.sha256(compiler.read_bytes()).hexdigest()
    command = [str(compiler), '-std=gnu23', '-O2', '-g', '-fPIC', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
        '-I', str(args.output), str(HERE / 'work-count.c'), '-lm', '-o', str(executable)]
    with (args.output / 'compile.log').open('w') as log:
        compiled = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if compiled.returncode:
        raise RuntimeError('Private probe compilation failed; see compile.log')
    run = subprocess.run([str(executable)] + (['require-proved'] if args.require_proved else []),
        text=True, capture_output=True)
    (args.output / 'work-count.csv').write_text(run.stdout)
    (args.output / 'work-count.log').write_text(run.stderr)
    rows = list(csv.DictReader(io.StringIO(run.stdout)))
    witnesses = re.findall(r'^ROUNDING,([0-3]),([0-9]+),PASS$', run.stderr, re.M)
    if len(witnesses) != 4 or [int(x[0]) for x in witnesses] != list(range(4)):
        raise RuntimeError('Incomplete directed-rounding witnesses')
    zero_witnesses = re.findall(r'^ZERO_OVERFLOW,([0-3]),([0-9]+),PASS$', run.stderr, re.M)
    if zero_witnesses != witnesses:
        raise RuntimeError('Incomplete signed-zero/finite-overflow release witnesses')
    modes = [int(x[1]) for x in witnesses]
    if len(set(modes)) != 4:
        raise RuntimeError('Rounding modes are not distinct')
    scalars = [0.0, -0.0, 1.01, -1.01, float.fromhex('0x1.0000000000001p0'),
        float.fromhex('0x1p-1074'), -float.fromhex('0x1p-1074'),
        float.fromhex('0x1.fffffep126'), -float.fromhex('0x1.fffffep126'),
        float.fromhex('0x1p127'), -float.fromhex('0x1p127'),
        float.fromhex('0x1.fffffffffffffp1022'), -float.fromhex('0x1.fffffffffffffp1022'),
        float.fromhex('0x1.fffffffffffffp1023'), -float.fromhex('0x1.fffffffffffffp1023')]
    expected = set()
    def key(n, pattern, scalar, legacy, chunk, minimum, mode):
        return (n, pattern, scalar.hex(), legacy, chunk, minimum, mode)
    for mode in modes:
        for legacy in (0, 1):
            for minimum in (3, 4):
                for pattern in (8, 9): expected.add(key(1000000, pattern, 1.01, legacy, 0, minimum, mode))
                for pattern in (11, 12): expected.add(key(1000000, pattern, 1.01, legacy, 0, minimum, mode))
                for scalar in scalars: expected.add(key(128, 9, scalar, legacy, 0, minimum, mode))
                for n in (63, 64, 65, 16383, 16384, 16385):
                    for chunk in (0, 7): expected.add(key(n, 10, 1.01, legacy, chunk, minimum, mode))
        for pattern in (0, 1): expected.add(key(1000000, pattern, 1.01, 0, 0, 3, mode))
        expected.add(key(16385, 7, 1.01, 0, 0, 3, mode))
        for legacy in (0, 1):
            for chunk in (0, 7):
                for scalar in scalars:
                    for minimum in (3, 4):
                        for n, pattern in ((128, 2), (72, 6), (16, 5)):
                            expected.add(key(n, pattern, scalar, legacy, chunk, minimum, mode))
                expected.add(key(16385, 3, 1.01, legacy, chunk, 3, mode))
                expected.add(key(128, 4, scalars[-2], legacy, chunk, 3, mode))
    observed = []
    for row in rows:
        for name, value in row.items():
            if name != 'scalar' and re.fullmatch(r'[0-9]+', value or '') is None:
                raise RuntimeError('Malformed count or status: ' + name)
        observed.append(key(int(row['length']), int(row['pattern']), float.fromhex(row['scalar']),
            int(row['legacy']), int(row['chunk']), int(row['minimum']), int(row['rounding'])))
        n, pattern = int(row['length']), int(row['pattern'])
        get=lambda name:int(row[name])
        red = args.require_proved and (
            (pattern == 8 and (get('generic_output_rows')+get('reciprocal_exact_rows') >= n//10 or
                get('output_result_checks') >= n//10 or get('float_fit_rows')+get('reciprocal_fit_rows') >= n//10)) or
            (pattern == 9 and (get('reciprocal_all_missing_rows') != n or get('output_span_rows') != 0 or
                get('reciprocal_threshold_calls') != 0 or get('reciprocal_prepare_rows') != 0)) or
            (pattern == 0 and get('reciprocal_prepare_rows') != 0) or
            (pattern == 1 and get('reciprocal_prepare_rows') >= n//10) or
            (pattern == 11 and (get('reciprocal_prepare_rows') > 16384 or get('reciprocal_fast_rows') < n-16384)) or
            (pattern == 12 and (get('reciprocal_prepare_rows') > n//2+16384 or get('reciprocal_fast_rows') < n//2-16384)))
        if int(row['generic_output_rows'])+int(row['reciprocal_exact_rows'])+int(row['reciprocal_fast_rows'])+int(row['reciprocal_prepared_rows'])+int(row['reciprocal_fill_rows']) != int(row['output_span_rows']):
            raise RuntimeError('Producer row ledger differs from consumed spans')
        if int(row['reciprocal_proof_rows']) > int(row['output_span_rows']):
            raise RuntimeError('Proof row ledger exceeds visited producer rows')
        if int(row['reciprocal_scratch_bytes']) != 5*int(row['reciprocal_prepare_rows']):
            raise RuntimeError('Preparation scratch ledger is incomplete')
        if int(row['reciprocal_prepare_rows']) > int(row['output_span_rows']):
            raise RuntimeError('Speculative preparation exceeds consumed rows')
        if int(row['reciprocal_prepared_rows']) != int(row['reciprocal_prepared_divisions']):
            raise RuntimeError('Prepared source-quotient rows differ from writer rows')
        if int(row['reciprocal_prepared_rows'])+int(row['reciprocal_fill_rows']) > int(row['reciprocal_prepare_rows']):
            raise RuntimeError('Prepared output has no classified source')
        if get('reciprocal_all_missing_rows'):
            if get('reciprocal_all_missing_rows') != n or get('result_missing') != n or any(get(k) for k in (
                'preflight_span_rows','preflight_rows','preflight_result_checks','float_loads',
                'float_fit_rows','reciprocal_fit_rows','output_result_checks',
                'output_span_rows','generic_output_rows','reciprocal_exact_rows','reciprocal_fast_rows',
                'reciprocal_prepared_rows','reciprocal_fill_rows','reciprocal_proof_rows',
                'reciprocal_prepare_rows','reciprocal_threshold_calls')):
                raise RuntimeError('Whole-result fill has unaccounted work or count')
        if int(row['work_failure']) != int(red):
            raise RuntimeError('Work failure disagrees with recorded counts')
    if len(rows) != 1980 or len(set(observed)) != len(rows) or set(observed) != expected:
        raise RuntimeError('Incomplete or duplicate semantic matrix')
    semantic_failures = sum(int(row['semantic_failure']) != 0 for row in rows)
    work_failures = sum(int(row['work_failure']) for row in rows)
    summary = re.findall(r'^(PASS|FAIL): ([0-9]+) semantic failures, ([0-9]+) work failures across ([0-9]+) cases$', run.stderr, re.M)
    if len(summary) != 1 or tuple(map(int, summary[0][1:])) != (semantic_failures, work_failures, 1980):
        raise RuntimeError('Probe summary does not match complete observations')
    expected_exit = 2 if semantic_failures else 1 if work_failures else 0
    if run.returncode != expected_exit or summary[0][0] != ('PASS' if expected_exit == 0 else 'FAIL'):
        raise RuntimeError('Probe exit does not match semantic/work status')
    status = 'SEMANTIC_FAILURE' if semantic_failures else 'EXPECTED_RED' if work_failures else 'PASS'
    patch = git('diff', 'HEAD', '--binary', '--', 'r-package/dtatools/src')
    if patch:
        raise RuntimeError('Runtime source changed during the structural run')
    if git('rev-parse', 'HEAD').decode().strip() != args.source_commit:
        raise RuntimeError('Source HEAD changed during the structural run')
    for name, digest in sources.items():
        if hashlib.sha256((src / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError('Consumed source changed during the structural run: ' + name)
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_before or \
            hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != controller_before or \
            hashlib.sha256((HERE / 'work-count.c').read_bytes()).hexdigest() != probe_before:
        raise RuntimeError('Compiler/controller/probe changed during the run')
    (args.output / 'source.patch').write_bytes(patch)
    record = {'status': status, 'matrix_cases': len(rows), 'semantic_failures': semantic_failures,
        'work_failures': work_failures, 'rounding_witnesses': witnesses, 'zero_overflow_witnesses': zero_witnesses, 'commit': git('rev-parse', 'HEAD').decode().strip(),
        'requested_commit': args.source_commit,
        'working_tree_status': git('status', '--porcelain').decode(),
        'source_patch_sha256': hashlib.sha256(patch).hexdigest(),
        'source_before_after_equal': True,
        'compiler_sha256': compiler_before,
        'compiler_version': subprocess.check_output([str(compiler), '--version'], text=True),
        'source_sha256': sources, 'controller_sha256': controller_before,
        'probe_sha256': probe_before,
        'command': command, 'require_proved': args.require_proved, 'exit_code': run.returncode,
        'artifact_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in args.output.iterdir() if p.is_file() and p.name != 'receipt.json'},
        'scope': 'Release-flag actual float reciprocal result/preflight/producer headers, no FENV_ACCESS pragma and no strict-rounding compiler override. Allocation, scalar R reader and retained-span boundaries mocked. Independent raw encoding/result oracle and all four rounding modes. No timing, R dispatch, floating exception-state, or ownership proof. All ordinary proof, exact input preparation, five scratch bytes per prepared row, prepared source-quotient rows, local missing fills, whole-result missing fills and exact fallback rows are counted explicitly. Counts describe source work, not emitted instruction counts.'}
    (args.output / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(run.stderr, end='')
    raise SystemExit(run.returncode)

if __name__ == '__main__':
    main()
