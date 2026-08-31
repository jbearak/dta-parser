import { describe, it, expect, afterEach, spyOn } from 'bun:test';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
    DtaFile,
    listStataNotes,
    make_missing_value,
} from '../../src/node';
import { parse_legacy_metadata } from '../../src/legacy-header';
import { parse_metadata } from '../../src/header';
import {
    V119_STRL_VALUE,
    v119_strl_fixture,
} from '../helpers/v119-strl-fixture';

// -----------------------------------------------------------
// DtaFile public API integration tests
// -----------------------------------------------------------

const FIXTURE_DIR = path.resolve(
    __dirname, '../../../../tests/fixtures/dta'
);
const V111_FIXTURE = path.resolve(
    __dirname, '../../../../r-package/dtatools/src/dta-tools/tests/data/synthetic-v111.dta'
);

function wideV119MetadataFixture(nvar: number): Buffer {
    const headerPrefix = Buffer.from(
        '<stata_dta><header><release>119</release>'
        + '<byteorder>LSF</byteorder><K>',
        'ascii'
    );
    const headerSuffix = Buffer.from(
        '</K><N>\0\0\0\0\0\0\0\0</N><label>\0\0</label>'
        + '<timestamp>\0</timestamp></header>',
        'ascii'
    );
    const headerLength = headerPrefix.length + 4 + headerSuffix.length;
    const sectionLengths = [
        '<map>'.length + 14 * 8 + '</map>'.length,
        '<variable_types>'.length + nvar * 2 + '</variable_types>'.length,
        '<varnames>'.length + nvar * 129 + '</varnames>'.length,
        '<sortlist>'.length + (nvar + 1) * 4 + '</sortlist>'.length,
        '<formats>'.length + nvar * 57 + '</formats>'.length,
        '<value_label_names>'.length + nvar * 129
            + '</value_label_names>'.length,
        '<variable_labels>'.length + nvar * 321
            + '</variable_labels>'.length,
        '<characteristics></characteristics>'.length,
        '<data></data>'.length,
        '<strls></strls>'.length,
        '<value_labels></value_labels>'.length,
        '</stata_dta>'.length,
    ];
    const totalLength = headerLength
        + sectionLengths.reduce((sum, length) => sum + length, 0);
    const output = Buffer.alloc(totalLength);
    let position = 0;
    const writeAscii = (value: string): void => {
        position += output.write(value, position, 'ascii');
    };

    headerPrefix.copy(output, position);
    position += headerPrefix.length;
    output.writeUInt32LE(nvar, position);
    position += 4;
    headerSuffix.copy(output, position);
    position += headerSuffix.length;

    const offsets = new Array<number>(14).fill(0);
    offsets[1] = position;
    writeAscii('<map>');
    const mapPayload = position;
    position += 14 * 8;
    writeAscii('</map>');

    offsets[2] = position;
    writeAscii('<variable_types>');
    for (let index = 0; index < nvar; index++) {
        output.writeUInt16LE(65_530, position + index * 2);
    }
    position += nvar * 2;
    writeAscii('</variable_types>');

    offsets[3] = position;
    writeAscii('<varnames>');
    for (let index = 0; index < nvar; index++) {
        output.write(`v${index}`, position + index * 129, 'ascii');
    }
    position += nvar * 129;
    writeAscii('</varnames>');

    offsets[4] = position;
    writeAscii('<sortlist>');
    position += (nvar + 1) * 4;
    writeAscii('</sortlist>');

    offsets[5] = position;
    writeAscii('<formats>');
    for (let index = 0; index < nvar; index++) {
        output.write('%8.0g', position + index * 57, 'ascii');
    }
    position += nvar * 57;
    writeAscii('</formats>');

    offsets[6] = position;
    writeAscii('<value_label_names>');
    position += nvar * 129;
    writeAscii('</value_label_names>');

    offsets[7] = position;
    writeAscii('<variable_labels>');
    position += nvar * 321;
    writeAscii('</variable_labels>');

    offsets[8] = position;
    writeAscii('<characteristics></characteristics>');
    offsets[9] = position;
    writeAscii('<data></data>');
    offsets[10] = position;
    writeAscii('<strls></strls>');
    offsets[11] = position;
    writeAscii('<value_labels></value_labels>');
    offsets[12] = position;
    writeAscii('</stata_dta>');
    offsets[13] = position;

    expect(position).toBe(output.length);
    for (let index = 0; index < offsets.length; index++) {
        output.writeBigUInt64LE(BigInt(offsets[index]), mapPayload + index * 8);
    }
    return output;
}

