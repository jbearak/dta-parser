#!/usr/bin/env python3
"""Local actual-header reciprocal work probe; no timing or R ownership claim."""
import argparse
from collections import Counter
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parents[1]
FIELDS = ('domain,length,pattern,scalar,legacy,chunk,minimum,rounding,output,'
          'preflight_rows,generic_output_rows,preflight_result_checks,output_result_checks,'
          'float_fit_rows,float_loads,preflight_span_rows,output_span_rows,result_missing,'
          'semantic_failure,work_failure,reciprocal_proof_rows,reciprocal_fast_rows,'
          'reciprocal_exact_rows,reciprocal_fit_rows,reciprocal_threshold_calls,'
          'reciprocal_prepare_rows,reciprocal_scratch_bytes,reciprocal_prepared_rows,'
          'reciprocal_prepared_divisions,reciprocal_fill_rows,reciprocal_all_missing_rows,'
          'canonical_attempt_rows,canonical_committed_rows').split(',')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def function(text, name):
    declaration = text.index(name + '(')
    start = text.rfind('static ', 0, declaration)
    opening = text.index('{', declaration)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def replace_once(text, old, new):
    require(text.count(old) == 1, 'Instrumentation site is not unique: ' + old)
    return text.replace(old, new)


def inventory(root, commit):
    require(re.fullmatch(r'[0-9a-f]{40}', commit) is not None, 'Expected a full immutable source commit')
    src = root / 'r-package/dtatools/src'
    paths = sorted(src.glob('numeric-arithmetic*.h')) + [src / 'numeric-payload.c', src / 'dtatools-internal.h']
    git_env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    result = {}
    for path in paths:
        blob = subprocess.check_output(['git', '--no-replace-objects', 'show',
            commit + ':r-package/dtatools/src/' + path.name], cwd=root, env=git_env)
        require(hashlib.sha256(blob).hexdigest() == sha(path), 'Source differs from immutable commit: ' + path.name)
        result[path.name] = sha(path)
    return result


def expected_cases(modes):
    scalars = [0.0, -0.0, 1.01, -1.01] + [float.fromhex(value) for value in (
        '0x1.0000000000001p0', '0x1p-1074', '-0x1p-1074', '0x1.fffffep126',
        '-0x1.fffffep126', '0x1p127', '-0x1p127', '0x1.fffffffffffffp1022',
        '-0x1.fffffffffffffp1022', '0x1.fffffffffffffp1023', '-0x1.fffffffffffffp1023')]
    cases = []
    def add(domain, n, pattern, scalar, legacy, chunks, minimum, mode):
        cases.append((domain, n, pattern, scalar.hex(), legacy, chunks, minimum, mode))
    for mode in modes:
        for domain in (0, 1):
            for legacy in (0, 1):
                for minimum in (3, 4):
                    add(domain, 16384, 8, 1.01, legacy, 0, minimum, mode)
                    add(domain, 16385, 8, 1.01, legacy, 7, minimum, mode)
                    add(domain, 16385, 11, 1.01, legacy, 0, minimum, mode)
                    add(domain, 16385, 12, 1.01, legacy, 0, minimum, mode)
                    add(domain, 1025, 9, 1.01, legacy, 0, minimum, mode)
                    for scalar in scalars:
                        add(domain, 1025, 13, scalar, legacy, 0, minimum, mode)
                        add(domain, 1025, 14, scalar, legacy, 0, minimum, mode)
        for minimum in (3, 4):
            add(0, 1025, 2, 1.01, 0, 0, minimum, mode)
            add(0, 1025, 10, 1.01, 1, 0, minimum, mode)
    return cases


