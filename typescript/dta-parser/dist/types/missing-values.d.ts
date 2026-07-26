import type { MissingType, MissingValue } from './types';
type NumericDtaType = 'byte' | 'int' | 'long' | 'float' | 'double';
export declare const FLOAT_MISSING_DOT_RAW = 2130706432;
export declare const FLOAT_MISSING_STEP_RAW = 2048;
export declare const FLOAT_MISSING_Z_RAW: number;
/** System missing (.) as a JS number. */
export declare const STATA_MISSING: number;
/** Extended missing .a as a JS number. */
export declare const STATA_MISSING_A: number;
/** Extended missing .b as a JS number. */
export declare const STATA_MISSING_B: number;
/** Extended missing .z as a JS number. */
export declare const STATA_MISSING_Z: number;
export declare function make_missing_value(missing_type: MissingType): MissingValue;
export declare function is_missing_value_object(value: unknown): value is MissingValue;
export declare function classify_raw_float_missing(raw_value: number): MissingType | null;
export declare function classify_raw_double_missing_at(view: DataView, offset: number, little_endian: boolean): MissingType | null;
/**
 * Returns true if `value` is a Stata missing value for the
 * given type. When no type is provided, uses the double
 * encoding used by in-memory JS numeric values.
 */
export declare function is_missing_value(value: number, type?: NumericDtaType): boolean;
/**
 * Classify a Stata missing value. Returns '.', '.a' .. '.z',
 * or null if the value is not missing.
 */
/**
 * Convert a MissingType to the int32 key used in value
 * label tables (long encoding).
 */
export declare function missing_type_to_label_key(missing_type: MissingType): number;
export declare function classify_missing_value(value: number, type?: NumericDtaType): MissingType | null;
export {};
//# sourceMappingURL=missing-values.d.ts.map