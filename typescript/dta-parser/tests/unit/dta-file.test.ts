import { describe, it, expect, afterEach } from 'bun:test';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
    DtaFile,
    make_missing_value,
} from '../../src/node';
import { parse_legacy_metadata } from '../../src/legacy-header';
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
    __dirname, '../../../../r-package/dtaparser/src/dta-parser/tests/data/synthetic-v111.dta'
);

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
            expect(metadata.notes).toEqual(['Release 111 note']);
            const expansion = metadata.section_offsets.characteristics;
            const oldLength = original.readInt32LE(expansion + 1);
            const names = original.subarray(expansion + 5, expansion + 5 + 66);
            const payload = Buffer.concat([
                names,
                Buffer.alloc(70_000, 0x78),
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