def validate_rows(rows, modes, require_proved):
    require(len(modes) == 4 and len(set(modes)) == 4, 'Four distinct rounding modes are required')
    coordinates = ('domain', 'length', 'pattern', 'scalar', 'legacy', 'chunk', 'minimum', 'rounding')
    actual = []
    for row in rows:
        require(list(row) == FIELDS, 'Unexpected or incomplete CSV fields')
        for name, value in row.items():
            require(isinstance(value, str), 'Missing CSV value: ' + name)
            if name != 'scalar':
                require(re.fullmatch(r'[0-9]+', value) is not None, 'Malformed numeric record: ' + name)
        actual.append(tuple(float.fromhex(row[name]).hex() if name == 'scalar' else int(row[name])
            for name in coordinates))
    expected = expected_cases(modes)
    require(Counter(actual) == Counter(expected) and actual == expected, 'Incomplete, duplicate or reordered semantic matrix')
    for row in rows:
        value = lambda name: int(row[name])
        n = value('length')
        require(value('semantic_failure') in range(8), 'Unknown semantic result status')
        require(value('result_missing') <= n, 'Result missing count exceeds input length')
        require(value('reciprocal_scratch_bytes') == value('reciprocal_prepare_rows') * 5, 'Preparation scratch ledger differs')
        require(value('canonical_committed_rows') <= value('canonical_attempt_rows') <= value('output_span_rows'), 'Fused writer ledger differs')
        gated = (value('pattern') == 8 and value('domain') == 1 and value('legacy') == 0 and value('chunk') == 0)
        work_failure = require_proved and ((gated and value('reciprocal_prepare_rows') > 256) or
            ((value('domain') == 0 or value('legacy') == 1) and value('canonical_attempt_rows') != 0))
        require(value('work_failure') == int(work_failure), 'Work failure differs from observed counters')
        if gated:
            require(value('result_missing') == n // 2, 'Dense tag missing count differs from independent fixture')
    return sum(int(row['semantic_failure']) != 0 for row in rows), sum(int(row['work_failure']) for row in rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    parser.add_argument('--commit', help='Full immutable source commit; defaults to checkout HEAD')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--require-proved', action='store_true')
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    if args.commit is None:
        git_env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        args.commit = subprocess.check_output(['git', '--no-replace-objects', 'rev-parse', 'HEAD'],
            cwd=root, env=git_env, text=True).strip()
    sources = inventory(root, args.commit)
    output.mkdir(parents=True, exist_ok=False)
    src = root / 'r-package/dtatools/src'
    controller_before, probe_before = sha(Path(__file__)), sha(HERE / 'work-count.c')
    for name in sources:
        if name.endswith('.h'):
            (output / name).write_bytes((src / name).read_bytes())
    payload = (src / 'numeric-payload.c').read_text()
    arithmetic = (src / 'numeric-arithmetic.h').read_text()
    begin = arithmetic.index('typedef struct {\n    double minimum;')
    end = arithmetic.index('/* Missing-bearing same-width', begin)
    common = arithmetic[begin:end] + '\n' + function(payload, 'numeric_float_observed_limit')
    common += '\n' + function(payload, 'scalar_arithmetic_result_valid').replace('scalar_arithmetic_result_valid', 'uncounted_result_valid')
    common += '\nstatic int scalar_arithmetic_result_valid(double value) { result_checks[phase]++; return uncounted_result_valid(value); }\n'
    common += '\n' + function((src / 'numeric-arithmetic-integer.h').read_text(), 'arithmetic_integer_missing')
    for name in ('arithmetic_scale_float_invalid_modern', 'arithmetic_scale_float_invalid_legacy'):
        common += '\n' + function((src / 'numeric-arithmetic-scale.h').read_text(), name)
    (output / 'production-common.h').write_text(common)
    internal = (src / 'dtatools-internal.h').read_text()
    domain = 'enum { NUMERIC_DOMAIN_STRICT_MODERN_FLOAT = 1U };\n' + function(internal, 'numeric_strict_modern_float')
    (output / 'production-domain.h').write_text(domain)
    reciprocal_path = output / 'numeric-arithmetic-float-reciprocal.h'
    reciprocal = replace_once(reciprocal_path.read_text(), '    uint32_t minimum = UINT32_MAX;\n',
        '    reciprocal_prepare_rows += count;\n    reciprocal_scratch_bytes += count * 5;\n    uint32_t minimum = UINT32_MAX;\n')
    if 'RECIPROCAL_CANONICAL_WRITE' in reciprocal:
        continuation = chr(92) + '\n'
        reciprocal = replace_once(reciprocal, '        unsigned invalid_count = 0, too_small = 0;',
            '        canonical_attempt_rows += count; ' + continuation + '        unsigned invalid_count = 0, too_small = 0;')
        reciprocal = replace_once(reciprocal, '        *missing_count = invalid_count;',
            '        canonical_committed_rows += count; ' + continuation + '        *missing_count = invalid_count;')
    reciprocal_path.write_text(reciprocal)
    compiler_path = shutil.which('cc')
    require(compiler_path is not None, 'C compiler cc is required for the local probe')
    compiler, executable = Path(compiler_path).resolve(), output / 'work-count'
    compiler_before = sha(compiler)
    command = [str(compiler), '-std=gnu23', '-O2', '-g', '-fPIC', '-Wall', '-Wextra', '-Werror',
        '-Wno-unused-function', '-I', str(output), str(HERE / 'work-count.c'), '-lm', '-o', str(executable)]
    with (output / 'compile.log').open('w') as log:
        compiled = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=output)
    require(compiled.returncode == 0, 'Probe compilation failed; see compile.log')
    run_command = [str(executable)] + (['require-proved'] if args.require_proved else [])
    run = subprocess.run(run_command, capture_output=True, text=True, cwd=output)
    (output / 'work-count.csv').write_text(run.stdout)
    (output / 'work-count.log').write_text(run.stderr)
    witnesses = re.findall(r'^ROUNDING,([0-3]),([0-9]+),PASS$', run.stderr, re.M)
    require(len(witnesses) == 4 and [int(x[0]) for x in witnesses] == list(range(4)), 'Incomplete rounding witnesses')
    require(re.findall(r'^ZERO_OVERFLOW,([0-3]),([0-9]+),PASS$', run.stderr, re.M) == witnesses, 'Incomplete zero/overflow witnesses')
    rows = list(csv.DictReader(run.stdout.splitlines()))
    semantic_failures, work_failures = validate_rows(rows, [int(x[1]) for x in witnesses], args.require_proved)
    expected_code = 2 if semantic_failures else 1 if work_failures else 0
    summary = re.findall(r'^(PASS|FAIL): ([0-9]+) semantic failures, ([0-9]+) work failures across ([0-9]+) cases$', run.stderr, re.M)
    require(len(summary) == 1 and tuple(map(int, summary[0][1:])) == (semantic_failures, work_failures, len(rows)), 'Probe summary differs from complete records')
    require(summary[0][0] == ('PASS' if expected_code == 0 else 'FAIL') and run.returncode == expected_code, 'Probe exit differs from records')
    require(sources == inventory(root, args.commit), 'Consumed source changed during probe')
    require(compiler_before == sha(compiler) and controller_before == sha(Path(__file__)) and probe_before == sha(HERE / 'work-count.c'), 'Compiler/controller/probe changed')
    record = dict(status='SEMANTIC_FAILURE' if semantic_failures else 'EXPECTED_RED' if work_failures else 'PASS',
        commit=args.commit, root=str(root), cwd=str(output), source_sha256=sources, source_before_after_equal=True,
        controller_sha256=controller_before, probe_sha256=probe_before, compiler_sha256=compiler_before,
        compiler_version=subprocess.check_output([str(compiler), '--version'], text=True),
        command=command, run_command=run_command, require_proved=args.require_proved, exit_code=run.returncode,
        cases=len(rows), semantic_failures=semantic_failures, work_failures=work_failures, rounding_witnesses=witnesses,
        artifact_sha256={p.name: sha(p) for p in output.iterdir() if p.is_file()},
        scope='Actual general dispatch, reciprocal proof and producer headers with counters only in private copies. Independent raw input/result oracle under four verified release-flag rounding modes. Strict/unknown/legacy bytes, signed zero/subnormals, discarded provisional writes and whole-column promotion, dense-prefix recovery and seven-row retained spans. R allocation/reader/interrupt boundaries mocked; no timing, R ownership or floating exception-state claim.')
    (output / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(run.stderr, end='')
    print('Receipt:', output / 'receipt.json')
    raise SystemExit(run.returncode)


if __name__ == '__main__':
    main()
