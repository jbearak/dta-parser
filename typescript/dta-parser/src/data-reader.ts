// -----------------------------------------------------------
// .dta data section row and column readers
// -----------------------------------------------------------

import { missing_value_from_offset } from './missing-values';
import type {
    DtaMetadata,
    Row,
    RowCell,
    VariableInfo,
} from './types';
import { is_legacy_format } from './types';
import type { DtaTextDecoder } from './text-encoding';
import {
    resolve_text_encoding,
    text_decoder,
} from './text-encoding';

const DATA_TAG_LENGTH = '<data>'.length;
const STRL_PLACEHOLDER = '__strl__';

const BYTE_MISSING_DOT = 101;
const INT_MISSING_DOT = 32741;
const LONG_MISSING_DOT = 2147483621;
const FLOAT_MISSING_DOT_RAW = 0x7F000000;
const FLOAT_MISSING_STEP_RAW = 0x00000800;
const FLOAT_MISSING_Z_RAW =
    FLOAT_MISSING_DOT_RAW + 26 * FLOAT_MISSING_STEP_RAW;

type DataBuffer = ArrayBuffer | Uint8Array;

interface BufferViews {
    view: DataView;
    bytes: Uint8Array;
}

function buffer_views(buffer: DataBuffer): BufferViews {
    if (buffer instanceof Uint8Array) {
        return {
            view: new DataView(
                buffer.buffer,
                buffer.byteOffset,
                buffer.byteLength
            ),
            bytes: new Uint8Array(
                buffer.buffer,
                buffer.byteOffset,
                buffer.byteLength
            ),
        };
    }
    return {
        view: new DataView(buffer),
        bytes: new Uint8Array(buffer),
    };
}

function decoder_for_metadata(
    metadata: DtaMetadata
): DtaTextDecoder {
    return text_decoder(
        metadata.text_encoding
        ?? resolve_text_encoding(metadata.format_version)
    );
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
    return decoder.decode(bytes.subarray(offset, my_end));
}

function modern_double_missing_offset(
    view: DataView,
    offset: number,
    little_endian: boolean
): number {
    const my_hi_word = little_endian
        ? view.getUint32(offset + 4, true)
        : view.getUint32(offset, false);
    if ((my_hi_word >>> 16) !== 0x7FE0) return -1;

    const my_letter = (my_hi_word >>> 8) & 0xFF;
    if (my_letter > 26 || (my_hi_word & 0xFF) !== 0) {
        return -1;
    }
    const my_lo_word = little_endian
        ? view.getUint32(offset, true)
        : view.getUint32(offset + 4, false);
    return my_lo_word === 0 ? my_letter : -1;
}

function legacy_double_is_missing(
    view: DataView,
    offset: number,
    little_endian: boolean,
    is_v105: boolean
): boolean {
    const my_hi_word = little_endian
        ? view.getUint32(offset + 4, true)
        : view.getUint32(offset, false);
    if (my_hi_word >= 0x7FE00000 && my_hi_word < 0x80000000) {
        return true;
    }
    if (!is_v105 || my_hi_word !== 0x54C00000) return false;

    const my_lo_word = little_endian
        ? view.getUint32(offset, true)
        : view.getUint32(offset + 4, false);
    return my_lo_word === 0;
}

