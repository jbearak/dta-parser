import { describe, expect, it } from 'bun:test';

import { parse_benchmark_iterations } from '../../benchmarks/config';

describe('benchmark iteration configuration', () => {
    it('accepts canonical safe unsigned decimals and clamps valid values', () => {
        for (const [value, expected] of [
            ['0', 1],
            ['1', 1],
            ['200', 200],
            ['10000', 10_000],
            ['10001', 10_000],
            ['9007199254740991', 10_000],
        ] as const) {
            expect(parse_benchmark_iterations(value)).toBe(expected);
        }
    });

    it('uses the default for non-canonical, unsafe, or overflowing values', () => {
        for (const value of [
            undefined,
            '',
            ' ',
            '01',
            '1e3',
            '1.0',
            '0x10',
            ' 1',
            '1 ',
            '+1',
            '-1',
            '9007199254740992',
            '18446744073709551616',
            '999999999999999999999999999999999999999999999999999999',
            'NaN',
            'Infinity',
            'nope',
        ]) {
            expect(parse_benchmark_iterations(value)).toBe(25);
        }
    });
});
