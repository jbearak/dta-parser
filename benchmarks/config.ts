const DEFAULT_ITERATIONS = 25;

export function parse_benchmark_iterations(value: string | undefined): number {
    if (value === undefined || value.trim() === '') return DEFAULT_ITERATIONS;
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
        return DEFAULT_ITERATIONS;
    }
    return Math.max(1, Math.min(10_000, parsed));
}
