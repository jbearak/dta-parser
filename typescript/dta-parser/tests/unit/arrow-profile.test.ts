import { describe, expect, test } from 'bun:test';
import { canonicalBufferHashes, xxh64 } from '../../src/arrow-checksum';
import { classifyProfileMissing, parseProfileJson, validateChecksumsDocument,
    validateDatasetDocument, validateFieldDocument, validateProfileVersion,
    validateValueLabelReference } from '../../src/arrow-profile';

const bytes = (text: string): Uint8Array => new TextEncoder().encode(text);
const integers = (values: number[], width = 4): Uint8Array => {
    const result = new Uint8Array(values.length * width);
    const view = new DataView(result.buffer);
    values.forEach((value, index) => width === 4
        ? view.setInt32(index * width, value, true)
        : view.setBigInt64(index * width, BigInt(value), true));
    return result;
};

describe('canonical Arrow checksums', () => {
    test('matches libxxhash 0.8.3 vectors across lane and tail boundaries', () => {
        // Reference values produced by the upstream XXH64 C function, seed zero.
        const vectors = [[0, 'ef46db3751d8e999'], [1, '72e2a190a8928fcf'],
            [3, '48569903e09d34bc'], [4, '20314ed83411020a'], [7, '01704c161f2cca23'],
            [8, 'd987b654aa7e1ccb'], [9, 'b00152bf74ca164f'], [15, '76b95b2a57a13122'],
            [16, '87e2e9897dfb0df6'], [31, 'fa27902339cb5a58'], [32, '94b268118fb56331'],
            [33, '4a8c5c67ec2cae61'], [63, '0d1167413545da0e'], [64, '5255a99ae2fc1f94'],
            [65, 'e21c1bb95335f4df'], [255, 'c57ec68f2fb44f08']] as const;
        for (const [length, hash] of vectors) {
            const data = Uint8Array.from({ length }, (_, i) => (i * 17 + 29) % 256);
            expect(xxh64(data).toString(16).padStart(16, '0')).toBe(hash);
            const padded = new Uint8Array(length + 7);
            padded.set(data, 3);
            expect(xxh64(padded.subarray(3, length + 3))).toBe(xxh64(data));
        }
    });

    test('masks bitmap padding and hashes validity before values', () => {
        const dirty = canonicalBufferHashes({ type: 'bool', length: 3,
            validity: Uint8Array.of(0xfd), buffers: [Uint8Array.of(0xfd)] });
        const clean = canonicalBufferHashes({ type: 'bool', length: 3,
            validity: Uint8Array.of(5), buffers: [Uint8Array.of(5)] });
        expect(dirty).toEqual(clean);
        expect(dirty).toHaveLength(2);
        expect(canonicalBufferHashes({ type: 'bool', length: 3, offset: 8,
            buffers: [Uint8Array.of(255, 5)] })).toEqual(clean.slice(1));
        expect(() => canonicalBufferHashes({ type: 'bool', length: 1, offset: 1,
            buffers: [Uint8Array.of(3)] })).toThrow('byte-aligned');
    });

    test('rebases string offsets and ignores bytes outside the logical slice', () => {
        for (const [type, width] of [['utf8', 4], ['large-utf8', 8]] as const) {
            const sliced = canonicalBufferHashes({ type, length: 2, offset: 2,
                buffers: [integers([0, 5, 5, 9, 14], width), bytes('alphabetagamma-padding')] });
            const rebuilt = canonicalBufferHashes({ type, length: 2,
                buffers: [integers([0, 4, 9], width), bytes('betagamma')] });
            expect(sliced).toEqual(rebuilt);
            expect(() => canonicalBufferHashes({ type, length: 2,
                buffers: [integers([0, 3, 2], width), bytes('abc')] })).toThrow('offsets');
            expect(() => canonicalBufferHashes({ type, length: 2,
                buffers: [integers([0, 3, 6], width), bytes('abc')] })).toThrow('too short');
        }
    });

    test('dictionary arrays hash only logical key bytes', () => {
        const dictionary = canonicalBufferHashes({ type: 'dictionary', dictionaryKeyType: 'int32',
            length: 2, offset: 1, buffers: [integers([99, 2, 0, 99])] });
        expect(dictionary).toEqual(canonicalBufferHashes({ type: 'int32', length: 2,
            buffers: [integers([2, 0])] }));
        expect(dictionary).toHaveLength(1);
        expect(() => canonicalBufferHashes({ type: 'int32', length: 3,
            buffers: [integers([1, 2])] })).toThrow('too short');
    });
});