let my_file: DtaFile | null = null;

afterEach(() => {
    my_file?.close();
    my_file = null;
});

describe('DtaFile', () => {

    // ----- open + metadata -----

    describe('open and metadata', () => {
        it('opens and reads metadata from auto_v118.dta', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            expect(my_file.nobs).toBe(74);
            expect(my_file.nvar).toBe(12);
            expect(my_file.variables.length).toBe(12);
            expect(my_file.metadata.notes).toEqual([
                { number: 1, text: 'From Consumer Reports with permission' },
            ]);
            expect(listStataNotes(my_file.metadata)).toEqual(my_file.metadata.notes);
        });

        it('provides dataset label', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'value_labels.dta')
            );
            expect(my_file.dataset_label).toBe(
                'Value labels test dataset'
            );
        });

        it('provides variable names', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_names = my_file.variables.map(
                v => v.name
            );
            expect(the_names).toEqual([
                'make', 'price', 'mpg', 'rep78',
                'headroom', 'trunk', 'weight', 'length',
                'turn', 'displacement', 'gear_ratio',
                'foreign',
            ]);
        });

        it('keeps file read geometry isolated from editable metadata', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const expected = await my_file.read_rows(0, 74);
            const metadata = my_file.metadata;

            metadata.nobs = 0;
            metadata.nvar = 1;
            metadata.obs_length = 1;
            metadata.section_offsets.data = 0;
            metadata.section_offsets.strls = 0;
            metadata.section_offsets.value_labels = 0;
            metadata.variables[0].type = 'double';
            metadata.variables[0].byte_width = 8;
            metadata.variables[0].byte_offset = 999_999;
            metadata.variables.length = 0;
            metadata.byte_order = 'MSF';
            metadata.format_version = 117;
            metadata.text_encoding = 'iso-8859-1';

            expect(my_file.nobs).toBe(74);
            expect(my_file.nvar).toBe(12);
            expect(await my_file.read_rows(0, 2)).toEqual(expected.slice(0, 2));
            expect(await my_file.read_columns([0, 1])).toEqual(new Map([
                [0, expected.map(row => row[0])],
                [1, expected.map(row => row[1])],
            ]));
        });
    });

    // ----- read_rows -----

    describe('read_rows', () => {
        it('reads the first row', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_rows = await my_file.read_rows(0, 1);
            expect(the_rows.length).toBe(1);
            expect(the_rows[0].length).toBe(12);

            // make is a string
            expect(typeof the_rows[0][0]).toBe('string');
            expect(
                (the_rows[0][0] as string).length
            ).toBeGreaterThan(0);

            // price is numeric
            expect(typeof the_rows[0][1]).toBe('number');
            expect(
                the_rows[0][1] as number
            ).toBeGreaterThan(0);
        });

        it('reads all 74 rows', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_rows = await my_file.read_rows(0, 74);
            expect(the_rows.length).toBe(74);

            for (const my_row of the_rows) {
                expect(my_row.length).toBe(12);
            }
        });

        it('clamps count past end of data', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_rows = await my_file.read_rows(70, 10);
            expect(the_rows.length).toBe(4);
        });

        it('preserves extended missing values exactly', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'missing_values.dta')
            );
            const the_rows = await my_file.read_rows(0, 5);
            expect(the_rows[0][0]).toEqual(
                make_missing_value('.')
            );
            expect(the_rows[1][0]).toEqual(
                make_missing_value('.a')
            );
            expect(the_rows[2][0]).toEqual(
                make_missing_value('.b')
            );
            expect(the_rows[4][0]).toEqual(
                make_missing_value('.z')
            );
        });
    });

    // ----- column subsetting -----

    describe('column subsetting', () => {
        it('reads rows with column subsetting', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            // Only columns 0..3 (make, price, mpg)
            const the_rows = await my_file.read_rows(
                0, 1, 0, 3
            );
            expect(the_rows.length).toBe(1);
            expect(the_rows[0].length).toBe(3);

            // Verify values match full read
            const the_full = await my_file.read_rows(0, 1);
            expect(the_rows[0][0]).toEqual(the_full[0][0]);
            expect(the_rows[0][1]).toEqual(the_full[0][1]);
            expect(the_rows[0][2]).toEqual(the_full[0][2]);
        });
    });

    // ----- value labels -----

    describe('value label tables', () => {
        it('provides value label tables', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'value_labels.dta')
            );
            const my_tables = my_file.value_label_tables;
            expect(my_tables.size).toBeGreaterThan(0);

            // foreign_lbl: 0 = "Domestic", 1 = "Foreign"
            const my_foreign = my_tables.get('foreign_lbl');
            expect(my_foreign).toBeDefined();
            expect(my_foreign!.get(0)).toBe('Domestic');
            expect(my_foreign!.get(1)).toBe('Foreign');

            // rep_lbl has 5 entries
            const my_rep = my_tables.get('rep_lbl');
            expect(my_rep).toBeDefined();
            expect(my_rep!.size).toBe(5);
            expect(my_rep!.get(1)).toBe('Poor');
            expect(my_rep!.get(5)).toBe('Excellent');
        });
    });

    // ----- strL resolution -----

    describe('strL resolution', () => {
        it('resolves strL values (strl_test.dta)', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'strl_test.dta')
            );

            // Find the strL column index
            const my_strl_idx = my_file.variables
                .findIndex(v => v.type === 'strL');
            expect(my_strl_idx).toBeGreaterThanOrEqual(0);

            const the_rows = await my_file.read_rows(0, 5);
            expect(the_rows.length).toBe(5);

            // All strL cells should be resolved strings,
            // not the "__strl__" placeholder
            for (const my_row of the_rows) {
                const my_cell = my_row[my_strl_idx];
                expect(typeof my_cell).toBe('string');
                expect(my_cell).not.toBe('__strl__');
            }

            // Obs 1: "This is observation 1"
            expect(the_rows[0][my_strl_idx]).toBe(
                'This is observation 1'
            );

            // Obs 4 (index 3): empty string (v=0, o=0)
            expect(the_rows[3][my_strl_idx]).toBe('');

            // Obs 3 has extra padding
            expect(
                (the_rows[2][my_strl_idx] as string).length
            ).toBeGreaterThan(
                (the_rows[0][my_strl_idx] as string).length
            );
        });

        it('resolves strL values from v118 format', async () => {
            my_file = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'strl_test_v118.dta'
                )
            );

            const my_strl_idx = my_file.variables
                .findIndex(v => v.type === 'strL');
            expect(my_strl_idx).toBeGreaterThanOrEqual(0);

            const the_rows = await my_file.read_rows(0, 1);
            const my_cell = the_rows[0][my_strl_idx];
            expect(typeof my_cell).toBe('string');
            expect(my_cell).not.toBe('__strl__');
            expect(
                (my_cell as string).length
            ).toBeGreaterThan(0);
        });

        it('resolves release-119 strLs in both byte orders', async () => {
            for (const my_byte_order of ['LSF', 'MSF'] as const) {
                const my_directory = fs.mkdtempSync(
                    path.join(os.tmpdir(), 'dta-v119-strl-')
                );
                const my_path = path.join(
                    my_directory, `${my_byte_order}.dta`
                );
                try {
                    fs.writeFileSync(
                        my_path,
                        new Uint8Array(v119_strl_fixture(my_byte_order))
                    );
                    my_file = await DtaFile.open(my_path);
                    expect(my_file.format_version).toBe(119);
                    expect(await my_file.read_rows(0, 1)).toEqual([
                        [V119_STRL_VALUE],
                    ]);
                    my_file.close();
                    my_file = null;
                } finally {
                    fs.rmSync(my_directory, {
                        recursive: true,
                        force: true,
                    });
                }
            }
        });

        it('resolves strL in all_types.dta', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'all_types.dta')
            );

            // v_strL is index 7
            const my_strl_idx = my_file.variables
                .findIndex(v => v.type === 'strL');
            expect(my_strl_idx).toBe(7);

            const the_rows = await my_file.read_rows(0, 5);
            for (let i = 0; i < 5; i++) {
                const my_cell = the_rows[i][my_strl_idx];
                expect(typeof my_cell).toBe('string');
                expect(my_cell).not.toBe('__strl__');
                expect(my_cell).toContain(
                    'strL value for obs ' + (i + 1)
                );
            }
        });
    });

    // ----- cross-version -----

    describe('cross-version compatibility', () => {
        it('handles v117 format', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v117.dta')
            );
            expect(my_file.nobs).toBe(74);
            expect(my_file.nvar).toBe(12);

            const the_rows = await my_file.read_rows(0, 1);
            expect(the_rows.length).toBe(1);
            expect(typeof the_rows[0][0]).toBe('string');
        });

        it('produces same data across v117 and v118', async () => {
            const my_f117 = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v117.dta')
            );
            const my_f118 = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );

            const the_rows_117 =
                await my_f117.read_rows(0, 5);
            const the_rows_118 =
                await my_f118.read_rows(0, 5);
            expect(the_rows_117).toEqual(the_rows_118);

            my_f117.close();
            my_f118.close();
        });
    });

    // ----- legacy format (v115) -----

    describe('legacy format v111', () => {
        it('reads metadata, rows, missing tags, labels, and projections', async () => {
            my_file = await DtaFile.open(V111_FIXTURE);
            expect(my_file.format_version).toBe(111);
            expect(my_file.dataset_label).toBe('Stata/SE 7 Café fixture');
            expect(my_file.nvar).toBe(6);
            expect(my_file.nobs).toBe(4);
            expect(my_file.variables.map(variable => variable.name)).toEqual([
                'b', 'i', 'l', 'f', 'd', 'text',
            ]);
            expect(my_file.value_label_tables.get('b_labels')?.get(1)).toBe('One');

            const the_rows = await my_file.read_rows(0, 4);
            expect(the_rows[0]).toEqual([1, 321, -123456, 1.5, -2.25, 'alpha']);
            for (let column = 0; column < 3; column++) {
                expect(the_rows[1][column]).not.toEqual(make_missing_value('.'));
                expect(the_rows[2][column]).not.toEqual(make_missing_value('.'));
                expect(the_rows[3][column]).toEqual(make_missing_value('.'));
            }
            for (let column = 3; column < 5; column++) {
                expect(the_rows[1][column]).toEqual(make_missing_value('.'));
                expect(the_rows[2][column]).toEqual(make_missing_value('.'));
                expect(the_rows[3][column]).toEqual(make_missing_value('.'));
            }
            expect(the_rows.map(row => row[5])).toEqual(['alpha', '', 'Café', 'omega']);

            const the_columns = await my_file.read_columns([5, 0]);
            expect(the_columns.get(5)?.slice(1, 3)).toEqual(['', 'Café']);
            expect(the_columns.get(0)?.slice(1, 3)).toEqual([
                101, 102,
            ]);
        });

        it('scans characteristics beyond the initial 64 KiB metadata window', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            expect(metadata.notes).toEqual([
                { number: 1, text: 'Release 111 note' },
            ]);
            const expansion = metadata.section_offsets.characteristics;
            const oldLength = original.readInt32LE(expansion + 1);
            const names = original.subarray(expansion + 5, expansion + 5 + 66);
            const payload = Buffer.concat([
                names,
                Buffer.alloc(67_000, 0x78),
                Buffer.from([0]),
            ]);
            const header = Buffer.alloc(5);
            header[0] = 1;
            header.writeInt32LE(payload.length, 1);
            const enlarged = Buffer.concat([
                original.subarray(0, expansion),
                header,
                payload,
                original.subarray(expansion + 5 + oldLength),
            ]);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'large-note.dta');
            try {
                fs.writeFileSync(filePath, enlarged);
                my_file = await DtaFile.open(filePath);
                expect(my_file.nobs).toBe(4);
                expect((await my_file.read_rows(0, 1))[0][0]).toBe(1);
            } finally {
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('bounds accepted legacy values and skips structural payloads', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            const expansion = metadata.section_offsets.characteristics;
            const oldLength = original.readInt32LE(expansion + 1);
            const names = original.subarray(expansion + 5, expansion + 5 + 66);
            const payload = Buffer.concat([
                names,
                Buffer.alloc(67_784, 0x78),
                Buffer.from([0]),
            ]);
            const header = Buffer.alloc(5);
            header[0] = 1;
            header.writeInt32LE(payload.length, 1);
            const exactWithNul = Buffer.concat([
                original.subarray(0, expansion),
                header,
                payload,
                original.subarray(expansion + 5 + oldLength),
            ]);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'over-limit-note.dta');
            try {
                fs.writeFileSync(filePath, exactWithNul);
                my_file = await DtaFile.open(filePath);
                expect(my_file.metadata.notes).not.toHaveLength(0);

                const oversized = Buffer.from(exactWithNul);
                const finalValueByte = expansion + 5 + 66 + 67_785 - 1;
                expect(oversized[finalValueByte]).toBe(0);
                oversized[finalValueByte] = 0x78;
                fs.writeFileSync(filePath, oversized);
                await expect(DtaFile.open(filePath)).rejects.toThrow('67,784-byte limit');

                const reservedOversized = Buffer.from(oversized);
                const name = expansion + 5 + 33;
                reservedOversized.fill(0, name, name + 33);
                reservedOversized.write('note0', name, 'ascii');
                fs.writeFileSync(filePath, reservedOversized);
                const ignored = await DtaFile.open(filePath);
                expect(ignored.metadata.notes).toEqual([]);
                expect(ignored.metadata.characteristics).toEqual([]);
                ignored.close();
            } finally {
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('rejects invalid raw legacy characteristic names', async () => {
            const malformed = Buffer.from(fs.readFileSync(V111_FIXTURE));
            const arrayBuffer = malformed.buffer.slice(
                malformed.byteOffset,
                malformed.byteOffset + malformed.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, malformed.length);
            const name = metadata.section_offsets.characteristics + 5 + 33;
            malformed.fill(0, name, name + 33);
            malformed.write('2bad', name, 'ascii');
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'invalid-name.dta');
            try {
                fs.writeFileSync(filePath, malformed);
                await expect(DtaFile.open(filePath)).rejects.toThrow(
                    'Invalid on-disk Stata characteristic name'
                );
            } finally {
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('bounds oversized release-111 metadata before reading its payload', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            const expansion = metadata.section_offsets.characteristics;
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'oversized-note.dta');
            const fieldLength = 64 * 1024 * 1024;
            const header = Buffer.alloc(5);
            header[0] = 1;
            header.writeInt32LE(fieldLength, 1);
            let fileDescriptor: number | null = null;
            try {
                fileDescriptor = fs.openSync(filePath, 'w');
                fs.writeSync(fileDescriptor, original.subarray(0, expansion));
                fs.writeSync(fileDescriptor, header);
                fs.ftruncateSync(fileDescriptor, expansion + 5 + fieldLength);
                fs.closeSync(fileDescriptor);
                fileDescriptor = null;
                await expect(DtaFile.open(filePath)).rejects.toThrow(
                    'Legacy metadata exceeds 64 MiB safety limit'
                );
            } finally {
                if (fileDescriptor !== null) fs.closeSync(fileDescriptor);
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('scans dense expansion headers through bounded read blocks', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            const expansion = metadata.section_offsets.characteristics;
            const recordCount = 50_000;
            const records = Buffer.alloc(recordCount * 5 + 5);
            for (let offset = 0; offset < recordCount * 5; offset += 5) {
                records[offset] = 1;
            }
            const dense = Buffer.concat([
                original.subarray(0, expansion),
                records,
                original.subarray(metadata.section_offsets.data),
            ]);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'dense-expansions.dta');
            const readSpy = spyOn(fs, 'readSync');
            try {
                fs.writeFileSync(filePath, dense);
                my_file = await DtaFile.open(filePath);
                expect(my_file.nobs).toBe(4);
                expect(readSpy.mock.calls.length).toBeLessThan(100);
                const bytesRead = readSpy.mock.calls.reduce(
                    (total, call) => total + Number(call[3]), 0
                );
                expect(bytesRead).toBeLessThan(dense.length + 128 * 1024);
            } finally {
                readSpy.mockRestore();
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('does not reread large legacy expansion payloads while locating data', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            const expansion = metadata.section_offsets.characteristics;
            const recordCount = 32;
            const valueLength = 67_784;
            const records: Buffer[] = [];
            for (let index = 0; index < recordCount; index++) {
                const payload = Buffer.alloc(66 + valueLength);
                payload.write('_dta', 0, 'ascii');
                payload.write(`c${index}`, 33, 'ascii');
                payload.fill(120, 66);
                const header = Buffer.alloc(5);
                header[0] = 1;
                header.writeInt32LE(payload.length, 1);
                records.push(header, payload);
            }
            records.push(Buffer.alloc(5));
            const large = Buffer.concat([
                original.subarray(0, expansion),
                ...records,
                original.subarray(metadata.section_offsets.data),
            ]);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'large-expansions.dta');
            const readSpy = spyOn(fs, 'readSync');
            try {
                fs.writeFileSync(filePath, large);
                my_file = await DtaFile.open(filePath);
                expect(my_file.metadata.characteristics).toHaveLength(recordCount);
                const bytesRead = readSpy.mock.calls.reduce(
                    (total, call) => total + Number(call[3]),
                    0
                );
                expect(bytesRead).toBeLessThan(large.length + 256 * 1024);
            } finally {
                readSpy.mockRestore();
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('rejects truncated release-111 observations during open', async () => {
            const original = fs.readFileSync(V111_FIXTURE);
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_legacy_metadata(arrayBuffer, original.length);
            const truncated = original.subarray(0, metadata.section_offsets.value_labels - 1);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-'));
            const filePath = path.join(directory, 'truncated.dta');
            try {
                fs.writeFileSync(filePath, truncated);
                await expect(DtaFile.open(filePath)).rejects.toThrow(
                    'Truncated legacy observation data'
                );
            } finally {
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });
    });

    describe('modern metadata bounds', () => {
        it('rejects an oversized map without prefix retries', async () => {
            const original = Buffer.from(fs.readFileSync(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            ));
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_metadata(arrayBuffer);
            const mapData = metadata.section_offsets.map + '<map>'.length;
            original.writeBigUInt64LE(BigInt(65 * 1024 * 1024), mapData + 9 * 8);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v118-'));
            const filePath = path.join(directory, 'oversized-metadata.dta');
            const readSpy = spyOn(fs, 'readSync');
            try {
                fs.writeFileSync(filePath, original);
                await expect(DtaFile.open(filePath)).rejects.toThrow(
                    'Modern metadata exceeds its dimensioned safety limit'
                );
                const prefixReads = readSpy.mock.calls
                    .filter(call => Number(call[4]) === 0)
                    .map(call => call[3] as number);
                expect(prefixReads[0]).toBeLessThanOrEqual(1024);
                expect(Math.max(...prefixReads)).toBeLessThan(original.length);
            } finally {
                readSpy.mockRestore();
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('opens release-119 fixed metadata at the 120,000-variable limit', async () => {
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v119-wide-'));
            const filePath = path.join(directory, 'wide-metadata.dta');
            try {
                fs.writeFileSync(filePath, wideV119MetadataFixture(120_000));
                expect(fs.statSync(filePath).size).toBeGreaterThan(64 * 1024 * 1024);
                my_file = await DtaFile.open(filePath);
                expect(my_file.nvar).toBe(120_000);
                expect(my_file.nobs).toBe(0);
                expect(my_file.variables[119_999].name).toBe('v119999');
                const readPlan = (
                    my_file as unknown as {
                        _read_plan: {
                            variables: readonly Record<string, unknown>[];
                            section_offsets: Record<string, unknown>;
                        };
                    }
                )._read_plan;
                expect(Object.isFrozen(readPlan)).toBeTrue();
                expect(Object.isFrozen(readPlan.variables)).toBeTrue();
                expect(Object.isFrozen(readPlan.variables[119_999])).toBeTrue();
                expect(Object.keys(readPlan.variables[119_999]).sort()).toEqual([
                    'byte_offset', 'byte_width', 'type',
                ]);
                expect(Object.keys(readPlan.section_offsets).sort()).toEqual([
                    'data', 'strls', 'value_labels',
                ]);
            } finally {
                my_file?.close();
                my_file = null;
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });

        it('starts modern opens with a small map read and extends exactly once', async () => {
            const filePath = path.join(FIXTURE_DIR, 'auto_v118.dta');
            const readSpy = spyOn(fs, 'readSync');
            try {
                my_file = await DtaFile.open(filePath);
                const reads = readSpy.mock.calls.map(call => ({
                    length: Number(call[3]),
                    offset: Number(call[4]),
                }));
                expect(reads[1]).toEqual({ length: 1024, offset: 0 });
                expect(reads.filter(read => read.offset === 0)).toHaveLength(2);
                expect(reads.some(read => read.length === 128 * 1024)).toBeFalse();
            } finally {
                readSpy.mockRestore();
            }
        });

        it('does not resolve mapped metadata tags beyond the data boundary', async () => {
            const original = Buffer.from(fs.readFileSync(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            ));
            const arrayBuffer = original.buffer.slice(
                original.byteOffset,
                original.byteOffset + original.byteLength
            );
            const metadata = parse_metadata(arrayBuffer);
            const mapData = metadata.section_offsets.map + '<map>'.length;
            const variableTypes = metadata.section_offsets.variable_types;
            const injected = metadata.section_offsets.data + '<data>'.length;
            const payloadLength = '<variable_types>'.length + metadata.nvar * 2;
            original.copy(
                original, injected, variableTypes, variableTypes + payloadLength
            );
            original.writeBigUInt64LE(BigInt(injected), mapData + 2 * 8);
            const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v118-'));
            const filePath = path.join(directory, 'post-data-metadata-tag.dta');
            try {
                fs.writeFileSync(filePath, original);
                await expect(DtaFile.open(filePath)).rejects.toThrow(
                    'Missing <variable_types> tag'
                );
            } finally {
                fs.rmSync(directory, { recursive: true, force: true });
            }
        });
    });

    describe('legacy format v115', () => {
        it('opens and reads metadata from auto_v115.dta', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            expect(my_file.nobs).toBe(74);
            expect(my_file.nvar).toBe(12);
            expect(my_file.variables.length).toBe(12);
        });

        it('provides variable names matching modern format', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            const the_names = my_file.variables.map(
                v => v.name
            );
            expect(the_names).toEqual([
                'make', 'price', 'mpg', 'rep78',
                'headroom', 'trunk', 'weight', 'length',
                'turn', 'displacement', 'gear_ratio',
                'foreign',
            ]);
        });

        it('reads the first row', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            const the_rows = await my_file.read_rows(0, 1);
            expect(the_rows.length).toBe(1);
            expect(the_rows[0].length).toBe(12);

            // make is a string
            expect(typeof the_rows[0][0]).toBe('string');
            expect(
                (the_rows[0][0] as string).length
            ).toBeGreaterThan(0);

            // price is numeric
            expect(typeof the_rows[0][1]).toBe('number');
            expect(
                the_rows[0][1] as number
            ).toBeGreaterThan(0);
        });

        it('reads all 74 rows', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            const the_rows = await my_file.read_rows(0, 74);
            expect(the_rows.length).toBe(74);

            for (const my_row of the_rows) {
                expect(my_row.length).toBe(12);
            }
        });

        it('clamps count past end of data', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            const the_rows = await my_file.read_rows(70, 10);
            expect(the_rows.length).toBe(4);
        });

        it('provides value label tables', async () => {
            my_file = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'value_labels_v115.dta'
                )
            );
            const my_tables = my_file.value_label_tables;
            expect(my_tables.size).toBeGreaterThan(0);

            const my_foreign = my_tables.get('foreign_lbl');
            expect(my_foreign).toBeDefined();
            expect(my_foreign!.get(0)).toBe('Domestic');
            expect(my_foreign!.get(1)).toBe('Foreign');
        });

        it('preserves extended missing values', async () => {
            my_file = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'missing_values_v115.dta'
                )
            );
            const the_rows = await my_file.read_rows(0, 5);
            expect(the_rows[0][0]).toEqual(
                make_missing_value('.')
            );
            expect(the_rows[1][0]).toEqual(
                make_missing_value('.a')
            );
            expect(the_rows[4][0]).toEqual(
                make_missing_value('.z')
            );
        });

        it('handles empty dataset', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'empty_v115.dta')
            );
            expect(my_file.nobs).toBe(0);
            expect(my_file.nvar).toBe(3);

            const the_rows = await my_file.read_rows(0, 10);
            expect(the_rows).toEqual([]);
        });

        it('handles wide dataset (120 variables)', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'wide_v115.dta')
            );
            expect(my_file.nvar).toBe(120);
            expect(my_file.nobs).toBe(20);

            const the_rows = await my_file.read_rows(0, 1);
            expect(the_rows[0].length).toBe(120);
        });

        it('provides dataset label', async () => {
            my_file = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'value_labels_v115.dta'
                )
            );
            expect(my_file.dataset_label).toBe(
                'Value labels test dataset'
            );
        });
    });

    // ----- cross-version (legacy vs modern) -----

    describe('legacy-to-modern cross-version', () => {
        it('produces same data across v115 and v117', async () => {
            const my_f115 = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v115.dta')
            );
            const my_f117 = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v117.dta')
            );

            // Same variable count and names
            expect(my_f115.nvar).toBe(my_f117.nvar);
            expect(my_f115.nobs).toBe(my_f117.nobs);
            const the_names_115 = my_f115.variables.map(
                v => v.name
            );
            const the_names_117 = my_f117.variables.map(
                v => v.name
            );
            expect(the_names_115).toEqual(the_names_117);

            // Same data (first 5 rows)
            const the_rows_115 =
                await my_f115.read_rows(0, 5);
            const the_rows_117 =
                await my_f117.read_rows(0, 5);
            expect(the_rows_115).toEqual(the_rows_117);

            my_f115.close();
            my_f117.close();
        });

        it('value labels match across v115 and v117', async () => {
            const my_f115 = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'value_labels_v115.dta'
                )
            );
            const my_f117 = await DtaFile.open(
                path.join(
                    FIXTURE_DIR, 'value_labels_v117.dta'
                )
            );

            const my_tables_115 = my_f115.value_label_tables;
            const my_tables_117 = my_f117.value_label_tables;

            expect(my_tables_115.size).toBe(
                my_tables_117.size
            );

            for (const [my_name, my_map] of my_tables_115) {
                const my_modern_map =
                    my_tables_117.get(my_name);
                expect(my_modern_map).toBeDefined();
                expect(my_map).toEqual(my_modern_map);
            }

            my_f115.close();
            my_f117.close();
        });
    });

    // ----- empty dataset -----

    describe('empty dataset', () => {
        it('handles empty dataset', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'empty.dta')
            );
            expect(my_file.nobs).toBe(0);
            expect(my_file.nvar).toBe(3);
            expect(my_file.variables.length).toBe(3);

            const the_rows = await my_file.read_rows(0, 10);
            expect(the_rows).toEqual([]);
        });
    });

    // ----- close -----

    describe('close', () => {
        it('releases resources on close', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            my_file.close();

            // After close, read_rows should return empty
            const the_rows = await my_file.read_rows(0, 1);
            expect(the_rows).toEqual([]);

            // Prevent afterEach double-close
            my_file = null;
        });

        it('keeps reading after the source path is unlinked', async () => {
            if (process.platform === 'win32') {
                return;
            }

            const my_source_path = path.join(
                FIXTURE_DIR,
                'auto_v118.dta'
            );
            const my_copy_path = path.join(
                FIXTURE_DIR,
                'auto_v118.unlink-copy.dta'
            );

            fs.copyFileSync(my_source_path, my_copy_path);

            try {
                my_file = await DtaFile.open(my_copy_path);
                fs.unlinkSync(my_copy_path);

                const the_rows =
                    await my_file.read_rows(0, 2);
                expect(the_rows.length).toBe(2);
                expect(the_rows[0].length).toBe(12);
            } finally {
                try {
                    fs.unlinkSync(my_copy_path);
                } catch {
                    /* file may already be gone */
                }
            }
        });
    });
});
