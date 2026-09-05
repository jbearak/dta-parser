// -----------------------------------------------------------
// Value label table parsing
//
// The <value_labels> section contains zero or more label
// tables, each wrapped in <lbl>...</lbl> tags. Each table
// maps integer values to string labels.
//
// Supports format versions 105, 108, 110-111, 113-115
// (legacy) and 117-119.
// -----------------------------------------------------------

import type { DtaMetadata } from './types';
import { is_legacy_format } from './types';
import {
    legacy_layout_for_version,
} from './legacy-layout';
import type {
    LegacyValueLabelLayout,
} from './legacy-layout';
import type { DtaTextDecoder } from './text-encoding';
import {
    decode_text_range,
    resolve_text_encoding,
    text_decoder,
} from './text-encoding';

// -----------------------------------------------------------
// Constants
// -----------------------------------------------------------

const VALUE_LABELS_TAG = '<value_labels>';
const VALUE_LABELS_CLOSE_TAG = '</value_labels>';
const VALUE_LABELS_TAG_LENGTH = VALUE_LABELS_TAG.length;
const LBL_OPEN_TAG = '<lbl>';
const MAX_VALUE_LABEL_ENTRIES = 65_536;
const STRICT_UTF8 = new TextDecoder('utf-8', { fatal: true });

/** Invalid UTF-8 bytes decode independently; only split valid code points fail. */
function is_utf8_boundary(bytes: Uint8Array, start: number, end: number, offset: number): boolean {
    if (offset === start || (bytes[offset] & 0xc0) !== 0x80) return true;
    let lead = offset;
    // A valid UTF-8 code point has at most three continuation bytes.
    // Invalid runs can be arbitrarily long and must not be rescanned per label.
    const earliest = Math.max(start, offset - 3);
    while (lead > earliest && (bytes[lead] & 0xc0) === 0x80) lead--;
    const byte = bytes[lead];
    const width = byte >= 0xc2 && byte <= 0xdf ? 2
        : byte >= 0xe0 && byte <= 0xef ? 3
        : byte >= 0xf0 && byte <= 0xf4 ? 4 : 0;
    if (width === 0 || offset >= lead + width || lead + width > end) return true;
    try {
        STRICT_UTF8.decode(bytes.subarray(lead, lead + width));
        return false;
    } catch {
        return true;
    }
}

function expect_tag(bytes: Uint8Array, pos: number, tag: string, end: number): number {
    if (pos + tag.length > end) throw new Error(`Truncated ${tag} tag`);
    for (let i = 0; i < tag.length; i++) {
        if (bytes[pos + i] !== tag.charCodeAt(i)) {
            throw new Error(`Expected ${tag} at offset ${pos}`);
        }
    }
    return pos + tag.length;
}

// Label name field widths for XML-wrapped formats
const MODERN_LABEL_NAME_WIDTH: Record<number, number> = {
    117: 33,
    118: 129,
    119: 129,
};

const PADDING_BYTES = 3;

// -----------------------------------------------------------
// Shared label entry parser
// -----------------------------------------------------------

/**
 * Parse a single value label entry starting at `pos`.
 * The binary payload (n, txt_len, offsets[], values[],
 * text[]) is identical across all format versions.
 *
 * Returns the parsed label map and the position after
 * the entry.
 */
