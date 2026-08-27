// -----------------------------------------------------------
// Stata missing value detection and classification
//
// Integer storage types encode missing values at the top of
// their numeric ranges. Float and double storage types use
// storage-specific IEEE 754 bit patterns that must be
// classified from raw bytes to preserve .a-.z exactly.
// -----------------------------------------------------------

import type {
    FormatVersion,
    MissingType,
    MissingValue,
} from './types';

type NumericDtaType =
    | 'byte'
    | 'int'
    | 'long'
    | 'float'
    | 'double';

// ----- Integer-type thresholds -----

const BYTE_MISSING_DOT = 101;
const BYTE_MISSING_Z = 127;

const INT_MISSING_DOT = 32741;
const INT_MISSING_Z = 32767;

const LONG_MISSING_DOT = 2147483621;
const LONG_MISSING_Z = 2147483647;

// ----- Raw float/double storage encodings -----

export const FLOAT_MISSING_DOT_RAW = 0x7F000000;
export const FLOAT_MISSING_STEP_RAW = 0x00000800;
export const FLOAT_MISSING_Z_RAW =
    FLOAT_MISSING_DOT_RAW + (26 * FLOAT_MISSING_STEP_RAW);

const DOUBLE_PREFIX_HI = 0x7FE0;
const DOUBLE_LETTER_MAX = 0x1A;

function bytes_to_double(bytes: number[]): number {
    const my_buf = new ArrayBuffer(8);
    const my_view = new DataView(my_buf);
    bytes.forEach((my_byte, my_index) => {
        my_view.setUint8(my_index, my_byte);
    });
    return my_view.getFloat64(0, false);
}

