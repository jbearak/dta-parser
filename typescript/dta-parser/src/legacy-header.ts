// -----------------------------------------------------------
// Legacy .dta header and metadata parsing (formats 105, 108, 110-111, 113-115)
//
// Parses the fixed-offset binary header used by Stata/SE 7 and Stata 8-12.
// Produces the same DtaMetadata shape as the modern parser,
// with section offsets computed from nvar rather than read
// from a section map.
//
// Layout (all offsets are byte positions):
//   0:       format version (uint8: 111/113/114/115)
//   1:       byte order (uint8: 0x01=MSF, 0x02=LSF)
//   2:       filetype (always 0x01)
//   3:       unused
//   4-5:     nvar (int16)
//   6-9:     nobs (int32)
//   10-90:   dataset label (81 bytes, null-terminated)
//   91-108:  timestamp (18 bytes, null-terminated)
//   109+:    sequential variable metadata sections
// -----------------------------------------------------------

import type {
    DtaMetadata,
    LegacyFormatVersion,
    VariableInfo,
    SectionOffsets,
} from './types';
import {
    legacy_layout_for_version,
    legacy_expansion_header_size,
} from './legacy-layout';
import {
    byte_width_for_legacy_type_code,
    legacy_type_code_to_dta_type,
} from './types';
import type {
    DtaTextDecoder,
    TextEncodingOptions,
} from './text-encoding';
import {
    resolve_text_encoding,
    text_decoder,
} from './text-encoding';

// -----------------------------------------------------------
// Constants
// -----------------------------------------------------------

const SORTLIST_ENTRY_WIDTH = 2;

// -----------------------------------------------------------
// Helpers
// -----------------------------------------------------------

function read_fixed_string(
    bytes: Uint8Array,
    offset: number,
    field_width: number,
    decoder: DtaTextDecoder
): string {
    let my_end = offset;
    const my_limit = offset + field_width;
    while (my_end < my_limit && bytes[my_end] !== 0) {
        my_end++;
    }
    return decoder.decode(
        bytes.subarray(offset, my_end)
    );
}

/**
 * Compute the minimum buffer size needed to read all
 * metadata sections for a legacy .dta file, given nvar.
 * This is everything up to and including the expansion
 * fields terminator (we add a generous allowance for
 * expansion fields since they're typically tiny).
 */
export function legacy_metadata_buffer_size(
    nvar: number,
    format_version: LegacyFormatVersion
): number {
    return legacy_metadata_fixed_size(nvar, format_version) + 65536;
}

/** Compute the byte offset where legacy expansion fields begin. */
export function legacy_metadata_fixed_size(
    nvar: number,
    format_version: LegacyFormatVersion
): number {
    const layout = legacy_layout_for_version(format_version);
    const my_sections_size =
        nvar + nvar * layout.varname_width
        + (nvar + 1) * SORTLIST_ENTRY_WIDTH
        + nvar * layout.format_width
        + nvar * layout.value_label_name_width
        + nvar * layout.variable_label_width;
    return layout.header_size + my_sections_size;
}

// -----------------------------------------------------------
// Expansion field scanning
// -----------------------------------------------------------

/**
 * Scan past the expansion fields section and return the
 * byte offset immediately after it (= start of data).
 *
 * Expansion fields are a sequence of entries:
 *   uint8  data_type
 *   int32  len
 *   byte[len] content
 *
 * The section terminates when data_type=0 and len=0.
 */
