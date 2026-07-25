import { readFileSync } from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

import { read_rows_from_buffer } from '../src/data-reader';
import { parse_metadata } from '../src/header';
import { parse_legacy_metadata } from '../src/legacy-header';
import { DtaFile } from '../src/node';

const fixtureDir = path.resolve(import.meta.dir, '../tests/fixtures/dta');
const iterations = Math.max(
    1,
    Math.min(10_000, Number(process.env.DTA_BENCH_ITERATIONS ?? 25))
);

async function measure(operation: () => unknown | Promise<unknown>): Promise<number> {
    const start = performance.now();
    for (let index = 0; index < iterations; index++) await operation();
    return (performance.now() - start) / iterations;
}

console.log('case\tphase\tinput_bytes\titerations\tmean_ms');
for (const [caseName, fixtureName] of [
    ['modern-all-types', 'all_types_v118.dta'],
    ['wide', 'wide_v118.dta'],
    ['strl', 'strl_test_v118.dta'],
    ['legacy', 'all_types_v115.dta'],
] as const) {
    const fixturePath = path.join(fixtureDir, fixtureName);
    const bytes = readFileSync(fixturePath);
    const arrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
    );
    const metadata = bytes[0] >= 113 && bytes[0] <= 115
        ? parse_legacy_metadata(arrayBuffer, bytes.length)
        : parse_metadata(arrayBuffer);
    const report = async (phase: string, operation: () => unknown | Promise<unknown>) => {
        const mean = await measure(operation);
        console.log(`${caseName}\t${phase}\t${bytes.length}\t${iterations}\t${mean.toFixed(6)}`);
    };

    await report('file-io', () => readFileSync(fixturePath));
    await report('metadata', () => bytes[0] >= 113 && bytes[0] <= 115
        ? parse_legacy_metadata(arrayBuffer, bytes.length)
        : parse_metadata(arrayBuffer));
    await report('buffer-full-decode', () =>
        read_rows_from_buffer(arrayBuffer, metadata, 0, metadata.nobs));

    const file = await DtaFile.open(fixturePath);
    try {
        await report('node-file-projected-window', () =>
            file.read_rows(1, 16, 0, Math.min(2, metadata.nvar)));
    } finally {
        file.close();
    }
}
