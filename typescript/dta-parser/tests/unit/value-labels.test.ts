import { describe, it, expect } from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';
import { parse_metadata } from '../../src/header';
import { parse_legacy_metadata } from '../../src/legacy-header';
import { parse_value_labels } from '../../src/value-labels';
import type { DtaMetadata } from '../../src/types';

// -----------------------------------------------------------
// Value label table parsing tests
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
    const my_meta = my_buf[0] === 115
        ? parse_legacy_metadata(my_array_buf, my_buf.length)
        : parse_metadata(my_array_buf);
    return { buffer: my_array_buf, metadata: my_meta };
}

describe('parse_value_labels', () => {

    describe('structural validation', () => {
        for (const name of ['auto_v117.dta', 'auto_v118.dta', 'auto_v115.dta']) {
            it(`${name}: rejects inconsistent declared table lengths`, () => {
                for (const length of [0, 1, -1, 8, 0x7fffffff]) {
                    const { buffer, metadata } = load_fixture(name);
                    const offset = metadata.section_offsets.value_labels
                        + (metadata.format_version === 115 ? 0 : '<value_labels><lbl>'.length);
                    new DataView(buffer).setInt32(offset, length, metadata.byte_order === 'LSF');
                    expect(() => parse_value_labels(buffer, metadata)).toThrow();
                }
            });
        }

        for (const tag of ['<value_labels>', '<lbl>', '</lbl>', '</value_labels>']) {
            it(`rejects damaged ${tag} framing`, () => {
                const { buffer, metadata } = load_fixture('auto_v118.dta');
                const bytes = Buffer.from(buffer);
                const offset = bytes.indexOf(tag, metadata.section_offsets.value_labels);
                expect(offset).toBeGreaterThanOrEqual(0);
                bytes[offset] = 88;
                expect(() => parse_value_labels(buffer, metadata)).toThrow();
            });
        }

        it('rejects unterminated modern table names', () => {
            const { buffer, metadata } = load_fixture('auto_v118.dta');
            const offset = metadata.section_offsets.value_labels + '<value_labels><lbl>'.length + 4;
            new Uint8Array(buffer).fill(65, offset, offset + 129);
            expect(() => parse_value_labels(buffer, metadata)).toThrow();
        });

        it('rejects text offsets inside a UTF-8 code point', () => {
            const { buffer, metadata } = load_fixture('auto_v118.dta');
            const payload = metadata.section_offsets.value_labels
                + '<value_labels><lbl>'.length + 4 + 129 + 3;
            const view = new DataView(buffer);
            const text = payload + 8 + view.getInt32(payload, true) * 8;
            new Uint8Array(buffer).set([0xc3, 0xa9], text);
            view.setInt32(payload + 8, 1, true);
            expect(() => parse_value_labels(buffer, metadata)).toThrow();
            metadata.text_encoding = 'windows-1252';
            expect(parse_value_labels(buffer, metadata).get('origin')?.get(0)).toStartWith('©');
        });

        it('rejects every continuation offset in valid two-, three-, and four-byte code points', () => {
            for (const codePoint of ['é', '€', '😀']) {
                const encoded = new TextEncoder().encode(codePoint);
                for (let offset = 1; offset < encoded.length; offset++) {
                    const { buffer, metadata } = load_fixture('auto_v118.dta');
                    const payload = metadata.section_offsets.value_labels
                        + '<value_labels><lbl>'.length + 4 + 129 + 3;
                    const view = new DataView(buffer);
                    const text = payload + 8 + view.getInt32(payload, true) * 8;
                    new Uint8Array(buffer).set(encoded, text);
                    view.setInt32(payload + 8, offset, true);
                    expect(() => parse_value_labels(buffer, metadata)).toThrow('inside a UTF-8 code point');
                }
            }
        });

        it('decodes many labels after a long invalid continuation run', () => {
            const count = 1000;
            const textLength = 1024 * 1024;
            const length = 8 + count * 8 + textLength;
            const payload = Buffer.alloc(4 + 129 + 3 + length);
            payload.writeInt32LE(length);
            payload.write('invalid_utf8', 4);
            const table = 4 + 129 + 3;
            payload.writeInt32LE(count, table);
            payload.writeInt32LE(textLength, table + 4);
            for (let i = 0; i < count; i++) {
                payload.writeInt32LE(textLength - 2, table + 8 + i * 4);
                payload.writeInt32LE(i, table + 8 + count * 4 + i * 4);
            }
            payload.fill(0x80, table + 8 + count * 8, payload.length - 1);
            const section = Buffer.concat([
                Buffer.from('<value_labels><lbl>'), payload, Buffer.from('</lbl></value_labels>'),
            ]);
            const bytes = Buffer.concat([section, Buffer.from('</stata_dta>')]);
            const { metadata } = load_fixture('auto_v118.dta');
            metadata.section_offsets.value_labels = 0;
            metadata.section_offsets.dta_data_close = section.length;
            metadata.section_offsets.end_of_file = bytes.length;
            const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
            const labels = parse_value_labels(buffer, metadata).get('invalid_utf8')!;
            expect(labels.size).toBe(count);
            expect([...labels.values()]).toEqual(Array(count).fill('\ufffd'));
        });

        it('rejects a truncated section even when the first table is intact', () => {
            const { buffer, metadata } = load_fixture('auto_v118.dta');
            expect(() => parse_value_labels(
                buffer.slice(0, metadata.section_offsets.dta_data_close - 1), metadata
            )).toThrow();
        });
    });

    // ----- value_labels.dta -----

    describe('value_labels.dta', () => {
        const { buffer, metadata } =
            load_fixture('value_labels.dta');

        it('parses value labels from value_labels.dta', () => {
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            // Should have 3 label tables
            expect(my_labels.size).toBe(3);
            expect(my_labels.has('foreign_lbl')).toBe(true);
            expect(my_labels.has('rep_lbl')).toBe(true);
            expect(my_labels.has('region_lbl')).toBe(true);
        });

        it('reads foreign label table correctly (0=Domestic, 1=Foreign)', () => {
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            const my_foreign = my_labels.get('foreign_lbl');
            expect(my_foreign).toBeDefined();
            expect(my_foreign!.get(0)).toBe('Domestic');
            expect(my_foreign!.get(1)).toBe('Foreign');
            expect(my_foreign!.size).toBe(2);
        });

        it('reads repair record label table (1=Poor, 5=Excellent)', () => {
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            const my_rep = my_labels.get('rep_lbl');
            expect(my_rep).toBeDefined();
            expect(my_rep!.get(1)).toBe('Poor');
            expect(my_rep!.get(5)).toBe('Excellent');
            expect(my_rep!.size).toBe(5);
        });

        it('reads region label table', () => {
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            const my_region = my_labels.get('region_lbl');
            expect(my_region).toBeDefined();
            expect(my_region!.size).toBeGreaterThan(0);
            // At least verify one entry exists
            const the_values = [...my_region!.values()];
            for (const my_val of the_values) {
                expect(typeof my_val).toBe('string');
                expect(my_val.length).toBeGreaterThan(0);
            }
        });
    });

    // ----- auto_v118.dta -----

    describe('auto_v118.dta', () => {
        it('parses auto.dta value labels (origin)', () => {
            const { buffer, metadata } =
                load_fixture('auto_v118.dta');
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            expect(my_labels.has('origin')).toBe(true);

            const my_origin = my_labels.get('origin');
            expect(my_origin).toBeDefined();
            expect(my_origin!.get(0)).toBe('Domestic');
            expect(my_origin!.get(1)).toBe('Foreign');
        });
    });

    // ----- Cross-version -----

    describe('cross-version', () => {
        it('parses v118 value labels fixture', () => {
            const { buffer, metadata } =
                load_fixture('value_labels_v118.dta');
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            expect(my_labels.size).toBe(3);
            expect(my_labels.has('foreign_lbl')).toBe(true);

            const my_foreign = my_labels.get('foreign_lbl');
            expect(my_foreign!.get(0)).toBe('Domestic');
            expect(my_foreign!.get(1)).toBe('Foreign');
        });

        it('parses v117 value labels fixture', () => {
            const { buffer, metadata } =
                load_fixture('value_labels_v117.dta');
            const my_labels = parse_value_labels(
                buffer, metadata
            );
            expect(my_labels.size).toBe(3);
            expect(my_labels.has('foreign_lbl')).toBe(true);

            const my_foreign = my_labels.get('foreign_lbl');
            expect(my_foreign!.get(0)).toBe('Domestic');
            expect(my_foreign!.get(1)).toBe('Foreign');
        });
    });

    // ----- Empty dataset -----

    it('returns empty map for datasets without value labels', () => {
        const { buffer, metadata } =
            load_fixture('empty.dta');
        const my_labels = parse_value_labels(
            buffer, metadata
        );
        expect(my_labels.size).toBe(0);
    });
});