function scan_expansion_fields(
    view: DataView,
    little_endian: boolean,
    start: number,
    buffer_length: number,
    format_version: LegacyFormatVersion,
    decoder: DtaTextDecoder
): { data_offset: number; notes: string[] } {
    let pos = start;
    const layout = legacy_layout_for_version(format_version);
    const my_header_size = legacy_expansion_header_size(layout);
    const the_notes: string[] = [];

    while (pos + my_header_size <= buffer_length) {
        const my_data_type = view.getUint8(pos);
        const my_len = layout.expansion_length_width === 2
            ? view.getInt16(pos + 1, little_endian)
            : view.getInt32(pos + 1, little_endian);

        pos += my_header_size;

        if (my_data_type === 0 && my_len === 0) {
            return { data_offset: pos, notes: the_notes };
        }

        if (my_data_type === 0 || my_len < 0) {
            throw new Error('Invalid legacy expansion field');
        }
        if (pos + my_len > buffer_length) {
            throw new Error('Truncated legacy expansion field');
        }

        if (my_data_type === 1 && my_len >= 2 * layout.varname_width) {
            const my_variable = read_fixed_string(
                bytes_from_view(view), pos, layout.varname_width, decoder
            );
            const my_characteristic = read_fixed_string(
                bytes_from_view(view), pos + layout.varname_width,
                layout.varname_width, decoder
            );
            if (my_variable === '_dta' && /^note[0-9]+$/.test(my_characteristic)) {
                const my_note = read_fixed_string(
                    bytes_from_view(view),
                    pos + 2 * layout.varname_width,
                    my_len - 2 * layout.varname_width,
                    decoder
                );
                if (my_note.length > 0) the_notes.push(my_note);
            }
        }

        pos += my_len;
    }

    throw new Error('Missing legacy expansion-field terminator');
}

function bytes_from_view(view: DataView): Uint8Array {
    return new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
}

// -----------------------------------------------------------
// Public API
// -----------------------------------------------------------

/**
 * Parse legacy .dta metadata from a buffer containing at
 * least the header and all variable metadata sections.
 *
 * The buffer does NOT need to contain the entire file —
 * it only needs to extend past the expansion fields.
 *
 * @param buffer - Buffer starting at byte 0 of the file
 * @param file_size - Total file size (for end_of_file)
 */
