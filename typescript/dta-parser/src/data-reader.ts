// -----------------------------------------------------------
// .dta data section row and column readers
// -----------------------------------------------------------

import {
    byte_missing_offset,
    double_missing_offset_for_version,
    float_missing_offset,
    int_missing_offset,
    long_missing_offset,
    missing_value_from_offset,
} from './missing-values';
import type {
    DtaMetadata,
    FormatVersion,
    Row,
    RowCell,
    VariableInfo,
} from './types';
import { is_legacy_format } from './types';
import type { DtaTextDecoder } from './text-encoding';
import {
    decode_text_range,
    resolve_text_encoding,
    text_decoder,
} from './text-encoding';

const DATA_TAG_LENGTH = '<data>'.length;
const STRL_PLACEHOLDER = '__strl__';

type DataBuffer = ArrayBuffer | Uint8Array;

interface BufferViews {
    view: DataView;
    bytes: Uint8Array;
}

/** Reject NaN and finite fractions; infinities retain sentinel semantics. */
export function assert_valid_row_range(
    start: number,
    count: number
): void {
    const my_start_valid = Number.isInteger(start)
        || start === Infinity
        || start === -Infinity;
    const my_count_valid = Number.isInteger(count)
        || count === Infinity
        || count === -Infinity;
    if (!my_start_valid || !my_count_valid) {
        throw new RangeError(
            'Row start and count must not be NaN or fractional'
        );
    }
}

export function data_buffer_view(buffer: DataBuffer): DataView {
    return buffer instanceof Uint8Array
        ? new DataView(
            buffer.buffer,
            buffer.byteOffset,
            buffer.byteLength
        )
        : new DataView(buffer);
}

function buffer_views(buffer: DataBuffer): BufferViews {
    return {
        view: data_buffer_view(buffer),
        bytes: buffer instanceof Uint8Array
            ? buffer
            : new Uint8Array(buffer),
    };
}

function decoder_for_metadata(
    metadata: DtaMetadata
): DtaTextDecoder {
    switch (metadata.text_encoding) {
        case 'utf-8':
        case 'windows-1252':
        case 'iso-8859-1':
            return text_decoder(metadata.text_encoding);
        default:
            return text_decoder(resolve_text_encoding(
                metadata.format_version,
                metadata.text_encoding
            ));
    }
}

function read_fixed_string(
    bytes: Uint8Array,
    offset: number,
    width: number,
    decoder: DtaTextDecoder
): string {
    if (width === 0 || bytes[offset] === 0) return '';

    let my_end = offset + 1;
    const my_limit = offset + width;
    while (my_end < my_limit && bytes[my_end] !== 0) {
        my_end++;
    }
    return decode_text_range(decoder, bytes, offset, my_end);
}

function read_cell(
    view: DataView,
    bytes: Uint8Array,
    offset: number,
    variable: VariableInfo,
    little_endian: boolean,
    modern_missing: boolean,
    decoder: DtaTextDecoder,
    format_version: FormatVersion
): RowCell {
    let my_missing = -1;
    switch (variable.type) {
        case 'byte': {
            const my_value = view.getInt8(offset);
            my_missing = byte_missing_offset(
                my_value, modern_missing
            );
            return my_missing >= 0
                ? missing_value_from_offset(my_missing)
                : my_value;
        }
        case 'int': {
            const my_value = view.getInt16(
                offset, little_endian
            );
            my_missing = int_missing_offset(
                my_value, modern_missing
            );
            return my_missing >= 0
                ? missing_value_from_offset(my_missing)
                : my_value;
        }
        case 'long': {
            const my_value = view.getInt32(
                offset, little_endian
            );
            my_missing = long_missing_offset(
                my_value, modern_missing
            );
            return my_missing >= 0
                ? missing_value_from_offset(my_missing)
                : my_value;
        }
        case 'float': {
            const my_raw = view.getUint32(
                offset, little_endian
            );
            my_missing = float_missing_offset(
                my_raw, modern_missing
            );
            return my_missing >= 0
                ? missing_value_from_offset(my_missing)
                : view.getFloat32(offset, little_endian);
        }
        case 'double':
            my_missing = double_missing_offset_for_version(
                view, offset, little_endian, format_version
            );
            return my_missing >= 0
                ? missing_value_from_offset(my_missing)
                : view.getFloat64(offset, little_endian);
        case 'strL':
            return STRL_PLACEHOLDER;
        default:
            return read_fixed_string(
                bytes,
                offset,
                variable.byte_width,
                decoder
            );
    }
}