function decode_column_into_rows(
    view: DataView,
    bytes: Uint8Array,
    rows: Row[],
    variable: VariableInfo,
    output_column: number,
    row_base_offset: number,
    row_width: number,
    little_endian: boolean,
    modern_missing: boolean,
    is_v105: boolean,
    decoder: DtaTextDecoder
): void {
    let my_offset = row_base_offset + variable.byte_offset;

    switch (variable.type) {
        case 'byte':
            for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                const my_value = view.getInt8(my_offset);
                rows[i][output_column] = modern_missing
                    && my_value >= BYTE_MISSING_DOT
                    ? missing_value_from_offset(my_value - BYTE_MISSING_DOT)
                    : !modern_missing && my_value === 127
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'int':
            for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                const my_value = view.getInt16(my_offset, little_endian);
                rows[i][output_column] = modern_missing
                    && my_value >= INT_MISSING_DOT
                    ? missing_value_from_offset(my_value - INT_MISSING_DOT)
                    : !modern_missing && my_value === 32767
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'long':
            for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                const my_value = view.getInt32(my_offset, little_endian);
                rows[i][output_column] = modern_missing
                    && my_value >= LONG_MISSING_DOT
                    ? missing_value_from_offset(my_value - LONG_MISSING_DOT)
                    : !modern_missing && my_value === 2147483647
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'float':
            for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                const my_raw = view.getUint32(my_offset, little_endian);
                if (modern_missing) {
                    const my_delta = my_raw - FLOAT_MISSING_DOT_RAW;
                    rows[i][output_column] =
                        my_raw <= FLOAT_MISSING_Z_RAW
                        && my_delta >= 0
                        && my_delta % FLOAT_MISSING_STEP_RAW === 0
                            ? missing_value_from_offset(
                                my_delta / FLOAT_MISSING_STEP_RAW
                            )
                            : view.getFloat32(my_offset, little_endian);
                } else {
                    rows[i][output_column] =
                        my_raw >= FLOAT_MISSING_DOT_RAW
                        && my_raw < 0x80000000
                            ? missing_value_from_offset(0)
                            : view.getFloat32(my_offset, little_endian);
                }
            }
            return;

        case 'double':
            if (modern_missing) {
                for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                    const my_missing = modern_double_missing_offset(
                        view, my_offset, little_endian
                    );
                    rows[i][output_column] = my_missing >= 0
                        ? missing_value_from_offset(my_missing)
                        : view.getFloat64(my_offset, little_endian);
                }
            } else {
                for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                    rows[i][output_column] = legacy_double_is_missing(
                        view, my_offset, little_endian, is_v105
                    )
                        ? missing_value_from_offset(0)
                        : view.getFloat64(my_offset, little_endian);
                }
            }
            return;

        case 'strL':
            for (let i = 0; i < rows.length; i++) {
                rows[i][output_column] = STRL_PLACEHOLDER;
            }
            return;

        default:
            for (let i = 0; i < rows.length; i++, my_offset += row_width) {
                rows[i][output_column] = read_fixed_string(
                    bytes,
                    my_offset,
                    variable.byte_width,
                    decoder
                );
            }
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
    is_v105: boolean,
    decoder: DtaTextDecoder
): void {
    let my_offset = variable.byte_offset;
    const my_end = output_start + count;

    switch (variable.type) {
        case 'byte':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt8(my_offset);
                values[i] = modern_missing && my_value >= BYTE_MISSING_DOT
                    ? missing_value_from_offset(my_value - BYTE_MISSING_DOT)
                    : !modern_missing && my_value === 127
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'int':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt16(my_offset, little_endian);
                values[i] = modern_missing && my_value >= INT_MISSING_DOT
                    ? missing_value_from_offset(my_value - INT_MISSING_DOT)
                    : !modern_missing && my_value === 32767
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'long':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_value = view.getInt32(my_offset, little_endian);
                values[i] = modern_missing && my_value >= LONG_MISSING_DOT
                    ? missing_value_from_offset(my_value - LONG_MISSING_DOT)
                    : !modern_missing && my_value === 2147483647
                        ? missing_value_from_offset(0)
                        : my_value;
            }
            return;

        case 'float':
            for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                const my_raw = view.getUint32(my_offset, little_endian);
                if (modern_missing) {
                    const my_delta = my_raw - FLOAT_MISSING_DOT_RAW;
                    values[i] = my_raw <= FLOAT_MISSING_Z_RAW
                        && my_delta >= 0
                        && my_delta % FLOAT_MISSING_STEP_RAW === 0
                            ? missing_value_from_offset(
                                my_delta / FLOAT_MISSING_STEP_RAW
                            )
                            : view.getFloat32(my_offset, little_endian);
                } else {
                    values[i] = my_raw >= FLOAT_MISSING_DOT_RAW
                        && my_raw < 0x80000000
                            ? missing_value_from_offset(0)
                            : view.getFloat32(my_offset, little_endian);
                }
            }
            return;

        case 'double':
            if (modern_missing) {
                for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                    const my_missing = modern_double_missing_offset(
                        view, my_offset, little_endian
                    );
                    values[i] = my_missing >= 0
                        ? missing_value_from_offset(my_missing)
                        : view.getFloat64(my_offset, little_endian);
                }
            } else {
                for (let i = output_start; i < my_end; i++, my_offset += row_width) {
                    values[i] = legacy_double_is_missing(
                        view, my_offset, little_endian, is_v105
                    )
                        ? missing_value_from_offset(0)
                        : view.getFloat64(my_offset, little_endian);
                }
            }
            return;

        case 'strL':
            for (let i = output_start; i < my_end; i++) {
                values[i] = STRL_PLACEHOLDER;
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

function read_rows_from_view(
    view: DataView,
    bytes: Uint8Array,
    metadata: DtaMetadata,
    row_base_offset: number,
    start: number,
    count: number,
    col_start?: number,
    col_end?: number
): Row[] {
    if (
        metadata.nobs === 0
        || start < 0
        || count <= 0
        || start >= metadata.nobs
    ) {
        return [];
    }

    const my_actual_count = Math.min(count, metadata.nobs - start);
    const my_col_start = Math.max(0, col_start ?? 0);
    const my_col_end = Math.min(
        metadata.nvar, col_end ?? metadata.nvar
    );
    if (my_col_start >= my_col_end) return [];

    const my_column_count = my_col_end - my_col_start;
    const the_rows = new Array<Row>(my_actual_count);
    for (let i = 0; i < my_actual_count; i++) {
        the_rows[i] = new Array<RowCell>(my_column_count);
    }

    const little_endian = metadata.byte_order === 'LSF';
    const modern_missing = metadata.format_version >= 113;
    const is_v105 = metadata.format_version === 105;
    const my_decoder = decoder_for_metadata(metadata);

    for (
        let my_abs_col = my_col_start, my_output_col = 0;
        my_abs_col < my_col_end;
        my_abs_col++, my_output_col++
    ) {
        decode_column_into_rows(
            view,
            bytes,
            the_rows,
            metadata.variables[my_abs_col],
            my_output_col,
            row_base_offset,
            metadata.obs_length,
            little_endian,
            modern_missing,
            is_v105,
            my_decoder
        );
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

/** Read rows from a buffer containing contiguous observation bytes. */
export function read_rows_from_data_buffer(
    buffer: DataBuffer,
    metadata: DtaMetadata,
    start: number,
    count: number,
    col_start?: number,
    col_end?: number
): Row[] {
    const { view, bytes } = buffer_views(buffer);
    return read_rows_from_view(
        view,
        bytes,
        metadata,
        0,
        start,
        count,
        col_start,
        col_end
    );
}

/**
 * Decode selected columns from contiguous observation bytes.
 *
 * When `out_offset` is present, values overwrite that range in each target.
 * Otherwise each target is appended to, preserving the original helper
 * contract for callers outside the Node reader.
 */
export function read_columns_from_data_buffer(
    buffer: DataBuffer,
    metadata: DtaMetadata,
    count: number,
    col_indices: number[],
    out: Map<number, RowCell[]>,
    out_offset?: number
): void {
    if (count <= 0 || col_indices.length === 0) return;

    const { view, bytes } = buffer_views(buffer);
    const little_endian = metadata.byte_order === 'LSF';
    const modern_missing = metadata.format_version >= 113;
    const is_v105 = metadata.format_version === 105;
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
            is_v105,
            my_decoder
        );
    }
}
