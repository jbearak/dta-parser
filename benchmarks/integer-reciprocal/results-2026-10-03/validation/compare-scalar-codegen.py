#!/usr/bin/env python3
"""Compare unchanged float-scalar writers in the two measured installed DLLs."""
import csv
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
BUILDS = {'baseline': Path('<baseline-build>'),
          'candidate': HERE / 'candidate-final'}
COMMITS = {'baseline': '7003eba901671797ee91fffc97f08e28a1f7f515',
           'candidate': '3a02e6d13309441366a7a727fdc934f424ce66c6'}
SYMBOL = '_arithmetic_float_scalar_write'

def require(value, message):
    if not value:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def body(text):
    function = text.split(SYMBOL + ':\n', 1)[1]
    function = re.split(r'^_\w+:', function, flags=re.M)[0]
    rows = []
    for line in function.splitlines():
        match = re.match(r'\s*([0-9a-f]+):?\s+(.*)', line)
        if match:
            rows.append((int(match[1], 16), match[2].strip()))
    require(bool(rows), 'Missing scalar writer')
    start, end = rows[0][0], rows[-1][0] + 4
    normalized = []
    for address, instruction in rows:
        code = re.sub(r'\s+', ' ', instruction.split(';', 1)[0].strip())
        if re.match(r'(b(?:\.\w+)?|cbnz|cbz|tbz|tbnz)\s', code):
            def relative(match):
                target = int(match[0], 16)
                return 'relative+' + hex(target - start) if start <= target < end else match[0]
            code = re.sub(r'0x[0-9a-f]+', relative, code)
        normalized.append(code)
    return function, rows, normalized

tool = Path(subprocess.check_output(['xcrun', '--find', 'otool'], text=True).strip()).resolve()
tool_hash = sha(tool)
bindings = {}
bodies = {}
for role, build in BUILDS.items():
    receipt_path = build / 'build-receipt.json'
    receipt = json.loads(receipt_path.read_text())
    require(receipt['base_commit'] == COMMITS[role], 'Wrong source build')
    dll = build / 'library/dtatools/libs/dtatools.so'
    binary_hash = sha(dll)
    require(binary_hash == receipt['installed_inventory']['libs/dtatools.so'], 'Changed installed DLL')
    command = [str(tool), '-tvV', '-p', SYMBOL, str(dll)]
    generated = subprocess.check_output(command, text=True)
    function, rows, normalized = body(generated)
    require(sha(dll) == binary_hash and sha(tool) == tool_hash, 'DLL/disassembler changed')
    output = HERE / f'{role}-float-scalar-writer.asm'
    output.write_text(SYMBOL + ':\n' + function)
    bindings[role] = {'commit': COMMITS[role], 'receipt_sha256': sha(receipt_path),
                      'dll_sha256': binary_hash, 'command': command,
                      'full_disassembler_output_sha256': hashlib.sha256(generated.encode()).hexdigest(),
                      'extracted_writer_sha256': sha(output), 'instructions': len(rows),
                      'header_sha256': sha(build / 'source/src/numeric-arithmetic-float-scalar.h')}
    bodies[role] = rows, normalized
require(bindings['baseline']['header_sha256'] == bindings['candidate']['header_sha256'], 'Scalar header changed')
old, old_norm = bodies['baseline']
new, new_norm = bodies['candidate']
differences = []
relocations = []
for index in range(max(len(old), len(new))):
    left = old_norm[index] if index < len(old) else '<absent>'
    right = new_norm[index] if index < len(new) else '<absent>'
    if left == right:
        continue
    same_symbol = None
    if left.startswith('adrp ') and right.startswith('adrp ') and left.split(',')[0] == right.split(',')[0]:
        next_old, next_new = old[index + 1][1], new[index + 1][1]
        if next_old == next_new and 'literal pool symbol address: _R_NaReal' in next_old:
            same_symbol = '_R_NaReal'
    elif left.startswith('bl ') and right.startswith('bl '):
        old_stub = re.search(r'symbol stub for: (\S+)', old[index][1])
        new_stub = re.search(r'symbol stub for: (\S+)', new[index][1])
        if old_stub and new_stub and old_stub[1] == new_stub[1]:
            same_symbol = old_stub[1]
    item = {'index': index, 'baseline': left, 'candidate': right}
    if same_symbol:
        relocations.append(dict(item, symbol=same_symbol))
    else:
        differences.append(item)

raw = list(csv.DictReader((HERE / 'screen-v1/raw.csv').open()))
controls = []
for missing in ('FALSE', 'TRUE'):
    selected = [row for row in raw if row['width'] == 'float' and row['missing'] == missing
                and row['operation'] == 'scale_general' and row['representation'] == 'compact']
    lookup = {(row['variant'], int(row['round'])): row for row in selected}
    require(len(selected) == len(lookup) == 12, 'Incomplete scalar control')
    rounds = []
    for number in range(1, 7):
        values = {role: float(lookup[role, number]['cpu']) / int(lookup[role, number]['iterations']) for role in BUILDS}
        rounds.append({'round': number, 'candidate_build_position': 2 if number % 2 else 1,
                       'baseline_seconds': values['baseline'], 'candidate_seconds': values['candidate'],
                       'speedup': values['baseline'] / values['candidate']})
    controls.append({'missing': missing, 'rounds': rounds,
                     'ratio_of_medians': statistics.median(row['baseline_seconds'] for row in rounds) /
                                         statistics.median(row['candidate_seconds'] for row in rounds),
                     'paired_median': statistics.median(row['speedup'] for row in rounds)})
result = {'status': 'IDENTICAL_AFTER_VERIFIED_RELOCATIONS' if not differences else 'BODY_DIFFERENCES',
          'bindings': bindings, 'tool_sha256': tool_hash, 'tool': str(tool),
          'relocations': relocations, 'other_differences': differences, 'controls': controls,
          'script_sha256': sha(Path(__file__).resolve()), 'raw_sha256': sha(HERE / 'screen-v1/raw.csv'),
          'scope': 'Full emitted float-scalar writer only. This does not cover dispatch, allocation history, addresses, cache effects or the whole public operation, and does not identify the timing cause.'}
(HERE / 'scalar-control-codegen.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print(json.dumps({'status': result['status'], 'instructions': {role: x['instructions'] for role, x in bindings.items()},
                  'relocations': len(relocations), 'other_differences': len(differences),
                  'controls': [{key: value for key, value in control.items() if key != 'rounds'} for control in controls]}))
