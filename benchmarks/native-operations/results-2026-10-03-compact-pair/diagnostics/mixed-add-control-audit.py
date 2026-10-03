#!/usr/bin/env python3
"""Reproduce a relocation-aware compiler comparison and paired control values.

This does not infer a performance cause from instruction equality. No builds,
R processes or clocks are started by this script.
"""
import csv
import hashlib
import json
from pathlib import Path
import re
import statistics

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def body(path):
    text = path.read_text().split('_arithmetic_pair_write:\n', 1)[1]
    text = re.split(r'^_\w+:', text, flags=re.M)[0]
    rows = []
    for line in text.splitlines():
        match = re.match(r'\s*([0-9a-f]+):?\s+(.*)', line)
        if match:
            rows.append((int(match[1], 16), match[2].strip()))
    if not rows:
        raise RuntimeError('Missing pair producer disassembly')
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
    return rows, normalized


def main():
    paths = [HERE / 'pair-prototype-disassembly.txt', HERE / 'float-product-otool-disassembly.txt']
    pairs = [body(path) for path in paths]
    old, new = pairs[0][0], pairs[1][0]
    if len(old) != len(new):
        raise RuntimeError('Instruction counts differ')
    differences = []
    for index, (left, right) in enumerate(zip(pairs[0][1], pairs[1][1])):
        if left == right:
            continue
        if left.startswith('adrp ') and right.startswith('adrp '):
            if left.split(',')[0] != right.split(',')[0]:
                raise RuntimeError('ADRP destination differs')
            next_old, next_new = old[index + 1][1], new[index + 1][1]
            if next_old != next_new or 'literal pool symbol address: _R_NaReal' not in next_old:
                raise RuntimeError('ADRP does not resolve to the same R_NaReal load')
            symbol = '_R_NaReal'
        elif left.startswith('bl ') and right.startswith('bl '):
            symbol = '_R_CheckUserInterrupt'
            if ('symbol stub for: ' + symbol) not in old[index][1] or ('symbol stub for: ' + symbol) not in new[index][1]:
                raise RuntimeError('External call target differs')
        else:
            raise RuntimeError(f'Nonrelocation instruction differs at {index}: {left} / {right}')
        differences.append({'index': index, 'old_address': hex(old[index][0]),
                            'new_address': hex(new[index][0]), 'symbol': symbol,
                            'old': old[index][1], 'new': new[index][1]})
    raw_path = HERE / 'float-product-timings/raw.csv'
    raw = list(csv.DictReader(raw_path.open()))
    controls = []
    for width in ('int', 'long'):
        selected = [r for r in raw if r['width'] == width and r['missing'] == 'TRUE'
                    and r['operation'] == 'pair_compact_float_add' and r['representation'] == 'compact']
        if not selected:
            # The maintained worker calls the same operator pair_mixed_add.
            selected = [r for r in raw if r['width'] == width and r['missing'] == 'TRUE'
                        and 'add' in r['operation'] and r['representation'] == 'compact']
        if len(selected) != 12:
            raise RuntimeError(f'Incomplete {width} add control: {len(selected)}')
        lookup = {(r['variant'], int(r['round'])): r for r in selected}
        if len(lookup) != 12:
            raise RuntimeError('Duplicate control observation')
        rounds = []
        for number in range(1, 7):
            base, candidate = lookup['baseline', number], lookup['candidate', number]
            b = float(base['cpu']) / int(base['iterations'])
            c = float(candidate['cpu']) / int(candidate['iterations'])
            rounds.append({'round': number, 'candidate_build_position': 2 if number % 2 else 1,
                           'baseline_seconds_per_call': b, 'candidate_seconds_per_call': c,
                           'paired_speedup': b / c, 'baseline_cpu_interval': float(base['cpu']),
                           'candidate_cpu_interval': float(candidate['cpu'])})
        controls.append({'width': width, 'operation': selected[0]['operation'], 'rounds': rounds,
                         'median_paired_speedup': statistics.median(r['paired_speedup'] for r in rounds),
                         'ratio_of_cpu_medians': statistics.median(r['baseline_seconds_per_call'] for r in rounds)
                         / statistics.median(r['candidate_seconds_per_call'] for r in rounds)})
    receipts = [HERE / name / 'build-receipt.json' for name in ('pair-prototype', 'float-product-prototype')]
    inputs = paths + receipts + [raw_path, Path(__file__).resolve()]
    report = {'status': 'PASS', 'scope': 'Entire arithmetic_pair_write instruction body, relocation-aware; paired control values only',
              'limits': 'Identical instructions apart from verified relocations do not exclude address, cache, allocation-history or run-order effects and do not identify the cause of timing variation.',
              'instruction_count_each': len(old), 'relocation_differences': differences,
              'symbol_counts': {symbol: sum(d['symbol'] == symbol for d in differences)
                                for symbol in ('_R_NaReal', '_R_CheckUserInterrupt')},
              'controls': controls, 'input_sha256': {str(path): sha(path) for path in inputs}}
    target = HERE / 'mixed-add-control-audit.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'instructions_each': len(old), 'symbols': report['symbol_counts'],
                      'controls': [{k: v for k, v in c.items() if k != 'rounds'} for c in controls], 'receipt': str(target)}))


if __name__ == '__main__':
    main()
