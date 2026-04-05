import type { VariableInfo, Row } from './types';
export declare class DtaFile {
    private _fd;
    private readonly _metadata;
    private _gso_index;
    private _value_label_tables;
    private _closed;
    private readonly _strl_col_indices;
    private constructor();
    /**
     * Open a .dta file and parse all metadata.
     *
     * Keeps the file descriptor open for fd-backed random
     * access. Only metadata and sidecar sections are loaded
     * into memory; observation rows are read on demand.
     */
    static open(file_path: string): Promise<DtaFile>;
    /** Number of observations (rows). */
    get nobs(): number;
    /** Number of variables (columns). */
    get nvar(): number;
    /** Variable metadata array. */
    get variables(): VariableInfo[];
    /** Dataset label string. */
    get dataset_label(): string;
    /** Value label tables (table_name -> value -> label). */
    get value_label_tables(): Map<string, Map<number, string>>;
    /**
     * Read observation rows, resolving strL pointers.
     *
     * @param start - First row index (0-based)
     * @param count - Number of rows to read
     * @param col_start - First column (inclusive, optional)
     * @param col_end - Last column (exclusive, optional)
     */
    read_rows(start: number, count: number, col_start?: number, col_end?: number): Promise<Row[]>;
    /**
     * Release the open file handle and internal caches.
     * After close, read_rows returns empty arrays.
     */
    close(): void;
    /**
     * Post-process rows to resolve strL placeholders.
     *
     * For each strL column in the requested range, decode
     * the pointer from the row buffer and fetch the GSO
     * payload through the open file descriptor.
     */
    private _resolve_strls;
}
export type { VariableInfo, Row, RowCell, MissingType, MissingValue, DtaMetadata, DtaType, FormatVersion, LegacyFormatVersion, SectionOffsets, } from './types';
export { is_legacy_format } from './types';
export { apply_display_format } from './display-format';
export { classify_missing_value, classify_raw_float_missing, classify_raw_double_missing_at, is_missing_value, is_missing_value_object, make_missing_value, missing_type_to_label_key, STATA_MISSING_B, } from './missing-values';
//# sourceMappingURL=node.d.ts.map