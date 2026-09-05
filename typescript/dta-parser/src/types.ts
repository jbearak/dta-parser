// -----------------------------------------------------------
// .dta format types, constants, and helper functions
// -----------------------------------------------------------

// Format version detection strings (first bytes of a .dta file)
export const FORMAT_SIGNATURES = {
    117: '<stata_dta><header><release>117</release>',
    118: '<stata_dta><header><release>118</release>',
    119: '<stata_dta><header><release>119</release>',
} as const;

export type FormatVersion =
    | 105 | 108 | 110 | 111 | 113 | 114 | 115
    | 117 | 118 | 119;

export type LegacyFormatVersion = 105 | 108 | 110 | 111 | 113 | 114 | 115;

const LEGACY_FORMAT_SET = new Set<number>([105, 108, 110, 111, 113, 114, 115]);

export function is_legacy_format(
    version: FormatVersion
): version is LegacyFormatVersion {
    return LEGACY_FORMAT_SET.has(version);
}

// Releases 117–119 share modern two-byte type codes. Legacy numeric codes
// 251–255 denote fixed-string widths in these releases.
const MODERN_TYPE_CODES: Record<number, { type: string; width: number }> = {
    65530: { type: 'byte',   width: 1 },
    65529: { type: 'int',    width: 2 },
    65528: { type: 'long',   width: 4 },
    65527: { type: 'float',  width: 4 },
    65526: { type: 'double', width: 8 },
    32768: { type: 'strL',   width: 8 },
};

const MAX_STR_WIDTH_MODERN = 2045;

// DtaType — the logical Stata storage type
export type DtaType =
    | 'byte'
    | 'int'
    | 'long'
    | 'float'
    | 'double'
    | 'strL'
    | `str${number}`;

/**
 * Return the byte width for a numeric type code in the
 * given modern format version. Fixed-string codes 1..2045 equal their width.
 */
export function byte_width_for_type_code(
    code: number,
    format_version: FormatVersion
): number {
    const my_entry = MODERN_TYPE_CODES[code];
    if (my_entry) return my_entry.width;
    if (Number.isInteger(code) && code >= 1 && code <= MAX_STR_WIDTH_MODERN) return code;

    throw new Error(
        `Unknown type code ${code} for format v${format_version}`
    );
}

/**
 * Convert a numeric type code to its DtaType label.
 *
 */
export function type_code_to_dta_type(
    code: number,
    format_version: FormatVersion
): DtaType {
    const my_entry = MODERN_TYPE_CODES[code];
    if (my_entry) return my_entry.type as DtaType;
    if (Number.isInteger(code) && code >= 1 && code <= MAX_STR_WIDTH_MODERN) return `str${code}`;

    throw new Error(
        `Unknown type code ${code} for format v${format_version}`
    );
}

// -----------------------------------------------------------
// Legacy format type codes (111/113/114/115)
//
// Legacy formats use 1-byte type codes. Numeric codes match
// the v117 set. Fixed strings are 1-244. No strL type.
// -----------------------------------------------------------

const LEGACY_TYPE_CODES: Record<
    number,
    { type: DtaType; width: number }
> = {
    251: { type: 'byte',   width: 1 },
    252: { type: 'int',    width: 2 },
    253: { type: 'long',   width: 4 },
    254: { type: 'float',  width: 4 },
    255: { type: 'double', width: 8 },
};

const PRE111_TYPE_CODES: Record<
    number,
    { type: DtaType; width: number }
> = {
    98: { type: 'byte', width: 1 },
    105: { type: 'int', width: 2 },
    108: { type: 'long', width: 4 },
    102: { type: 'float', width: 4 },
    100: { type: 'double', width: 8 },
};

const MAX_STR_WIDTH_LEGACY = 244;

export function byte_width_for_legacy_type_code(
    code: number,
    format_version: LegacyFormatVersion
): number {
    if (format_version < 111) {
        const my_entry = PRE111_TYPE_CODES[code];
        if (my_entry) return my_entry.width;
        if (code >= 128 && code <= 255) return code - 127;
    } else {
        const my_entry = LEGACY_TYPE_CODES[code];
        if (my_entry) return my_entry.width;
        if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) return code;
    }
    throw new Error(
        `Unknown legacy type code ${code}`
    );
}

export function legacy_type_code_to_dta_type(
    code: number,
    format_version: LegacyFormatVersion
): DtaType {
    if (format_version < 111) {
        const my_entry = PRE111_TYPE_CODES[code];
        if (my_entry) return my_entry.type;
        if (code >= 128 && code <= 255) {
            return `str${code - 127}` as DtaType;
        }
    } else {
        const my_entry = LEGACY_TYPE_CODES[code];
        if (my_entry) return my_entry.type as DtaType;
        if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) {
            return `str${code}` as DtaType;
        }
    }
    throw new Error(
        `Unknown legacy type code ${code}`
    );
}