function parse_label_entry_payload(
    bytes: Uint8Array,
    view: DataView,
    little_endian: boolean,
    pos: number,
    entry_end: number,
    decoder: DtaTextDecoder,
    declared_length: number,
    utf8: boolean
): { label_map: Map<number, string>; next_pos: number } {
    // n (int32): number of entries
    if (pos + 8 > entry_end) {
        throw new Error(
            'Corrupt value label table: truncated header'
        );
    }
    const my_n = view.getInt32(pos, little_endian);
    pos += 4;

    // txt_len (int32): total bytes in the text block
    const my_txt_len = view.getInt32(pos, little_endian);
    pos += 4;

    if (my_n < 0 || my_txt_len < 0) {
        throw new Error(
            'Corrupt value label table: negative count '
            + `or text length (n=${my_n}, `
            + `txt_len=${my_txt_len})`
        );
    }

    if (my_n > MAX_VALUE_LABEL_ENTRIES) {
        throw new Error('Corrupt value label table: entry count exceeds 65,536');
    }
    if (declared_length !== 8 + my_n * 8 + my_txt_len) {
        throw new Error('Corrupt value label table: inconsistent table length');
    }

    if (pos + my_n * 8 + my_txt_len > entry_end) {
        throw new Error(
            'Corrupt value label table: payload exceeds '
            + 'entry bounds'
        );
    }

    const my_offsets_start = pos;
    const my_values_start = my_offsets_start + my_n * 4;
    const my_text_start = my_values_start + my_n * 4;
    const my_label_map = new Map<number, string>();

    for (let i = 0; i < my_n; i++) {
        const my_text_offset = view.getInt32(
            my_offsets_start + i * 4,
            little_endian
        );
        if (my_text_offset < 0
            || my_text_offset >= my_txt_len) {
            throw new Error(
                'Corrupt value label table: invalid text offset'
            );
        }
        const my_str_start =
            my_text_start + my_text_offset;
        if (utf8 && !is_utf8_boundary(bytes, my_text_start,
            my_text_start + my_txt_len, my_str_start)) {
            throw new Error('Corrupt value label table: text offset is inside a UTF-8 code point');
        }
        let my_str_end = my_str_start;
        const my_str_limit =
            my_text_start + my_txt_len;

        while (
            my_str_end < my_str_limit
            && bytes[my_str_end] !== 0
        ) {
            my_str_end++;
        }

        if (my_str_end === my_str_limit) {
            throw new Error(
                'Corrupt value label table: missing text terminator'
            );
        }
        const my_label = decode_text_range(
            decoder, bytes, my_str_start, my_str_end
        );
        const my_value = view.getInt32(
            my_values_start + i * 4,
            little_endian
        );
        if (!my_label_map.has(my_value)) {
            my_label_map.set(my_value, my_label);
        }
    }

    return {
        label_map: my_label_map,
        next_pos: my_text_start + my_txt_len,
    };
}

/**
 * Read a null-terminated string from a fixed-width field.
 */
function read_label_name(
    bytes: Uint8Array,
    pos: number,
    name_width: number,
    decoder: DtaTextDecoder,
    require_terminator = false
): string {
    let my_end = pos;
    const my_limit = pos + name_width;
    while (my_end < my_limit && bytes[my_end] !== 0) {
        my_end++;
    }
    if (my_limit > bytes.length || (require_terminator && my_end === my_limit)) {
        throw new Error('Corrupt value label table: unterminated or truncated table name');
    }
    return decode_text_range(decoder, bytes, pos, my_end);
}

// -----------------------------------------------------------
// Modern format (117-119): XML-wrapped entries
// -----------------------------------------------------------

function parse_modern_entries(
    bytes: Uint8Array,
    view: DataView,
    little_endian: boolean,
    name_width: number,
    start_pos: number,
    section_end: number,
    decoder: DtaTextDecoder,
    utf8: boolean
): Map<string, Map<number, string>> {
    const my_result = new Map<string, Map<number, string>>();
    let pos = start_pos;

    const tables_end = section_end - VALUE_LABELS_CLOSE_TAG.length;
    while (pos < tables_end) {
        pos = expect_tag(bytes, pos, LBL_OPEN_TAG, tables_end);
        if (pos + 4 + name_width + PADDING_BYTES + 8 > tables_end) {
            throw new Error('Corrupt value label table: truncated header');
        }

        // table_length (int32)
        const declared_length = view.getInt32(pos, little_endian);
        pos += 4;

        // label_name
        const my_label_name = read_label_name(
            bytes, pos, name_width, decoder, true
        );
        pos += name_width;

        // 3 bytes padding
        pos += PADDING_BYTES;

        // Parse the entry payload
        const { label_map, next_pos } =
            parse_label_entry_payload(
                bytes, view, little_endian, pos,
                tables_end, decoder, declared_length, utf8
            );
        my_result.set(my_label_name, label_map);

        // Skip past text block + </lbl>
        pos = expect_tag(bytes, next_pos, '</lbl>', tables_end);
    }

    if (expect_tag(bytes, pos, VALUE_LABELS_CLOSE_TAG, section_end) !== section_end) {
        throw new Error('Corrupt value label section: trailing bytes');
    }

    return my_result;
}

// -----------------------------------------------------------
// Legacy offset-table formats: no XML wrapper
// -----------------------------------------------------------

