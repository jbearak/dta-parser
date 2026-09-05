import { describe, it, expect } from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';
import { parse_metadata } from '../../src/header';
import {
    read_columns_from_data_buffer,
    read_rows_from_data_buffer,
    read_rows_from_buffer,
} from '../../src/data-reader';
import { make_missing_value } from '../../src';
import type { DtaMetadata, RowCell } from '../../src/types';

// -----------------------------------------------------------
// Data section row reader tests
// -----------------------------------------------------------

const FIXTURE_DIR = path.resolve(
    __dirname, '../../../../tests/fixtures/dta'
);

function load_fixture(name: string): {
    buffer: ArrayBuffer;
    metadata: DtaMetadata;
} {
    const my_buf = fs.readFileSync(
        path.join(FIXTURE_DIR, name)
    );
    const my_array_buf = my_buf.buffer.slice(
        my_buf.byteOffset,
        my_buf.byteOffset + my_buf.byteLength
    );
    const my_meta = parse_metadata(my_array_buf);
    return { buffer: my_array_buf, metadata: my_meta };
}

describe('read_rows_from_buffer', () => {

    for (const tag of ['<data>', '</data>', '<strls>', '</strls>']) {
        it(`rejects damaged ${tag} even when reading an unrelated first cell`, () => {
            const { buffer, metadata } = load_fixture('auto_v118.dta');
            const bytes = Buffer.from(buffer);
            bytes[bytes.indexOf(tag)] = 88;
            expect(() => read_rows_from_buffer(buffer, metadata, 0, 1, 0, 1)).toThrow();
        });
    }

    it('rejects a declared observation extent inconsistent with its map', () => {
        const { buffer, metadata } = load_fixture('auto_v118.dta');
        metadata.nobs += 1;
        expect(() => read_rows_from_buffer(buffer, metadata, 0, 1)).toThrow();
    });

    for (const width of [245, 251, 255, 2045]) {
        it(`reads release-117 str${width} as a fixed string`, () => {
            const { buffer, metadata } = load_fixture('auto_v117.dta');
            const source = Buffer.from(buffer);
            const dataStart = metadata.section_offsets.data + '<data>'.length;
            const oldWidth = metadata.variables[0].byte_width;
            const delta = (width - oldWidth) * metadata.nobs;
            const rows: Buffer[] = [];
            for (let row = 0; row < metadata.nobs; row++) {
                const offset = dataStart + row * metadata.obs_length;
                const text = Buffer.alloc(width);
                source.copy(text, 0, offset, offset + oldWidth);
                rows.push(text, source.subarray(offset + oldWidth, offset + metadata.obs_length));
            }
            const modified = Buffer.concat([
                source.subarray(0, dataStart), ...rows,
                source.subarray(dataStart + metadata.nobs * metadata.obs_length),
            ]);
            modified.writeUInt16LE(width, metadata.section_offsets.variable_types + '<variable_types>'.length);
            for (let i = 10; i < 14; i++) {
                const offset = metadata.section_offsets.map + '<map>'.length + i * 8;
                modified.writeBigUInt64LE(modified.readBigUInt64LE(offset) + BigInt(delta), offset);
            }
            const modifiedBuffer = modified.buffer.slice(modified.byteOffset, modified.byteOffset + modified.byteLength);
            const actual = parse_metadata(modifiedBuffer);
            expect(actual.variables[0].type).toBe(`str${width}`);
            expect(actual.variables[0].byte_width).toBe(width);
            expect(read_rows_from_buffer(modifiedBuffer, actual, 0, 2)).toEqual(
                read_rows_from_buffer(buffer, metadata, 0, 2)
            );
        });
    }

    // ----- auto_v118.dta basic reads -----

    describe('auto_v118.dta', () => {
        const { buffer, metadata } =
            load_fixture('auto_v118.dta');

        it('reads the first row', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            expect(the_rows.length).toBe(1);
            const my_row = the_rows[0];
            // Row has 12 columns
            expect(my_row.length).toBe(12);
        });

        it('reads string values correctly (make is a non-empty string)', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            const my_make = the_rows[0][0];
            expect(typeof my_make).toBe('string');
            expect((my_make as string).length).toBeGreaterThan(0);
        });

        it('reads numeric values correctly (price > 0)', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            const my_price = the_rows[0][1];
            expect(typeof my_price).toBe('number');
            expect(my_price as number).toBeGreaterThan(0);
        });

        it('reads all 74 rows', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 74
            );
            expect(the_rows.length).toBe(74);

            // Every row should have 12 columns
            for (const my_row of the_rows) {
                expect(my_row.length).toBe(12);
            }

            // make should be a string in every row
            for (const my_row of the_rows) {
                expect(typeof my_row[0]).toBe('string');
            }
        });

        it('reads a middle page correctly (start=10, count=5)', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 10, 5
            );
            expect(the_rows.length).toBe(5);

            // Compare with individual reads to ensure
            // offset calculation is correct
            const the_all = read_rows_from_buffer(
                buffer, metadata, 0, 74
            );
            for (let i = 0; i < 5; i++) {
                expect(the_rows[i]).toEqual(the_all[10 + i]);
            }
        });

        it('handles reading past end of data (start=70, count=10)', () => {
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 70, 10
            );
            // 74 obs total, start=70 means 4 rows remain
            expect(the_rows.length).toBe(4);
        });
    });

    // ----- Empty dataset -----

    describe('empty dataset', () => {
        it('returns empty array for empty dataset', () => {
            const { buffer, metadata } =
                load_fixture('empty.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 100
            );
            expect(the_rows).toEqual([]);
        });
    });

    // ----- Missing values -----

    describe('missing values', () => {
        it('returns tagged missing values (missing_values.dta)', () => {
            const { buffer, metadata } =
                load_fixture('missing_values.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 5
            );

            // Row 0 (_n==1): all five columns are .
            // (system missing)
            // Variables: x_double, x_byte, x_int, x_long,
            //            x_float
            const my_row0 = the_rows[0];
            expect(my_row0[0]).toEqual(make_missing_value('.'));
            expect(my_row0[1]).toEqual(make_missing_value('.'));
            expect(my_row0[1]).not.toBe(my_row0[0]);
            expect(my_row0[2]).toEqual(make_missing_value('.'));
            expect(my_row0[3]).toEqual(make_missing_value('.'));
            expect(my_row0[4]).toEqual(make_missing_value('.'));

            // Row 1 (_n==2): .a in all columns
            const my_row1 = the_rows[1];
            expect(my_row1[0]).toEqual(make_missing_value('.a'));
            expect(my_row1[1]).toEqual(make_missing_value('.a'));
            expect(my_row1[2]).toEqual(make_missing_value('.a'));
            expect(my_row1[3]).toEqual(make_missing_value('.a'));
            expect(my_row1[4]).toEqual(make_missing_value('.a'));

            // Row 2 (_n==3): x_double = .b, x_byte = .z,
            // x_int = .z, x_long = .z, x_float = .z
            const my_row2 = the_rows[2];
            expect(my_row2[0]).toEqual(make_missing_value('.b'));
            expect(my_row2[1]).toEqual(make_missing_value('.z'));
            expect(my_row2[2]).toEqual(make_missing_value('.z'));
            expect(my_row2[3]).toEqual(make_missing_value('.z'));
            expect(my_row2[4]).toEqual(make_missing_value('.z'));

            // Row 4 (_n==5): x_double = .z, others are
            // numeric (not null)
            const my_row4 = the_rows[4];
            expect(my_row4[0]).toEqual(make_missing_value('.z'));

            // x_byte for _n==5: gen byte x_byte = _n
            // if _n <= 100 => 5
            expect(my_row4[1]).toBe(5);
        });
    });

    describe('read_columns_from_data_buffer', () => {
        it('appends strL placeholders to an empty target', () => {
            const { buffer, metadata } =
                load_fixture('all_types.dta');
            const my_strl_idx = metadata.variables.findIndex(
                my_var => my_var.type === 'strL'
            );
            const my_data_start =
                metadata.section_offsets.data + '<data>'.length;
            const my_data = buffer.slice(
                my_data_start,
                my_data_start + metadata.obs_length
            );
            const the_columns = new Map<number, RowCell[]>([
                [my_strl_idx, []],
            ]);

            read_columns_from_data_buffer(
                my_data,
                metadata,
                1,
                [my_strl_idx],
                the_columns
            );

            expect(the_columns.get(my_strl_idx)).toEqual([
                '__strl__',
            ]);
        });

        it('rejects a fractional row count', () => {
            const { buffer, metadata } =
                load_fixture('all_types.dta');
            const my_strl_idx = metadata.variables.findIndex(
                my_var => my_var.type === 'strL'
            );
            const the_columns = new Map<number, RowCell[]>([
                [my_strl_idx, []],
            ]);

            expect(() => read_columns_from_data_buffer(
                buffer,
                metadata,
                0.5,
                [my_strl_idx],
                the_columns
            )).toThrow(RangeError);
        });
    });

    // ----- Cross-version -----

    describe('cross-version compatibility', () => {
        it('reads v117 format correctly', () => {
            const { buffer, metadata } =
                load_fixture('auto_v117.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
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

        it('produces same data across v117 and v118', () => {
            const my_v117 = load_fixture('auto_v117.dta');
            const my_v118 = load_fixture('auto_v118.dta');

            const the_rows_117 = read_rows_from_buffer(
                my_v117.buffer, my_v117.metadata, 0, 5
            );
            const the_rows_118 = read_rows_from_buffer(
                my_v118.buffer, my_v118.metadata, 0, 5
            );
            expect(the_rows_117).toEqual(the_rows_118);
        });
    });

    // ----- Column subsetting -----

    describe('column subsetting', () => {
        it('handles column subsetting (col_start=0, col_end=3)', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1, 0, 3
            );
            expect(the_rows.length).toBe(1);
            // Only 3 columns: make, price, mpg
            expect(the_rows[0].length).toBe(3);

            // Verify values match full read
            const the_full = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            expect(the_rows[0][0]).toEqual(the_full[0][0]);
            expect(the_rows[0][1]).toEqual(the_full[0][1]);
            expect(the_rows[0][2]).toEqual(the_full[0][2]);
        });

        it('subsets middle columns correctly', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            // Get columns 3..6 (rep78, headroom, trunk)
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1, 3, 6
            );
            expect(the_rows[0].length).toBe(3);

            const the_full = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            expect(the_rows[0][0]).toEqual(the_full[0][3]);
            expect(the_rows[0][1]).toEqual(the_full[0][4]);
            expect(the_rows[0][2]).toEqual(the_full[0][5]);
        });

        it('matches full rows through every single-column decoder', () => {
            for (const my_fixture of [
                'all_types.dta',
                'missing_values.dta',
            ]) {
                const { buffer, metadata } = load_fixture(my_fixture);
                const the_full = read_rows_from_buffer(
                    buffer, metadata, 0, metadata.nobs
                );

                for (let my_col = 0; my_col < metadata.nvar; my_col++) {
                    expect(read_rows_from_buffer(
                        buffer,
                        metadata,
                        0,
                        metadata.nobs,
                        my_col,
                        my_col + 1
                    )).toEqual(the_full.map(
                        my_row => [my_row[my_col]]
                    ));
                }
            }
        });

        it('rejects truncated short strings in observation buffers', () => {
            const { metadata } = load_fixture('all_types.dta');
            const my_string_column = metadata.variables.findIndex(
                my_variable => my_variable.type === 'str5'
            );
            const my_string_offset = metadata.variables[
                my_string_column
            ].byte_offset;
            const my_truncated = new Uint8Array(my_string_offset + 2);
            my_truncated.set([0x61, 0x62], my_string_offset);

            expect(() => read_rows_from_data_buffer(
                my_truncated,
                metadata,
                0,
                1,
                my_string_column,
                my_string_column + 1
            )).toThrow('Truncated observation data');
            const out = new Map<number, RowCell[]>([[my_string_column, []]]);
            expect(() => read_columns_from_data_buffer(
                my_truncated, metadata, 1, [my_string_column], out
            )).toThrow('Truncated observation data');
            expect(out.get(my_string_column)).toEqual([]);
        });

        it('rejects truncated strL pointers before returning placeholders', () => {
            const { metadata } = load_fixture('all_types.dta');
            const col = metadata.variables.findIndex(variable => variable.type === 'strL');
            const truncated = new Uint8Array(metadata.obs_length - 1);
            expect(() => read_rows_from_data_buffer(
                truncated, metadata, 0, 1, col, col + 1
            )).toThrow('Truncated observation data');
        });
    });

    // ----- all_types.dta -----

    describe('all_types.dta', () => {
        it('reads all numeric types', () => {
            const { buffer, metadata } =
                load_fixture('all_types.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 5
            );
            expect(the_rows.length).toBe(5);

            // Variable order: v_byte, v_int, v_long,
            //   v_float, v_double, v_str5, v_str20, v_strL

            // Row 0 (_n==1): byte=1, int=100,
            //   long=100000, float~1.1, double~1.111111111
            const my_row0 = the_rows[0];
            expect(my_row0[0]).toBe(1);      // byte
            expect(my_row0[1]).toBe(100);    // int
            expect(my_row0[2]).toBe(100000); // long

            // float: 1.1 stored as float32 may lose
            // precision
            expect(typeof my_row0[3]).toBe('number');
            expect(
                Math.abs((my_row0[3] as number) - 1.1)
            ).toBeLessThan(0.01);

            // double: close to 1.111111111
            expect(typeof my_row0[4]).toBe('number');
            expect(
                Math.abs(
                    (my_row0[4] as number) - 1.111111111
                )
            ).toBeLessThan(0.0001);

            // Row 4 (_n==5): byte=5, int=500,
            //   long=500000
            const my_row4 = the_rows[4];
            expect(my_row4[0]).toBe(5);
            expect(my_row4[1]).toBe(500);
            expect(my_row4[2]).toBe(500000);
        });

        it('reads string types', () => {
            const { buffer, metadata } =
                load_fixture('all_types.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 5
            );

            // v_str5 (index 5): "s1" through "s5"
            expect(the_rows[0][5]).toBe('s1');
            expect(the_rows[1][5]).toBe('s2');
            expect(the_rows[4][5]).toBe('s5');

            // v_str20 (index 6): "longer_string_1" etc.
            expect(the_rows[0][6]).toBe('longer_string_1');
            expect(the_rows[4][6]).toBe('longer_string_5');

            // v_strL (index 7): placeholder for now
            expect(the_rows[0][7]).toBe('__strl__');
        });
    });

    // ----- wide.dta -----

    describe('wide.dta', () => {
        it('reads wide dataset (120 double vars)', () => {
            const { buffer, metadata } =
                load_fixture('wide.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 1
            );
            expect(the_rows.length).toBe(1);
            expect(the_rows[0].length).toBe(120);

            // All values should be numbers (doubles)
            for (const my_cell of the_rows[0]) {
                expect(typeof my_cell).toBe('number');
            }
        });
    });

    // ----- Edge cases -----

    describe('edge cases', () => {
        it('returns empty array when start >= nobs', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 100, 10
            );
            expect(the_rows).toEqual([]);
        });

        it('handles count of 0', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const the_rows = read_rows_from_buffer(
                buffer, metadata, 0, 0
            );
            expect(the_rows).toEqual([]);
        });

        it('rejects non-integer row ranges before decoding', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const my_data_start =
                metadata.section_offsets.data + '<data>'.length;
            const my_data = buffer.slice(my_data_start);

            for (const [my_start, my_count] of [
                [0.5, 1],
                [0, 1.5],
                [NaN, 1],
            ]) {
                expect(() => read_rows_from_buffer(
                    buffer,
                    metadata,
                    my_start,
                    my_count
                )).toThrow(RangeError);
                expect(() => read_rows_from_data_buffer(
                    my_data,
                    metadata,
                    my_start,
                    my_count
                )).toThrow(RangeError);
            }
        });

        it('preserves infinite row-bound sentinels', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const the_expected = read_rows_from_buffer(
                buffer,
                metadata,
                0,
                metadata.nobs
            );

            expect(read_rows_from_buffer(
                buffer,
                metadata,
                0,
                Infinity
            )).toEqual(the_expected);
            expect(read_rows_from_buffer(
                buffer,
                metadata,
                Infinity,
                1
            )).toEqual([]);
            expect(read_rows_from_buffer(
                buffer,
                metadata,
                -Infinity,
                1
            )).toEqual([]);
            expect(read_rows_from_buffer(
                buffer,
                metadata,
                0,
                -Infinity
            )).toEqual([]);
        });
    });
});
