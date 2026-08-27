import type { FormatVersion } from './types';

/** Source encoding requested for textual fields in a Stata file. */
export type TextEncoding =
    | 'auto'
    | 'utf-8'
    | 'windows-1252'
    | 'iso-8859-1';

/** Common labels accepted by the R and Rust APIs as well as canonical names. */
export type TextEncodingLabel =
    | TextEncoding
    | 'UTF-8'
    | 'UTF8'
    | 'utf8'
    | 'Windows-1252'
    | 'CP1252'
    | 'cp1252'
    | 'ISO-8859-1'
    | 'latin1'
    | (string & Record<never, never>);

/** Concrete encoding selected after the file release is known. */
export type ResolvedTextEncoding = Exclude<TextEncoding, 'auto'>;

/** Options shared by metadata parsers and the Node file entrypoint. */
export interface TextEncodingOptions {
    /**
     * Source encoding for every textual field. `auto` uses Windows-1252
     * through release 117 and UTF-8 for releases 118--119.
     */
    encoding?: TextEncodingLabel;
}

export interface DtaTextDecoder {
    decode(input: Uint8Array): string;
}

/** Decode a byte range without allocating a view for the common ASCII case. */
export function decode_text_range(
    decoder: DtaTextDecoder,
    bytes: Uint8Array,
    start: number,
    end: number
): string {
    const my_length = end - start;
    // Native TextDecoder wins for longer fields even after the view
    // allocation. Short labels and fixed strings are faster inline.
    if (my_length > 12) {
        return decoder.decode(bytes.subarray(start, end));
    }
    for (let i = start; i < end; i++) {
        if (bytes[i] >= 0x80) {
            return decoder.decode(bytes.subarray(start, end));
        }
    }
    // Each arm creates one flat string. Incremental concatenation retains
    // short rope fragments and costs more memory in large label tables.
    switch (my_length) {
        case 0:
            return '';
        case 1:
            return String.fromCharCode(bytes[start]);
        case 2:
            return String.fromCharCode(bytes[start], bytes[start + 1]);
        case 3:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2]
            );
        case 4:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3]
            );
        case 5:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4]
            );
        case 6:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5]
            );
        case 7:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6]
            );
        case 8:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6], bytes[start + 7]
            );
        case 9:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6], bytes[start + 7], bytes[start + 8]
            );
        case 10:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6], bytes[start + 7], bytes[start + 8],
                bytes[start + 9]
            );
        case 11:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6], bytes[start + 7], bytes[start + 8],
                bytes[start + 9], bytes[start + 10]
            );
        case 12:
            return String.fromCharCode(
                bytes[start], bytes[start + 1], bytes[start + 2],
                bytes[start + 3], bytes[start + 4], bytes[start + 5],
                bytes[start + 6], bytes[start + 7], bytes[start + 8],
                bytes[start + 9], bytes[start + 10], bytes[start + 11]
            );
        default:
            return decoder.decode(bytes.subarray(start, end));
    }
}

// DTA fields are independently bounded values, not BOM-signaled documents.
// Preserve a leading U+FEFF to match Rust's decoder_without_bom_handling.
const UTF8_DECODER = new TextDecoder(
    'utf-8', { ignoreBOM: true }
);
const WINDOWS_1252_DECODER = new TextDecoder(
    'windows-1252', { ignoreBOM: true }
);

const ISO_8859_1_DECODER: DtaTextDecoder = {
    decode(input: Uint8Array): string {
        // The Web Encoding Standard aliases ISO-8859-1 to Windows-1252,
        // so TextDecoder cannot express the distinct byte-for-code-point
        // behavior exposed by the Rust and R APIs.
        const my_chunk_size = 8192;
        let my_result = '';
        for (let i = 0; i < input.length; i += my_chunk_size) {
            my_result += String.fromCharCode(
                ...input.subarray(i, i + my_chunk_size)
            );
        }
        return my_result;
    },
};

function normalize_text_encoding(
    encoding: TextEncodingLabel = 'auto'
): TextEncoding {
    if (typeof encoding !== 'string') {
        throw new Error(
            `Unsupported text encoding ${JSON.stringify(encoding)}; `
            + 'use auto, utf-8, windows-1252, or iso-8859-1'
        );
    }
    const my_key = encoding.toLowerCase().replaceAll(/[-_ ]/g, '');
    switch (my_key) {
        case 'auto':
            return 'auto';
        case 'utf8':
            return 'utf-8';
        case 'windows1252':
        case 'cp1252':
            return 'windows-1252';
        case 'iso88591':
        case 'latin1':
            return 'iso-8859-1';
    }
    throw new Error(
        `Unsupported text encoding ${JSON.stringify(encoding)}; `
        + 'use auto, utf-8, windows-1252, or iso-8859-1'
    );
}

/** Validate an encoding label without requiring a file release. */
export function validate_text_encoding(
    encoding: TextEncodingLabel = 'auto'
): void {
    normalize_text_encoding(encoding);
}

/** Resolve the release-specific default or validate an explicit encoding. */
export function resolve_text_encoding(
    format_version: FormatVersion,
    encoding: TextEncodingLabel = 'auto'
): ResolvedTextEncoding {
    const my_encoding = normalize_text_encoding(encoding);
    if (my_encoding === 'auto') {
        return format_version >= 118
            ? 'utf-8'
            : 'windows-1252';
    }
    return my_encoding;
}

/** Return the deterministic decoder for an already resolved encoding. */
export function text_decoder(
    encoding: ResolvedTextEncoding
): DtaTextDecoder {
    switch (encoding) {
        case 'utf-8':
            return UTF8_DECODER;
        case 'windows-1252':
            return WINDOWS_1252_DECODER;
        case 'iso-8859-1':
            return ISO_8859_1_DECODER;
    }
}