function decode_column_into_values(
    view: DataView,
    bytes: Uint8Array,
    values: RowCell[],
    output_start: number,
    count: number,
    variable: VariableInfo,
    row_width: number,
    little_endian: boolean,
    modern_missing: boolean,
    decoder: DtaTextDecoder,
    format_version: FormatVersion,
    write_strl_placeholder: boolean
): void {
    let my_offset = variable.byte_offset;
    const my_end = output_start + count;

    switch (variable.type) {
        case 'byte':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt8(my_offset);
                const my_missing = byte_missing_offset(
                    my_value, modern_missing
                );
                values[i] = my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value;
            }
            return;

        case 'int':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt16(my_offset, little_endian);
                const my_missing = int_missing_offset(
                    my_value, modern_missing
                );
                values[i] = my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value;
            }
            return;

        case 'long':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt32(my_offset, little_endian);
                const my_missing = long_missing_offset(
                    my_value, modern_missing
                );
                values[i] = my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value;
            }
            return;

        case 'float':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_raw = view.getUint32(my_offset, little_endian);
                const my_missing = float_missing_offset(
                    my_raw, modern_missing
                );
                values[i] = my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : view.getFloat32(my_offset, little_endian);
            }
            return;

        case 'double':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_missing = double_missing_offset_for_version(
                    view,
                    my_offset,
                    little_endian,
                    format_version
                );
                values[i] = my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : view.getFloat64(my_offset, little_endian);
            }
            return;

        case 'strL':
            if (write_strl_placeholder) {
                for (let i = output_start; i < my_end; i++) {
                    values[i] = STRL_PLACEHOLDER;
                }
            }
            return;

        default:
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                values[i] = read_fixed_string(
                    bytes,
                    my_offset,
                    variable.byte_width,
                    decoder
                );
            }
    }
}

function decode_single_column_into_rows(
    view: DataView,
    bytes: Uint8Array,
    rows: Row[],
    output_start: number,
    count: number,
    row_base_offset: number,
    variable: VariableInfo,
    row_width: number,
    little_endian: boolean,
    modern_missing: boolean,
    decoder: DtaTextDecoder,
    format_version: FormatVersion
): void {
    let my_offset = row_base_offset + variable.byte_offset;
    const my_end = output_start + count;

    switch (variable.type) {
        case 'byte':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt8(my_offset);
                const my_missing = byte_missing_offset(
                    my_value, modern_missing
                );
                rows[i] = [my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value];
            }
            return;

        case 'int':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt16(my_offset, little_endian);
                const my_missing = int_missing_offset(
                    my_value, modern_missing
                );
                rows[i] = [my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value];
            }
            return;

        case 'long':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt32(my_offset, little_endian);
                const my_missing = long_missing_offset(
                    my_value, modern_missing
                );
                rows[i] = [my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : my_value];
            }
            return;

        case 'float':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_raw = view.getUint32(my_offset, little_endian);
                const my_missing = float_missing_offset(
                    my_raw, modern_missing
                );
                rows[i] = [my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : view.getFloat32(my_offset, little_endian)];
            }
            return;

        case 'double':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_missing = double_missing_offset_for_version(
                    view,
                    my_offset,
                    little_endian,
                    format_version
                );
                rows[i] = [my_missing >= 0
                    ? missing_value_from_offset(my_missing)
                    : view.getFloat64(my_offset, little_endian)];
            }
            return;

        case 'strL':
            for (let i = output_start; i < my_end; i++) {
                rows[i] = [STRL_PLACEHOLDER];
            }
            return;

        default:
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                rows[i] = [read_fixed_string(
                    bytes,
                    my_offset,
                    variable.byte_width,
                    decoder
                )];
            }
    }
}

