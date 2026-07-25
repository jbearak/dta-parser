const DEFAULT_ITERATIONS = 25;
const MIN_ITERATIONS = 1;
const MAX_ITERATIONS = 10_000;
const CANONICAL_UNSIGNED_DECIMAL = /^(?:0|[1-9][0-9]*)$/;

export function parse_benchmark_iterations(value: string | undefined): number {
    if (value === undefined || !CANONICAL_UNSIGNED_DECIMAL.test(value)) {
        return DEFAULT_ITERATIONS;
    }
    const parsed = Number(value);
    if (!Number.isSafeInteger(parsed)) {
        return DEFAULT_ITERATIONS;
    }
    return Math.max(MIN_ITERATIONS, Math.min(MAX_ITERATIONS, parsed));
}
