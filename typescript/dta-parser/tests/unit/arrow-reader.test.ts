import { describe, expect, test } from 'bun:test';
import { readFileSync, mkdtempSync, writeFileSync, renameSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ArrowBuffer } from '../../src/index';
import { ArrowFile } from '../../src/node';
import { ArrowReader } from '../../src/arrow-reader';
import { readFooter } from '../../src/arrow-ipc';
import { FlatBuffer } from '../../src/arrow-flatbuffer';

const fixturePath = (name: string): string => join(import.meta.dir, '../fixtures/arrow', `${name}.arrow`);
const fixture = (name: string): Uint8Array => new Uint8Array(readFileSync(fixturePath(name)));
const source = (bytes: Uint8Array) => ({ size: bytes.length, read: (offset: number, length: number) => bytes.subarray(offset, offset + length) });
function footerBuffer(bytes: Uint8Array): FlatBuffer {
    const length = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(bytes.length - 10, true);
    return new FlatBuffer(bytes.subarray(bytes.length - 10 - length, bytes.length - 10));
}
function decodeOracle(value: unknown): unknown {
    if (value && typeof value === 'object') {
        const tagged = value as Record<string, string>;
        if ('bigint' in tagged) return BigInt(tagged.bigint);
        if ('missing' in tagged) return { kind: 'missing', missing_type: tagged.missing };
        if ('number' in tagged) return Number(tagged.number);
    }
    return value;
}
function replaceLast(bytes: Uint8Array, before: string, after: string): Uint8Array {
    expect(before.length).toBe(after.length);
    const buffer = Buffer.from(bytes), index = buffer.lastIndexOf(before);
    expect(index).toBeGreaterThanOrEqual(0);
    buffer.write(after, index);
    return buffer;
}

