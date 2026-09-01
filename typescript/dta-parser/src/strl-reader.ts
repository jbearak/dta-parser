// -----------------------------------------------------------
// strL (GSO) resolution
//
// strL variables store variable-length strings in a GSO
// (Generic String Object) block at the end of the file.
// In the data section, each strL cell is an 8-byte pointer
// (v, o) that references a GSO entry.
//
// Supports format versions 117, 118, and 119.
// -----------------------------------------------------------

import type {
    DtaMetadata,
    DtaReadPlan,
    PackedDtaReadPlan,
    ReadVariablePlan,
} from './types';
import { isPackedDtaReadPlan } from './types';
import type { ResolvedTextEncoding } from './text-encoding';
import {
    resolve_text_encoding,
    text_decoder,
} from './text-encoding';

// -----------------------------------------------------------
// Public interfaces
// -----------------------------------------------------------

export interface GsoEntry {
    content_offset: number;  // offset within the supplied buffer
    content_length: number;  // bytes of content
    type: number;            // 129=binary, 130=ASCII
}

export interface StrlPointer {
    v: number;
    o: number;
}

function readVariable(
    metadata: DtaReadPlan | PackedDtaReadPlan,
    index: number
): ReadVariablePlan | undefined {
    return isPackedDtaReadPlan(metadata)
        ? metadata.variable(index)
        : metadata.variables[index];
}

// -----------------------------------------------------------
// Constants
// -----------------------------------------------------------

const GSO_MARKER = [0x47, 0x53, 0x4F]; // "GSO"
const STRLS_TAG = '<strls>';
const STRLS_TAG_LENGTH = STRLS_TAG.length; // 7

const ASCII_DECODER = new TextDecoder('utf-8');

// -----------------------------------------------------------
// Implementation
// -----------------------------------------------------------

/**
 * Build an index of all GSO entries from the strls section.
 *
 * Returns a Map keyed by "v:o" string for O(1) lookup. Content offsets
 * are relative to `buffer`; `base_offset` only maps file coordinates into it.
 * The map is empty when the dataset has no strL variables.
 */
export function build_gso_index(
    buffer: ArrayBuffer,
    metadata: DtaReadPlan | PackedDtaReadPlan,
    base_offset: number = 0
): Map<string, GsoEntry> {
    const my_index = new Map<string, GsoEntry>();

    // Quick exit: no strL variables means no GSO entries
    const my_has_strl = isPackedDtaReadPlan(metadata)
        ? metadata.strl_columns.length > 0
        : metadata.variables.some(v => v.type === 'strL');
    if (!my_has_strl) return my_index;

    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    const little_endian = metadata.byte_order === 'LSF';

    const my_section_start =
        metadata.section_offsets.strls - base_offset;
    if (
        my_section_start < 0
        || my_section_start + STRLS_TAG_LENGTH > bytes.length
        || ASCII_DECODER.decode(bytes.subarray(
            my_section_start,
            my_section_start + STRLS_TAG_LENGTH
        )) !== STRLS_TAG
    ) {
        throw new Error('Invalid <strls> section opening tag');
    }
    let pos = my_section_start + STRLS_TAG_LENGTH;

    // The section ends at the value_labels offset
    const my_section_end =
        metadata.section_offsets.value_labels
        - base_offset;
    const my_close_start = my_section_end - 8;
    if (
        my_close_start < pos
        || my_section_end > bytes.length
        || ASCII_DECODER.decode(bytes.subarray(
            my_close_start, my_section_end
        )) !== '</strls>'
    ) {
        throw new Error('Invalid </strls> section closing tag');
    }

    while (pos < my_close_start) {
        // Check for "GSO" marker
        if (
            pos + 3 > my_close_start
            ||
            bytes[pos] !== GSO_MARKER[0]
            || bytes[pos + 1] !== GSO_MARKER[1]
            || bytes[pos + 2] !== GSO_MARKER[2]
        ) {
            throw new Error(`Invalid GSO marker at offset ${pos + base_offset}`);
        }
        pos += 3;

        const my_header_tail = metadata.format_version === 117
            ? 13
            : 17;
        if (pos + my_header_tail > my_close_start) {
            throw new Error('Truncated GSO header');
        }

        // Read v (variable number, 1-indexed)
        const my_v = view.getUint32(pos, little_endian);
        pos += 4;

        // Read o (observation number, 1-indexed)
        // v117: uint32; v118/v119: uint64
        let my_o: number;
        if (metadata.format_version === 117) {
            my_o = view.getUint32(pos, little_endian);
            pos += 4;
        } else {
            const my_hi = little_endian
                ? view.getUint32(pos + 4, true)
                : view.getUint32(pos, false);
            const my_lo = little_endian
                ? view.getUint32(pos, true)
                : view.getUint32(pos + 4, false);
            if (my_hi > 0x1F_FFFF) {
                throw new Error(
                    'strL observation number exceeds '
                    + 'JavaScript safe integer range'
                );
            }
            my_o = my_hi * 0x1_0000_0000 + my_lo;
            pos += 8;
        }

        const my_variable = readVariable(metadata, my_v - 1);
        if (
            my_v < 1
            || my_o < 1
            || my_o > metadata.nobs
            || !my_variable
            || my_variable.type !== 'strL'
        ) {
            throw new Error(`Invalid GSO key ${my_v}:${my_o}`);
        }

        // type: 129=binary, 130=ASCII
        const my_type = bytes[pos];
        if (my_type !== 129 && my_type !== 130) {
            throw new Error(`Unsupported GSO type ${my_type}`);
        }
        pos += 1;

        // len: content length (includes null terminator
        //      for ASCII type 130)
        const my_len = view.getUint32(pos, little_endian);
        pos += 4;
        if (pos + my_len > my_close_start) {
            throw new Error('Truncated GSO content');
        }
        if (
            my_type === 130
            && (my_len === 0 || bytes[pos + my_len - 1] !== 0)
        ) {
            throw new Error('Type-130 GSO content is not NUL-terminated');
        }

        const my_key = my_v + ':' + my_o;
        if (my_index.has(my_key)) {
            throw new Error(`Duplicate GSO key ${my_key}`);
        }
        my_index.set(my_key, {
            content_offset: pos,
            content_length: my_len,
            type: my_type,
        });

        pos += my_len;
    }

    if (pos !== my_close_start) {
        throw new Error('Unexpected bytes in <strls> section');
    }
    return my_index;
}

