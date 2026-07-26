import type { DtaMetadata, Row, RowCell } from './types';
/**
 * Read observation rows from a .dta buffer.
 *
 * @param buffer - The full .dta file as an ArrayBuffer
 * @param metadata - Parsed metadata from parse_metadata()
 * @param start - First row index (0-based)
 * @param count - Number of rows to read
 * @param col_start - First column index (inclusive, optional)
 * @param col_end - Last column index (exclusive, optional)
 * @returns Array of rows, each row an array of cell values
 */
export declare function read_rows_from_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
/**
 * Read observation rows from a buffer that contains only
 * contiguous observation bytes, starting at `start`.
 */
export declare function read_rows_from_data_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
/**
 * Decode a set of columns from a contiguous chunk buffer in a single
 * pass, appending each column's values to its array in `out`.
 *
 * The buffer must contain exactly `count` observations starting at its
 * first byte (as produced for one chunk). Every index in `col_indices`
 * must already have an entry in `out`. strL cells decode to the
 * `'__strl__'` placeholder and must be resolved by the caller.
 *
 * One DataView/Uint8Array is built per call (not per column), and cells
 * are written straight into the flat column arrays — avoiding the
 * per-column re-parse and throwaway single-element rows that result from
 * calling the row reader once per column.
 */
export declare function read_columns_from_data_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, count: number, col_indices: number[], out: Map<number, RowCell[]>): void;
//# sourceMappingURL=data-reader.d.ts.map