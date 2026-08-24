import { afterEach, describe, expect, it } from 'bun:test';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import {
    parse_metadata,
    parse_legacy_metadata,
    parse_value_labels,
    read_rows_from_buffer,
    resolve_text_encoding,
} from '../../src/index';
import { DtaFile } from '../../src/node';

const FIXTURE_DIR = path.resolve(
    __dirname, '../../../../tests/fixtures/dta'
);

let temporary_directory: string | null = null;

afterEach(() => {
    if (temporary_directory !== null) {
        fs.rmSync(temporary_directory, {
            recursive: true,
            force: true,
        });
        temporary_directory = null;
    }
});

function fixture(name: string): Uint8Array {
    return new Uint8Array(
        fs.readFileSync(path.join(FIXTURE_DIR, name))
    );
}

function as_array_buffer(bytes: Uint8Array): ArrayBuffer {
    return bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
    ) as ArrayBuffer;
}

function replace_first_byte(
    bytes: Uint8Array,
    needle: string,
    replacement: number
): void {
    const the_needle = new TextEncoder().encode(needle);
    const my_offset = bytes.findIndex((_, index) => {
        if (index + the_needle.length > bytes.length) return false;
        return the_needle.every(
            (byte, inner_index) => bytes[index + inner_index] === byte
        );
    });
    if (my_offset < 0) {
        throw new Error(`fixture does not contain ${JSON.stringify(needle)}`);
    }
    bytes[my_offset] = replacement;
}

function replace_first_sequence(
    bytes: Uint8Array,
    needle: string,
    replacement: Uint8Array
): void {
    const the_needle = new TextEncoder().encode(needle);
    if (the_needle.length !== replacement.length) {
        throw new Error('replacement must preserve the fixture byte length');
    }
    const my_offset = bytes.findIndex((_, index) => {
        if (index + the_needle.length > bytes.length) return false;
        return the_needle.every(
            (byte, inner_index) => bytes[index + inner_index] === byte
        );
    });
    if (my_offset < 0) {
        throw new Error(`fixture does not contain ${JSON.stringify(needle)}`);
    }
    bytes.set(replacement, my_offset);
}

function mutate_ordinary_text(bytes: Uint8Array): void {
    replace_first_byte(bytes, '1978 automobile data', 0x80);
    replace_first_byte(bytes, 'Make and model', 0x80);
    replace_first_byte(bytes, 'AMC Concord', 0x80);
    replace_first_byte(bytes, 'Domestic', 0x80);
}

function first_text_surfaces(
    buffer: ArrayBuffer,
    encoding?: 'utf-8' | 'windows-1252' | 'iso-8859-1'
): string[] {
    const metadata = parse_metadata(
        buffer, encoding === undefined ? {} : { encoding }
    );
    const rows = read_rows_from_buffer(buffer, metadata, 0, 1);
    const labels = parse_value_labels(buffer, metadata);
    return [
        metadata.dataset_label,
        metadata.variables[0].label,
        rows[0][0] as string,
        labels.get('origin')?.get(0) ?? '',
    ];
}

describe('text encoding policy', () => {
    it('uses Windows-1252 through release 117 and permits strict UTF-8', () => {
        const bytes = fixture('auto_v117.dta');
        mutate_ordinary_text(bytes);
        const buffer = as_array_buffer(bytes);

        const auto = first_text_surfaces(buffer);
        const strict = first_text_surfaces(buffer, 'utf-8');
        const latin1 = first_text_surfaces(buffer, 'iso-8859-1');

        expect(auto.every(value => value.startsWith('\u20ac'))).toBe(true);
        expect(strict.every(value => value.startsWith('\ufffd'))).toBe(true);
        expect(latin1.every(value => value.startsWith('\u0080'))).toBe(true);
        expect(parse_metadata(buffer).text_encoding).toBe('windows-1252');
    });

    it('uses UTF-8 automatically for release 118', () => {
        const bytes = fixture('auto_v118.dta');
        const euro = new TextEncoder().encode('\u20ac');
        replace_first_sequence(bytes, '197', euro);
        replace_first_sequence(bytes, 'Mak', euro);
        replace_first_sequence(bytes, 'AMC', euro);
        replace_first_sequence(bytes, 'Dom', euro);
        const buffer = as_array_buffer(bytes);

        expect(
            first_text_surfaces(buffer).every(
                value => value.startsWith('\u20ac')
            )
        ).toBe(true);
        expect(parse_metadata(buffer).text_encoding).toBe('utf-8');
    });

    it('applies an explicit encoding to legacy metadata, rows, and labels', () => {
        const bytes = fixture('auto_v115.dta');
        mutate_ordinary_text(bytes);
        const buffer = as_array_buffer(bytes);
        const metadata = parse_legacy_metadata(
            buffer, bytes.byteLength, { encoding: 'ISO-8859-1' }
        );
        const rows = read_rows_from_buffer(buffer, metadata, 0, 1);
        const labels = parse_value_labels(buffer, metadata);

        expect(metadata.text_encoding).toBe('iso-8859-1');
        expect(metadata.dataset_label).toStartWith('\u0080');
        expect(metadata.variables[0].label).toStartWith('\u0080');
        expect(rows[0][0] as string).toStartWith('\u0080');
        expect(labels.get('origin')?.get(0)).toStartWith('\u0080');
    });

    it('threads an explicit encoding through the Node entrypoint and strL', async () => {
        const ordinary = fixture('auto_v117.dta');
        mutate_ordinary_text(ordinary);
        const strl = fixture('strl_test_v118.dta');
        replace_first_byte(strl, 'This is observation 1', 0x80);

        temporary_directory = fs.mkdtempSync(
            path.join(os.tmpdir(), 'dta-parser-encoding-')
        );
        const ordinary_path = path.join(temporary_directory, 'ordinary.dta');
        const strl_path = path.join(temporary_directory, 'strl.dta');
        fs.writeFileSync(ordinary_path, ordinary);
        fs.writeFileSync(strl_path, strl);

        const strict = await DtaFile.open(
            ordinary_path, { encoding: 'utf-8' }
        );
        const cp1252 = await DtaFile.open(
            strl_path, { encoding: 'windows-1252' }
        );
        const latin1 = await DtaFile.open(
            strl_path, { encoding: 'iso-8859-1' }
        );
        try {
            expect(strict.dataset_label.startsWith('\ufffd')).toBe(true);
            expect(
                (await strict.read_rows(0, 1))[0][0] as string
            ).toStartWith('\ufffd');
            expect(
                (await cp1252.read_rows(0, 1))[0][0] as string
            ).toStartWith('\u20ac');
            expect(
                (await latin1.read_rows(0, 1))[0][0] as string
            ).toStartWith('\u0080');
        } finally {
            strict.close();
            cp1252.close();
            latin1.close();
        }
    });

    it('rejects unsupported encoding names deterministically', () => {
        expect(() => resolve_text_encoding(
            117, 'koi8-r'
        )).toThrow('Unsupported text encoding');
    });

    it('normalizes the documented aliases', () => {
        expect(resolve_text_encoding(117, 'UTF8')).toBe('utf-8');
        expect(resolve_text_encoding(118, 'CP1252')).toBe('windows-1252');
        expect(resolve_text_encoding(118, 'latin1')).toBe('iso-8859-1');
    });
});