/** System missing (.) as a JS number. */
export const STATA_MISSING: number =
    bytes_to_double(
        [0x7f, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    );

/** Extended missing .a as a JS number. */
export const STATA_MISSING_A: number =
    bytes_to_double(
        [0x7f, 0xe0, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]
    );

/** Extended missing .b as a JS number. */
export const STATA_MISSING_B: number =
    bytes_to_double(
        [0x7f, 0xe0, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]
    );

/** Extended missing .z as a JS number. */
export const STATA_MISSING_Z: number =
    bytes_to_double(
        [0x7f, 0xe0, 0x1a, 0x00, 0x00, 0x00, 0x00, 0x00]
    );

const MISSING_TYPES: readonly MissingType[] = Array.from(
    { length: 27 },
    (_, offset) => (
        offset === 0
            ? '.'
            : `.${String.fromCharCode(96 + offset)}`
    ) as MissingType
);

function classify_missing_from_offset(
    offset: number
): MissingType | null {
    return MISSING_TYPES[offset] ?? null;
}

function integer_missing_offset(
    value: number,
    dot: number,
    z: number,
    modern: boolean
): number {
    if (!modern) return value === z ? 0 : -1;
    return value >= dot && value <= z
        ? value - dot
        : -1;
}

export function byte_missing_offset(
    value: number,
    modern: boolean
): number {
    return integer_missing_offset(
        value, BYTE_MISSING_DOT, BYTE_MISSING_Z, modern
    );
}

export function int_missing_offset(
    value: number,
    modern: boolean
): number {
    return integer_missing_offset(
        value, INT_MISSING_DOT, INT_MISSING_Z, modern
    );
}

export function long_missing_offset(
    value: number,
    modern: boolean
): number {
    return integer_missing_offset(
        value, LONG_MISSING_DOT, LONG_MISSING_Z, modern
    );
}

export function float_missing_offset(
    raw_value: number,
    modern: boolean
): number {
    if (!modern) {
        return raw_value >= FLOAT_MISSING_DOT_RAW
            && raw_value < 0x80000000
            ? 0
            : -1;
    }
    if (
        raw_value < FLOAT_MISSING_DOT_RAW
        || raw_value > FLOAT_MISSING_Z_RAW
    ) {
        return -1;
    }
    const my_delta = raw_value - FLOAT_MISSING_DOT_RAW;
    return my_delta % FLOAT_MISSING_STEP_RAW === 0
        ? my_delta / FLOAT_MISSING_STEP_RAW
        : -1;
}

function classify_float_raw_missing(
    raw_value: number
): MissingType | null {
    return classify_missing_from_offset(
        float_missing_offset(raw_value, true)
    );
}

function double_missing_offset_from_parts(
    hi_word: number,
    lo_word: number
): number {
    if ((hi_word >>> 16) !== DOUBLE_PREFIX_HI) {
        return -1;
    }

    const my_letter = (hi_word >>> 8) & 0xFF;
    if (
        my_letter > DOUBLE_LETTER_MAX
        || (hi_word & 0xFF) !== 0
        || lo_word !== 0
    ) {
        return -1;
    }

    return my_letter;
}

function classify_double_big_endian_parts(
    hi_word: number,
    lo_word: number
): MissingType | null {
    return classify_missing_from_offset(
        double_missing_offset_from_parts(hi_word, lo_word)
    );
}

function classify_double_js_missing(
    value: number
): MissingType | null {
    const my_buf = new ArrayBuffer(8);
    const my_view = new DataView(my_buf);
    my_view.setFloat64(0, value, false);
    return classify_double_big_endian_parts(
        my_view.getUint32(0, false),
        my_view.getUint32(4, false)
    );
}

export function make_missing_value(
    missing_type: MissingType
): MissingValue {
    return {
        kind: 'missing',
        missing_type,
    };
}

/** Create a missing value for a validated missing offset. */
export function missing_value_from_offset(
    offset: number
): MissingValue {
    return make_missing_value(MISSING_TYPES[offset]);
}

export function is_missing_value_object(
    value: unknown
): value is MissingValue {
    return (
        typeof value === 'object'
        && value !== null
        && (value as { kind?: unknown }).kind === 'missing'
        && typeof (
            value as { missing_type?: unknown }
        ).missing_type === 'string'
    );
}

export function classify_raw_float_missing(
    raw_value: number
): MissingType | null {
    return classify_float_raw_missing(raw_value);
}

export function double_missing_offset_for_version(
    view: DataView,
    offset: number,
    little_endian: boolean,
    format_version: FormatVersion
): number {
    const my_hi_word = little_endian
        ? view.getUint32(offset + 4, true)
        : view.getUint32(offset, false);
    const my_lo_word = little_endian
        ? view.getUint32(offset, true)
        : view.getUint32(offset + 4, false);

    if (format_version >= 113) {
        return double_missing_offset_from_parts(
            my_hi_word, my_lo_word
        );
    }
    if (
        my_hi_word >= 0x7FE00000
        && my_hi_word < 0x80000000
    ) {
        return 0;
    }
    return format_version === 105
        && my_hi_word === 0x54C00000
        && my_lo_word === 0
        ? 0
        : -1;
}

export function classify_raw_double_missing_at(
    view: DataView,
    offset: number,
    little_endian: boolean
): MissingType | null {
    const my_hi_word = little_endian
        ? view.getUint32(offset + 4, true)
        : view.getUint32(offset, false);
    const my_lo_word = little_endian
        ? view.getUint32(offset, true)
        : view.getUint32(offset + 4, false);
    return classify_double_big_endian_parts(
        my_hi_word, my_lo_word
    );
}

export function classify_double_missing_for_version(
    view: DataView,
    offset: number,
    little_endian: boolean,
    format_version: FormatVersion
): MissingType | null {
    return classify_missing_from_offset(
        double_missing_offset_for_version(
            view, offset, little_endian, format_version
        )
    );
}

/**
 * Returns true if `value` is a Stata missing value for the
 * given type. When no type is provided, uses the double
 * encoding used by in-memory JS numeric values.
 */
export function is_missing_value(
    value: number,
    type?: NumericDtaType
): boolean {
    return classify_missing_value(value, type) !== null;
}

/**
 * Classify a Stata missing value. Returns '.', '.a' .. '.z',
 * or null if the value is not missing.
 */
/**
 * Convert a MissingType to the int32 key used in value
 * label tables (long encoding).
 */
export function missing_type_to_label_key(
    missing_type: MissingType
): number {
    if (missing_type === '.') {
        return LONG_MISSING_DOT;
    }
    const my_offset =
        missing_type.charCodeAt(1) - 96; // 'a'=1 .. 'z'=26
    return LONG_MISSING_DOT + my_offset;
}

export function classify_missing_value(
    value: number,
    type?: NumericDtaType
): MissingType | null {
    switch (type) {
        case 'byte':
            return classify_missing_from_offset(
                byte_missing_offset(value, true)
            );
        case 'int':
            return classify_missing_from_offset(
                int_missing_offset(value, true)
            );
        case 'long':
            return classify_missing_from_offset(
                long_missing_offset(value, true)
            );
        case 'float':
            return classify_float_raw_missing(
                new DataView(
                    new Float32Array([value]).buffer
                ).getUint32(0, true)
            );
        case 'double':
        default:
            return classify_double_js_missing(value);
    }
}