/**
 * Resolve a strL pointer at the given byte offset in the
 * data section. Returns the string content, or an empty string
 * for a (v=0, o=0) null pointer. A missing non-null GSO key is
 * rejected as corrupt input.
 *
 * The pointer_offset must point to the first byte of an
 * 8-byte strL pointer field.
 */
export function resolve_strl(
    buffer: ArrayBuffer,
    metadata: DtaMetadata,
    gso_index: Map<string, GsoEntry>,
    pointer_offset: number
): string {
    const view = new DataView(buffer);
    const bytes = new Uint8Array(buffer);
    const my_pointer = read_strl_pointer(
        view, metadata, pointer_offset
    );
    if (!my_pointer) return '';

    const my_key = my_pointer.v + ':' + my_pointer.o;
    const my_entry = gso_index.get(my_key);
    if (!my_entry) {
        throw new Error(`Dangling strL pointer ${my_key}`);
    }

    return decode_gso_entry(
        bytes,
        my_entry,
        resolve_text_encoding(
            metadata.format_version, metadata.text_encoding
        )
    );
}

export function read_strl_pointer(
    view: DataView,
    metadata: DtaReadPlan | PackedDtaReadPlan,
    pointer_offset: number
): StrlPointer | null {
    const little_endian = metadata.byte_order === 'LSF';

    // v118 pointer layout (LE):
    //   bytes 0-1: v (uint16)
    //   bytes 2-7: o (6-byte little-endian integer)
    // v119 pointer layout (LE):
    //   bytes 0-2: v (3-byte little-endian integer)
    //   bytes 3-7: o (5-byte little-endian integer)
    // v117 pointer layout:
    //   bytes 0-3: v (uint32)
    //   bytes 4-7: o (uint32)
    let my_v: number;
    let my_o: number;

    if (metadata.format_version === 117) {
        my_v = view.getUint32(
            pointer_offset, little_endian
        );
        my_o = view.getUint32(
            pointer_offset + 4, little_endian
        );
    } else if (metadata.format_version === 118) {
        if (little_endian) {
            my_v = view.getUint16(pointer_offset, true);
            const my_lo = view.getUint32(
                pointer_offset + 2, true
            );
            const my_hi = view.getUint16(
                pointer_offset + 6, true
            );
            my_o = my_hi * 0x100000000 + my_lo;
        } else {
            my_v = view.getUint16(pointer_offset, false);
            const my_hi = view.getUint16(
                pointer_offset + 2, false
            );
            const my_lo = view.getUint32(
                pointer_offset + 4, false
            );
            my_o = my_hi * 0x100000000 + my_lo;
        }
    } else if (little_endian) {
        my_v = view.getUint16(pointer_offset, true)
            + view.getUint8(pointer_offset + 2) * 0x10000;
        my_o = view.getUint32(pointer_offset + 3, true)
            + view.getUint8(pointer_offset + 7) * 0x100000000;
    } else {
        my_v = view.getUint8(pointer_offset) * 0x10000
            + view.getUint16(pointer_offset + 1, false);
        my_o = view.getUint8(pointer_offset + 3) * 0x100000000
            + view.getUint32(pointer_offset + 4, false);
    }

    if (my_v === 0 && my_o === 0) {
        return null;
    }

    const my_variable = readVariable(metadata, my_v - 1);
    if (
        my_v < 1
        || my_o < 1
        || my_o > metadata.nobs
        || !my_variable
        || my_variable.type !== 'strL'
    ) {
        throw new Error(`Invalid strL pointer ${my_v}:${my_o}`);
    }

    return { v: my_v, o: my_o };
}

export function decode_gso_entry(
    bytes: Uint8Array,
    entry: GsoEntry,
    encoding: ResolvedTextEncoding = 'utf-8'
): string {
    if (entry.type !== 129 && entry.type !== 130) {
        throw new Error(`Unsupported GSO type ${entry.type}`);
    }
    const my_content_end = entry.content_offset
        + entry.content_length;
    if (
        entry.content_offset < 0
        || entry.content_length < 0
        || my_content_end > bytes.length
    ) {
        throw new Error('Truncated GSO content');
    }
    // Decode content
    if (entry.type === 130) {
        // ASCII: content_length includes null terminator
        if (
            entry.content_length === 0
            || bytes[my_content_end - 1] !== 0
        ) {
            throw new Error(
                'Type-130 GSO content is not NUL-terminated'
            );
        }
        const my_str_len = entry.content_length - 1;
        return text_decoder(encoding).decode(
            bytes.subarray(
                entry.content_offset,
                entry.content_offset + my_str_len
            )
        );
    }

    // Binary (type 129): return raw bytes as string
    return text_decoder(encoding).decode(
        bytes.subarray(
            entry.content_offset,
            entry.content_offset + entry.content_length
        )
    );
}