describe('Arrow profile documents', () => {
    test('requires paired Unicode surrogates in JSON keys and values', () => {
        for (const value of ['\\ud800', '\\udfff', '\\ud800x', '\\ud800\\ud800', '\\udfff\\ud800']) {
            expect(() => parseProfileJson(`{"version":0,"label":"${value}"}`)).toThrow('surrogate');
            expect(() => parseProfileJson(`{"${value}":0}`)).toThrow('surrogate');
        }
        expect(parseProfileJson('{"\\ud83d\\ude00":"\\ud83d\\ude00"}')).toEqual({ '😀': '😀' });
        expect(validateDatasetDocument(parseProfileJson('{"version":0,"label":"😀"}')).label).toBe('😀');
    });

    test('requires supported versions and strict JSON keys', () => {
        expect(() => validateProfileVersion('1')).toThrow('Unsupported');
        for (const json of ['{"version":0,"version":0}', '{"x":[],"\\u0078":[]}',
            '{"version":0,}', '[1,]', '{"version":0} true']) {
            expect(() => parseProfileJson(json)).toThrow();
        }
        for (const raw of [{ version: 1 }, { version: 0, lable: 'typo' }, { version: 0, label: null }]) {
            expect(() => validateDatasetDocument(raw)).toThrow();
        }
        expect(validateDatasetDocument(parseProfileJson('{"version":0,"label":"a\\\"b","notes":["first"]}')).notes)
            .toEqual([{ number: 1, text: 'first' }]);
        expect(validateDatasetDocument(undefined).value_labels).toEqual({});
    });

    test('preserves output provenance while checking its shape', () => {
        expect(validateDatasetDocument({ version: 0, output_container: 'matrix' }).output_container).toBe('matrix');
        for (const output_container of ['', ' tibble', 'tibble ']) {
            expect(() => validateDatasetDocument({ version: 0, output_container })).toThrow('output_container');
        }
    });

    test('validates bounded ascending notes and canonical characteristics', () => {
        const valid = { version: 0, notes: [{ number: 2, text: 'first' }, { number: 5, text: 'last' }],
            characteristics: [{ name: 'source', value: 'fixture' }] };
        expect(validateDatasetDocument(valid).notes).toEqual(valid.notes);
        for (const notes of [[{ number: 2, text: 'a' }, { number: 1, text: 'b' }],
            [{ number: 1, text: 'a' }, { number: 1, text: 'b' }], [{ number: 0, text: '' }],
            [{ number: 1, text: 'bad\0' }], [{ number: 1, text: 'x'.repeat(67785) }]]) {
            expect(() => validateDatasetDocument({ version: 0, notes })).toThrow();
        }
        for (const name of ['note1', '_lang_list', '', 'bad name']) {
            expect(() => validateDatasetDocument({ version: 0, characteristics: [{ name, value: '' }] })).toThrow();
        }
        expect(() => validateDatasetDocument({ version: 0, characteristics: [valid.characteristics[0], valid.characteristics[0]] })).toThrow();
    });

    test('projections validate discarded label entries and preserve special names safely', () => {
        const valid = parseProfileJson('{"version":0,"value_labels":{"__proto__":[{"value":1,"label":"one"}],"other":[{"tag":".z","label":"last"}]}}');
        const selected = validateDatasetDocument(valid, new Set(['__proto__']));
        expect(Object.keys(selected.value_labels)).toEqual(['__proto__']);
        expect(selected.value_labels.__proto__).toEqual([{ value: 1, label: 'one' }]);
        for (const entry of [{ label: 'none' }, { value: 1, tag: '.a', label: 'both' },
            { tag: '.', label: 'system' }, { value: 2147483648, label: 'large' }, { value: 1, label: 7 }]) {
            expect(() => validateDatasetDocument({ version: 0, value_labels: { discarded: [entry] } }, new Set())).toThrow();
        }
    });

    test('checks storage, semantic class, and label references against physical fields', () => {
        const field = { name: 'x', type: 'int8', nullable: false };
        const doc = validateFieldDocument({ version: 0, storage: 'byte', missing: 'sentinel', value_labels: 'labels' }, field);
        expect(doc.storage).toBe('byte');
        expect(() => validateValueLabelReference(field, doc, validateDatasetDocument(undefined))).toThrow('missing value-label');
        expect(() => validateFieldDocument({ version: 0, storage: 'byte', missing: 'sentinel' }, { ...field, nullable: true })).toThrow('nullable');
        expect(() => validateFieldDocument({ version: 0, storage: 'byte', missing: 'payload' }, field)).toThrow('missing encoding');
        expect(() => validateFieldDocument({ version: 0, r: { class: 'Date' } }, field)).toThrow('R class');
        expect(() => validateFieldDocument({ version: 0, r: { class: 'integer', ordered: false } }, field)).toThrow('ordered');
        expect(() => validateFieldDocument({ version: 0, missing: 'payload', r: { class: 'double' } }, { name: 'x', type: 'float64', nullable: true })).toThrow('payload');
        expect(validateFieldDocument({ version: 0, r: { class: 'factor', ordered: true } },
            { name: 'f', type: 'dictionary', nullable: true, dictionaryKeyType: 'int32', dictionaryValueType: 'utf8' }).r?.ordered).toBe(true);
    });

    test('accepts only compatible string storage and checksum documents', () => {
        const field = { name: 's', type: 'utf8', nullable: true };
        for (const string_storage of ['str0', 'str01', 'str2046', 'STR12']) {
            expect(() => validateFieldDocument({ version: 0, string_storage }, field)).toThrow('string storage');
        }
        expect(() => validateFieldDocument({ version: 0, string_storage: 'str12' }, { ...field, type: 'large-utf8' })).toThrow('string storage');
        expect(validateChecksumsDocument({ version: 0, algorithm: 'xxh64', batches: [] }).dictionaries).toEqual({});
        expect(() => validateChecksumsDocument({ version: 0, algorithm: 'md5', batches: [] })).toThrow('algorithm');
        expect(() => validateChecksumsDocument({ version: 0, algorithm: 'xxh64', batches: [{ columns: [], colums: [] }] })).toThrow('unknown field');
    });
});

