import { describe, it, expect } from 'bun:test';
import { parse_legacy_metadata } from '../../src/legacy-header';
import { read_rows_from_buffer } from '../../src/data-reader';
import { make_missing_value } from '../../src/missing-values';
import { parse_value_labels } from '../../src/value-labels';
import { DtaFile } from '../../src/node';
import { mkdtempSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

async function expect_node_label_parity(
    buffer: ArrayBuffer,
    expected: Map<string, Map<number, string>>
): Promise<void> {
    const dir = mkdtempSync(join(tmpdir(), 'dta-labels-'));
    const path = join(dir, 'labels.dta');
    try {
        writeFileSync(path, Buffer.from(buffer));
        const file = await DtaFile.open(path);
        try {
            expect(file.value_label_tables).toEqual(expected);
        } finally {
            file.close();
        }
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
}

// -----------------------------------------------------------
// Legacy header parser unit tests (formats 111, 113-115)
// -----------------------------------------------------------

/**
 * Build a minimal synthetic legacy .dta buffer with the
 * given parameters. No value labels. Data section follows
 * immediately after the expansion fields terminator.
 */
function build_legacy_buffer(opts: {
    version: 105 | 108 | 110 | 111 | 113 | 114 | 115;
    byte_order?: 'LSF' | 'MSF';
    nvar: number;
    nobs: number;
    label?: string;
    type_codes: number[];
    varnames: string[];
}): { buffer: ArrayBuffer; file_size: number } {
    const {
        version,
        byte_order = 'LSF',
        nvar,
        nobs,
        label = '',
        type_codes,
        varnames,
    } = opts;

    const little_endian = byte_order === 'LSF';
    const fmt_width = version <= 113 ? 12 : 49;
    const header_size = version === 105 ? 60 : 109;
    const dataset_label_width = version === 105 ? 32 : 81;
    const varname_width = version <= 108 ? 9 : 33;
    const value_label_name_width = version <= 108 ? 9 : 33;
    const variable_label_width = version === 105 ? 32 : 81;
    const expansion_header_size = version <= 108 ? 3 : 5;

    // Compute obs_length from type codes
    let obs_length = 0;
    for (const my_code of type_codes) {
        if (version < 111) {
            if (my_code === 98) obs_length += 1;
            else if (my_code === 105) obs_length += 2;
            else if (my_code === 108) obs_length += 4;
            else if (my_code === 102) obs_length += 4;
            else if (my_code === 100) obs_length += 8;
            else if (my_code >= 128) obs_length += my_code - 127;
        } else if (my_code >= 1 && my_code <= 244) {
            obs_length += my_code;
        } else if (my_code === 251) obs_length += 1;
        else if (my_code === 252) obs_length += 2;
        else if (my_code === 253) obs_length += 4;
        else if (my_code === 254) obs_length += 4;
        else if (my_code === 255) obs_length += 8;
    }

    const my_header_size = header_size;
    const my_types_size = nvar;
    const my_varnames_size = nvar * varname_width;
    const my_sortlist_size = (nvar + 1) * 2;
    const my_formats_size = nvar * fmt_width;
    const my_vlabel_names_size = nvar * value_label_name_width;
    const my_var_labels_size = nvar * variable_label_width;
    const my_expansion_size = expansion_header_size; // terminator only
    const my_data_size = nobs * obs_length;

    const my_total = my_header_size
        + my_types_size
        + my_varnames_size
        + my_sortlist_size
        + my_formats_size
        + my_vlabel_names_size
        + my_var_labels_size
        + my_expansion_size
        + my_data_size;

    const my_buf = Buffer.alloc(my_total);
    const my_view = new DataView(
        my_buf.buffer,
        my_buf.byteOffset,
        my_buf.byteLength
    );

    // Fixed header
    my_buf[0] = version;
    my_buf[1] = little_endian ? 0x02 : 0x01;
    my_buf[2] = 0x01;
    my_buf[3] = 0x00;
    my_view.setUint16(4, nvar, little_endian);
    my_view.setUint32(6, nobs, little_endian);

    // Dataset label, leaving the final field byte as a terminator.
    for (
        let i = 0;
        i < label.length && i < dataset_label_width - 1;
        i++
    ) {
        my_buf[10 + i] = label.charCodeAt(i);
    }

    let pos = my_header_size;

    // Variable types
    for (let i = 0; i < nvar; i++) {
        my_buf[pos + i] = type_codes[i];
    }
    pos += nvar;

    // Varnames (release-specific width)
    for (let i = 0; i < nvar; i++) {
        const my_name = varnames[i] || `v${i}`;
        for (
            let j = 0;
            j < my_name.length && j < varname_width - 1;
            j++
        ) {
            my_buf[pos + i * varname_width + j] =
                my_name.charCodeAt(j);
        }
    }
    pos += nvar * varname_width;

    // Sortlist
    pos += (nvar + 1) * 2;

    // Formats (fmt_width bytes each)
    for (let i = 0; i < nvar; i++) {
        const my_fmt = '%9.0g';
        for (let j = 0; j < my_fmt.length; j++) {
            my_buf[pos + i * fmt_width + j] =
                my_fmt.charCodeAt(j);
        }
    }
    pos += nvar * fmt_width;

    // Value label names (release-specific width) — empty
    pos += nvar * value_label_name_width;

    // Variable labels (release-specific width) — empty
    pos += nvar * variable_label_width;

    // Expansion-fields terminator (release-specific width)
    pos += expansion_header_size;

    // Data section — fill with zeros (no observation data)

    return {
        buffer: my_buf.buffer.slice(
            my_buf.byteOffset,
            my_buf.byteOffset + my_buf.byteLength
        ),
        file_size: my_total,
    };
}

describe('parse_legacy_metadata', () => {

    it('parses release 111 with Stata/SE 7 field widths', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 111,
            byte_order: 'MSF',
            nvar: 4,
            nobs: 2,
            label: 'Stata/SE 7',
            type_codes: [253, 254, 255, 6],
            varnames: ['long', 'float', 'double', 'text'],
        });

        const my_meta = parse_legacy_metadata(buffer, file_size);
        expect(my_meta.format_version).toBe(111);
        expect(my_meta.byte_order).toBe('MSF');
        expect(my_meta.dataset_label).toBe('Stata/SE 7');
        expect(my_meta.variables[0].format).toBe('%9.0g');
        expect(my_meta.variables[3].type).toBe('str6');

        const my_view = new DataView(buffer);
        const my_bytes = new Uint8Array(buffer);
        const data = my_meta.section_offsets.data;
        my_view.setInt32(data, 2147483647, false);
        my_view.setUint32(data + 4, 0x7F000001, false);
        my_view.setUint32(data + 8, 0x7FE00000, false);
        my_view.setUint32(data + 12, 1, false);
        my_bytes.set([0x43, 0x61, 0x66, 0xE9], data + 16);

        const second = data + my_meta.obs_length;
        my_view.setInt32(second, 2147483646, false);
        my_view.setUint32(second + 4, 0x7EFFFFFF, false);
        my_view.setUint32(second + 8, 0x7FDFFFFF, false);
        my_view.setUint32(second + 12, 0xFFFFFFFF, false);
        my_bytes.set([0x6F, 0x6B], second + 16);

        const rows = read_rows_from_buffer(buffer, my_meta, 0, 2);
        expect(rows[0]).toEqual([
            make_missing_value('.'),
            make_missing_value('.'),
            make_missing_value('.'),
            'Café',
        ]);
        expect(rows[1][0]).toBe(2147483646);
        expect(typeof rows[1][1]).toBe('number');
        expect(typeof rows[1][2]).toBe('number');
        expect(Number.isFinite(rows[1][2] as number)).toBe(true);
        expect(rows[1][3]).toBe('ok');
    });

    it('parses format 115 header', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 115,
            nvar: 3,
            nobs: 10,
            label: 'Test dataset',
            type_codes: [255, 252, 5], // double, int, str5
            varnames: ['price', 'mpg', 'make'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.format_version).toBe(115);
        expect(my_meta.byte_order).toBe('LSF');
        expect(my_meta.nvar).toBe(3);
        expect(my_meta.nobs).toBe(10);
        expect(my_meta.dataset_label).toBe('Test dataset');
        expect(my_meta.variables.length).toBe(3);

        // Variable types
        expect(my_meta.variables[0].type).toBe('double');
        expect(my_meta.variables[0].byte_width).toBe(8);
        expect(my_meta.variables[1].type).toBe('int');
        expect(my_meta.variables[1].byte_width).toBe(2);
        expect(my_meta.variables[2].type).toBe('str5');
        expect(my_meta.variables[2].byte_width).toBe(5);

        // Variable names
        expect(my_meta.variables[0].name).toBe('price');
        expect(my_meta.variables[1].name).toBe('mpg');
        expect(my_meta.variables[2].name).toBe('make');

        // Obs length
        expect(my_meta.obs_length).toBe(8 + 2 + 5);
    });

    it('bounds release 105 dataset labels to their header field', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 105,
            nvar: 1,
            nobs: 0,
            label: 'x'.repeat(80),
            type_codes: [105],
            varnames: ['answer'],
        });

        const metadata = parse_legacy_metadata(buffer, file_size);
        expect(metadata.dataset_label).toBe('x'.repeat(31));
        expect(metadata.variables[0].type).toBe('int');
        expect(metadata.variables[0].name).toBe('answer');
    });

    it('bounds release 105 variable names to their descriptor field', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 105,
            nvar: 1,
            nobs: 0,
            type_codes: [105],
            varnames: ['answer-is-much-too-long'],
        });

        const metadata = parse_legacy_metadata(buffer, file_size);
        expect(metadata.variables[0].name).toBe('answer-i');
        const bytes = new Uint8Array(buffer);
        const sortlist_start = 60 + 1 + 9;
        expect(bytes.slice(sortlist_start, sortlist_start + 4))
            .toEqual(new Uint8Array(4));
    });

    it('parses format 114 header', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 114,
            nvar: 2,
            nobs: 5,
            type_codes: [251, 253], // byte, long
            varnames: ['x', 'y'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.format_version).toBe(114);
        expect(my_meta.nvar).toBe(2);
        expect(my_meta.nobs).toBe(5);
        expect(my_meta.variables[0].type).toBe('byte');
        expect(my_meta.variables[1].type).toBe('long');
    });

    it('parses format 113 with 12-byte formats', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 113,
            nvar: 1,
            nobs: 3,
            type_codes: [254], // float
            varnames: ['z'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.format_version).toBe(113);
        expect(my_meta.nvar).toBe(1);
        expect(my_meta.variables[0].type).toBe('float');
        expect(my_meta.variables[0].format).toBe('%9.0g');
    });

    it('handles big-endian byte order', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 115,
            byte_order: 'MSF',
            nvar: 1,
            nobs: 2,
            type_codes: [255], // double
            varnames: ['val'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.byte_order).toBe('MSF');
        expect(my_meta.nvar).toBe(1);
        expect(my_meta.nobs).toBe(2);
    });

    it('handles empty dataset (nobs=0)', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 115,
            nvar: 2,
            nobs: 0,
            type_codes: [255, 252],
            varnames: ['a', 'b'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.nobs).toBe(0);
        expect(my_meta.nvar).toBe(2);
        // data offset = value_labels offset when nobs=0
        expect(my_meta.section_offsets.data).toBe(
            my_meta.section_offsets.value_labels
        );
    });

    it('computes correct byte offsets', () => {
        const { buffer, file_size } = build_legacy_buffer({
            version: 115,
            nvar: 4,
            nobs: 1,
            type_codes: [251, 252, 253, 255],
            varnames: ['a', 'b', 'c', 'd'],
        });

        const my_meta = parse_legacy_metadata(
            buffer, file_size
        );

        expect(my_meta.variables[0].byte_offset).toBe(0);
        expect(my_meta.variables[1].byte_offset).toBe(1);
        expect(my_meta.variables[2].byte_offset).toBe(3);
        expect(my_meta.variables[3].byte_offset).toBe(7);
        expect(my_meta.obs_length).toBe(15);
    });

    it('rejects invalid version byte', () => {
        const my_buf = Buffer.alloc(256);
        my_buf[0] = 112; // unsupported
        my_buf[1] = 0x02;
        my_buf[2] = 0x01;

        expect(() => {
            parse_legacy_metadata(
                my_buf.buffer.slice(
                    my_buf.byteOffset,
                    my_buf.byteOffset + my_buf.byteLength
                ),
                256
            );
        }).toThrow('Not a legacy .dta file');
    });

    it('rejects an invalid release-111 file type', () => {
        const valid = build_legacy_buffer({
            version: 111,
            nvar: 1,
            nobs: 0,
            type_codes: [251],
            varnames: ['x'],
        });
        const malformed = Buffer.from(valid.buffer);
        malformed[2] = 2;

        expect(() => parse_legacy_metadata(
            malformed.buffer.slice(
                malformed.byteOffset,
                malformed.byteOffset + malformed.byteLength
            ),
            malformed.byteLength
        )).toThrow('Invalid legacy file type');
    });

    it('rejects truncated and negative release-111 expansion fields', () => {
        const valid = build_legacy_buffer({
            version: 111,
            nvar: 1,
            nobs: 0,
            type_codes: [251],
            varnames: ['x'],
        });
        const metadata = parse_legacy_metadata(valid.buffer, valid.file_size);

        expect(() => parse_legacy_metadata(
            valid.buffer.slice(0, metadata.section_offsets.characteristics),
            metadata.section_offsets.characteristics
        )).toThrow('Missing legacy expansion-field terminator');

        const negative = Buffer.from(valid.buffer);
        const view = new DataView(
            negative.buffer, negative.byteOffset, negative.byteLength
        );
        negative[metadata.section_offsets.characteristics] = 1;
        view.setInt32(metadata.section_offsets.characteristics + 1, -1, true);
        expect(() => parse_legacy_metadata(
            negative.buffer.slice(
                negative.byteOffset,
                negative.byteOffset + negative.byteLength
            ),
            negative.byteLength
        )).toThrow('Invalid legacy expansion field');
    });

    it('rejects release-111 observation geometry beyond the file size', () => {
        const valid = build_legacy_buffer({
            version: 111,
            nvar: 1,
            nobs: 1,
            type_codes: [255],
            varnames: ['x'],
        });
        const truncated = valid.buffer.slice(0, valid.file_size - 1);
        expect(() => parse_legacy_metadata(
            truncated, valid.file_size - 1
        )).toThrow('Truncated legacy observation data');
    });

    for (const version of [105, 108, 110] as const) {
        it(`parses release ${version} layout, old type codes, and system missing`, () => {
            const { buffer, file_size } = build_legacy_buffer({
                version, nvar: 6, nobs: 1,
                type_codes: [98, 105, 108, 102, 100, 132],
                varnames: ['b', 'i', 'l', 'f', 'd', 'text'],
                label: `release ${version}`,
            });
            const meta = parse_legacy_metadata(buffer, file_size);
            expect(meta.format_version).toBe(version);
            expect(meta.variables.map(v => v.type)).toEqual([
                'byte', 'int', 'long', 'float', 'double', 'str5',
            ]);
            expect(file_size - meta.section_offsets.data).toBe(
                meta.obs_length
            );
            const view = new DataView(buffer);
            const data = meta.section_offsets.data;
            view.setInt8(data, 127);
            view.setInt16(data + 1, 32767, true);
            view.setInt32(data + 3, 2147483647, true);
            view.setUint32(data + 7, 0x7f000000, true);
            view.setUint32(data + 11, 0, true);
            view.setUint32(
                data + 15,
                version === 105 ? 0x54c00000 : 0x7fe00000,
                true
            );
            new Uint8Array(buffer).set([0x6f, 0x6c, 0x64], data + 19);
            expect(read_rows_from_buffer(buffer, meta, 0, 1)[0]).toEqual([
                make_missing_value('.'), make_missing_value('.'),
                make_missing_value('.'), make_missing_value('.'),
                make_missing_value('.'), 'old',
            ]);
        });
    }

    it('accepts both release 105 double missing encodings', () => {
        const built = build_legacy_buffer({
            version: 105, nvar: 1, nobs: 2,
            type_codes: [100], varnames: ['value'],
        });
        const meta = parse_legacy_metadata(
            built.buffer, built.file_size
        );
        const view = new DataView(built.buffer);
        const data = meta.section_offsets.data;
        view.setUint32(data, 0, true);
        view.setUint32(data + 4, 0x54c00000, true);
        view.setUint32(data + 8, 0, true);
        view.setUint32(data + 12, 0x7fe00000, true);
        const rows = read_rows_from_buffer(
            built.buffer, meta, 0, 2
        );
        expect(rows[0][0]).toEqual(make_missing_value('.'));
        expect(rows[1][0]).toEqual(make_missing_value('.'));
    });

    it('parses release 105 fixed-width value-label tables', () => {
        const built = build_legacy_buffer({
            version: 105, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const prefix = Buffer.from(built.buffer);
        const table = Buffer.alloc(12 + 2 * 2 + 2 * 8);
        const view = new DataView(
            table.buffer, table.byteOffset, table.byteLength
        );
        view.setUint16(0, 2, true);
        table.write('yesno', 2, 'latin1');
        view.setInt16(12, 1, true);
        view.setInt16(14, 1, true);
        table.write('first', 16, 'latin1');
        table.write('second', 24, 'latin1');
        const complete = Buffer.concat([prefix, table]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(
            buffer, complete.byteLength
        );
        expect(
            parse_value_labels(buffer, meta).get('yesno')?.get(1)
        ).toBe('first');
    });

    it('ignores release 105 trailing zero padding', () => {
        const built = build_legacy_buffer({
            version: 105, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const complete = Buffer.concat([
            Buffer.from(built.buffer), Buffer.alloc(24),
        ]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(
            buffer, complete.byteLength
        );
        expect(parse_value_labels(buffer, meta)).toEqual(new Map());
    });

    it('rejects short nonzero release 105 value-label tails', () => {
        const built = build_legacy_buffer({
            version: 105, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        for (let length = 1; length < 12; length++) {
            const complete = Buffer.concat([
                Buffer.from(built.buffer),
                Buffer.from([1]),
                Buffer.alloc(length - 1),
            ]);
            const buffer = complete.buffer.slice(
                complete.byteOffset,
                complete.byteOffset + complete.byteLength
            );
            const meta = parse_legacy_metadata(
                buffer, complete.byteLength
            );
            expect(() => parse_value_labels(buffer, meta)).toThrow(
                'trailing bytes'
            );
        }
    });

    it('does not misclassify release 105 fixed tables with empty labels', () => {
        const built = build_legacy_buffer({
            version: 105, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const prefix = Buffer.from(built.buffer);
        const table = Buffer.alloc(12 + 4 * 2 + 4 * 8);
        const view = new DataView(
            table.buffer, table.byteOffset, table.byteLength
        );
        view.setUint16(0, 4, true);
        table.write('empty', 2, 'latin1');
        for (let i = 0; i < 4; i++) {
            view.setInt16(12 + i * 2, i, true);
        }
        const complete = Buffer.concat([prefix, table]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(
            buffer, complete.byteLength
        );
        expect(
            parse_value_labels(buffer, meta).get('empty')
        ).toEqual(new Map([
            [0, ''], [1, ''], [2, ''], [3, ''],
        ]));
    });

    for (const { version, table_name_width } of [
        { version: 105 as const, table_name_width: 33 },
        { version: 108 as const, table_name_width: 9 },
        { version: 108 as const, table_name_width: 33 },
        { version: 110 as const, table_name_width: 33 },
    ]) {
        it(`parses release ${version} variable-length value labels with ${table_name_width}-byte names`, () => {
            const built = build_legacy_buffer({
                version, nvar: 1, nobs: 0,
                type_codes: [105], varnames: ['answer'],
            });
            const prefix = Buffer.from(built.buffer);
            const text = Buffer.from(
                'first\0second\0', 'latin1'
            );
            const payload_size = 8 + 2 * 4 + 2 * 4 + text.length;
            const table = Buffer.alloc(
                4 + table_name_width + 3 + payload_size
            );
            const view = new DataView(
                table.buffer, table.byteOffset, table.byteLength
            );
            view.setInt32(0, payload_size, true);
            table.write('table1', 4, 'latin1');
            const pos = 4 + table_name_width + 3;
            view.setInt32(pos, 2, true);
            view.setInt32(pos + 4, text.length, true);
            view.setInt32(pos + 8, 0, true);
            view.setInt32(pos + 12, 6, true);
            view.setInt32(pos + 16, 1, true);
            view.setInt32(pos + 20, 2, true);
            text.copy(table, pos + 24);
            const complete = Buffer.concat([prefix, table]);
            const buffer = complete.buffer.slice(
                complete.byteOffset,
                complete.byteOffset + complete.byteLength
            );
            const meta = parse_legacy_metadata(
                buffer, complete.byteLength
            );
            const labels = parse_value_labels(buffer, meta).get('table1');
            expect(labels?.get(1)).toBe('first');
            expect(labels?.get(2)).toBe('second');
        });
    }

    it('prefers complete 9-byte framing for release 108', async () => {
        const built = build_legacy_buffer({
            version: 108, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const text = Buffer.from('a\0b\0c\0', 'latin1');
        const payload_size = 8 + 3 * 4 + 3 * 4 + text.length;
        const table = Buffer.alloc(4 + 9 + 3 + payload_size);
        const view = new DataView(
            table.buffer, table.byteOffset, table.byteLength
        );
        view.setInt32(0, payload_size, true);
        table.write('short', 4, 'latin1');
        const pos = 4 + 9 + 3;
        view.setInt32(pos, 3, true);
        view.setInt32(pos + 4, text.length, true);
        for (const [index, offset] of [0, 2, 4].entries()) {
            view.setInt32(pos + 8 + index * 4, offset, true);
        }
        for (const [index, value] of [0, 1, 22].entries()) {
            view.setInt32(pos + 20 + index * 4, value, true);
        }
        text.copy(table, pos + 32);
        const complete = Buffer.concat([Buffer.from(built.buffer), table]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(buffer, complete.byteLength);
        const labels = parse_value_labels(buffer, meta);
        expect(labels.get('short')).toEqual(
            new Map([[0, 'a'], [1, 'b'], [22, 'c']])
        );
        await expect_node_label_parity(buffer, labels);
    });

    it('uses 33-byte names when the first release 108 table is empty', async () => {
        const built = build_legacy_buffer({
            version: 108, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const empty = Buffer.alloc(4 + 33 + 3 + 8);
        const empty_view = new DataView(
            empty.buffer, empty.byteOffset, empty.byteLength
        );
        empty_view.setInt32(0, 8, true);
        empty.write('empty', 4, 'latin1');

        const text = Buffer.from('one\0', 'latin1');
        const payload_size = 8 + 4 + 4 + text.length;
        const populated = Buffer.alloc(4 + 33 + 3 + payload_size);
        const populated_view = new DataView(
            populated.buffer, populated.byteOffset, populated.byteLength
        );
        populated_view.setInt32(0, payload_size, true);
        populated.write('codes', 4, 'latin1');
        const pos = 4 + 33 + 3;
        populated_view.setInt32(pos, 1, true);
        populated_view.setInt32(pos + 4, text.length, true);
        populated_view.setInt32(pos + 8, 0, true);
        populated_view.setInt32(pos + 12, 1, true);
        text.copy(populated, pos + 16);

        const complete = Buffer.concat([
            Buffer.from(built.buffer), empty, populated,
        ]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(buffer, complete.byteLength);
        const labels = parse_value_labels(buffer, meta);
        expect(labels.get('empty')).toEqual(new Map());
        expect(labels.get('codes')?.get(1)).toBe('one');
        await expect_node_label_parity(buffer, labels);
    });

    it('does not fall back after selecting release 108 long framing', async () => {
        const built = build_legacy_buffer({
            version: 108, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const text = Buffer.from('one\0', 'latin1');
        const payload_size = 8 + 4 + 4 + text.length;
        const table = Buffer.alloc(4 + 33 + 3 + payload_size);
        const view = new DataView(
            table.buffer, table.byteOffset, table.byteLength
        );
        view.setInt32(0, payload_size, true);
        table.write('codes', 4, 'latin1');
        const pos = 4 + 33 + 3;
        view.setInt32(pos, 1, true);
        view.setInt32(pos + 4, text.length, true);
        view.setInt32(pos + 8, -1, true);
        view.setInt32(pos + 12, 1, true);
        text.copy(table, pos + 16);
        const complete = Buffer.concat([Buffer.from(built.buffer), table]);
        const buffer = complete.buffer.slice(
            complete.byteOffset,
            complete.byteOffset + complete.byteLength
        );
        const meta = parse_legacy_metadata(buffer, complete.byteLength);
        expect(() => parse_value_labels(buffer, meta)).toThrow(
            'invalid text offset'
        );

        const dir = mkdtempSync(join(tmpdir(), 'dta-corrupt-labels-'));
        const path = join(dir, 'labels.dta');
        try {
            writeFileSync(path, complete);
            await expect(DtaFile.open(path)).rejects.toThrow(
                'invalid text offset'
            );
        } finally {
            rmSync(dir, { recursive: true, force: true });
        }
    });

    it('rejects nonzero bytes after release 108 zero padding', async () => {
        const built = build_legacy_buffer({
            version: 108, nvar: 1, nobs: 0,
            type_codes: [105], varnames: ['answer'],
        });
        const text = Buffer.from('one\0', 'latin1');
        const payload_size = 8 + 4 + 4 + text.length;
        const table = Buffer.alloc(4 + 9 + 3 + payload_size);
        const table_view = new DataView(
            table.buffer, table.byteOffset, table.byteLength
        );
        table_view.setInt32(0, payload_size, true);
        table.write('codes', 4, 'latin1');
        const pos = 4 + 9 + 3;
        table_view.setInt32(pos, 1, true);
        table_view.setInt32(pos + 4, text.length, true);
        table_view.setInt32(pos + 8, 0, true);
        table_view.setInt32(pos + 12, 1, true);
        text.copy(table, pos + 16);

        const cases = [
            Buffer.concat([table, Buffer.alloc(8), Buffer.from([1])]),
            Buffer.concat([Buffer.alloc(8), Buffer.from([1])]),
            Buffer.concat([table, Buffer.from([1, 2, 3])]),
        ];
        for (const [index, suffix] of cases.entries()) {
            const complete = Buffer.concat([
                Buffer.from(built.buffer), suffix,
            ]);
            const buffer = complete.buffer.slice(
                complete.byteOffset,
                complete.byteOffset + complete.byteLength
            );
            const meta = parse_legacy_metadata(
                buffer, complete.byteLength
            );
            expect(() => parse_value_labels(buffer, meta)).toThrow(
                'Corrupt value label table'
            );

            const dir = mkdtempSync(
                join(tmpdir(), `dta-trailing-labels-${index}-`)
            );
            const path = join(dir, 'labels.dta');
            try {
                writeFileSync(path, complete);
                await expect(DtaFile.open(path)).rejects.toThrow(
                    'Corrupt value label table'
                );
            } finally {
                rmSync(dir, { recursive: true, force: true });
            }
        }
    });

    it('keeps in-memory and Node file-backed readers in parity for release 108', async () => {
        const built = build_legacy_buffer({
            version: 108, nvar: 2, nobs: 1,
            type_codes: [108, 131], varnames: ['number', 'text'],
        });
        const meta = parse_legacy_metadata(built.buffer, built.file_size);
        const view = new DataView(built.buffer);
        view.setInt32(meta.section_offsets.data, 42, true);
        new Uint8Array(built.buffer).set([0x63, 0x61, 0x66, 0xe9], meta.section_offsets.data + 4);
        const memory_rows = read_rows_from_buffer(built.buffer, meta, 0, 1);
        const dir = mkdtempSync(join(tmpdir(), 'dta-early-'));
        const path = join(dir, 'release108.dta');
        try {
            writeFileSync(path, Buffer.from(built.buffer));
            const file = await DtaFile.open(path);
            try {
                expect(file.format_version).toBe(108);
                expect(await file.read_rows(0, 1)).toEqual(memory_rows);
                expect(await file.read_columns([0, 1])).toEqual(new Map([
                    [0, [42]], [1, ['café']],
                ]));
            } finally {
                file.close();
            }
        } finally {
            rmSync(dir, { recursive: true, force: true });
        }
    });

});
