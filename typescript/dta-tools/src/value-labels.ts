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
const VALUE_LABELS_TAG_LENGTH = VALUE_LABELS_TAG.length;
const LBL_OPEN_TAG = '<lbl>';
const LBL_OPEN_TAG_LENGTH = LBL_OPEN_TAG.length; // 5
const LBL_CLOSE_TAG_LENGTH = 6; // "</lbl>"

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
    decoder: DtaTextDecoder
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
    decoder: DtaTextDecoder
): string {
    let my_end = pos;
    const my_limit = pos + name_width;
    while (my_end < my_limit && bytes[my_end] !== 0) {
        my_end++;
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
    decoder: DtaTextDecoder
): Map<string, Map<number, string>> {
    const my_result = new Map<string, Map<number, string>>();
    let pos = start_pos;

    while (pos + LBL_OPEN_TAG_LENGTH <= section_end) {
        // Check for <lbl> opening tag
        if (
            bytes[pos] !== 0x3C     // '<'
            || bytes[pos + 1] !== 0x6C  // 'l'
            || bytes[pos + 2] !== 0x62  // 'b'
            || bytes[pos + 3] !== 0x6C  // 'l'
            || bytes[pos + 4] !== 0x3E  // '>'
        ) {
            break;
        }
        pos += LBL_OPEN_TAG_LENGTH;

        // table_length (int32)
        pos += 4;

        // label_name
        const my_label_name = read_label_name(
            bytes, pos, name_width, decoder
        );
        pos += name_width;

        // 3 bytes padding
        pos += PADDING_BYTES;

        // Parse the entry payload
        const { label_map, next_pos } =
            parse_label_entry_payload(
                bytes, view, little_endian, pos,
                section_end, decoder
            );
        my_result.set(my_label_name, label_map);

        // Skip past text block + </lbl>
        pos = next_pos + LBL_CLOSE_TAG_LENGTH;
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
        if (pos + 4 > section_end) {
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
                section_end, decoder
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
    const my_decoder = text_decoder(resolve_text_encoding(
        metadata.format_version, metadata.text_encoding
    ));

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
            my_decoder
        );
    }

    return parse_modern_entries(
        bytes, view, little_endian,
        MODERN_LABEL_NAME_WIDTH[metadata.format_version],
        my_start_pos, my_section_end, my_decoder
    );
}