// -----------------------------------------------------------
// Public interfaces
// -----------------------------------------------------------

export interface VariableInfo {
    name: string;
    type: DtaType;
    type_code: number;
    format: string;           // e.g., "%9.0g", "%20s", "%td"
    label: string;            // variable label
    value_label_name: string; // associated value label table
    /** Numbered notes. Omitted and legacy string arrays remain accepted. */
    notes?: StataNote[] | string[];
    /** Arbitrary user characteristics. Omitted means none. */
    characteristics?: StataCharacteristic[];
    byte_width: number;       // width in bytes in data section
    byte_offset: number;      // offset within an observation row
}

export interface StataNote {
    number: number;
    text: string;
}

export interface StataCharacteristic {
    name: string;
    value: string;
}

export type MissingType =
    | '.'
    | '.a' | '.b' | '.c' | '.d' | '.e' | '.f' | '.g'
    | '.h' | '.i' | '.j' | '.k' | '.l' | '.m' | '.n'
    | '.o' | '.p' | '.q' | '.r' | '.s' | '.t' | '.u'
    | '.v' | '.w' | '.x' | '.y' | '.z';

export interface MissingValue {
    kind: 'missing';
    missing_type: MissingType;
}

export type RowCell = number | string | MissingValue;
export type Row = RowCell[];

export interface SectionOffsets {
    dta_data: number;
    map: number;
    variable_types: number;
    varnames: number;
    sortlist: number;
    formats: number;
    value_label_names: number;
    variable_labels: number;
    characteristics: number;
    data: number;
    strls: number;
    value_labels: number;
    dta_data_close: number;
    end_of_file: number;
}

export interface DtaMetadata {
    format_version: FormatVersion;
    /**
     * Resolved source encoding used for every textual field. Present on
     * parser-produced metadata; omitted caller-built metadata uses `auto`.
     */
    text_encoding?: import('./text-encoding').ResolvedTextEncoding;
    byte_order: 'MSF' | 'LSF';
    nvar: number;
    nobs: number;
    dataset_label: string;
    /** Numbered notes. Omitted and legacy string arrays remain accepted. */
    notes?: StataNote[] | string[];
    /** Arbitrary user characteristics. Omitted means none. */
    characteristics?: StataCharacteristic[];
    variables: VariableInfo[];
    section_offsets: SectionOffsets;
    obs_length: number;
}

/** Minimal immutable geometry consumed by observation and strL readers. */
export interface DtaReadPlan {
    readonly format_version: FormatVersion;
    readonly text_encoding?: import('./text-encoding').ResolvedTextEncoding;
    readonly byte_order: 'MSF' | 'LSF';
    readonly nvar: number;
    readonly nobs: number;
    readonly obs_length: number;
    readonly section_offsets: Readonly<Pick<
        SectionOffsets, 'data' | 'strls' | 'value_labels'
    >>;
    readonly variables: readonly ReadVariablePlan[];
}

/** Immutable parallel read geometry used by long-lived file handles. */
export interface PackedDtaReadPlan {
    readonly format_version: FormatVersion;
    readonly text_encoding?: import('./text-encoding').ResolvedTextEncoding;
    readonly byte_order: 'MSF' | 'LSF';
    readonly nvar: number;
    readonly nobs: number;
    readonly obs_length: number;
    readonly section_offsets: Readonly<Pick<
        SectionOffsets, 'data' | 'strls' | 'value_labels'
    >>;
    readonly variable_count: number;
    readonly variable_types: readonly DtaType[];
    readonly variable_byte_widths: readonly number[];
    readonly variable_byte_offsets: readonly number[];
    readonly strl_columns: readonly number[];
    variable(index: number): ReadVariablePlan | undefined;
}

export function isPackedDtaReadPlan(
    metadata: DtaReadPlan | PackedDtaReadPlan
): metadata is PackedDtaReadPlan {
    return 'variable_types' in metadata;
}

/** Per-column fields needed to locate and decode one observation cell. */
export interface ReadVariablePlan {
    readonly type: DtaType;
    readonly byte_width: number;
    readonly byte_offset: number;
}

/** Canonical variable shape returned by this package's parsers. */
export interface ParsedVariableInfo extends VariableInfo {
    notes: StataNote[];
    characteristics: StataCharacteristic[];
}

/** Canonical metadata shape returned by this package's parsers. */
export interface ParsedDtaMetadata extends DtaMetadata {
    notes: StataNote[];
    characteristics: StataCharacteristic[];
    variables: ParsedVariableInfo[];
}