function parse_legacy_entries(
    bytes: Uint8Array,
    view: DataView,
    little_endian: boolean,
    name_width: number,
    start_pos: number,
    section_end: number,
    decoder: DtaTextDecoder,
    utf8: boolean
): Map<string, Map<number, string>> {
    const my_result = new Map<string, Map<number, string>>();
    let pos = start_pos;
    let my_known_nonzero = -1;

    while (pos < section_end) {
        if (my_known_nonzero < pos) {
            my_known_nonzero = -1;
            for (let i = pos; i < section_end; i++) {
                if (bytes[i] !== 0) {
                    my_known_nonzero = i;
                    break;
                }
            }
        }
        if (my_known_nonzero < pos) break;
        if (pos + 4 + name_width + PADDING_BYTES + 8 > section_end) {
            throw new Error(
                'Corrupt value label table: trailing bytes'
            );
        }

        // table_length (int32)
        const my_table_len = view.getInt32(
            pos, little_endian
        );
        if (my_table_len <= 0) {
            throw new Error(
                'Corrupt value label table: invalid table length'
            );
        }
        pos += 4;

        // label_name
        const my_label_name = read_label_name(
            bytes, pos, name_width, decoder
        );
        pos += name_width;

        // 3 bytes padding
        pos += PADDING_BYTES;

        // Parse the entry payload (identical layout)
        const { label_map, next_pos } =
            parse_label_entry_payload(
                bytes, view, little_endian, pos,
                section_end, decoder, my_table_len, utf8
            );
        my_result.set(my_label_name, label_map);
        pos = next_pos;
    }

    return my_result;
}

function parse_fixed8_entries(
    bytes: Uint8Array,
    view: DataView,
    little_endian: boolean,
    name_width: number,
    start_pos: number,
    section_end: number,
    decoder: DtaTextDecoder
): Map<string, Map<number, string>> {
    const my_result = new Map<string, Map<number, string>>();
    let pos = start_pos;
    let my_known_nonzero = -1;
    while (pos < section_end) {
        if (my_known_nonzero < pos) {
            my_known_nonzero = -1;
            for (let i = pos; i < section_end; i++) {
                if (bytes[i] !== 0) {
                    my_known_nonzero = i;
                    break;
                }
            }
        }
        if (my_known_nonzero < pos) break;
        const my_header_width = 2 + name_width + 1;
        if (pos + my_header_width > section_end) {
            throw new Error(
                'Corrupt value label table: trailing bytes'
            );
        }

        const my_n = view.getUint16(pos, little_endian);
        pos += 2;
        const my_name = read_label_name(
            bytes, pos, name_width, decoder
        );
        pos += name_width + 1;
        if (pos + my_n * 10 > section_end) {
            throw new Error(
                'Corrupt value label table: truncated entry'
            );
        }
        const the_codes: number[] = [];
        for (let i = 0; i < my_n; i++) {
            the_codes.push(view.getInt16(pos, little_endian));
            pos += 2;
        }
        const my_labels = new Map<number, string>();
        for (let i = 0; i < my_n; i++) {
            const my_label = read_label_name(
                bytes, pos, 8, decoder
            );
            if (!my_labels.has(the_codes[i])) {
                my_labels.set(the_codes[i], my_label);
            }
            pos += 8;
        }
        my_result.set(my_name, my_labels);
    }
    return my_result;
}

function has_variable_label_table_framing(
    view: DataView,
    little_endian: boolean,
    start_pos: number,
    section_end: number,
    name_width: number
): boolean {
    const my_payload_start = start_pos + 4 + name_width + 3;
    if (my_payload_start + 8 > section_end) return false;
    const my_table_len = view.getInt32(start_pos, little_endian);
    const my_n = view.getInt32(my_payload_start, little_endian);
    const my_text_len = view.getInt32(
        my_payload_start + 4, little_endian
    );
    if (my_table_len <= 0 || my_n < 0 || my_text_len < 0) {
        return false;
    }
    const my_payload_len = 8 + my_n * 8 + my_text_len;
    return my_payload_len === my_table_len
        && my_payload_start + my_payload_len <= section_end;
}