export function parse_legacy_metadata(
    buffer: ArrayBuffer,
    file_size: number,
    options: TextEncodingOptions = {}
): DtaMetadata {
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);

    // 1. Format version
    const my_version_byte = bytes[0];
    if (
        my_version_byte !== 105
        && my_version_byte !== 108
        && my_version_byte !== 110
        && my_version_byte !== 111
        && my_version_byte !== 113
        && my_version_byte !== 114
        && my_version_byte !== 115
    ) {
        throw new Error(
            `Not a legacy .dta file: ` +
            `version byte ${my_version_byte}`
        );
    }
    const format_version =
        my_version_byte as LegacyFormatVersion;
    const text_encoding = resolve_text_encoding(
        format_version, options.encoding
    );
    const my_decoder = text_decoder(text_encoding);
    const layout = legacy_layout_for_version(format_version);

    // 2. Byte order
    const my_byte_order_code = bytes[1];
    if (my_byte_order_code !== 1 && my_byte_order_code !== 2) {
        throw new Error(
            `Invalid byte order code: ${my_byte_order_code}`
        );
    }
    const byte_order: 'MSF' | 'LSF' =
        my_byte_order_code === 1 ? 'MSF' : 'LSF';
    const little_endian = byte_order === 'LSF';

    if (bytes[2] !== 1) {
        throw new Error(`Invalid legacy file type: ${bytes[2]}`);
    }

    // 3. nvar (uint16 at bytes 4-5)
    const nvar = view.getUint16(4, little_endian);

    // 4. nobs (int32 at bytes 6-9)
    const nobs = view.getInt32(6, little_endian);
    if (nobs < 0) {
        throw new Error(
            `Invalid observation count: ${nobs}`
        );
    }

    // 5. Dataset label (release-specific width at offset 10)
    const dataset_label = read_fixed_string(
        bytes, 10, layout.dataset_label_width, my_decoder
    );

    // 6. Skip the 18-byte timestamp that ends the header

    // 7. Compute section offsets from nvar
    const my_fmt_width = layout.format_width;

    let pos = layout.header_size;

    // -- variable types: nvar × 1 byte --
    const my_variable_types_offset = pos;
    const the_type_codes: number[] = [];
    for (let i = 0; i < nvar; i++) {
        the_type_codes.push(bytes[pos + i]);
    }
    pos += nvar;

    // -- varnames: nvar × release-specific name width --
    const my_varnames_offset = pos;
    const the_varnames: string[] = [];
    for (let i = 0; i < nvar; i++) {
        the_varnames.push(
            read_fixed_string(
                bytes,
                pos + i * layout.varname_width,
                layout.varname_width,
                my_decoder
            )
        );
    }
    pos += nvar * layout.varname_width;

    // -- sortlist: (nvar+1) × 2 bytes --
    const my_sortlist_offset = pos;
    pos += (nvar + 1) * SORTLIST_ENTRY_WIDTH;

    // -- formats: nvar × fmt_width bytes --
    const my_formats_offset = pos;
    const the_formats: string[] = [];
    for (let i = 0; i < nvar; i++) {
        the_formats.push(
            read_fixed_string(
                bytes,
                pos + i * my_fmt_width,
                my_fmt_width,
                my_decoder
            )
        );
    }
    pos += nvar * my_fmt_width;

    // -- value-label names: nvar × release-specific name width --
    const my_value_label_names_offset = pos;
    const the_value_label_names: string[] = [];
    for (let i = 0; i < nvar; i++) {
        the_value_label_names.push(
            read_fixed_string(
                bytes,
                pos + i * layout.value_label_name_width,
                layout.value_label_name_width,
                my_decoder
            )
        );
    }
    pos += nvar * layout.value_label_name_width;

    // -- variable labels: nvar × release-specific label width --
    const my_variable_labels_offset = pos;
    const the_variable_labels: string[] = [];
    for (let i = 0; i < nvar; i++) {
        the_variable_labels.push(
            read_fixed_string(
                bytes,
                pos + i * layout.variable_label_width,
                layout.variable_label_width,
                my_decoder
            )
        );
    }
    pos += nvar * layout.variable_label_width;

    // -- expansion fields --
    const my_expansion_offset = pos;
    const { data_offset: my_data_offset, notes } = scan_expansion_fields(
        view, little_endian, pos, buffer.byteLength,
        format_version, my_decoder
    );

    // 8. Build VariableInfo with byte widths and offsets
    let my_running_offset = 0;
    const the_variables: VariableInfo[] = [];
    for (let i = 0; i < nvar; i++) {
        const my_code = the_type_codes[i];
        const my_width =
            byte_width_for_legacy_type_code(my_code, format_version);
        the_variables.push({
            name: the_varnames[i],
            type: legacy_type_code_to_dta_type(my_code, format_version),
            type_code: my_code,
            format: the_formats[i],
            label: the_variable_labels[i],
            value_label_name: the_value_label_names[i],
            byte_width: my_width,
            byte_offset: my_running_offset,
        });
        my_running_offset += my_width;
    }
    const obs_length = my_running_offset;

    // 9. Compute value labels offset (BigInt to avoid
    //    overflow for large legacy files)
    const my_value_labels_offset = Number(
        BigInt(my_data_offset)
        + BigInt(nobs) * BigInt(obs_length)
    );
    if (
        !Number.isSafeInteger(my_value_labels_offset)
        || my_value_labels_offset > file_size
    ) {
        throw new Error('Truncated legacy observation data');
    }

    // 10. Synthesize SectionOffsets
    const section_offsets: SectionOffsets = {
        stata_data: 0,
        map: 0,
        variable_types: my_variable_types_offset,
        varnames: my_varnames_offset,
        sortlist: my_sortlist_offset,
        formats: my_formats_offset,
        value_label_names: my_value_label_names_offset,
        variable_labels: my_variable_labels_offset,
        characteristics: my_expansion_offset,
        data: my_data_offset,
        strls: my_value_labels_offset,
        value_labels: my_value_labels_offset,
        stata_data_close: file_size,
        end_of_file: file_size,
    };

    return {
        format_version,
        text_encoding,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        notes,
        variables: the_variables,
        section_offsets,
        obs_length,
    };
}
