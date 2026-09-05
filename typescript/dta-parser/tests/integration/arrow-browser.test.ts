import { expect, test } from 'bun:test';
import { build } from 'esbuild';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { runInNewContext } from 'node:vm';

test('portable browser bundle synchronously reads compressed Arrow without Node globals', async () => {
    const bundle = await build({ entryPoints: [join(import.meta.dir, '../../src/index.ts')],
        bundle: true, platform: 'browser', format: 'iife', globalName: 'Parser', write: false, target: 'es2022' });
    const parser = runInNewContext(`${bundle.outputFiles![0].text}\nParser`, {
        TextDecoder, TextEncoder, structuredClone, Uint8Array, ArrayBuffer, DataView, DOMException,
    });
    for (const compression of ['lz4', 'zstd']) {
        const bytes = new Uint8Array(readFileSync(join(import.meta.dir, '../fixtures/arrow', `profile-${compression}.arrow`)));
        const reader = parser.ArrowBuffer.open(bytes);
        expect(reader.read_rows(2, 1, 0, 1)).toEqual([[{ kind: 'missing', missing_type: '.a' }]]);
    }
});
