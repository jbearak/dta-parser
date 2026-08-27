import { describe, it, expect } from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';
import { parse_metadata } from '../../src/header';
import {
    build_gso_index as build_public_gso_index,
    resolve_strl as resolve_public_strl,
} from '../../src/index';
import {
    build_gso_index,
    decode_gso_entry,
    read_strl_pointer,
    resolve_strl,
} from '../../src/strl-reader';
import type { DtaMetadata } from '../../src/types';
import {
    V119_STRL_VALUE,
    v119_strl_fixture,
} from '../helpers/v119-strl-fixture';

// -----------------------------------------------------------
// strL (GSO) resolution tests
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

describe('build_gso_index', () => {

    // ----- release-119 pointer layout and checked strL fixture -----

    describe('release-specific pointer layouts', () => {
        const { buffer, metadata } =
            load_fixture('strl_test.dta');

        function boundary_metadata(
            byte_order: 'LSF' | 'MSF'
        ): DtaMetadata {
            const my_variable_id = 0x010203;
            const the_variables = new Array(
                my_variable_id
            );
            the_variables[my_variable_id - 1] = {
                ...metadata.variables[0],
                type: 'strL',
            };
            return {
                ...metadata,
                format_version: 119,
                byte_order,
                nvar: my_variable_id,
                nobs: 0x0102030405,
                variables: the_variables,
            };
        }

        it('reads little-endian release-119 3+5 boundary bytes', () => {
            const my_little_endian = new Uint8Array([
                0x03, 0x02, 0x01,
                0x05, 0x04, 0x03, 0x02, 0x01,
            ]);

            expect(read_strl_pointer(
                new DataView(my_little_endian.buffer),
                boundary_metadata('LSF'),
                0
            )).toEqual({
                v: 0x010203,
                o: 0x0102030405,
            });
        });

        it('reads big-endian release-119 3+5 boundary bytes', () => {
            const my_big_endian = new Uint8Array([
                0x01, 0x02, 0x03,
                0x01, 0x02, 0x03, 0x04, 0x05,
            ]);

            expect(read_strl_pointer(
                new DataView(my_big_endian.buffer),
                boundary_metadata('MSF'),
                0
            )).toEqual({
                v: 0x010203,
                o: 0x0102030405,
            });
        });

        it('resolves release-119 strLs from complete buffers', () => {
            for (const my_byte_order of ['LSF', 'MSF'] as const) {
                const my_buffer = v119_strl_fixture(my_byte_order);
                const my_metadata = parse_metadata(my_buffer);
                const my_index = build_public_gso_index(
                    my_buffer, my_metadata
                );
                expect(resolve_public_strl(
                    my_buffer,
                    my_metadata,
                    my_index,
                    my_metadata.section_offsets.data + 6
                )).toBe(V119_STRL_VALUE);
            }
        });

        it('indexes the maximum safe GSO observation in both byte orders', () => {
            for (const my_byte_order of ['LSF', 'MSF'] as const) {
                const my_buffer = v119_strl_fixture(my_byte_order);
                const my_metadata = parse_metadata(my_buffer);
                const my_copy = my_buffer.slice(0);
                const my_o_offset =
                    my_metadata.section_offsets.strls
                    + '<strls>'.length
                    + 'GSO'.length
                    + 4;
                const my_view = new DataView(my_copy);
                if (my_byte_order === 'LSF') {
                    my_view.setUint32(my_o_offset, 0xffff_ffff, true);
                    my_view.setUint32(
                        my_o_offset + 4, 0x001f_ffff, true
                    );
                } else {
                    my_view.setUint32(
                        my_o_offset, 0x001f_ffff, false
                    );
                    my_view.setUint32(
                        my_o_offset + 4, 0xffff_ffff, false
                    );
                }

                expect(build_gso_index(my_copy, {
                    ...my_metadata,
                    nobs: Number.MAX_SAFE_INTEGER,
                }).has(`1:${Number.MAX_SAFE_INTEGER}`)).toBe(true);
            }
        });

        it('builds an index from strl_test.dta', () => {
            const my_index = build_gso_index(
                buffer, metadata
            );
            // 5 observations with strL values
            expect(my_index.size).toBeGreaterThan(0);
        });

        it('resolves strL values to strings', () => {
            const my_index = build_gso_index(
                buffer, metadata
            );

            // Find the strL variable
            const my_strl_var = metadata.variables.find(
                v => v.type === 'strL'
            );
            expect(my_strl_var).toBeDefined();

            // Data starts after the <data> tag (6 bytes)
            const my_data_start =
                metadata.section_offsets.data + 6;

            // Read first observation's strL pointer
            const my_pointer_offset =
                my_data_start + my_strl_var!.byte_offset;
            const my_val = resolve_strl(
                buffer, metadata, my_index, my_pointer_offset
            );

            expect(typeof my_val).toBe('string');
            expect(my_val!.length).toBeGreaterThan(0);
        });

        it('resolves all 5 observations', () => {
            const my_index = build_gso_index(
                buffer, metadata
            );

            const my_strl_var = metadata.variables.find(
                v => v.type === 'strL'
            );
            expect(my_strl_var).toBeDefined();

            const my_data_start =
                metadata.section_offsets.data + 6;

            const the_values: (string | null)[] = [];
            for (let i = 0; i < 5; i++) {
                const my_pointer_offset = my_data_start
                    + i * metadata.obs_length
                    + my_strl_var!.byte_offset;
                the_values.push(
                    resolve_strl(
                        buffer,
                        metadata,
                        my_index,
                        my_pointer_offset
                    )
                );
            }

            // All 5 should be strings (not null)
            for (const my_val of the_values) {
                expect(typeof my_val).toBe('string');
            }

            // Obs 4 has (v=0,o=0) pointer => empty string
            expect(the_values[3]).toBe('');

            // The other 4 should be non-empty
            for (let i = 0; i < 5; i++) {
                if (i === 3) continue;
                expect(the_values[i]!.length)
                    .toBeGreaterThan(0);
            }

            // Each value should be distinct
            const my_unique = new Set(the_values);
            expect(my_unique.size).toBe(5);
        });
    });

    // ----- strl_test_v118.dta -----

    describe('strl_test_v118.dta', () => {
        it('resolves strL values from v118 format', () => {
            const { buffer, metadata } =
                load_fixture('strl_test_v118.dta');
            const my_index = build_gso_index(
                buffer, metadata
            );

            const my_strl_var = metadata.variables.find(
                v => v.type === 'strL'
            );
            expect(my_strl_var).toBeDefined();

            const my_data_start =
                metadata.section_offsets.data + 6;

            const my_pointer_offset =
                my_data_start + my_strl_var!.byte_offset;
            const my_val = resolve_strl(
                buffer, metadata, my_index, my_pointer_offset
            );

            expect(typeof my_val).toBe('string');
            expect(my_val!.length).toBeGreaterThan(0);
        });

        it('reads all six little-endian observation bytes', () => {
            const { metadata } = load_fixture('strl_test_v118.dta');
            const my_buffer = new ArrayBuffer(8);
            const my_view = new DataView(my_buffer);

            my_view.setUint16(0, 1, true);
            my_view.setUint32(2, 1, true);
            my_view.setUint16(6, 1, true);

            expect(read_strl_pointer(my_view, {
                ...metadata,
                nobs: 0x100000001,
            }, 0)).toEqual({
                v: 1,
                o: 0x100000001,
            });
        });

        it('rejects GSO observation numbers above the safe range', () => {
            const { buffer, metadata } =
                load_fixture('strl_test_v118.dta');
            const my_copy = buffer.slice(0);
            const my_first_gso = metadata.section_offsets.strls + 7;
            const my_o_offset = my_first_gso + 3 + 4;
            const my_view = new DataView(my_copy);
            my_view.setUint32(my_o_offset, 0, true);
            my_view.setUint32(my_o_offset + 4, 0x20_0000, true);

            expect(() => build_gso_index(
                my_copy,
                { ...metadata, nobs: Number.MAX_SAFE_INTEGER }
            )).toThrow('safe integer range');
        });
    });

    // ----- (v=0, o=0) empty pointer -----

    it('returns empty string for (v=0, o=0) pointer', () => {
        const { buffer, metadata } =
            load_fixture('strl_test.dta');
        const my_index = build_gso_index(
            buffer, metadata
        );

        // Create a fake buffer with a zero pointer
        const my_fake_buf = new ArrayBuffer(8);
        const my_view = new DataView(my_fake_buf);
        my_view.setUint32(0, 0, true); // v = 0
        my_view.setUint32(4, 0, true); // o = 0

        const my_val = resolve_strl(
            my_fake_buf, metadata, my_index, 0
        );
        expect(my_val).toBe('');
    });

    // ----- Dataset without strL -----

    it('returns empty index for datasets without strL', () => {
        const { buffer, metadata } =
            load_fixture('auto_v118.dta');
        const my_index = build_gso_index(
            buffer, metadata
        );
        expect(my_index.size).toBe(0);
    });

    it('resolves a shared GSO reference deterministically', () => {
        const { buffer, metadata } =
            load_fixture('strl_test_v118.dta');
        const my_copy = buffer.slice(0);
        const my_bytes = new Uint8Array(my_copy);
        const my_data_start = metadata.section_offsets.data + 6;
        const my_strl = metadata.variables[0];
        const my_first = my_data_start + my_strl.byte_offset;
        const my_fifth = my_first + 4 * metadata.obs_length;
        my_bytes.set(my_bytes.subarray(my_first, my_first + 8), my_fifth);
        const my_index = build_gso_index(my_copy, metadata);
        expect(resolve_strl(
            my_copy, metadata, my_index, my_first
        )).toBe(resolve_strl(
            my_copy, metadata, my_index, my_fifth
        ));
    });

    it('rejects partial and dangling pointers like the Rust core', () => {
        const { buffer, metadata } =
            load_fixture('strl_test_v118.dta');
        const my_pointer = metadata.section_offsets.data + 6;

        const my_partial = buffer.slice(0);
        new DataView(my_partial).setUint16(my_pointer, 0, true);
        expect(() => resolve_strl(
            my_partial,
            metadata,
            build_gso_index(my_partial, metadata),
            my_pointer
        )).toThrow('Invalid strL pointer 0:1');

        const my_dangling = buffer.slice(0);
        const my_view = new DataView(my_dangling);
        my_view.setUint32(my_pointer + 2, 4, true);
        my_view.setUint16(my_pointer + 6, 0, true);
        expect(() => resolve_strl(
            my_dangling,
            metadata,
            build_gso_index(my_dangling, metadata),
            my_pointer
        )).toThrow('Dangling strL pointer 1:4');
    });

    it('rejects duplicate keys, invalid types, and unterminated text like Rust', () => {
        const { buffer, metadata } =
            load_fixture('strl_test_v118.dta');
        const my_first = metadata.section_offsets.strls + 7;
        const my_length = new DataView(buffer).getUint32(
            my_first + 16, true
        );
        const my_second = my_first + 20 + my_length;

        const my_duplicate = buffer.slice(0);
        const my_duplicate_bytes = new Uint8Array(my_duplicate);
        my_duplicate_bytes.set(
            new Uint8Array(buffer, my_first + 3, 12),
            my_second + 3
        );
        expect(() => build_gso_index(
            my_duplicate, metadata
        )).toThrow('Duplicate GSO key 1:1');

        const my_invalid_type = buffer.slice(0);
        new Uint8Array(my_invalid_type)[my_first + 15] = 42;
        expect(() => build_gso_index(
            my_invalid_type, metadata
        )).toThrow('Unsupported GSO type 42');

        const my_unterminated = buffer.slice(0);
        new Uint8Array(my_unterminated)[
            my_first + 20 + my_length - 1
        ] = 0x78;
        expect(() => build_gso_index(
            my_unterminated, metadata
        )).toThrow('not NUL-terminated');

        expect(() => decode_gso_entry(
            new Uint8Array([0x61]),
            { content_offset: 0, content_length: 1, type: 130 }
        )).toThrow('not NUL-terminated');
        expect(() => decode_gso_entry(
            new Uint8Array([0]),
            { content_offset: 0, content_length: 2, type: 130 }
        )).toThrow('Truncated GSO content');
    });
});
