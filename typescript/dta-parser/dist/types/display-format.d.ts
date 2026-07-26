/**
 * Apply a Stata display format string to a raw value.
 *
 * - null values return null.
 * - String values pass through unchanged.
 * - Unknown or unparseable formats fall back to String(value).
 */
export declare function apply_display_format(value: number | string | null, format: string): string | null;
//# sourceMappingURL=display-format.d.ts.map