import type { VariableInfo, Row } from './types';
/** Options for {@link DtaFile.read_rows}. */
export interface ReadRowsOptions {
    /**
     * When provided, the read is performed in chunks that yield to the
     * event loop between them, and is abandoned with an `AbortError` as
     * soon as the signal fires. Without a signal, the read is a single
     * synchronous pass (the original fast path).
     */
    signal?: AbortSignal;
    /** Rows per chunk on the cancellable path (default 65536). */
    chunk_rows?: number;
}
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
     * @param options - Cancellation options (see {@link ReadRowsOptions}).
     *   When `options.signal` is provided, the read is chunked and
     *   yields between chunks so the abort can be observed; it rejects
     *   with an `AbortError` if the signal fires. Without a signal the
     *   read is a single synchronous pass identical to prior behavior.
     */
    read_rows(start: number, count: number, col_start?: number, col_end?: number, options?: ReadRowsOptions): Promise<Row[]>;
    /**
     * Read a contiguous row range in a single synchronous pass and
     * resolve any strL columns in range. Shared by both the fast path
     * and each chunk of the cancellable path. Callers must ensure the
     * file is open (`_fd !== null`).
     */
    private _read_rows_range;
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