describe('profile missing bit patterns', () => {
    test('classifies all Stata missing codes without treating plain floats as profiled', () => {
        const bytes = new Uint8Array(8);
        const view = new DataView(bytes.buffer);
        for (const [storage, type] of [['byte', 'int8'], ['int', 'int16'], ['long', 'int32'], ['float', 'float32'], ['double', 'float64']] as const) {
            const doc = validateFieldDocument({ version: 0, storage,
                missing: storage === 'float' || storage === 'double' ? 'payload' : 'sentinel' }, { name: 'x', type, nullable: false });
            for (let code = 0; code <= 26; code++) {
                if (storage === 'byte') view.setInt8(0, 101 + code);
                if (storage === 'int') view.setInt16(0, 32741 + code, true);
                if (storage === 'long') view.setInt32(0, 2147483621 + code, true);
                if (storage === 'float') view.setUint32(0, 0x7f000000 + code * 0x800, true);
                if (storage === 'double') view.setBigUint64(0, 0x7fe0000000000000n + BigInt(code) * 0x10000000000n, true);
                expect(classifyProfileMissing(bytes, 0, doc)?.missing_type).toBe(code === 0 ? '.' : `.${String.fromCharCode(96 + code)}`);
                expect(classifyProfileMissing(bytes, 0, validateFieldDocument({ version: 0 }, { name: 'x', type, nullable: true }))).toBeNull();
            }
        }
    });

    test('handles legacy compact storage and canonical R/haven tags', () => {
        const legacy = validateFieldDocument({ version: 0, storage: 'byte', missing: 'sentinel', missing_release: 111 },
            { name: 'x', type: 'int8', nullable: false });
        expect(classifyProfileMissing(Uint8Array.of(101), 0, legacy)).toBeNull();
        expect(classifyProfileMissing(Uint8Array.of(127), 0, legacy)?.missing_type).toBe('.');
        const payload = validateFieldDocument({ version: 0, missing: 'payload', r: { class: 'Date' } },
            { name: 'date', type: 'float64', nullable: false });
        const bytes = new Uint8Array(8);
        const view = new DataView(bytes.buffer);
        for (let code = 0; code <= 26; code++) {
            const tag = code === 0 ? 0 : 96 + code;
            for (const ignored of [0n, 0x8000000000000000n, 0x0008000000000000n]) {
                view.setBigUint64(0, 0x7ff00000000007a2n | BigInt(tag) << 32n | ignored, true);
                expect(classifyProfileMissing(bytes, 0, payload)?.missing_type).toBe(code === 0 ? '.' : `.${String.fromCharCode(96 + code)}`);
            }
        }
        for (const ordinary of [0x7ff8000000000000n, 0x7ff00000000007a3n, 0x7ff00041000007a2n, 0x7ff10000000007a2n]) {
            view.setBigUint64(0, ordinary, true);
            expect(classifyProfileMissing(bytes, 0, payload)).toBeNull();
        }
    });
});
