import { describe, expect, it } from 'bun:test';

import { parse_benchmark_iterations } from '../../benchmarks/config';

describe('benchmark iteration configuration', () => {
    it('accepts finite integers and clamps them to the supported range', () => {
        expect(parse_benchmark_iterations('1')).toBe(1);
        expect(parse_benchmark_iterations('200')).toBe(200);
        expect(parse_benchmark_iterations('0')).toBe(1);
        expect(parse_benchmark_iterations('10001')).toBe(10_000);
    });

    it('uses the default for absent, fractional, or non-finite values', () => {
        for (const value of [undefined, '', ' ', '1.5', 'NaN', 'Infinity', 'nope']) {
            expect(parse_benchmark_iterations(value)).toBe(25);
        }
    });
});
