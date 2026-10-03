#!/usr/bin/env python3
"""Build and run a standalone semantic diagnostic. No performance clock."""
import hashlib
import json
import pathlib
import shutil
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path('<repo>')
SOURCE = ROOT / 'r-package/dtatools/src/numeric-payload.c'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(text, name):
    start = text.index('static int ' + name + '(')
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end] + '\n'


def main():
    source_hash = sha(SOURCE)
    text = SOURCE.read_text()
    functions = {name: extract(text, name) for name in (
        'byte_missing_offset', 'int_missing_offset', 'float_missing_offset')}
    header = HERE / 'extracted-classifiers.h'
    header.write_text('/* Exact source extraction; see receipt.json. */\n' + '\n'.join(functions.values()))
    compiler = pathlib.Path(shutil.which('clang')).resolve()
    flags = ['-std=c11', '-O2', '-ffp-contract=off', '-frounding-math',
             '-Wall', '-Wextra', '-Werror']
    before = {str(path): sha(path) for path in (SOURCE, HERE / 'probe.c', pathlib.Path(__file__).resolve(), header, compiler)}
    variants = []
    for label, additional in [('optimized', []), ('undefined-sanitizer', ['-fsanitize=undefined', '-fno-sanitize-recover=all'])]:
        binary = HERE / ('probe-' + label)
        command = [str(compiler), *flags, *additional, str(HERE / 'probe.c'), '-lm', '-o', str(binary)]
        compile_result = subprocess.run(command, cwd=HERE, text=True, capture_output=True)
        (HERE / (label + '-compile.log')).write_text(compile_result.stdout + compile_result.stderr)
        compile_result.check_returncode()
        result = subprocess.run([str(binary)], cwd=HERE, text=True, capture_output=True)
        (HERE / (label + '-result.json')).write_text(result.stdout)
        (HERE / (label + '-stderr.log')).write_text(result.stderr)
        result.check_returncode()
        parsed = json.loads(result.stdout)
        if parsed['mismatches'] != 0 or parsed['rounding_modes'] != 4 or parsed['operations'] != 2 or parsed['column_checks'] < 12:
            raise RuntimeError('Incomplete semantic qualification')
        if len(parsed['modes']) != 8 or len({(m['operation'], m['mode']) for m in parsed['modes']}) != 8:
            raise RuntimeError('Incomplete per-mode evidence')
        if sum(m['columns'] for m in parsed['modes']) != parsed['column_checks'] or sum(m['checked'] for m in parsed['modes']) != parsed['checked']:
            raise RuntimeError('Per-mode counters disagree')
        if any(parsed[key] <= 0 for key in ('checked', 'ambiguous_above', 'ambiguous_below', 'exact_boundary', 'strict_promotion')):
            raise RuntimeError('Incomplete boundary coverage')
        variants.append({'label': label, 'command': command, 'binary_sha256': sha(binary),
                         'result_sha256': sha(HERE / (label + '-result.json')), 'result': parsed})
    after = {path: sha(pathlib.Path(path)) for path in before}
    if before != after or sha(SOURCE) != source_hash:
        raise RuntimeError('Source or compiler changed during qualification')
    if variants[0]['result'] != variants[1]['result']:
        raise RuntimeError('Optimized and sanitizer outcomes differ')
    receipt = {
        'scope': 'Standalone semantic experiment only; no package source changes or performance measurements',
        'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
        'before': before, 'after': after,
        'compiler_version': subprocess.check_output([str(compiler), '--version'], cwd=HERE, text=True),
        'functions': {name: {'sha256': hashlib.sha256(value.encode()).hexdigest(), 'text': value} for name, value in functions.items()},
        'variants': variants,
    }
    (HERE / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'receipt': str(HERE / 'receipt.json'), 'checked': variants[0]['result']['checked'], 'checksum': variants[0]['result']['checksum']}))


if __name__ == '__main__':
    main()