describe('Arrow IPC readers', () => {
    for (const compression of ['none', 'lz4', 'zstd']) {
        test(`all decoded cells match Rust oracles, ${compression}`, async () => {
            for (const kind of ['plain', 'profile']) {
                const oracle = JSON.parse(readFileSync(join(import.meta.dir, '../fixtures/arrow', `${kind}.expected.json`), 'utf8'));
                const columns = kind === 'plain' ? oracle : oracle.columns;
                const portable = ArrowBuffer.open(fixture(`${kind}-${compression}`));
                const actual = portable.read_columns(columns.map((_: unknown, i: number) => i));
                for (let i = 0; i < columns.length; i++) {
                    expect(portable.variables[i].name).toBe(columns[i].name);
                    expect(actual.get(i)).toEqual(columns[i].values.map(decodeOracle));
                    if (columns[i].field) expect(portable.variables[i].profile).toMatchObject(columns[i].field);
                }
                if (kind === 'profile') expect(portable.metadata.dataset).toMatchObject(oracle.dataset);
                const node = await ArrowFile.open(fixturePath(`${kind}-${compression}`));
                try { expect(await node.read_columns(columns.map((_: unknown, i: number) => i))).toEqual(actual); }
                finally { node.close(); }
            }
        });
        test(`exact ordinary values and metadata, ${compression}`, async () => {
            const portable = ArrowBuffer.open(fixture(`plain-${compression}`));
            expect(portable.nobs).toBe(4);
            expect(portable.nvar).toBe(26);
            const rows = portable.read_rows(0, 4);
            expect(rows[0].slice(0, 9)).toEqual([true, -128, -32768, -2147483648, -9223372036854775808n, 0, 0, 0, 0n]);
            expect(rows[1]).toEqual(Array(26).fill(null));
            expect(rows[0][11]).toBe('café');
            expect(rows[0][12]).toBe('東京');
            expect(rows[0][25]).toBe(1n);
            expect(Object.is(rows[0][10], -0)).toBe(true);
            expect(portable.variables[17].unit).toBe('nanosecond');
            expect(portable.variables[19].unit).toBe('millisecond');
            expect(portable.variables[13].epoch).toBe('1970-01-01');
            expect(portable.get_dictionary(22)?.levels).toEqual(['low', 'high', 'unused']);
            expect(portable.read_rows(1, 2, 11, 14)).toEqual(rows.slice(1, 3).map(row => row.slice(11, 14)));
            expect([...portable.read_columns([25, 0, 25]).keys()]).toEqual([25, 0]);
            const node = await ArrowFile.open(fixturePath(`plain-${compression}`));
            try {
                expect(await node.read_rows(0, 4, 0, 26, { chunk_rows: 1 })).toEqual(rows);
                expect(await node.read_columns([25, 0])).toEqual(portable.read_columns([25, 0]));
                expect(node.metadata).toEqual(portable.metadata);
                expect(node.dictionaries).toEqual(portable.dictionaries);
            } finally { node.close(); }
            await expect(node.read_rows(0, 1)).rejects.toThrow('closed');
            node.close();
        });
        test(`profile missing codes and canonical checksums, ${compression}`, async () => {
            const portable = ArrowBuffer.open(fixture(`profile-${compression}`));
            const rows = portable.read_rows(0, 28);
            for (let row = 1; row <= 27; row++) {
                const missing_type = row === 1 ? '.' : `.${String.fromCharCode(95 + row)}`;
                for (let column = 0; column < 5; column++) expect(rows[row][column]).toEqual({ kind: 'missing', missing_type });
            }
            expect(rows[0].slice(5, 8)).toEqual([1.25, 1.0000000001, 2.5]);
            expect(portable.metadata.profile_version).toBe('0');
            expect(portable.variables[0].profile?.storage).toBe('byte');
            expect(portable.variables[5].temporal_semantics).toEqual({ unit: 'days', epoch: '1970-01-01' });
            expect(portable.variables[6].temporal_semantics?.unit).toBe('secs');
            const node = await ArrowFile.open(fixturePath(`profile-${compression}`));
            try { expect(await node.read_rows(0, 28)).toEqual(rows); }
            finally { node.close(); }
        });
    }
    test('dictionary deltas preserve codes and complete levels', () => {
        const reader = ArrowBuffer.open(fixture('dictionary-delta'));
        expect(reader.read_rows(0, 3)).toEqual([[0], [1], [0]]);
        expect(reader.get_dictionary(0)).toEqual({ levels: ['a', 'b'], ordered: false });
    });
    test('leading U+FEFF remains part of Arrow string values', () => {
        const bytes = fixture('plain-none'), footer = readFooter(source(bytes));
        const batch = footer.batches[0], field = footer.fields[11];
        const values = batch.buffers[field.bufferIndex + 2];
        bytes.set([0xef, 0xbb, 0xbf, 0x61, 0x62], batch.block.offset + batch.block.metadataLength + values.offset);
        expect(ArrowBuffer.open(bytes).read_rows(0, 1, 11, 12)).toEqual([['\uFEFFab']]);
    });
    test('omitted dictionary indexType defaults to signed Int32', () => {
        const bytes = fixture('plain-none'), fb = footerBuffer(bytes);
        const schema = fb.child(fb.root(), 1, true)!;
        const field = fb.tables(schema, 1)[24];
        const dictionary = fb.child(field, 4, true)!;
        const vtable = dictionary - fb.i32(dictionary);
        fb.view.setUint16(vtable + 6, 0, true);
        expect(ArrowBuffer.open(bytes).read_rows(0, 4, 24, 25)).toEqual([[1], [null], [0], [1]]);
    });
    test('empty input, empty projections, row bounds, and options', () => {
        expect(ArrowBuffer.open(fixture('empty')).read_rows(0, 1)).toEqual([]);
        const reader = ArrowBuffer.open(fixture('plain-none'));
        expect(reader.read_rows(100, 10)).toEqual([]);
        expect(reader.read_rows(1, 2, 0, 0)).toEqual([[], []]);
        expect(reader.read_columns([])).toEqual(new Map());
        for (const value of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
            expect(() => reader.read_rows(value, 1)).toThrow();
            expect(() => reader.read_rows(0, value)).toThrow();
            expect(() => reader.read_columns([value])).toThrow();
        }
        expect(() => reader.read_rows(0, 1, 2, 1)).toThrow();
        expect(() => reader.read_rows(0, 1, 0, 1, { chunk_rows: 0 })).toThrow();
        expect(() => ArrowBuffer.open(fixture('plain-none'), { max_output_rows: 2 }).read_rows(0, 3)).toThrow('max_output_rows');
        expect(() => ArrowBuffer.open(fixture('plain-zstd'), { max_buffer_bytes: 1 }).read_rows(0, 1)).toThrow('max_buffer_bytes');
    });
    test('metadata edits cannot change decoding or file geometry', async () => {
        const node = await ArrowFile.open(fixturePath('plain-none'));
        try {
            const before = await node.read_rows(0, 2);
            const metadata = node.metadata;
            metadata.nobs = 999;
            metadata.variables[0].type = 'utf8';
            metadata.variables.splice(1);
            node.get_dictionary(22)!.levels[0] = 'changed';
            expect(await node.read_rows(0, 2)).toEqual(before);
            expect(node.get_dictionary(22)!.levels[0]).toBe('low');
        } finally { node.close(); }
    });
    test('unknown or malformed profiles fail; explicit raw reads remain available', () => {
        const bytes = replaceLast(fixture('profile-none'), 'dtatools:profile-version', 'dtatools:profile-version');
        // Field corruption must affect only a projection that consumes the field.
        const malformed = replaceLast(bytes, '"storage":"byte"', '"storage":"nope"');
        const reader = ArrowBuffer.open(malformed);
        expect(() => reader.read_rows(0, 1, 0, 1)).toThrow('profile');
        expect(reader.read_rows(0, 1, 1, 2)).toEqual([[1]]);
        expect(() => reader.metadata).toThrow('profile');
        expect(ArrowBuffer.open(malformed, { profile: false }).read_rows(1, 1, 0, 1)).toEqual([[101]]);
        expect(ArrowBuffer.open(malformed, { profile: false }).metadata.profile_version).toBeUndefined();
        const unknown = fixture('profile-none'), fb = footerBuffer(unknown);
        const schema = fb.child(fb.root(), 1, true)!;
        const entry = fb.tables(schema, 2).find(table => fb.string(table, 0) === 'dtatools:profile-version')!;
        const value = fb.child(entry, 1, true)!;
        fb.bytes[value + 4] = 0x39;
        expect(() => ArrowBuffer.open(unknown)).toThrow('profile version 9');
        expect(ArrowBuffer.open(unknown, { profile: false }).read_rows(0, 1, 0, 1)).toEqual([[1]]);
    });
    test('checksum corruption is detected only for touched columns and batches', () => {
        const bytes = fixture('profile-none'), footer = readFooter(source(bytes));
        const batch = footer.batches[0], values = batch.buffers[1];
        bytes[batch.block.offset + batch.block.metadataLength + values.offset] ^= 1;
        expect(() => ArrowBuffer.open(bytes).read_rows(0, 1, 0, 1)).toThrow('checksum mismatch');
        expect(ArrowBuffer.open(bytes).read_rows(0, 1, 1, 2)).toEqual([[1]]);
        expect(ArrowBuffer.open(bytes, { verify: false }).read_rows(0, 1, 0, 1)).toEqual([[0]]);
        expect(ArrowBuffer.open(bytes, { profile: false }).read_rows(0, 1, 0, 1)).toEqual([[0]]);
    });
    test('bad magic, footer offsets and truncated buffers are rejected', () => {
        const bytes = fixture('plain-none');
        expect(() => ArrowBuffer.open(bytes.subarray(1))).toThrow();
        expect(() => ArrowBuffer.open(bytes.subarray(0, bytes.length - 1))).toThrow();
        const corrupt = bytes.slice();
        new DataView(corrupt.buffer).setUint32(corrupt.length - 10, 0xffffffff, true);
        expect(() => ArrowBuffer.open(corrupt)).toThrow('footer length');
    });
    test('oversized logical buffers are rejected instead of ignoring extra bytes', () => {
        const bytes = fixture('plain-none'), footer = readFooter(source(bytes)), block = footer.batches[0].block;
        const prefix = new DataView(bytes.buffer).getUint32(block.offset, true) === 0xffffffff ? 8 : 4;
        const fb = new FlatBuffer(bytes.subarray(block.offset + prefix, block.offset + block.metadataLength));
        const batch = fb.child(fb.root(), 2, true)!;
        const buffers = fb.vector(batch, 2, 16);
        const valueBuffer = buffers.start + 3 * 16;
        fb.view.setBigInt64(valueBuffer + 8, 3n, true);
        expect(() => ArrowBuffer.open(bytes).read_rows(0, 1, 1, 2)).toThrow('buffer length');
        expect(ArrowBuffer.open(bytes).read_rows(0, 1, 2, 3)).toEqual([[-32768]]);
    });
    test('projection reads selected buffers and skips other batch bodies and dictionaries', () => {
        const bytes = fixture('plain-zstd'), ranges: Array<[number, number]> = [];
        const footer = readFooter(source(bytes));
        const reader = new ArrowReader({ size: bytes.length, read(offset, length) { ranges.push([offset, length]); return bytes.subarray(offset, offset + length); } });
        ranges.length = 0;
        expect([...reader.chunks([0], 0, 1)][0].get(0)).toEqual([true]);
        const batch = footer.batches[0];
        const allowed = batch.buffers.slice(0, 2).filter(entry => entry.length).map(entry => [batch.block.offset + batch.block.metadataLength + entry.offset, entry.length]);
        expect(ranges).toEqual(allowed);
    });
    test('Node cancellation before and between chunks and file identity', async () => {
        const node = await ArrowFile.open(fixturePath('plain-none'));
        try {
            const controller = new AbortController();
            controller.abort();
            await expect(node.read_rows(0, 4, 0, 26, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' });
            const later = new AbortController();
            const reading = node.read_rows(0, 4, 0, 26, { signal: later.signal, chunk_rows: 1 });
            setImmediate(() => later.abort());
            await expect(reading).rejects.toMatchObject({ name: 'AbortError' });
            expect((await node.read_rows(0, 1)).length).toBe(1);
        } finally { node.close(); }
        const directory = mkdtempSync(join(tmpdir(), 'arrow-snapshot-'));
        try {
            const path = join(directory, 'data.arrow'), replacement = join(directory, 'new.arrow');
            writeFileSync(path, fixture('plain-none'));
            const file = await ArrowFile.open(path);
            try {
                writeFileSync(replacement, fixture('empty'));
                renameSync(replacement, path);
                expect((await file.read_rows(0, 1))[0][0]).toBe(true);
            } finally { file.close(); }
        } finally { rmSync(directory, { recursive: true, force: true }); }
    });
});
