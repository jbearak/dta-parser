export declare const FORMAT_SIGNATURES: {
    readonly 117: "<stata_dta><header><release>117</release>";
    readonly 118: "<stata_dta><header><release>118</release>";
    readonly 119: "<stata_dta><header><release>119</release>";
};
export type FormatVersion = 113 | 114 | 115 | 117 | 118 | 119;
export type LegacyFormatVersion = 113 | 114 | 115;
export declare function is_legacy_format(version: FormatVersion): version is LegacyFormatVersion;
export type DtaType = 'byte' | 'int' | 'long' | 'float' | 'double' | 'strL' | `str${number}`;
/**
 * Return the byte width for a numeric type code in the
 * given format version. Fixed-string codes (1..244 for
 * v117, 1..2045 for v118/v119) equal their own width.
 *
 * Note: Modern Stata (16+) writes v118 type codes even
 * in saveold v117 files, so v117 accepts both code sets.
 */
export declare function byte_width_for_type_code(code: number, format_version: FormatVersion): number;
/**
 * Convert a numeric type code to its DtaType label.
 *
 * Note: Modern Stata (16+) writes v118 type codes even
 * in saveold v117 files, so v117 accepts both code sets.
 */
export declare function type_code_to_dta_type(code: number, format_version: FormatVersion): DtaType;
export declare function byte_width_for_legacy_type_code(code: number): number;
export declare function legacy_type_code_to_dta_type(code: number): DtaType;
export interface VariableInfo {
    name: string;
    type: DtaType;
    type_code: number;
    format: string;
    label: string;
    value_label_name: string;
    byte_width: number;
    byte_offset: number;
}
export type MissingType = '.' | '.a' | '.b' | '.c' | '.d' | '.e' | '.f' | '.g' | '.h' | '.i' | '.j' | '.k' | '.l' | '.m' | '.n' | '.o' | '.p' | '.q' | '.r' | '.s' | '.t' | '.u' | '.v' | '.w' | '.x' | '.y' | '.z';
export interface MissingValue {
    kind: 'missing';
    missing_type: MissingType;
}
export type RowCell = number | string | MissingValue;
export type Row = RowCell[];
export interface SectionOffsets {
    stata_data: number;
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
    stata_data_close: number;
    end_of_file: number;
}
export interface DtaMetadata {
    format_version: FormatVersion;
    byte_order: 'MSF' | 'LSF';
    nvar: number;
    nobs: number;
    dataset_label: string;
    variables: VariableInfo[];
    section_offsets: SectionOffsets;
    obs_length: number;
}
//# sourceMappingURL=types.d.ts.map