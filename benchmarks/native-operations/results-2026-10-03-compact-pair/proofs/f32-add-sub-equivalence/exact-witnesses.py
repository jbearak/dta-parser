#!/usr/bin/env python3
"""Independent exact-rational IEEE rounding and storage checks; no floats."""
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
        raise ValueError('Nonfinite input to rational decoder')
    significand = fraction if exponent == 0 else (1 << fraction_bits) | fraction
    power = (1 - bias if exponent == 0 else exponent - bias) - fraction_bits
    return sign * Fraction(significand) * Fraction(2) ** power


def value(record):
    return binary(int(record['bits'], 16), 23, 8, 127) if record['kind'] == 2 else Fraction(record['integer'])


def negative(record):
    return bool(int(record['bits'], 16) >> 31) if record['kind'] == 2 else record['integer'] < 0


def floor_log2(q):
    guess = q.numerator.bit_length() - q.denominator.bit_length()
    return guess - (q < Fraction(2) ** guess)


def rounded(q, fb, eb, bias, mode, negative_zero=False):
    sign = q < 0 or (q == 0 and negative_zero)
    sign_bits = int(sign) << (fb + eb)
    if not q:
        return sign_bits
    a = abs(q)
    exponent = floor_log2(a)
    minimum, maximum = 1 - bias, ((1 << eb) - 2) - bias
    quantum = max(exponent - fb, minimum - fb)
    scaled = a / (Fraction(2) ** quantum)
    n, remainder = divmod(scaled.numerator, scaled.denominator)
    increment = (2 * remainder > scaled.denominator or
                 (2 * remainder == scaled.denominator and n % 2)) if mode == 'nearest' else (
                 bool(remainder) and ((mode == 'down' and sign) or (mode == 'up' and not sign)))
    n += int(increment)
    if n == 0:
        return sign_bits
    if n >= 1 << (fb + 1):
        n >>= 1
        quantum += 1
    result_exponent = quantum + fb
    if result_exponent > maximum:
        infinity = mode == 'nearest' or (mode == 'down' and sign) or (mode == 'up' and not sign)
        magnitude = ((1 << eb) - 1) << fb if infinity else (((1 << eb) - 1) << fb) - 1
        return sign_bits | magnitude
    if n < 1 << fb:
        return sign_bits | n
    return sign_bits | ((result_exponent + bias) << fb) | (n - (1 << fb))


def check(record, operation, mode):
    a, b = value(record['x']), value(record['y'])
    effective_b = b if operation == '+' else -b
    q = a + effective_b
    sx, sy = negative(record['x']), negative(record['y']) ^ (operation == '-')
    zero_sign = sx if not a and not b and sx == sy else mode == 'down'
    d_bits = rounded(q, 52, 11, 1023, mode, zero_sign)
    f_bits = rounded(q, 23, 8, 127, mode, zero_sign)
    if int(record['binary64_result'], 16) != d_bits:
        raise RuntimeError(f'Binary64 rounding disagrees: {operation}/{mode}/{record}')
    if int(record['binary32_result'], 16) != f_bits:
        raise RuntimeError(f'Direct binary32 rounding disagrees: {operation}/{mode}/{record}')
    d = binary(d_bits, 52, 11, 1023)
    nested_f_bits = rounded(d, 23, 8, 127, mode, bool(d_bits >> 63))
    if nested_f_bits != f_bits:
        raise RuntimeError('Nested binary64-to-binary32 differs from direct rounding')
    limit = binary(0x7effffff, 23, 8, 127)
    promoted = abs(d) > limit
    if 'encoded_bits' in record:
        if record['missing'] != 0 or record['kind'] != (3 if promoted else 2):
            raise RuntimeError('Incorrect storage or missing decision')
        if int(record['encoded_bits'], 16) != (d_bits if promoted else nested_f_bits):
            raise RuntimeError('Incorrect encoded result bits')
    category = record.get('category')
    difference = abs(d) - limit
    f_magnitude = f_bits & 0x7fffffff
    if category is not None:
        if category < 3 and f_magnitude != 0x7effffff:
            raise RuntimeError('Non-equality boundary witness')
        if (category == 0 and difference <= 0 or category == 1 and difference >= 0 or
                category == 2 and difference != 0 or category == 3 and (not promoted or f_magnitude <= 0x7effffff)):
            raise RuntimeError('Boundary category disagrees with rounded binary64 storage')
    return {'exact_rational': str(q), 'binary64_rounding_changed_value': d != q,
            'promoted': promoted, 'zero_sign': bool(d_bits >> 63) if not q else None,
            'exact_above_but_binary64_fits': abs(q) > limit and not promoted}


def self_test():
    # Independent fixed known encodings for ties, subnormals, carry and overflow.
    fixtures = [(Fraction(1), 0x3f800000), (Fraction(2), 0x40000000),
                (Fraction(2) ** -149, 1), (Fraction(2) ** -150, 0),
                (Fraction(3) * Fraction(2) ** -150, 2),
                (Fraction(1) + Fraction(2) ** -24, 0x3f800000),
                (Fraction(1) + 3 * Fraction(2) ** -24, 0x3f800002),
                (Fraction(2) ** 128, 0x7f800000)]
    for q, expected in fixtures:
        if rounded(q, 23, 8, 127, 'nearest') != expected:
            raise RuntimeError('Rational rounding oracle self-test failed')
    if rounded(Fraction(2) ** 128, 23, 8, 127, 'zero') != 0x7f7fffff:
        raise RuntimeError('Toward-zero overflow self-test failed')


def main():
    self_test()
    path = HERE / 'optimized-result.json'
    result = json.loads(path.read_text())
    if len(result['modes']) != 8:
        raise RuntimeError('Incomplete operation/mode matrix')
    records = []
    mode_names = ('nearest', 'down', 'up', 'zero')
    for index, record in enumerate(result['modes']):
        operation = '+' if index < 4 else '-'
        mode = mode_names[index % 4]
        if record['operation'] != operation:
            raise RuntimeError('Unexpected operation order')
        witnesses = [w for w in record['witnesses'] if w['present']] + record['oracle_witnesses']
        checks = [check(w, operation, mode) for w in witnesses]
        if not any(c['zero_sign'] is not None for c in checks):
            raise RuntimeError('No signed-zero witnesses in this operation/mode')
        if not any(c['binary64_rounding_changed_value'] for c in checks):
            raise RuntimeError('No inexact-binary64 witness in this operation/mode')
        records.append({'operation': operation, 'mode': mode, 'checks': checks})
    if not any(c['exact_above_but_binary64_fits'] for r in records for c in r['checks']):
        raise RuntimeError('Missing rounded-binary64 storage-policy witness')
    receipt = {'status': 'PASS', 'method': 'Exact Fraction inputs and independent IEEE rounding to p53 and p24; no host floating arithmetic',
               'scope': 'Recorded boundary, exponent-gap, binade, subnormal and zero witnesses; full C differential matrix is separately recorded',
               'result_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
               'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'records': records}
    (HERE / 'exact-witnesses.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'operation_modes': len(records), 'witnesses': sum(len(r['checks']) for r in records)}))


if __name__ == '__main__':
    main()