function read_rows_from_view(
    view: DataView,
    bytes: Uint8Array,
    metadata: DtaMetadata,
    row_base_offset: number,
    start: number,
    count: number,
    col_start?: number,
    col_end?: number,
    out?: Row[],
    out_offset = 0
): Row[] {
    if (
        metadata.nobs === 0
        || start < 0
        || count <= 0
        || start >= metadata.nobs
    ) {
        return out ?? [];
    }

    const my_actual_count = Math.min(count, metadata.nobs - start);
    const my_col_start = Math.max(0, col_start ?? 0);
    const my_col_end = Math.min(
        metadata.nvar, col_end ?? metadata.nvar
    );
    if (my_col_start >= my_col_end) return out ?? [];

    const little_endian = metadata.byte_order === 'LSF';
    const modern_missing = metadata.format_version >= 113;
    const my_decoder = decoder_for_metadata(metadata);
    const the_rows = out ?? new Array<Row>(my_actual_count);
    const my_column_count = my_col_end - my_col_start;

    if (my_column_count === 1) {
        decode_single_column_into_rows(
            view,
            bytes,
            the_rows,
            out_offset,
            my_actual_count,
            row_base_offset,
            metadata.variables[my_col_start],
            metadata.obs_length,
            little_endian,
            modern_missing,
            my_decoder,
            metadata.format_version
        );
        return the_rows;
    }

    for (let i = 0; i < my_actual_count; i++) {
        const my_row = new Array<RowCell>(my_column_count);
        const my_row_offset =
            row_base_offset + i * metadata.obs_length;
        for (
            let my_abs_col = my_col_start, my_output_col = 0;
            my_abs_col < my_col_end;
            my_abs_col++, my_output_col++
        ) {
            const my_variable = metadata.variables[my_abs_col];
            my_row[my_output_col] = read_cell(
                view,
                bytes,
                my_row_offset + my_variable.byte_offset,
                my_variable,
                little_endian,
                modern_missing,
                my_decoder,
                metadata.format_version
            );
        }
        the_rows[out_offset + i] = my_row;
    }

    return the_rows;
}

/** Read observation rows from a complete .dta file buffer. */
export function read_rows_from_buffer(
    buffer: ArrayBuffer,
    metadata: DtaMetadata,
    start: number,
    count: number,
    col_start?: number,
    col_end?: number
): Row[] {
    assert_valid_row_range(start, count);
    const { view, bytes } = buffer_views(buffer);
    const my_tag_length = is_legacy_format(metadata.format_version)
        ? 0
        : DATA_TAG_LENGTH;
    const my_data_start =
        metadata.section_offsets.data + my_tag_length;

    return read_rows_from_view(
        view,
        bytes,
        metadata,
        my_data_start + start * metadata.obs_length,
        start,
        count,
        col_start,
        col_end
    );
}

/**
 * Read rows from a buffer containing contiguous observation bytes.
 * When `out` is provided, decoded rows overwrite it from `out_offset`.
 */
export function read_rows_from_data_buffer(
    buffer: DataBuffer,
    metadata: DtaMetadata,
    start: number,
    count: number,
    col_start?: number,
    col_end?: number,
    out?: Row[],
    out_offset = 0
): Row[] {
    assert_valid_row_range(start, count);
    const { view, bytes } = buffer_views(buffer);
    return read_rows_from_view(
        view,
        bytes,
        metadata,
        0,
        start,
        count,
        col_start,
        col_end,
        out,
        out_offset
    );
}

/**
 * Decode selected columns from contiguous observation bytes.
 *
 * When `out_offset` is present, values overwrite that range in each target.
 * Otherwise each target is appended to, preserving the original helper
 * contract for callers outside the Node reader. Callers that immediately
 * resolve strLs may disable placeholder writes.
 */
export function read_columns_from_data_buffer(
    buffer: DataBuffer,
    metadata: DtaMetadata,
    count: number,
    col_indices: number[],
    out: Map<number, RowCell[]>,
    out_offset?: number,
    write_strl_placeholders = true
): void {
    if (!Number.isInteger(count)) {
        throw new RangeError('Row count must be an integer');
    }
    if (count <= 0 || col_indices.length === 0) return;

    const { view, bytes } = buffer_views(buffer);
    const little_endian = metadata.byte_order === 'LSF';
    const modern_missing = metadata.format_version >= 113;
    const my_decoder = decoder_for_metadata(metadata);

    for (const my_col of col_indices) {
        const my_target = out.get(my_col)!;
        decode_column_into_values(
            view,
            bytes,
            my_target,
            out_offset ?? my_target.length,
            count,
            metadata.variables[my_col],
            metadata.obs_length,
            little_endian,
            modern_missing,
            my_decoder,
            metadata.format_version,
            write_strl_placeholders
        );
    }
}
