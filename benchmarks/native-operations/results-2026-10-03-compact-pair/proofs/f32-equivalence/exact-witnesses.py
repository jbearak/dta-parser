#!/usr/bin/env python3
"""Recheck recorded boundary witnesses using exact rational arithmetic."""
from fractions import Fraction
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def binary(bits, fraction_bits, exponent_bits, bias):
    fraction = bits & ((1 << fraction_bits) - 1)
    exponent = (bits >> fraction_bits) & ((1 << exponent_bits) - 1)
    sign = -1 if bits >> (fraction_bits + exponent_bits) else 1
    if exponent == (1 << exponent_bits) - 1:
        raise ValueError('Nonfinite witness')
    significand = fraction if exponent == 0 else (1 << fraction_bits) | fraction
    power = (1 - bias if exponent == 0 else exponent - bias) - fraction_bits
    return sign * Fraction(significand) * Fraction(2) ** power


def value(record):
    return binary(int(record['bits'], 16), 23, 8, 127) if record['kind'] == 2 else Fraction(record['integer'])


def main():
    path = HERE / 'optimized-result.json'
    result = json.loads(path.read_text())
    limit = binary(0x7effffff, 23, 8, 127)
    checks = []
    for mode in result['modes']:
        for witness in mode['witnesses']:
            if not witness['present']:
                continue
            exact = value(witness['x']) * value(witness['y'])
            recorded = binary(int(witness['exact_product'], 16), 52, 11, 1023)
            if exact != recorded:
                raise RuntimeError('Binary64 product is not mathematically exact')
            difference = abs(exact) - limit
            rounded = binary(int(witness['rounded_product'], 16), 23, 8, 127)
            category = witness['category']
            if category < 3 and abs(rounded) != limit:
                raise RuntimeError('Equality witness is not at float observed limit')
            if category == 0 and difference <= 0 or category == 1 and difference >= 0 or category == 2 and difference != 0:
                raise RuntimeError('Incorrect exact boundary category')
            if category == 3 and (difference <= 0 or abs(rounded) <= limit):
                raise RuntimeError('Strict promotion witness does not require promotion')
            checks.append({'mode': mode['mode'], 'category': category, 'exact_product': str(exact),
                           'absolute_difference_from_limit': str(difference)})
    receipt = {'status': 'PASS', 'method': 'Python Fraction; no floating arithmetic',
               'result_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
               'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'checks': checks}
    (HERE / 'exact-witnesses.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'witnesses': len(checks)}))


if __name__ == '__main__':
    main()