function has_variable_label_section_framing(
    bytes: Uint8Array,
    view: DataView,
    little_endian: boolean,
    start_pos: number,
    section_end: number,
    name_width: number
): boolean {
    const my_prefix_width = 4 + name_width + PADDING_BYTES;
    let pos = start_pos;
    let my_known_nonzero = -1;
    while (pos < section_end) {
        const my_header_end = Math.min(
            section_end, pos + my_prefix_width + 8
        );
        let my_header_has_nonzero = false;
        for (let i = pos; i < my_header_end; i++) {
            if (bytes[i] !== 0) {
                my_header_has_nonzero = true;
                break;
            }
        }
        if (!my_header_has_nonzero) {
            if (my_known_nonzero < pos) {
                my_known_nonzero = -1;
                for (let i = my_header_end; i < section_end; i++) {
                    if (bytes[i] !== 0) {
                        my_known_nonzero = i;
                        break;
                    }
                }
            }
            if (my_known_nonzero < pos) return true;
        }
        if (!has_variable_label_table_framing(
            view, little_endian, pos, section_end, name_width
        )) {
            return false;
        }
        const my_table_len = view.getInt32(pos, little_endian);
        const my_next = pos + my_prefix_width + my_table_len;
        if (my_next <= pos || my_next > section_end) return false;
        pos = my_next;
    }
    return true;
}

// -----------------------------------------------------------
// Public API
// -----------------------------------------------------------

/**
 * Parse all value label tables from the value_labels
 * section of a .dta file.
 *
 * Returns a Map of table_name to a Map of integer_value
 * to label_string.
 */
export function parse_value_labels(
    buffer: ArrayBuffer,
    metadata: DtaMetadata,
    base_offset: number = 0
): Map<string, Map<number, string>> {
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    const little_endian = metadata.byte_order === 'LSF';

    const my_legacy = is_legacy_format(
        metadata.format_version
    );
    const encoding = resolve_text_encoding(
        metadata.format_version, metadata.text_encoding
    );
    const my_decoder = text_decoder(encoding);

    // Start position: skip XML tag for modern formats
    const my_tag_skip = my_legacy
        ? 0
        : VALUE_LABELS_TAG_LENGTH;
    const my_start_pos =
        metadata.section_offsets.value_labels
        - base_offset
        + my_tag_skip;

    // Section end sentinel
    const my_section_end =
        metadata.section_offsets.stata_data_close
        - base_offset;
    const section_start = metadata.section_offsets.value_labels - base_offset;
    if (!Number.isSafeInteger(section_start) || !Number.isSafeInteger(my_section_end)
        || section_start < 0 || my_section_end < section_start || my_section_end > bytes.length) {
        throw new Error('Corrupt value label section: invalid bounds');
    }
    if (!my_legacy) {
        expect_tag(bytes, section_start, VALUE_LABELS_TAG, my_section_end);
        const end = expect_tag(bytes, my_section_end, '</stata_dta>', bytes.length);
        if (end !== bytes.length || base_offset + end !== metadata.section_offsets.end_of_file) {
            throw new Error('Corrupt value label section: mapped file extent mismatch');
        }
    }

    if (is_legacy_format(metadata.format_version)) {
        const my_layout = legacy_layout_for_version(
            metadata.format_version
        );
        let my_value_label_layout: LegacyValueLabelLayout =
            my_layout.value_label_layout;
        let my_name_width =
            my_layout.value_label_table_name_width;

        if (metadata.format_version === 105
            && has_variable_label_section_framing(
                bytes, view, little_endian,
                my_start_pos, my_section_end, 33
            )) {
            my_value_label_layout = 'offset_table';
            my_name_width = 33;
        } else if (metadata.format_version === 108
            && !has_variable_label_section_framing(
                bytes, view, little_endian,
                my_start_pos, my_section_end, 9
            )
            && has_variable_label_section_framing(
                bytes, view, little_endian,
                my_start_pos, my_section_end, 33
            )) {
            my_name_width = 33;
        }

        if (my_value_label_layout === 'fixed8') {
            return parse_fixed8_entries(
                bytes, view, little_endian,
                my_name_width, my_start_pos, my_section_end,
                my_decoder
            );
        }

        return parse_legacy_entries(
            bytes, view, little_endian,
            my_name_width, my_start_pos, my_section_end,
            my_decoder, encoding === 'utf-8'
        );
    }

    return parse_modern_entries(
        bytes, view, little_endian,
        MODERN_LABEL_NAME_WIDTH[metadata.format_version],
        my_start_pos, my_section_end, my_decoder, encoding === 'utf-8'
    );
}
